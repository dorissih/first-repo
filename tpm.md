

vTPM

Add vTPM after Packer builds the base template (or right after you clone to a “gold image” VM).

Reason: adding a vTPM requires a vSphere Key Provider and changes the VM’s encryption state. Keeping the base template neutral avoids key-provider coupling and lets you reuse it anywhere.

Implementation detail: you can’t add devices to a template. Either:

Clone the template to a VM (your “gold image”), power it off, add vTPM, then snapshot/seal it, or

Temporarily convert template → VM, add vTPM, then convert back to template.

Prereqs in vSphere: a configured/trusted Native Key Provider (NKP) or external KMS, the VM must be UEFI firmware (Secure Boot optional but recommended), and the VM must be powered off to attach vTPM.

FIPS mode (Windows)

Do not enable FIPS in the base template. Put it at the gold image stage (targeted images only) or apply via GPO to specific OUs. Microsoft guidance is that FIPS mode can break some crypto implementations; turning it on everywhere often causes surprises.

Enabling FIPS is a policy/registry switch + reboot. Easy to automate per-image or per-OU once you’ve tested your app set.

Ansible-friendly automation patterns
1) Add vTPM from your Ansible control node (PowerCLI)

Ansible doesn’t have a first-class “add TPM” VMware module yet, so call PowerCLI from your control node. This play targets localhost and runs PowerShell:

---
- name: Attach vTPM to Win11 gold images
  hosts: localhost
  gather_facts: no

  vars:
    vcenter_server: "vcsa.example.local"
    vcenter_user: "svc-ansible@vsphere.local"
    vcenter_password: "{{ vault_vcenter_password }}"
    vm_names:
      - "WIN11-GOLD-2025-08"
      - "WIN11-GOLD-ENG"

  tasks:
    - name: Ensure PowerCLI is available
      ansible.builtin.command: pwsh -NoLogo -Command "Get-Module VMware.PowerCLI -ListAvailable"
      changed_when: false

    - name: Add vTPM to each VM if missing
      ansible.builtin.shell: |
        pwsh -NoLogo -Command @'
        Import-Module VMware.PowerCLI
        Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -Confirm:$false | Out-Null
        $secure = ConvertTo-SecureString "{{ vcenter_password }}" -AsPlainText -Force
        $cred   = New-Object System.Management.Automation.PSCredential("{{ vcenter_user }}", $secure)
        Connect-VIServer -Server "{{ vcenter_server }}" -Credential $cred | Out-Null

        foreach ($name in {{ vm_names | to_json }}) {
          $vm = Get-VM -Name $name -ErrorAction Stop

          # Ensure UEFI firmware (best for Win11 + Secure Boot)
          if ($vm.ExtensionData.Config.Firmware -ne "efi") {
            Set-VM -VM $vm -Firmware efi -Confirm:$false | Out-Null
          }

          # Must be powered off to attach vTPM
          if ($vm.PowerState -ne "PoweredOff") { Stop-VM -VM $vm -Confirm:$false | Out-Null }

          # Add vTPM if not present
          $hasTpm = Get-VTpm -VM $vm -ErrorAction SilentlyContinue
          if (-not $hasTpm) {
            New-VTpm -VM $vm | Out-Null
          }

          # (Optional) turn on Secure Boot
          $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
          $spec.bootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
          $spec.bootOptions.EfiSecureBootEnabled = $true
          $vm.ExtensionData.ReconfigVM($spec)

          Write-Host "vTPM present and Secure Boot set for $name"
        }
        '@
      args:
        executable: /bin/bash


Notes

Requires PowerCLI ≥ 12.5 (the Get-VTpm/New-VTpm cmdlets).

Make sure your cluster has an NKP/KMS. If not, New-VTpm will fail.

Keep vCenter creds in Ansible Vault.

2) Enable Windows FIPS mode on the gold image (per-host)

Run this against the Windows gold image VM (not the base template), or scope it with an inventory group so you only flip it where intended.

---
- name: Enable FIPS on Windows 11 (gold images only)
  hosts: win_gold
  gather_facts: no

  vars:
    enable_fips: true  # set to false to ensure it's OFF

  tasks:
    - name: Set FIPS registry key
      ansible.windows.win_regedit:
        path: HKLM:\System\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy
        name: Enabled
        type: dword
        data: "{{ 1 if enable_fips else 0 }}"

    - name: Also set via Local Security Policy (for clarity)
      ansible.windows.win_security_policy:
        section: System Cryptography
        key: "Use FIPS compliant algorithms for encryption, hashing, and signing"
        value: "{{ 'enabled' if enable_fips else 'disabled' }}"

    - name: Reboot if required
      ansible.windows.win_reboot:
        msg: "Rebooting to apply FIPS setting"

Recommended build flow

Packer (base template)

Win11 installed, updates, VMXNET3, VMware Tools, base hardening.

No vTPM, no FIPS here. Keep it portable.

Clone to “gold image” VM

Generalize/seal steps you usually do after clone.

Ansible: vSphere step (localhost)

Power off VM, attach vTPM (PowerCLI), enable UEFI + Secure Boot.

Snapshot if you use a “pre-seal” snapshot.

Ansible: Windows step (win host)

Optional: enable FIPS (only if this gold image needs it).

Run app compatibility tests; if all green, seal/capture the image.

Publish

Convert back to template or capture to your image catalog.

Quick decision guide

vTPM: add at gold image (or convert template→VM→template).

FIPS: enable per gold image or via GPO, not in the base template.

If you want, I can fold these into a single Ansible playbook with variables like add_vtpm: true/false and enable_fips: true/false, plus a small precheck that fails early if the vSphere Key Provider isn’t configured.

Perfect—that’s exactly what we want. With EFI + Secure Boot in place, here’s how to line it up with the vTPM + FIPS plan:

What this changes (and what to watch)

vTPM add-on: still add it after you clone the template to a gold image. EFI-Secure is already compatible; the VM just needs to be powered off and your cluster must have an NKP/KMS.

Secure Boot side effects: only signed boot-time drivers will load. Make sure any storage/NIC drivers and tooling you bake in are properly signed (Windows/VMware Tools are fine).

VBS/Credential Guard: with Secure Boot + vTPM, enabling VBS is straightforward later via GPO or Ansible if you choose. Test app compatibility first.

BitLocker: if you plan to enable it, do it after vTPM is attached so keys bind to the TPM.

Quick PowerCLI task (idempotent)

Drop this into your Ansible “localhost” step to enforce EFI + Secure Boot and attach vTPM only if missing:

Import-Module VMware.PowerCLI
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -Confirm:$false | Out-Null
$cred = New-Object pscredential("{{ vcenter_user }}", (ConvertTo-SecureString "{{ vcenter_password }}" -AsPlainText -Force))
Connect-VIServer -Server "{{ vcenter_server }}" -Credential $cred | Out-Null

$vm = Get-VM -Name "{{ gold_vm_name }}" -ErrorAction Stop

# Ensure EFI firmware
if ($vm.ExtensionData.Config.Firmware -ne "efi") {
  if ($vm.PowerState -ne "PoweredOff") { Stop-VM -VM $vm -Confirm:$false | Out-Null }
  Set-VM -VM $vm -Firmware efi -Confirm:$false | Out-Null
}

# Ensure Secure Boot ON
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.bootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
$spec.bootOptions.EfiSecureBootEnabled = $true
$vm.ExtensionData.ReconfigVM($spec)

# Attach vTPM if missing
if (-not (Get-VTpm -VM $vm -ErrorAction SilentlyContinue)) {
  if ($vm.PowerState -ne "PoweredOff") { Stop-VM -VM $vm -Confirm:$false | Out-Null }
  New-VTpm -VM $vm | Out-Null
}
Write-Host "EFI + Secure Boot enforced, vTPM present."

Packer/template notes (since you’re on EFI-Secure)

Keep the base template EFI-Secure but without vTPM and without FIPS. That keeps it portable and avoids tying it to a key provider.

In your Packer builder, confirm:

Firmware/boot is UEFI.

Secure Boot is enabled (or enable it post-clone with the script above if your builder can’t).

After clone to gold:

Run the PowerCLI step to attach vTPM and confirm Secure Boot is on.

If this image needs it, run the Windows play to enable FIPS (registry + policy + reboot).

Optional: enable VBS once app testing passes.
