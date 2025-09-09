```
- name: Ensure Omnissa Horizon Agent is installed, PATHed, and running
  hosts: windows
  gather_facts: no
  vars:
    horizon_installer_path: 'C:\Temp\Omnissa-Horizon-Agent-2412.exe'
    horizon_silent_args: '/s /v"/qn REBOOT=ReallySuppress ADDLOCAL=Core,BlastUDP,PCoIP,USB,RTAV,ClientDriveRedirection"'
    omnissa_agent_bin: 'C:\Program Files\Omnissa\Horizon Agent\bin'
    candidate_services:
      - 'Omnissa Horizon Agent'
      - 'VMware Horizon View Agent'
      - 'VMwareViewAgent'
      - 'VmAgentService'

  tasks:
    - name: Ensure installer exists
      ansible.windows.win_stat:
        path: "{{ horizon_installer_path }}"
      register: installer_stat

    - name: Fail if installer is missing
      when: not installer_stat.stat.exists
      ansible.builtin.fail:
        msg: "Installer not found at {{ horizon_installer_path }}"

    - name: Ensure agent bin folder exists
      ansible.windows.win_file:
        path: "{{ omnissa_agent_bin }}"
        state: directory

    - name: Ensure agent bin folder is in system PATH
      ansible.windows.win_path:
        elements:
          - "{{ omnissa_agent_bin }}"
        scope: machine
        state: present

    - name: Ensure Horizon Agent is installed
      ansible.windows.win_package:
        path: "{{ horizon_installer_path }}"
        arguments: "{{ horizon_silent_args }}"
        state: present
      register: install_result

    - name: Reboot if installer requires it
      ansible.windows.win_reboot:
        post_reboot_delay: 30
        reboot_timeout: 1800
      when: install_result.reboot_required | default(false)

    - name: Probe Horizon Agent services
      ansible.windows.win_service_info:
        name: "{{ item }}"
      loop: "{{ candidate_services }}"
      register: svc_info_results
      ignore_errors: yes

    - name: Pick detected service
      ansible.builtin.set_fact:
        horizon_service_name: "{{ (svc_info_results.results | selectattr('exists', 'defined') | selectattr('exists') | map(attribute='name') | list | first) | default('') }}"

    - name: Fail if no service found
      ansible.builtin.fail:
        msg: "No Horizon Agent service detected. Install may have failed."
      when: horizon_service_name | length == 0

    - name: Ensure Horizon Agent service is running
      ansible.windows.win_service:
        name: "{{ horizon_service_name }}"
        start_mode: auto
        state: started
```
