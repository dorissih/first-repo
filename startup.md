Here’s a clean, production-ready way to run Coverity (Coverity Connect / cov-serve) as a systemd service using Ansible. It’s flexible even if your start/stop commands differ—just set variables.

1) Role layout (minimal)

```
roles/
  coverity_service/
    defaults/main.yml
    tasks/main.yml
    handlers/main.yml
    templates/coverity.service.j2
    templates/coverity.env.j2
```

defaults/main.yml
# Service identity
coverity_user: coverity
coverity_group: coverity


# Paths
```
coverity_env_dir: /etc/coverity
coverity_env_file: /etc/coverity/coverity.env
coverity_workdir: /var/lib/coverity
coverity_systemd_unit: /etc/systemd/system/coverity.service
```
# Set these to match your install
```
coverity_home: /opt/coverity
java_home: /usr/lib/jvm/java-17-openjdk
coverity_license: 27000@licenseserver.example.com   # Or host:port; use your format
```
# Start/stop commands (keep fully explicit; no guessing flags here)
# If you use a wrapper or a different command, just change these.
```
coverity_start_cmd: "{{ coverity_home }}/bin/cov-serve --port 8080 --data-dir {{ coverity_workdir }} --license {{ coverity_license }} --java-home {{ java_home }}"
coverity_stop_cmd: "{{ coverity_home }}/bin/cov-serve --stop"
```
# Systemd knobs
```
coverity_restart: on-failure
coverity_restart_sec: 5s
coverity_limit_nofile: 65535
coverity_timeout_start: 120
coverity_timeout_stop: 120
```
# Optional: open firewall (RHEL family with firewalld). Set to the port you use.
```
coverity_firewalld_open: false
coverity_port: 8080
```
templates/coverity.env.j2
# Exported into the service environment by systemd
```
COV_HOME="{{ coverity_home }}"
JAVA_HOME="{{ java_home }}"
COVERITY_LICENSE="{{ coverity_license }}"
```
templates/coverity.service.j2
```
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
```
tasks/main.yml
```
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
```
handlers/main.yml
```
---
- name: Daemon reload
  ansible.builtin.systemd:
    daemon_reload: true

- name: Restart coverity
  ansible.builtin.systemd:
    name: coverity.service
    state: restarted
```
2) Playbook example
# coverity.yml
```
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
```

Run it:

ansible-playbook -i inventory coverity.yml

Notes & tweaks

Command flags: Different Coverity versions/environments use slightly different cov-serve options. Keep them entirely in coverity_start_cmd so you don’t have to touch the unit file.

Stop behavior: If your environment requires a specific stop command, set coverity_stop_cmd. Otherwise systemd will send TERM to the main process.

SELinux: If enforcing and you use a nonstandard port, add an SELinux rule (e.g., semanage port -a -t http_port_t -p tcp 8443) or run behind a reverse proxy.

Logs: View with journalctl -u coverity -f.

If you drop in your exact start/stop commands or version, I can tailor the defaults for you.

Here’s a clean Ansible role to run the GrammaTech CodeSonar Hub under systemd. I’ve kept the service flexible so you can drop in your exact start/stop flags (different versions sometimes vary). Defaults assume the Hub is managed with the hub wrapper script.

Role layout
roles/
  codesonar_service/
    defaults/main.yml
    tasks/main.yml
    handlers/main.yml
    templates/codesonar.service.j2
    templates/codesonar.env.j2

defaults/main.yml
# Service identity
codesonar_user: codesonar
codesonar_group: codesonar

# Install & data paths
codesonar_home: /opt/codesonar                # CodeSonar install path (contains bin/hub)
codesonar_var_dir: /var/lib/codesonar         # Parent state dir
codesonar_hub_dir: /var/lib/codesonar/hub     # Hub config/state dir (existing or created)
codesonar_log_dir: /var/log/codesonar

# Environment
codesonar_env_dir: /etc/codesonar
codesonar_env_file: /etc/codesonar/codesonar.env
codesonar_license: "7340@licenseserver.example.com"  # Adjust or leave blank if not needed
codesonar_java_home: /usr/lib/jvm/java-17-openjdk     # If required by your build

# Network
codesonar_port: 7340
codesonar_bind: "0.0.0.0"                     # or "127.0.0.1" if reverse proxying
codesonar_firewalld_open: false               # set true on RHEL-family with firewalld

# Start/stop commands (override to match your version/flags)
# Common patterns include:
#   {{ codesonar_home }}/bin/hub start -C {{ codesonar_hub_dir }} -l {{ codesonar_bind }}:{{ codesonar_port }} -d
#   {{ codesonar_home }}/bin/hub stop -C {{ codesonar_hub_dir }}
```
codesonar_start_cmd: >-
  {{ codesonar_home }}/bin/hub start
  -C {{ codesonar_hub_dir }}
  -l {{ codesonar_bind }}:{{ codesonar_port }}
  -d
codesonar_stop_cmd: "{{ codesonar_home }}/bin/hub stop -C {{ codesonar_hub_dir }}"
```
# Systemd
```
codesonar_systemd_unit: /etc/systemd/system/codesonar-hub.service
codesonar_restart: on-failure
codesonar_restart_sec: 5s
codesonar_timeout_start: 120
codesonar_timeout_stop: 120
codesonar_limit_nofile: 65535
```
templates/codesonar.env.j2
# Loaded by systemd EnvironmentFile=
```
CODESONAR_HOME="{{ codesonar_home }}"
CODESONAR_HUB_DIR="{{ codesonar_hub_dir }}"
CODESONAR_LICENSE="{{ codesonar_license }}"
JAVA_HOME="{{ codesonar_java_home }}"
```
templates/codesonar.service.j2
```
[Unit]
Description=GrammaTech CodeSonar Hub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{ codesonar_user }}
Group={{ codesonar_group }}
EnvironmentFile={{ codesonar_env_file }}
WorkingDirectory={{ codesonar_hub_dir }}

# Use a shell to allow env expansion and multi-arg commands
ExecStart=/bin/bash -lc "{{ codesonar_start_cmd }}"
ExecStop=/bin/bash -lc "{{ codesonar_stop_cmd | default('/bin/kill -TERM $MAINPID') }}"

# Resource & lifecycle
Restart={{ codesonar_restart }}
RestartSec={{ codesonar_restart_sec }}
LimitNOFILE={{ codesonar_limit_nofile }}
TimeoutStartSec={{ codesonar_timeout_start }}
TimeoutStopSec={{ codesonar_timeout_stop }}

# Hardening (tune per environment)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
```
tasks/main.yml
```
---
- name: Ensure group exists
  ansible.builtin.group:
    name: "{{ codesonar_group }}"
    system: true

- name: Ensure service user exists
  ansible.builtin.user:
    name: "{{ codesonar_user }}"
    group: "{{ codesonar_group }}"
    shell: /sbin/nologin
    system: true
    create_home: false

- name: Create directories
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    owner: "{{ item.owner | default(codesonar_user) }}"
    group: "{{ item.group | default(codesonar_group) }}"
    mode: "{{ item.mode | default('0750') }}"
  loop:
    - { path: "{{ codesonar_var_dir }}" }
    - { path: "{{ codesonar_hub_dir }}" }
    - { path: "{{ codesonar_log_dir }}" }
    - { path: "{{ codesonar_env_dir }}", owner: "root", group: "root", mode: "0755" }

- name: Drop environment file
  ansible.builtin.template:
    src: codesonar.env.j2
    dest: "{{ codesonar_env_file }}"
    owner: root
    group: root
    mode: '0644'
  notify: Restart codesonar

- name: Install systemd unit
  ansible.builtin.template:
    src: codesonar.service.j2
    dest: "{{ codesonar_systemd_unit }}"
    owner: root
    group: root
    mode: '0644'
  notify:
    - Daemon reload
    - Restart codesonar

- name: Optionally open firewalld port
  when: codesonar_firewalld_open
  ansible.builtin.firewalld:
    port: "{{ codesonar_port }}/tcp"
    permanent: true
    immediate: true
    state: enabled

- name: Enable and start CodeSonar Hub
  ansible.builtin.systemd:
    name: codesonar-hub.service
    enabled: true
    state: started
```
handlers/main.yml
```
---
- name: Daemon reload
  ansible.builtin.systemd:
    daemon_reload: true

- name: Restart codesonar
  ansible.builtin.systemd:
    name: codesonar-hub.service
    state: restarted
```
Example playbook
# codesonar.yml
```
- hosts: codesonar_hubs
  become: yes
  roles:
    - role: codesonar_service
      vars:
        codesonar_home: /opt/codesonar
        codesonar_hub_dir: /var/lib/codesonar/hub
        codesonar_bind: 0.0.0.0
        codesonar_port: 7340
        codesonar_license: 7340@license01.mycorp.local
        codesonar_firewalld_open: true
        # If your version needs different flags, override start/stop:
        # codesonar_start_cmd: "/opt/codesonar/bin/hub start -C /var/lib/codesonar/hub -l 0.0.0.0:7340 -d"
        # codesonar_stop_cmd:  "/opt/codesonar/bin/hub stop -C /var/lib/codesonar/hub"
```

Run:

ansible-playbook -i inventory.ini codesonar.yml

Notes and tips

Exact flags: CodeSonar versions differ. If your hub uses a different CLI (e.g., codesonar hub ...), just override codesonar_start_cmd/codesonar_stop_cmd in vars.

Permissions: Make sure codesonar_user can read the install dir and owns the hub dir.

SELinux: If listening on a nonstandard port under a web context, you may need semanage port -a -t http_port_t -p tcp 7340.

Logs: Check journalctl -u codesonar-hub -f. If the hub writes its own logs, point them into codesonar_log_dir via your hub config.

Reverse proxy: If you’ll front it with NGINX/Apache, set codesonar_bind: 127.0.0.1 and proxy the port.
