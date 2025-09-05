I used the 2406 docs you shared (plus the “Silent Installation Properties” page) to wire up a clean, reusable Ansible role that installs the Omnissa Horizon Agent on Windows with the usual silent-install properties (e.g., ADDLOCAL, VDM_SERVER_NAME, optional URL_FILTERING_ENABLED, ENABLE_UNC_REDIRECTION, etc.). 
Omnissa Documentation
+2
Omnissa Documentation
+2

Below is a drop-in role you can paste into your repo.

Role layout
roles/
  horizon_agent_win/
    defaults/
      main.yml
    tasks/
      main.yml
      install.yml
      verify.yml
    handlers/
      main.yml
    meta/
      main.yml
    README.md

defaults/main.yml
# Where to fetch the installer from. Can be HTTP/HTTPS/SMB/file.
horizon_agent_installer_url: 'https://filesrv.local/share/Omnissa-Horizon-Agent-x86_64-2406.exe'
horizon_agent_installer_checksum: ''   # optional: sha256:xxxx

# Folder on the target to stage the installer
horizon_agent_download_dir: 'C:\Temp\HorizonAgent'
horizon_agent_installer_name: 'Omnissa-Horizon-Agent-x86_64-2406.exe'

# Register to a Connection Server (optional for unmanaged or imaging workflows)
horizon_agent_register: true
horizon_connection_server: 'cs1.example.local'   # VDM_SERVER_NAME
horizon_register_user: ''                        # VDM_SERVER_USERNAME (domain\user)
horizon_register_password: ''                    # VDM_SERVER_PASSWORD (plain text; consider Ansible Vault)

# vCenter managed? (1=yes, 0=no). If you register directly to Connection Server, set 0.
horizon_vc_managed_agent: 0  # VDM_VC_MANAGED_AGENT

# Feature set for ADDLOCAL (comma-separated string).
# Start lean; add only what you need to avoid 1603 errors.
horizon_agent_addlocal: >-
  Core,BlastProtocol,PCoIP,USB,RTAV,ClientDriveRedirection,VmwVaudio,VmVideo,VmwVidd,TSMMR

# Optional MSI properties toggles (set to 1 to enable)
horizon_enable_url_redirection: 0     # URL_FILTERING_ENABLED (URL Content Redirection)
horizon_enable_unc_redirection: 0     # ENABLE_UNC_REDIRECTION (UNC Path Redirection)

# Enable RDP in the registry via installer (optional)
horizon_rdp_choice: 1                 # RDP_CHOICE=1 enables RDP

# Reboot behavior
horizon_reboot_after_install: true

# Extra raw properties if you need to pass anything not modeled above
horizon_agent_extra_properties: ''  # e.g. 'INSTALLDIR=C:\HorizonAgent'

tasks/main.yml
---
- name: Include install steps
  ansible.builtin.import_tasks: install.yml

- name: Include verification
  ansible.builtin.import_tasks: verify.yml

tasks/install.yml
---
- name: Ensure download folder exists
  ansible.windows.win_file:
    path: "{{ horizon_agent_download_dir }}"
    state: directory

- name: Download Horizon Agent installer (HTTP/HTTPS)
  ansible.windows.win_get_url:
    url: "{{ horizon_agent_installer_url }}"
    dest: "{{ horizon_agent_download_dir }}\\{{ horizon_agent_installer_name }}"
    checksum: "{{ horizon_agent_installer_checksum | default(omit) }}"
  when: horizon_agent_installer_url is search('^https?://')

- name: Copy installer from controller (if using bundled file)
  ansible.windows.win_copy:
    src: "files/{{ horizon_agent_installer_name }}"
    dest: "{{ horizon_agent_download_dir }}\\{{ horizon_agent_installer_name }}"
  when: horizon_agent_installer_url is not search('^https?://')

# Build the MSI property string
- name: Compose MSI properties
  ansible.builtin.set_fact:
    horizon_msi_props: >-
      VDM_VC_MANAGED_AGENT={{ horizon_vc_managed_agent }}
      {{ 'VDM_SERVER_NAME=' + horizon_connection_server if horizon_agent_register else '' }}
      {{ 'VDM_SERVER_USERNAME=' + horizon_register_user if (horizon_agent_register and horizon_register_user|length > 0) else '' }}
      {{ 'VDM_SERVER_PASSWORD=' + horizon_register_password if (horizon_agent_register and horizon_register_password|length > 0) else '' }}
      {{ 'URL_FILTERING_ENABLED=1' if horizon_enable_url_redirection | bool else '' }}
      {{ 'ENABLE_UNC_REDIRECTION=1' if horizon_enable_unc_redirection | bool else '' }}
      {{ 'RDP_CHOICE=' + (horizon_rdp_choice | string) if horizon_rdp_choice is not none else '' }}
      ADDLOCAL={{ horizon_agent_addlocal }}
      REBOOT=ReallySuppress
      {{ horizon_agent_extra_properties }}

- name: Install Omnissa Horizon Agent silently
  ansible.windows.win_package:
    path: "{{ horizon_agent_download_dir }}\\{{ horizon_agent_installer_name }}"
    # Silent install: EXE wrapper passes MSI props with /v"..."
    arguments: '/s /v"/qn {{ horizon_msi_props | regex_replace("\\s+", " ") | trim }}"'
    state: present
    # Write a log for troubleshooting (vminst.log is also created by the installer)
    log_path: "{{ horizon_agent_download_dir }}\\horizon_agent_install.log"

- name: Reboot if required
  ansible.windows.win_reboot:
    msg: "Rebooting to finalize Horizon Agent installation."
    reboot_timeout: 1800
  when: horizon_reboot_after_install

tasks/verify.yml
---
- name: Check Horizon Agent service
  ansible.windows.win_service:
    name: VMware Horizon View Agent
  register: svc

- name: Fail if service not present
  ansible.builtin.fail:
    msg: "Horizon Agent service not found; check the installer log and %WINDIR%\\Temp\\vminst.log."
  when: svc.exists is not defined or not svc.exists

- name: Show installed features from registry (best-effort)
  ansible.windows.win_reg_stat:
    path: 'HKLM:\\Software\\VMware, Inc.\\Installer\\Features_HorizonAgent'
  register: reg_feats

- name: Debug features
  ansible.builtin.debug:
    var: reg_feats

handlers/main.yml
---
# (reserved if you add things like firewall rule reloads, etc.)

meta/main.yml
---
galaxy_info:
  role_name: horizon_agent_win
  author: you
  description: Install Omnissa Horizon Agent for Windows silently
  license: MIT
  min_ansible_version: "2.14"
  platforms:
    - name: Windows
      versions: ['2019', '2022', '10', '11']
dependencies: []

README.md (short)
# horizon_agent_win

Installs Omnissa Horizon Agent for Windows (8.x / YYMM) silently using MSI properties.

## Key variables
- `horizon_agent_installer_url` – where to fetch the EXE wrapper.
- `horizon_agent_addlocal` – comma-separated features for `ADDLOCAL`.
- `horizon_connection_server` + creds – sets `VDM_SERVER_*` if `horizon_agent_register: true`.
- `horizon_enable_url_redirection` → `URL_FILTERING_ENABLED=1`.
- `horizon_enable_unc_redirection` → `ENABLE_UNC_REDIRECTION=1`.
- `horizon_rdp_choice` → `RDP_CHOICE=1`.

> Notes:
> - `VDM_SERVER_NAME` registers unmanaged desktops directly to a Connection Server. Use only if that’s your flow. :contentReference[oaicite:1]{index=1}  
> - URL and UNC redirection require the corresponding MSI properties to be set during install. :contentReference[oaicite:2]{index=2}  
> - Use standard MSI quiet flags via the EXE wrapper (`/s /v"/qn ..."`). :contentReference[oaicite:3]{index=3}

## Example play
```yaml
- name: Install Horizon Agent on Windows 11 template
  hosts: win_templates
  gather_facts: no
  vars:
    horizon_agent_installer_url: "https://repo.example.com/Omnissa-Horizon-Agent-x86_64-2406.exe"
    horizon_agent_register: true
    horizon_connection_server: "hzn-conn01.example.com"
    horizon_register_user: "EXAMPLE\\horizonjoin"
    horizon_register_password: "{{ vault_horizonjoin_password }}"
    horizon_agent_addlocal: "Core,BlastProtocol,PCoIP,USB,RTAV,ClientDriveRedirection,VmwVaudio,VmVideo,VmwVidd,TSMMR"
    horizon_enable_url_redirection: 1
    horizon_enable_unc_redirection: 1
    horizon_rdp_choice: 1
  roles:
    - horizon_agent_win


---

## Why these switches?
- `ADDLOCAL` lets you pick specific features instead of installing everything (safer and reduces 1603s when OS prerequisites aren’t present). :contentReference[oaicite:4]{index=4}  
- `VDM_SERVER_NAME`/`VDM_VC_MANAGED_AGENT` control registration path (direct to Connection Server vs. vCenter-managed). :contentReference[oaicite:5]{index=5}  
- `URL_FILTERING_ENABLED=1` (URL Content Redirection) and `ENABLE_UNC_REDIRECTION=1` (UNC path redirection) are explicitly required during install if you want those capabilities. :contentReference[oaicite:6]{index=6}  
- `RDP_CHOICE=1` toggles RDP on the desktop during install (handy in templates). (Older but still referenced property.) :contentReference[oaicite:7]{index=7}

## Troubleshooting tips
- Check `%WINDIR%\Temp\vminst.log` and the `log_path` you set on `win_package` if you hit exit code 1603. Common causes: missing prerequisites, unsupported/removed features, or wrong property names. :contentReference[oaicite:8]{index=8}
- If you need to discover valid feature names for your exact build, install once interactively on a lab VM, then read `HKLM\Software\VMware, Inc.\Installer\Features_HorizonAgent`. That list maps directly to `ADDLOCAL` options. :contentReference[oaicite:9]{index=9}

If you want, I can tailor `ADDLOCAL` for your exact use case (Instant Clone vs. manual, RDSH vs. desktop, Teams optimization, etc.) and wire this role into your existing Windows image pipeline.
::contentReference[oaicite:10]{index=10}

You said:
am using 2412 version
ChatGPT said:
Thought for 19s

Perfect — let’s switch the role to Horizon Agent 2412. The MSI properties and silent flags are unchanged, so this is mostly a version bump plus a quick reminder to re-confirm your ADDLOCAL list for your image. 
docs.omnissa.com
+1

What to change

defaults/main.yml

# Where to fetch the installer from
horizon_agent_installer_url: 'https://filesrv.local/share/Omnissa-Horizon-Agent-x86_64-2412.exe'
horizon_agent_installer_checksum: ''   # e.g., sha256:xxxx

# Staging folder and file name on the target
horizon_agent_download_dir: 'C:\Temp\HorizonAgent'
horizon_agent_installer_name: 'Omnissa-Horizon-Agent-x86_64-2412.exe'

# (keep the rest the same)


No other task changes are required. The EXE wrapper is still called with:

/s /v"/qn <MSI_PROPERTIES>"


which remains the supported pattern for silent installs. 
docs.omnissa.com

Sanity checks for 2412

Features list (ADDLOCAL) — keep it lean and explicit (e.g., Core,BlastProtocol,PCoIP,USB,RTAV,ClientDriveRedirection,VmwVaudio,VmVideo,VmwVidd,TSMMR). If you prefer a kitchen-sink build for testing, ADDLOCAL=ALL is valid but only for validation; be selective for your template. 
docs.omnissa.com
Microsoft Learn

Optional properties you can toggle the same way as before:

VDM_SERVER_NAME, VDM_VC_MANAGED_AGENT for registration path. 
docs.omnissa.com

URL_FILTERING_ENABLED=1 (URL Content Redirection), ENABLE_UNC_REDIRECTION=1 (UNC redirection). 
docs.omnissa.com
+1

Teams optimization is still controlled post-install by GPO/registry (not an MSI switch). Keep your existing optimization steps. 
Tech Zone

Quick example play (2412)
- name: Install Horizon Agent 2412 on Windows 11 template
  hosts: win_templates
  gather_facts: no
  vars:
    horizon_agent_installer_url: "https://repo.example.com/Omnissa-Horizon-Agent-x86_64-2412.exe"
    horizon_agent_register: true
    horizon_connection_server: "hzn-conn01.example.com"
    horizon_register_user: "EXAMPLE\\horizonjoin"
    horizon_register_password: "{{ vault_horizonjoin_password }}"
    horizon_agent_addlocal: "Core,BlastProtocol,PCoIP,USB,RTAV,ClientDriveRedirection,VmwVaudio,VmVideo,VmwVidd,TSMMR"
    horizon_enable_url_redirection: 1
    horizon_enable_unc_redirection: 1
    horizon_rdp_choice: 1
  roles:
    - horizon_agent_win


If you want, tell me the exact features you need (Instant Clone vs manual, RDSH vs VDI, Teams, Scanner Redirection, etc.), and I’ll pin a 2412-specific ADDLOCAL string for your image.


Got you. Here’s a clean, production-ready Ansible role + example play to install the Omnissa (Horizon) Agent for Windows—works for golden images or unmanaged desktops, handles silent switches, optional broker registration, reboots, and logging.

Folder layout
roles/
  horizon_agent/
    defaults/main.yml
    tasks/main.yml
playbooks/
  install_horizon_agent.yml

roles/horizon_agent/defaults/main.yml
# Where to get the installer
horizon_agent_installer_url: "\\\\fileserver\\packages\\VMware-Horizon-Agent-x86_64-2412.exe"
# (Optional) If you’d rather upload from your Ansible control machine:
# horizon_agent_installer_src: "/files/VMware-Horizon-Agent-x86_64-2412.exe"

horizon_agent_installer_path: "C:\\Temp\\VMware-Horizon-Agent.exe"
horizon_agent_log_path: "C:\\Windows\\Temp\\HorizonAgent-Install.log"

# Features to install (must include Core if using ADDLOCAL)
# Common picks: PCoIP, BlastUDP, RTAV, USB, ClientDriveRedirection, PrintRedir, TSMMR
horizon_agent_features:
  - Core
  - BlastUDP
  - PCoIP
  - RTAV
  - USB
  - ClientDriveRedirection
  - PrintRedir

# Golden image? Skip broker pairing so clones register later.
horizon_skip_broker_registration: true

# If you’re installing on an unmanaged desktop and want immediate registration:
horizon_register_with_broker: false
horizon_connection_servers: []   # e.g. ["cs1.domain.local","cs2.domain.local"]

# Windows Server used as single-user VDI desktop? Set to true to force desktop agent.
horizon_force_desktop_agent_on_server: false

# Enable RDP option in the installer dialog equivalent
horizon_rdp_choice: 1  # 1 = enable RDP, 0 = disable

roles/horizon_agent/tasks/main.yml
- name: Ensure temp directory exists
  ansible.windows.win_file:
    path: 'C:\Temp'
    state: directory

- name: Ensure VMware Tools looks present (recommended prerequisite)
  ansible.windows.win_stat:
    path: 'C:\Program Files\VMware\VMware Tools\vmtoolsd.exe'
  register: vmtools_bin

- name: Warn if VMware Tools not found
  ansible.builtin.debug:
    msg: "Heads up: VMware Tools not found at expected path. Horizon Agent install is supported, but Tools should be installed first."
  when: not vmtools_bin.stat.exists

- name: Download Horizon Agent installer from URL/UNC
  ansible.windows.win_get_url:
    url: "{{ horizon_agent_installer_url }}"
    dest: "{{ horizon_agent_installer_path }}"
  when: horizon_agent_installer_url is defined

- name: (Alternative) Copy installer from control machine
  ansible.windows.win_copy:
    src: "{{ horizon_agent_installer_src }}"
    dest: "{{ horizon_agent_installer_path }}"
  when: horizon_agent_installer_src is defined

- name: Build MSI property string
  ansible.builtin.set_fact:
    horizon_msi_props: >-
      ADDLOCAL={{ horizon_agent_features | join(',') }}
      RDP_CHOICE={{ horizon_rdp_choice }}
      REBOOT=ReallySuppress
      {{ 'VDM_SKIP_BROKER_REGISTRATION=1' if horizon_skip_broker_registration else '' }}
      {{ 'VDM_SERVER_NAME=' + (horizon_connection_servers | join(';')) if horizon_register_with_broker and horizon_connection_servers|length>0 else '' }}
      {{ 'VDM_FORCE_DESKTOP_AGENT=1' if horizon_force_desktop_agent_on_server else '' }}

# Note:
# Horizon Agent EXE wraps MSI. /s makes the wrapper silent; /v"..." passes MSI options.
# /qn for silent, /l*v for verbose log.
- name: Install Omnissa Horizon Agent silently
  ansible.windows.win_package:
    path: "{{ horizon_agent_installer_path }}"
    arguments: '/s /v"/qn /l*v {{ horizon_log_path }} {{ horizon_msi_props | trim }}"'
    state: present
  register: horizon_install

- name: Reboot if the installer requested it
  ansible.windows.win_reboot:
    msg: "Rebooting to complete Omnissa Horizon Agent installation"
    pre_reboot_delay: 5
  when: horizon_install.reboot_required | default(false)

# Quick verification (registry exists + optional broker hostname if registered)
- name: Check Agent registry base
  ansible.windows.win_reg_stat:
    path: 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent'
  register: agent_reg

- name: Check broker hostname (only if registering to broker)
  ansible.windows.win_reg_stat:
    path: 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent\Configuration'
    name: 'BrokerHostname'
  register: broker_reg
  when: horizon_register_with_broker

- name: Report install summary
  ansible.builtin.debug:
    msg:
      - "Horizon Agent registry present: {{ agent_reg.exists }}"
      - "Broker registered to: {{ broker_reg.value | default('N/A') }}"
      - "Installer log: {{ horizon_log_path }}"

playbooks/install_horizon_agent.yml
- name: Install Omnissa Horizon Agent
  hosts: windows
  gather_facts: false
  roles:
    - role: horizon_agent
      vars:
        horizon_agent_installer_url: "\\\\swrepo\\Horizon\\VMware-Horizon-Agent-x86_64-2412.exe"
        horizon_skip_broker_registration: true          # true for golden image
        horizon_register_with_broker: false             # set true for unmanaged desktops
        horizon_connection_servers: ["hzn-cs01.domain.local","hzn-cs02.domain.local"]
        horizon_force_desktop_agent_on_server: false    # set true if Windows Server as single-user VDI
        horizon_agent_features:
          - Core
          - BlastUDP
          - PCoIP
          - RTAV
          - USB
          - ClientDriveRedirection
          - PrintRedir

Notes that matter

Silent switches & features. The Agent supports MSI properties like ADDLOCAL, VDM_SKIP_BROKER_REGISTRATION, VDM_SERVER_NAME, VDM_FORCE_DESKTOP_AGENT, REBOOT=ReallySuppress, etc. Use ADDLOCAL to list features you want (must include Core). Omnissa’s docs cover these properties and examples. 
Omnissa Documentation
+1

Golden images. Use VDM_SKIP_BROKER_REGISTRATION=1 so your clones register at first boot/pool creation instead of the template attempting it. Example usage is shown in community and tech blogs. 
vcloudnine.de

Firewall. The installer can open required local firewall rules for Agent protocols (Blast/PCoIP/RDP). If you harden firewalls later, make sure those rules remain. 
Omnissa Documentation
+1

Services. After install and reboot you should see Horizon Agent/Blast services present and set to Automatic. (Service listing and roles are documented.) 
Omnissa Documentation

MSI semantics. The wrapper uses standard MSI syntax; the /s /v"/qn ..." pattern here is intentional. 
VMware Documentation
 I can tailor the defaults to your exact version (2412/2503), add checksum validation, or wire this into your existing Packer/Ansible golden-image flow.
