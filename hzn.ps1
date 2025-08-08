<# 
.SYNOPSIS
Create an automated instant-clone desktop pool in Horizon via REST, then entitle users/groups.

.REQUIREMENTS
- PowerShell 7+
- Network access to Horizon Connection Server (HTTPS/443)
- Account with Horizon admin rights

#>

param(
  # ======== CONFIG: Horizon ========
  [string]$HznServer = "https://hzn-conn01.mycorp.com",
  [string]$HznDomain = "MYCORP",            # NetBIOS or short name accepted by /rest/login
  [string]$HznUser   = "administrator",
  [securestring]$HznPassword = $(Read-Host "Horizon password" -AsSecureString),

  # ======== CONFIG: Pool basics ========
  [string]$PoolName  = "ENG-IC-Pool01",
  [string]$PoolDisplayName = "Engineering Instant Clone",
  [ValidateSet("DEDICATED","FLOATING")] [string]$UserAssignment = "FLOATING",
  [ValidateSet("PATTERN","SPECIFIED")] [string]$NamingMethod = "PATTERN",
  [string]$NamingPattern = "eng-ic-{n}",   # used when NamingMethod=PATTERN
  [int]$MinVMs = 2,
  [int]$MaxVMs = 10,
  [int]$SpareVMs = 1,

  # ======== CONFIG: vCenter & image bits (names, not IDs) ========
  [string]$VcName = "vcsa01.mycorp.com",
  [string]$DatacenterName = "DC1",
  [string]$ClusterName = "Compute-Cluster",
  [string]$ResourcePoolName = "Resources",  # often "Resources" at the cluster root
  [string]$VmFolderName = "Horizon-VDI",
  [string]$DatastoreName = "vsanDatastore",
  [string]$BaseVmName = "Win11-Gold",
  [string]$SnapshotName = "IC-Ready",

  # If you want to pin NIC network labels (optional). Leave empty to skip.
  [string]$NetworkLabelName = "VM Network",

  # ======== CONFIG: IC Domain Account & OU (optional) ========
  # If you have multiple IC domain accounts, set the username to pick the right one.
  [string]$IcAccountUsername = "svc-hzn-ic",
  # Optionally place computer objects into a specific OU: "OU=VDI,OU=Computers,DC=mycorp,DC=com"
  [string]$AdContainerRdn = "CN=Computers",

  # ======== CONFIG: Access Group (recommended) ========
  [string]$AccessGroupName = "Engineering",

  # ======== CONFIG: Entitlements (SAM account names or groups; will resolve to SIDs) ========
  [string[]]$EntitleUsersOrGroups = @("ENG-VDI-Users","[email protected]"),

  # ======== OTHER ========
  [switch]$IgnoreCert
)

# ---------- Helpers ----------
function ConvertFrom-SecureStringPlain {
  param([securestring]$Secure)
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

if ($IgnoreCert) {
  add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

$baseUri = $HznServer.TrimEnd('/')

function Invoke-Hzn {
  param(
    [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')]$Method,
    [Parameter(Mandatory)][string]$Path,   # starts with /rest/...
    $Body,
    $Query
  )
  $uri = if ($Query) { "$baseUri$Path?$(($Query.GetEnumerator() | ForEach-Object { '{0}={1}' -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value) }) -join '&')" } else { "$baseUri$Path" }
  $params = @{
    Method = $Method
    Uri    = $uri
    Headers = @{ Authorization = "Bearer $script:Token" }
  }
  if ($Body) { $params.ContentType = "application/json"; $params.Body = ($Body | ConvertTo-Json -Depth 20) }
  try {
    Invoke-RestMethod @params
  } catch {
    throw "REST error $Method $Path : $($_.Exception.Message)`nResponse: $($_.ErrorDetails?.Message)"
  }
}

# ---------- Login (/rest/login) ----------
# Returns { access_token, refresh_token }
# Ref: Horizon Auth API operation index shows Login User in the Auth category
# (bearer used on all subsequent calls).
$pwdPlain = ConvertFrom-SecureStringPlain $HznPassword
try {
  $login = Invoke-RestMethod -Method POST -Uri "$baseUri/rest/login" -ContentType "application/json" -Body (@{
    username = $HznUser
    password = $pwdPlain
    domain   = $HznDomain
  } | ConvertTo-Json)
} catch {
  throw "Login failed: $($_.Exception.Message)`nEnsure the server URL and creds/domain are correct."
}
$script:Token = $login.access_token
if (-not $Token) { throw "No access_token returned from /rest/login" }

Write-Host "Authenticated to Horizon at $($HznServer)" -ForegroundColor Green

# ---------- Name → ID lookups (External + Config APIs) ----------
# vCenter
$vc = Invoke-Hzn -Method GET -Path "/rest/config/v1/virtual-centers" | Where-Object { $_.server_name -eq $VcName -or $_.display_name -eq $VcName }
if (-not $vc) { throw "vCenter '$VcName' not found." }                                      # :contentReference[oaicite:1]{index=1}
$vcId = $vc.id

# Datacenter
$dc = Invoke-Hzn -Method GET -Path "/rest/external/v1/datacenters" -Query @{ vcenter_id = $vcId } | Where-Object { $_.name -eq $DatacenterName }
if (-not $dc) { throw "Datacenter '$DatacenterName' not found." }                            # :contentReference[oaicite:2]{index=2}
$dcId = $dc.id

# Cluster (HostOrCluster)
$hoc = Invoke-Hzn -Method GET -Path "/rest/external/v1/hosts-or-clusters" -Query @{ vcenter_id=$vcId; datacenter_id=$dcId } | Where-Object { $_.details.name -eq $ClusterName -and $_.details.cluster }
if (-not $hoc) { throw "Cluster '$ClusterName' not found." }                                 # :contentReference[oaicite:3]{index=3}
$clusterId = $hoc.id

# Resource Pool
$rp = Invoke-Hzn -Method GET -Path "/rest/external/v1/resource-pools" -Query @{ vcenter_id=$vcId; host_or_cluster_id=$clusterId } | Where-Object { $_.name -eq $ResourcePoolName }
if (-not $rp) { throw "Resource Pool '$ResourcePoolName' not found." }                       # :contentReference[oaicite:4]{index=4}
$rpid = $rp.id

# VM Folder
$folder = Invoke-Hzn -Method GET -Path "/rest/external/v1/vm-folders" -Query @{ vcenter_id=$vcId; datacenter_id=$dcId } | Where-Object { $_.name -eq $VmFolderName }
if (-not $folder) { throw "VM Folder '$VmFolderName' not found." }                           # :contentReference[oaicite:5]{index=5}
$folderId = $folder.id

# Datastore
$ds = Invoke-Hzn -Method GET -Path "/rest/external/v1/datastores" -Query @{ vcenter_id=$vcId; host_or_cluster_id=$clusterId } | Where-Object { $_.name -eq $DatastoreName }
if (-not $ds) { throw "Datastore '$DatastoreName' not found." }                              # :contentReference[oaicite:6]{index=6}
$datastoreId = $ds.id

# Base VM (image) and Snapshot
$baseVm = Invoke-Hzn -Method GET -Path "/rest/external/v2/base-vms" -Query @{ vcenter_id=$vcId } | Where-Object { $_.name -eq $BaseVmName }
if (-not $baseVm) { throw "Base VM '$BaseVmName' not found." }                               # :contentReference[oaicite:7]{index=7}
$baseVmId = $baseVm.id

$snap = Invoke-Hzn -Method GET -Path "/rest/external/v2/base-snapshots" -Query @{ vcenter_id=$vcId; base_vm_id=$baseVmId } | Where-Object { $_.name -eq $SnapshotName }
if (-not $snap) { throw "Snapshot '$SnapshotName' on '$BaseVmName' not found." }             # :contentReference[oaicite:8]{index=8}
$snapshotId = $snap.id

# NICs (optional — attach a network label from the base VM snapshot)
$nicSpecs = @()
if ($NetworkLabelName) {
  $nics = Invoke-Hzn -Method GET -Path "/rest/external/v2/network-interface-cards" -Query @{ vcenter_id=$vcId; base_vm_id=$baseVmId; base_snapshot_id=$snapshotId }
  if ($nics) {
    foreach ($nic in $nics) {
      $nicSpecs += @{
        network_interface_card_id = $nic.id
        network_label_assignment_specs = @(@{
          enabled = $true
          max_label = 1
          max_label_type = "LIMITED"
          network_label_name = $NetworkLabelName
        })
      }
    }
  }
}                                                                                             # :contentReference[oaicite:9]{index=9}

# IC Domain Account (optional but recommended for instant clones)
$icAcct = Invoke-Hzn -Method GET -Path "/rest/config/v1/ic-domain-accounts" | Where-Object { $_.username -eq $IcAccountUsername }
$icAcctId = $icAcct?.id                                                                        # :contentReference[oaicite:10]{index=10}

# Access Group
$ag = Invoke-Hzn -Method GET -Path "/rest/config/v2/local-access-groups" | Where-Object { $_.name -eq $AccessGroupName }
if (-not $ag) { throw "Access Group '$AccessGroupName' not found (create it first)." }        # :contentReference[oaicite:11]{index=11}
$accessGroupId = $ag.id

# ---------- Build Create Spec ----------
$provisioning = @{
  vcenter_id        = $vcId
  datacenter_id     = $dcId
  host_or_cluster_id= $clusterId
  resource_pool_id  = $rpid
  vm_folder_id      = $folderId
  datastore_id      = $datastoreId
  parent_vm_id      = $baseVmId
  base_snapshot_id  = $snapshotId
}

$pattern = if ($NamingMethod -eq "PATTERN") { @{
  naming_pattern = $NamingPattern
  min_number_of_machines = $MinVMs
  max_number_of_machines = $MaxVMs
  number_of_spare_machines = $SpareVMs
  provisioning_time = "UP_FRONT"
} } else { $null }

$customization = @{
  customization_type = "CLONE_PREP"   # or "SYSPREP" if you use a vCenter spec
  ad_container_rdn   = $AdContainerRdn
}
if ($icAcctId) { $customization.instant_clone_domain_account_id = $icAcctId }

$displayProto = @{
  allow_users_to_choose_protocol = $true
  default_display_protocol       = "BLAST"
  session_collaboration_enabled  = $false
  renderer3d                     = "DISABLED"
}

$sessionSettings = @{
  allow_multiple_sessions_per_user = $false
  power_policy                     = "TAKE_NO_POWER_ACTION"
  delete_or_refresh_machine_after_logoff = "NEVER"
  session_timeout_policy           = "DEFAULT"
}

$storage = @{
  datastores = @(@{ datastore_id = $datastoreId; sdrs_cluster = $false })
  use_vsan = $false
}

$createSpec = @{
  name                 = $PoolName
  display_name         = $PoolDisplayName
  description          = "Created by REST API"
  type                 = "AUTOMATED"
  source               = "INSTANT_CLONE"
  user_assignment      = $UserAssignment
  naming_method        = $NamingMethod
  access_group_id      = $accessGroupId
  enable_provisioning  = $true
  enabled              = $true
  provisioning_settings= $provisioning
  customization_settings = $customization
  display_protocol_settings = $displayProto
  session_settings     = $sessionSettings
  storage_settings     = $storage
  shortcut_locations_v2= @("DESKTOP")
}

if ($pattern) { $createSpec.pattern_naming_settings = $pattern }
if ($nicSpecs.Count -gt 0) { $createSpec.nics = $nicSpecs }

# ---------- Create the pool ----------
Write-Host "Creating desktop pool '$PoolName'..." -ForegroundColor Cyan
$createResp = Invoke-Hzn -Method POST -Path "/rest/inventory/v1/desktop-pools" -Body $createSpec    # :contentReference[oaicite:12]{index=12}
# The API returns a task id or the pool id, depending on version; fetch the pool by name to get ID.
$pool = Invoke-Hzn -Method GET -Path "/rest/inventory/v1/desktop-pools" | Where-Object { $_.name -eq $PoolName }  # :contentReference[oaicite:13]{index=13}
if (-not $pool) { throw "Pool creation call returned, but the pool '$PoolName' was not found when listing. Check Horizon tasks." }
$poolId = $pool.id
Write-Host "Pool created. ID: $poolId" -ForegroundColor Green

# ---------- Resolve entitlements (user/group → SID) ----------
# We’ll use the Users/Groups Local Summary endpoint and filter client-side by login_name or display_name.
$ugList = Invoke-Hzn -Method GET -Path "/rest/config/v1/users-or-groups-local-summary" -Query @{ size = 1000 }   # :contentReference[oaicite:14]{index=14}

$entitledSids = New-Object System.Collections.Generic.List[string]
foreach ($entry in $EntitleUsersOrGroups) {
  $match = $ugList | Where-Object {
    ($_.login_name -eq $entry) -or
    ($_.display_name -eq $entry) -or
    ($_.user_principal_name -eq $entry) -or
    ($_.long_display_name -eq $entry)
  }
  if (-not $match) {
    Write-Warning "Could not resolve '$entry' to a user/group SID. Skipping."
    continue
  }
  if ($match.Count -gt 1) {
    Write-Warning "'$entry' matched multiple directory objects. Taking the first: $($match[0].display_name)"
    $match = $match[0]
  }
  $entitledSids.Add($match.id)
}

if ($entitledSids.Count -gt 0) {
  Write-Host "Entitling $($entitledSids.Count) user(s)/group(s) to pool '$PoolName'..." -ForegroundColor Cyan
  $entBody = @(@{
    id = $poolId
    ad_user_or_group_ids = $entitledSids
  })
  $entResp = Invoke-Hzn -Method POST -Path "/rest/entitlements/v1/desktop-pools" -Body $entBody       # :contentReference[oaicite:15]{index=15}
  Write-Host "Entitlements applied." -ForegroundColor Green
} else {
  Write-Host "No valid users/groups to entitle. Skipping entitlements." -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green
