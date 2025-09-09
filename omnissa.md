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


ChatGPT said:

You’ll need a CA‑signed TLS (SSL) certificate for the Omnissa (VMware) Horizon Connection Server. Here’s what that means and what it must include:

Certificate Requirements
1. CA‑Signed Server Certificate

You cannot rely on self‑signed certificates for production. The Connection Server requires a standard TLS certificate issued by a trusted Certificate Authority that your clients recognize 
Omnissa Docs
.

2. Full Certificate Chain Installed

You need to install the server certificate plus the entire chain: this means the Intermediate and Root CA certificates, so the server’s chain can be properly validated 
Omnissa Docs
+1
.

3. Matching FQDN/Common Name

The certificate’s Subject Name (or SAN) must exactly match the External URL or FQDN that clients use to connect to the Horizon Connection Server. Mismatch here will trigger “invalid certificate” errors 
Omnissa Community
.

4. Private Key Must Be Exportable

When installing your certificate, ensure the private key is marked as exportable. If it isn’t, the Connection Server won’t accept it 
carlstalhood.com
.

5. Friendly Name “vdm”

Horizon expects the machine identity certificate to have the friendly name vdm. Only one certificate with that friendly name should be present; older ones must be renamed or removed 
theDXT
carlstalhood.com
.

6. FIPS‑Compliant Mode (if applicable)

If your Connection Server is configured for FIPS-compliant mode, the same type of CA‑signed “vdm” certificate still applies—but it must specifically be installed into the Windows certificate store (Local Computer) 
Omnissa Docs
.

Quick Checklist
Step	Requirement	Notes
1	Get a CA-signed certificate (PFX)	Use a public or internal CA
2	Install full chain	Include intermediate and root certs
3	Ensure FQDN matches	External URL must match certificate subject/SAN
4	Mark private key exportable	Essential for import
5	Rename Friendly Name to “vdm”	Only one cert should have this name
6	Restart Connection Server service	Apply the new certificate

Optionally, you can use the Horizon Console (if version 2212 or newer) for certificate management—just be sure you have the Certificate Management privilege and understand how friendly names are handled 
carlstalhood.com
.

If you’re using a Unified Access Gateway (UAG) alongside Connection Server, don’t forget: once the Connection Server certificate is updated, you'll often need to update the certificate thumbprint in the UAG settings so they trust each other 
theDXT
.

Want help crafting a step-by-step based on your Horizon version? Happy to walk through it with you—just let me know your setup!

You said:
my omnissa horizon server appares to be unable some times  what is the cause of this
ChatGPT said:

If your Omnissa Horizon Connection Server appears to be intermittently unavailable, the issue could stem from several areas: certificate problems, DNS resolution, service health, or load balancer issues. Here's a breakdown to help you troubleshoot the likely causes.

🔍 Common Causes of Intermittent Unavailability
1. TLS Certificate Issues

Expired or incorrect certificate: If the cert has expired, is not trusted, or has the wrong FQDN, clients may intermittently fail to connect (especially with different browsers).

Wrong “Friendly Name”: Only one cert should be marked as vdm. Multiple vdm-named certs confuse Horizon.

Check with:

Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq "vdm" }

2. Connection Server Service Crashing or Delayed Start

If the VMware Horizon Connection Server service (wsbroker) stops or crashes, it becomes unavailable until restarted.

Delayed starts due to slow AD authentication or policy processing can also cause downtime.

Check with:

Get-Service -Name wsbroker


Also check Windows Event Viewer:
Application and System logs → Filter for vmware-* or wsbroke* related errors

3. DNS or FQDN Mismatch

If DNS isn’t resolving the FQDN properly, especially across VLANs or domains, some clients may fail to connect.

Ensure forward and reverse lookups are correct for the Horizon FQDN.

nslookup horizon.company.com
ping horizon.company.com

4. Load Balancer or Reverse Proxy Issues

If you're using a load balancer, UAG, or reverse proxy, issues may include:

Incorrect health checks (LB thinks server is alive when it's not).

Stickiness misconfiguration.

TLS termination errors (wrong cert passed to client).

HTTP 421 errors: Typically from Host header or SNI mismatches.

Fixes:

Ensure LB health check hits /favicon.ico or /portal/webclient/index.html.

Confirm certs match on both LB and backend if TLS is terminated.

5. Firewall / Port Blocking

If a firewall or endpoint security is closing Horizon ports (443, 8443, 4172, etc.), you’ll see intermittent timeouts.

Use:

Test-NetConnection -ComputerName <fqdn> -Port 443

6. High Resource Usage or Memory Leaks

Horizon Connection Server can become unresponsive if the server is under-resourced:

Not enough RAM or CPU.

Java heap space exhaustion.

Check:

Task Manager (memory/CPU spikes).

vmware-*.log files in C:\ProgramData\VMware\VDM\logs.

7. LDAP or AD Authentication Issues

If the server cannot reach your AD or the bind account is failing, login sessions will hang or fail.

Make sure time is synced (Kerberos relies on clock sync).

Check vdm-sdctask logs for LDAP or bind errors.

🛠️ How to Start Troubleshooting
Step	Action
1	Run services.msc and check if VMware Horizon Connection Server is always running
2	Check Event Viewer under Application + System logs
3	Verify certificate (valid, trusted, friendly name is vdm)
4	Run nslookup and ping on your Horizon FQDN
5	Check CPU/RAM usage during outages
6	Review C:\ProgramData\VMware\VDM\logs
7	If using UAG or LB, check load balancer logs and SNI passthrough settings
Optional: Enable Horizon REST API Health Checks

You can script or monitor Horizon server health via REST API if you're on 2303+:

Invoke-RestMethod -Uri "https://<hzn-server>/rest/monitoring/service-status" -UseBasicParsing


If you tell me:

What version of Horizon you're using

Whether you're using Unified Access Gateway or Load Balancer

If this happens after a certain time (e.g., after reboots, cert changes, etc.)

…I can give you a more targeted checklist or even a PowerShell script to automate checks.

You said:
a member of my team can not login to the connection server but others can login what can cause this
ChatGPT said:

If only one team member can’t log in to the Omnissa Horizon Connection Server, but everyone else can, then the issue is specific to that user or their device. Here are the most likely causes, grouped by category:

🔐 1. User-Specific Certificate Trust Issues

If your Horizon Connection Server uses a CA-signed certificate, and:

The user’s system doesn’t trust the CA (root or intermediate),

Or the certificate has SAN/FQDN mismatch and that user’s browser or Horizon Client is stricter,

Then: Only that user will be blocked with a TLS/security error.

🔍 Check:

Can they access the URL in Firefox, Edge, or Chrome?

Any “Your connection is not private” or “SEC_ERROR_UNKNOWN_ISSUER” messages?

Is the root or intermediate CA missing on their system?

👤 2. Active Directory Account Problems

If Horizon is integrated with AD:

The user’s account may be locked out, expired, or in the wrong OU/group.

Some pools use entitlement-based access: if they’re not entitled, they won’t see anything.

🔍 Check:

Is the user in the correct AD group (HorizonAccess, VDI-Users, etc.)?

Can they log in to a regular domain-joined PC using the same credentials?

Use PowerShell:

Get-ADUser -Identity "username" | Select-Object Enabled, LockedOut

🪪 3. Entitlement Missing

Even if they authenticate successfully, if they’re not entitled to any pool, Horizon will show a blank screen or error.

🔍 Fix:

Go to Horizon Console → Inventory → Desktops (or Farms) → Pool → Entitlements

Add the user or their AD group

🧱 4. Local Machine or Horizon Client Issue

It could be a local Horizon Client problem:

Outdated Horizon Client version

Client not trusting the cert

Firewall or VPN interfering

🔍 Steps:

Try from another device using the same account

Reinstall the Horizon Client

Try using the web portal (https://fqdn-of-horizon-server
)

🌐 5. DNS Resolution or Network Access

Sometimes a single user's device can’t resolve the FQDN of the Horizon server due to:

DNS misconfiguration

Split DNS not working

Local /etc/hosts override

🔍 Try:
nslookup horizon.company.com
ping horizon.company.com

🧪 6. Two-Factor or Conditional Access Failing

If you’re using MFA (Duo, RSA, etc.) or conditional access:

That user might be missing registration

Might be failing policy requirements (IP block, device posture)

🪵 7. Review Logs for the User

On the Connection Server, check:

vdm-sdctask.log

debug-*.log

Filter for the username to see if authentication started and failed.

You can find logs here:

C:\ProgramData\VMware\VDM\logs\

✅ What You Should Do
Check	What to Look For
Horizon Client	Can they log in from another machine?
AD Account	Not locked out? Belongs to correct group?
Entitlements	Are they added to the correct pool?
Certificate Trust	Is there a trust issue on their machine?
Firewall/VPN	Any restrictions blocking ports (443, 4172, etc.)
Logs	What does Horizon say about the failed login?

Let me know:

What version of Horizon you’re using

Whether you use MFA

If the user gets any specific error code (like Invalid Credentials vs. No resources available vs. Unable to connect)

I can help you narrow it down more or even write a script to check cert trust or entitlement.


I am still getting a certificate version 3 despite create a certificate template as described in the omnissa certificate template creation page 
https://docs.omnissa.com/bundle/HorizonDaaSTenantAdministrationV9.2.0/page/SetUpaCertificateTemplateontheCA.html
ChatGPT said:
Thought for 33s

Short answer: nothing’s wrong with your cert. You’re mixing up two different “versions.”

X.509 certificate version (what you see in the cert details) — for any modern TLS cert, this is Version 3 and that’s exactly what Horizon/vSphere expect. You cannot (and shouldn’t) make an X.509 v2 TLS cert; v3 is the current standard and supports SANs, EKUs, etc. 
Broadcom TechDocs
+1
Microsoft Learn

Windows “certificate template version” — this is the AD CS template schema (v1/v2/v3) you pick in certtmpl.msc via the Compatibility tab. Choosing a v2 template does not make the issued certificate “X.509 v2”; the issued cert will still be X.509 v3. 
Microsoft Learn

What Horizon actually needs

For Connection Server / UAG / Agents, use a normal X.509 v3 server cert issued from a template with sane settings (SHA-256, RSA 2048+). Omnissa docs and Tech Zone materials focus on the template (KSP/CSP, EKUs, etc.), not changing the X.509 version. 
Omnissa Docs
Tech Zone

Template checklist (recommended):

Compatibility (template version): Windows Server 2008 R2 or later (lets you use KSP). If your org requires “legacy CSP,” pick Microsoft Enhanced RSA and AES Cryptographic Provider (supports SHA-256). 
Omnissa Docs
+1

Cryptography: RSA, 2048 or 3072 bits; Signature hash = SHA-256. 
Omnissa Docs

Subject name: Supply in the request; CN = FQDN of the Horizon component.

SAN: DNS = FQDN (and short name if used). Modern clients rely on SAN, not CN. (This requires X.509 v3 — again, expected.) 
Information Security Stack Exchange

EKUs: Server Authentication (1.3.6.1.5.5.7.3.1). If you’re doing device/client auth scenarios, add the relevant EKUs per Omnissa docs. 
Omnissa Community

Private key: exportable No (typical), allow private key, key usage Digital Signature and Key Encipherment.

How to confirm you’re good

On the Horizon server, open certlm.msc → Personal → Certificates → your cert → Details and check:

Version: “V3” (this is expected)

Signature hash algorithm: sha256RSA

Public key: RSA 2048+

Enhanced Key Usage: includes Server Authentication

Subject / SAN: match the server’s FQDN
All of that is normal for Horizon’s TLS. 
Omnissa Docs

If your goal was a “v2 template”

That’s only about the AD CS template schema (auto-enroll support, etc.). Set it in certtmpl.msc → Duplicate Template → Compatibility to older CA/OS levels to force a template v2. The issued cert will still be X.509 v3, which is correct. 
Microsoft Learn

If you share a screenshot of your current template’s Compatibility tab and Request Handling/Cryptography/EKU tabs, I can spot-check the exact fields you might need to tweak for Horizon.

You said:
so what about the SHA being 384?
ChatGPT said:
Thought for 27s

Short version: SHA-384 is fine for Horizon, but SHA-256 is the safest default. If you’re seeing SHA-384 and want SHA-256 instead, that choice lives on the CA, not the template.

What Horizon/UAG supports

Omnissa documents list SHA-256, SHA-384, and SHA-512 as supported hash sizes (SHA-1 discouraged). So Horizon/UAG won’t break just because your cert is sha384RSA. 
Omnissa Docs
+2
Omnissa Docs
+2

Why you got SHA-384

The signature hash algorithm on issued certs (sha256RSA vs sha384RSA) is determined by the CA’s configuration and key provider, not by the certificate template. A template can affect the request signature, but the CA signs the certificate using whatever it’s configured to use. 
PKI Solutions
Server Fault

If you want SHA-256 instead

Change the CA’s hash algorithm, renew the CA cert (if required), and re-issue the Horizon server cert:

Check current CA settings (GUI shows KSP/CSP and hash): Certification Authority → right-click CA → Properties → view current CA certificate. 
Microsoft Learn

Set CA to SHA-256 (KSP/CNG): e.g., certutil -setreg ca\csp\CNGHashAlgorithm SHA256, then renew the CA certificate and restart the service. (Plan impact on the chain if you’re changing the CA cert.) 
TECHCOMMUNITY.MICROSOFT.COM
SysAdmins

Re-issue the Horizon cert from your (unchanged) web-server template; the issued cert will now be sha256RSA.

UAG thumbprints: if you use UAG, its “Minimum SHA Hash Size”/thumbprint settings accept SHA-256/384/512; SHA-256 is the recommended minimum. 
Omnissa Docs
+1

Legacy note (only if you truly have 2003-era systems)

Windows Server 2003 needs specific updates to handle SHA-2 at all; SHA-384/512 are especially troublesome there. If you have any such stragglers, stick to SHA-256 and ensure SHA-2 updates are installed. 
Server Fault
DigiCert Knowledge Base
Cloud Direct

Bottom line: For Horizon, SHA-256 or SHA-384 both work. Choose SHA-256 unless your security policy explicitly requires SHA-384/512, and set it on the CA, not the template.

You said:
when creating the cert can i add the option to give a SHA 256 instead on 384
ChatGPT said:
Thought for 18s

Short answer: not on the request. In AD CS, the signature hash for issued certs (sha256RSA vs sha384RSA) is chosen by the CA, not by the certificate template or the individual request. To get SHA-256, set the CA to use SHA-256, then re-issue the cert. 
PKI Solutions

What to do (CA side)

Check current setting

certutil -getreg ca\csp\CNGHashAlgorithm


If it shows SHA384, your CA is signing issued certs with SHA-384. 
docs.securosys.com

Switch to SHA-256

certutil -setreg ca\csp\CNGHashAlgorithm SHA256
net stop certsvc
net start certsvc


(Some environments will also renew the CA certificate so the CA itself is SHA-256; plan that change window.) 
PeteNetLive
Microsoft Learn

(Optional but recommended) If you ever ran with RSASSA-PSS and hit VMware/Omnissa import issues, ensure you’re on sha256RSA, not PSS, before renewing the CA. 
Derek Seaman's Tech Blog

Re-issue your Horizon/Connection Server cert from the same web-server template. The new issued cert will now show Signature hash algorithm: sha256RSA. Per-template control of the signature hash isn’t a thing in AD CS. 
PKI Solutions

Horizon context

Horizon/UAG accept SHA-256/384/512, but SHA-256 is the safest default and maximizes compatibility with older clients and tools. 
Omnissa Docs

If you want, tell me your CA OS version (2012 R2/2016/2019/2022), CSP/KSP, and whether you use an HSM, and I’ll tailor exact renewal steps (including CAPolicy.inf tips like disabling alternate signatures). 
michaelwaterman.nl

You said:
like using this command certreq -submit -attrib  "Certificatetemplate:Webservers" Something.csr 
then add the option for the SHA 256
ChatGPT said:
Thought for 10s

Short answer: No—certreq -submit -attrib "CertificateTemplate:WebServer" can’t force SHA-256. The hash on the issued cert is chosen by the CA’s signing setting, not by the request/attributes. To get SHA-256, change the CA’s hash algorithm and reissue. 
Server Fault
Microsoft Learn

What actually works

Set the CA to SHA-256 (server-wide):

certutil -setreg ca\csp\CNGHashAlgorithm SHA256
net stop certsvc
net start certsvc


(Some environments also renew the CA cert afterward.) 
Microsoft Learn
+1

Re-issue your Horizon cert from the same template. It will now show Signature hash algorithm: sha256RSA because the CA is signing with SHA-256. 
Server Fault

Optional: sign the request with SHA-256 (for completeness)

This affects only the CSR’s signature, not the CA’s signature on the issued cert:

; request.inf
[Version]
Signature="$Windows NT$"

[NewRequest]
Subject = "CN=hzn.example.com"
KeyLength = 2048
KeySpec = 1
KeyAlgorithm = RSA
Exportable = FALSE
HashAlgorithm = sha256      ; CSR hash only
MachineKeySet = TRUE
RequestType = PKCS10

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=hzn.example.com&"

certreq -new request.inf request.req
certreq -submit -attrib "CertificateTemplate:WebServer" request.req


The issued cert’s hash still follows the CA setting above. 
Microsoft Learn
+1
PKI Solutions

If you want, tell me the CA OS version (2016/2019/2022) and whether it’s KSP/CSP or HSM-backed, and I’ll tailor the exact renewal steps (including avoiding RSASSA-PSS if any downstream appliances are picky). 
Derek Seaman's Tech Blog

You said:
i am using a windows 2022 server
ChatGPT said:
Thought for 7s

Got it — since you’re on Windows Server 2022 AD CS, here’s the clean, CA-side way to make all issued certs come out as SHA-256 (sha256RSA) instead of SHA-384.

TL;DR

You can’t force SHA-256 from certreq or the template. Set the CA’s signing hash to SHA-256, restart the CA service, and (if needed) renew the CA certificate, then re-issue your Horizon cert. 
Microsoft Learn

Step-by-step on the CA (Server 2022)

Check the CA’s current signing hash

certutil -getreg ca\csp\CNGHashAlgorithm


If it returns SHA384, your CA is signing issued certs with SHA-384. 
Evotec

Switch the CA to SHA-256

certutil -setreg ca\csp\CNGHashAlgorithm SHA256
net stop certsvc
net start certsvc


This changes the hash the CA uses when it signs issued certs. 
Evotec

(Often required) Renew the CA certificate

Open Certification Authority → right-click your CA → All Tasks → Renew CA Certificate… → choose Same key (usually fine) unless you’re rotating keys.

Follow the wizard; the new CA cert will be signed with SHA-256. After renewal, distribute the updated CA cert to clients (GPO/MDM, etc.). 
Microsoft Learn
+1

Avoid the RSASSA-PSS surprise (VMware/Omnissa)
If your CA was configured to issue RSASSA-PSS signatures, Horizon/vSphere appliances can choke on the chain. Ensure you’re on sha256RSA (PKCS#1 v1.5), not PSS, before you renew. 
Derek Seaman's Tech Blog

CAPolicy.inf (only if you’re renewing/standing up a CA)
If you use a CAPolicy.inf during renewal, don’t enable the alternate signature format:

[Certsrv_Server]
AlternateSignatureAlgorithm=0


Enabling it can break non-Windows or older clients. Place CAPolicy.inf in C:\Windows\ before renewal if you need to control CA behavior. 
Microsoft Learn
+1
Server Fault

Re-issue your Horizon/Connection Server cert
Submit the same way you already do:

certreq -submit -attrib "CertificateTemplate:WebServer" request.req


The issued cert will now show Signature hash algorithm: sha256RSA because the CA is set to SHA-256. (Templates/certreq can’t override the CA’s signing hash.) 
Microsoft Learn

How to verify

On the issuing CA: Certification Authority → Properties → View Certificate shows the CA cert’s Signature hash algorithm (should be SHA-256 after renewal). 
Microsoft Learn

On the Horizon server: certlm.msc → Personal → Certificates → your cert → Details → Signature hash algorithm should read sha256RSA.

If you tell me whether your CA key is software KSP or HSM-backed, I can tailor the renewal choice (same key vs new key) and any extra HSM steps.

Got it. That error usually means your environment’s firewall module doesn’t recognize the enabled parameter (older community.windows/ansible.windows versions) or it’s using a different FQCN. Two solid fixes below—pick one.

Fix A — Use the firewall module, but compatible with older collections

Call the module by its fully qualified name, and

Drop enabled: (most versions create rules enabled by default).

- name: Open inbound ports for Horizon (module path + no 'enabled')
  community.windows.win_firewall_rule:
    name: "{{ item.name }}"
    localport: "{{ item.port }}"
    protocol: "{{ item.protocol }}"
    action: allow
    direction: in
    state: present
    profile: any
  loop:
    - { name: 'Horizon Blast TCP 8443', port: 8443, protocol: tcp }
    - { name: 'Horizon Blast TCP 8444', port: 8444, protocol: tcp }
    - { name: 'Horizon Blast TCP 443',  port: 443,  protocol: tcp }
    - { name: 'Horizon Blast UDP 8443', port: 8443, protocol: udp }
    - { name: 'PCoIP TCP 4172',        port: 4172, protocol: tcp }
    - { name: 'PCoIP UDP 4172',        port: 4172, protocol: udp }
    - { name: 'RDP TCP 3389',          port: 3389, protocol: tcp }


If your collection is ansible.windows, switch the FQCN to ansible.windows.win_firewall_rule.

Fix B — PowerShell fallback (works everywhere, idempotent)

This bypasses module-version quirks entirely and ensures rules are enabled.

- name: Define Horizon firewall rules
  vars:
    horizon_fw_rules:
      - { name: 'Horizon Blast TCP 8443', port: 8443, proto: 'TCP' }
      - { name: 'Horizon Blast TCP 8444', port: 8444, proto: 'TCP' }
      - { name: 'Horizon Blast TCP 443',  port: 443,  proto: 'TCP' }
      - { name: 'Horizon Blast UDP 8443', port: 8443, proto: 'UDP' }
      - { name: 'PCoIP TCP 4172',        port: 4172, proto: 'TCP' }
      - { name: 'PCoIP UDP 4172',        port: 4172, proto: 'UDP' }
      - { name: 'RDP TCP 3389',          port: 3389, proto: 'TCP' }

- name: Ensure inbound rules exist and are enabled (PowerShell)
  ansible.windows.win_powershell:
    parameters:
      DisplayName: "{{ item.name }}"
      Port: "{{ item.port }}"
      Protocol: "{{ item.proto }}"
    script: |
      param(
        [string]$DisplayName,
        [int]$Port,
        [ValidateSet('TCP','UDP')][string]$Protocol
      )

      $rule = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
      if (-not $rule) {
        New-NetFirewallRule `
          -DisplayName $DisplayName `
          -Direction Inbound `
          -Action Allow `
          -Enabled True `
          -Profile Any `
          -Protocol $Protocol `
          -LocalPort $Port | Out-Null
        Write-Output "created"
      }
      else {
        # Make sure it stays enabled and matches desired settings
        Set-NetFirewallRule -DisplayName $DisplayName -Enabled True -Action Allow -Direction Inbound -Profile Any | Out-Null
        Set-NetFirewallRule -DisplayName $DisplayName -NewDisplayName $DisplayName | Out-Null
        Set-NetFirewallRule -DisplayName $DisplayName | Out-Null
        Set-NetFirewallRule -DisplayName $DisplayName -PolicyStore ActiveStore | Out-Null
        Set-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue | Out-Null

        # Update port/protocol if needed (requires filter on rule’s associated port filter)
        $filters = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        if ($filters.LocalPort -ne "$Port" -or $filters.Protocol -ne $Protocol) {
          # Remove and recreate to make it exact
          Remove-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
          New-NetFirewallRule `
            -DisplayName $DisplayName `
            -Direction Inbound `
            -Action Allow `
            -Enabled True `
            -Profile Any `
            -Protocol $Protocol `
            -LocalPort $Port | Out-Null
          Write-Output "recreated"
        }
        else {
          Write-Output "ok"
        }
      }
  loop: "{{ horizon_fw_rules }}"
  register: fw_result
  changed_when: "'created' in fw_result.stdout or 'recreated' in fw_result.stdout"

# Optional: show a short summary
- name: Firewall update summary
  ansible.builtin.debug:
    var: fw_result.results | map(attribute='stdout') | list

Quick tips

Run with elevation:

become: yes
become_method: runas
vars:
  ansible_become_user: Administrator


If you already have similarly named GPO-pushed rules, use unique names (e.g., prefix with HZN:) to avoid collisions.

If you don’t want RDP open, just remove the 3389 entry.

Want me to fold this into your existing horizon_agent role and add outbound (egress) rules for Agent→Connection Server too?



- name: Check Horizon Agent status
  win_service_info:
    name: "VMwareViewAgent"
  register: viewagent_status

- debug:
    var: viewagent_status

