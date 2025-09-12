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


Yes — the Omnissa Horizon Agent absolutely must be installed and running on a Windows VM before that VM can be used in a Horizon desktop pool. Horizon Connection Server relies on the agent to broker the session, handle protocols (Blast/PCoIP/RDP), and report health and status. Without the agent, the VM will not register with Horizon and won’t show up as available for pool creation.

Here’s why you might be seeing “no agent found” in Ansible:

1. Agent Installation Validation

On Windows, the Horizon Agent installs as a service called VMware Horizon View Agent or Omnissa Horizon Agent (the name varies slightly depending on version).

You can confirm manually by running:

Get-Service | Where-Object { $_.DisplayName -like "*Horizon*" }


If your Ansible task is failing, it may be because the service name you’re checking doesn’t match exactly.

2. Path and Service Check

By default, the Horizon Agent installs into:

C:\Program Files\VMware\VMware View\Agent\


You should check both the install path and the Windows service. For example, in Ansible (via win_service):

- name: Check Horizon Agent service
  ansible.windows.win_service:
    name: "VMware Horizon View Agent"
  register: horizon_service

- debug:
    var: horizon_service

3. Why Your Task Says “No Agent Found”

If your playbook is only checking the path, but the path doesn’t exist (e.g., version mismatch, wrong folder), it will report missing.

If you’re checking the wrong service name, Ansible won’t find it.

If the agent didn’t install correctly (requires admin rights, firewall ports, prerequisites like .NET and Visual C++ runtime), the install might have silently failed.

4. Requirement for Pools

Yes, the agent is mandatory for building Windows pools.

Without it, Horizon cannot communicate with the guest VM, so pool creation will fail (the VM won’t register).

Once the agent is installed and the VM is joined to the domain, you can snapshot it and use it as the parent for an Instant Clone or linked clone pool.

✅ Recommendation for you:

Double-check the exact service name in your Horizon Agent version.

Update your Ansible task to check for that service instead of only the path.

Confirm the install prerequisites (.NET, Visual C++ runtime, firewall rules).

Do you want me to write you a ready-to-use Ansible task that both installs the Horizon Agent and then verifies by checking the Windows service, so you’ll know 100% if it’s running before using the VM in a pool?

You said:
Can I check with powershell but using ansible 
ChatGPT said:

Yes 👍 you can absolutely run a PowerShell command through Ansible to check if the Omnissa Horizon Agent is installed and running. You’d do this with the ansible.windows.win_powershell or ansible.windows.win_shell module.

Here’s a practical example:
````

- name: Check if Horizon Agent service is installed and running
  ansible.windows.win_powershell:
    script: |
      $service = Get-Service | Where-Object { $_.DisplayName -like "*Horizon*" }
      if ($service) {
        $service | Select-Object DisplayName, Status
      } else {
        Write-Output "No Horizon Agent service found"
      }
  register: horizon_agent_status

- name: Show Horizon Agent service status
  debug:
    var: horizon_agent_status.stdout
```
How this works

PowerShell script runs inside the Windows VM.

It searches for any service with “Horizon” in its display name.

If found, it prints the display name and current status (Running, Stopped, etc.).

If not found, it outputs a message.

Ansible registers output into horizon_agent_status.

Debug task prints the result so you can see it in your Ansible run.



https://lucaberton.medium.com/add-a-new-hard-disk-to-vmware-vsphere-virtual-machine-ansible-module-vmware-guest-disk-599ff8b9a738
