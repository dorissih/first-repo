# © Broadcom. All Rights Reserved.
# The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

<#
    .DESCRIPTION
    Performs post-VMware Tools configuration, including:
    - Setting network to private
    - Installing and configuring OpenSSH Server via MSI
    - Resetting autologon count
#>

$ErrorActionPreference = 'Stop'

# Wait for network to be ready
Write-Output "Checking for network profile readiness..."
$maxTries = 12
$try = 0
$connected = $false

while (-not $connected -and $try -lt $maxTries) {
    try {
        $profile = Get-NetConnectionProfile -ErrorAction Stop
        if ($profile.Name -ne 'Identifying...') {
            $connected = $true
        }
    } catch {
        Write-Output "Attempt $try: Network not ready."
    }
    if (-not $connected) {
        Start-Sleep -Seconds 5
        $try++
    }
}

if ($connected) {
    Write-Output "Setting network profile '$($profile.Name)' to Private..."
    Set-NetConnectionProfile -Name $profile.Name -NetworkCategory Private
} else {
    Write-Warning "No valid network connection profile detected. Proceeding with default settings..."
}

# Install OpenSSH Server from MSI
$opensshMsiPath = "F:\OpenSSH-Win64-v9.8.1.0.msi"
if (-Not (Test-Path $opensshMsiPath)) {
    throw "OpenSSH MSI not found at $opensshMsiPath"
}

Write-Output "Installing OpenSSH Server from MSI..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$opensshMsiPath`" /qn"

# Start and configure sshd service
Write-Output "Starting and enabling sshd service..."
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Configure Windows Firewall for OpenSSH
Write-Output "Configuring Windows Firewall rule for OpenSSH..."
if (!(Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (Inbound)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22
} else {
    Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
}

# Reset autologon count (if used in unattend.xml)
Write-Output "Resetting AutoLogonCount..."
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoLogonCount -Value 0

Write-Output "windows-init.ps1 completed successfully."
