Here’s a clean, production-ready way to run Coverity (Coverity Connect / cov-serve) as a systemd service using Ansible. It’s flexible even if your start/stop commands differ—just set variables.

1) Role layout (minimal)
roles/
  coverity_service/
    defaults/main.yml
    tasks/main.yml
    handlers/main.yml
    templates/coverity.service.j2
    templates/coverity.env.j2

defaults/main.yml
# Service identity
coverity_user: coverity
coverity_group: coverity

# Paths
coverity_env_dir: /etc/coverity
coverity_env_file: /etc/coverity/coverity.env
coverity_workdir: /var/lib/coverity
coverity_systemd_unit: /etc/systemd/system/coverity.service

# Set these to match your install
coverity_home: /opt/coverity
java_home: /usr/lib/jvm/java-17-openjdk
coverity_license: 27000@licenseserver.example.com   # Or host:port; use your format

# Start/stop commands (keep fully explicit; no guessing flags here)
# If you use a wrapper or a different command, just change these.
coverity_start_cmd: "{{ coverity_home }}/bin/cov-serve --port 8080 --data-dir {{ coverity_workdir }} --license {{ coverity_license }} --java-home {{ java_home }}"
coverity_stop_cmd: "{{ coverity_home }}/bin/cov-serve --stop"

# Systemd knobs
coverity_restart: on-failure
coverity_restart_sec: 5s
coverity_limit_nofile: 65535
coverity_timeout_start: 120
coverity_timeout_stop: 120

# Optional: open firewall (RHEL family with firewalld). Set to the port you use.
coverity_firewalld_open: false
coverity_port: 8080

templates/coverity.env.j2
# Exported into the service environment by systemd
COV_HOME="{{ coverity_home }}"
JAVA_HOME="{{ java_home }}"
COVERITY_LICENSE="{{ coverity_license }}"

templates/coverity.service.j2
[Unit]
Description=Coverity Connect (cov-serve)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{ coverity_user }}
Group={{ coverity_group }}
EnvironmentFile={{ coverity_env_file }}
WorkingDirectory={{ coverity_workdir }}

# Use an explicit shell so env expansion and quoted args are honored
ExecStart=/bin/bash -lc "{{ coverity_start_cmd }}"
ExecStop=/bin/bash -lc "{{ coverity_stop_cmd | default('/bin/kill -TERM $MAINPID') }}"

Restart={{ coverity_restart }}
RestartSec={{ coverity_restart_sec }}
LimitNOFILE={{ coverity_limit_nofile }}
TimeoutStartSec={{ coverity_timeout_start }}
TimeoutStopSec={{ coverity_timeout_stop }}

# Hardening (tune as needed)
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target

tasks/main.yml
---
- name: Ensure group exists
  ansible.builtin.group:
    name: "{{ coverity_group }}"
    system: true

- name: Ensure user exists
  ansible.builtin.user:
    name: "{{ coverity_user }}"
    group: "{{ coverity_group }}"
    shell: /sbin/nologin
    system: true
    create_home: false

- name: Create env directory
  ansible.builtin.file:
    path: "{{ coverity_env_dir }}"
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Ensure work directory exists
  ansible.builtin.file:
    path: "{{ coverity_workdir }}"
    state: directory
    owner: "{{ coverity_user }}"
    group: "{{ coverity_group }}"
    mode: '0750'

- name: Drop environment file
  ansible.builtin.template:
    src: coverity.env.j2
    dest: "{{ coverity_env_file }}"
    owner: root
    group: root
    mode: '0644'
  notify: Restart coverity

- name: Drop systemd unit
  ansible.builtin.template:
    src: coverity.service.j2
    dest: "{{ coverity_systemd_unit }}"
    owner: root
    group: root
    mode: '0644'
  notify:
    - Daemon reload
    - Restart coverity

- name: Optionally open firewalld port
  when: coverity_firewalld_open
  ansible.builtin.firewalld:
    port: "{{ coverity_port }}/tcp"
    permanent: true
    state: enabled
    immediate: true

- name: Enable and start service
  ansible.builtin.systemd:
    name: coverity.service
    enabled: true
    state: started

handlers/main.yml
---
- name: Daemon reload
  ansible.builtin.systemd:
    daemon_reload: true

- name: Restart coverity
  ansible.builtin.systemd:
    name: coverity.service
    state: restarted

2) Playbook example
# coverity.yml
- hosts: coverity_servers
  become: yes
  roles:
    - role: coverity_service
      vars:
        coverity_home: /opt/coverity       # adjust
        java_home: /usr/lib/jvm/java-17-openjdk
        coverity_license: 27000@license01.mycorp.local
        coverity_start_cmd: "/opt/coverity/bin/cov-serve --port 8443 --data-dir /var/lib/coverity --license 27000@license01.mycorp.local --java-home /usr/lib/jvm/java-17-openjdk"
        coverity_port: 8443
        coverity_firewalld_open: true


Run it:

ansible-playbook -i inventory coverity.yml

Notes & tweaks

Command flags: Different Coverity versions/environments use slightly different cov-serve options. Keep them entirely in coverity_start_cmd so you don’t have to touch the unit file.

Stop behavior: If your environment requires a specific stop command, set coverity_stop_cmd. Otherwise systemd will send TERM to the main process.

SELinux: If enforcing and you use a nonstandard port, add an SELinux rule (e.g., semanage port -a -t http_port_t -p tcp 8443) or run behind a reverse proxy.

Logs: View with journalctl -u coverity -f.

If you drop in your exact start/stop commands or version, I can tailor the defaults for you.
