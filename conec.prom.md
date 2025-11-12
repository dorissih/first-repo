Got it. Here’s a clean, battle-tested way to (1) stand up health checks for Omnissa Horizon and (2) expose useful metrics to Prometheus/Grafana. I’ll give you two exporter options—pick the one that fits your environment—and include alerting + dashboard tips.

1) Horizon health checks you should enable/verify

A. Built-in health monitors (Connection Server)
On each Connection Server, use vdmadmin -H to list and inspect health monitors (AD LDS replication, Events DB, JMS, etc.). This is your first-line “is the broker happy?” signal.

cd "C:\Program Files\VMware\VMware View\Server\bin"
# List existing monitors
.\vdmadmin.exe -H -list

# Show details for a specific monitor (example: Events DB)
.\vdmadmin.exe -H -display -monitor "Event Database"


You’ll see status fields per component that you can script into a check (Task Scheduler/Windows service) and emit to logs or a metric file. 
Omnissa Docs
+1

B. Unified Access Gateway (UAG) health
For load balancers/blackbox probes, UAG exposes a simple HTTPS reachability health—commonly the favicon.ico trick: if all UAG services are green, the icon is reachable (LB health = up); if any service is down, it fails. Use your LB/blackbox_exporter to probe:

https://<uagFQDN>/favicon.ico


(Ensure the external interface cert is trusted by the probe/LB so TLS health works properly.) You can also surface UAG status in Horizon Console. 
Mobile Jon's Blog
+1

2) Collect Horizon metrics for Prometheus

Horizon exposes monitoring APIs for system and session metrics (Connection Server). You can poll these with a small exporter. Key endpoints include “Get System Metrics Info” and “Get Session Metrics.” You’ll need a Horizon API user with read/monitor privileges. 
developer.broadcom.com
+2
developer.broadcom.com
+2

You have two practical paths:

Option A — Use a community Horizon exporter (fastest)

There are lightweight exporters that log in to Horizon and expose Prometheus-format metrics:

vmware_horizon_exporter (Go): runs as a container or binary. 
GitHub

horizon_exporter (NSLS-II): similar concept; review repo for examples. 
GitHub

Example (Linux container on a utility VM):

docker run -d --name horizon-exporter \
  -e HORIZON_BASE_URL="https://connserver.company.lan" \
  -e HORIZON_USERNAME="svc_prometheus" \
  -e HORIZON_PASSWORD="********" \
  -e HORIZON_SKIP_VERIFY="true" \
  -p 9105:9105 \
  ghcr.io/<your-chosen-repo>/vmware_horizon_exporter:latest


Then scrape http://<utility-vm>:9105/metrics.

Tip: if you’re air-gapped, mirror the container image into your local registry and pin a digest.

Option B — Roll your own with Windows windows_exporter + small script

Install the standard windows_exporter on each Connection Server (for CPU, memory, TCP, service states). It’s reliable and well-maintained. 
GitHub

Install windows_exporter (service on port 9182 by default).

Add a scheduled PowerShell that calls the Horizon Monitor API and writes key values to the textfile collector directory so they appear as custom metrics.

windows_exporter service example (PowerShell elevated):

$Params = @(
  '--collectors.enabled=default,textfile',
  '--collector.textfile.directory="C:\Program Files\windows_exporter\textfile_inputs"'
)
New-Item -ItemType Directory -Force "C:\Program Files\windows_exporter\textfile_inputs" | Out-Null
& 'C:\Program Files\windows_exporter\windows_exporter.exe' --install --% $Params
Start-Service windows_exporter


Horizon API scrape script (runs every minute):

$base   = "https://connserver.company.lan"
$user   = "svc_prometheus"
$pass   = "********"
$outDir = "C:\Program Files\windows_exporter\textfile_inputs"
$out    = Join-Path $outDir "horizon.prom"

# Acquire session cookie or token as your API requires (example pseudocode)
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$body = @{ username=$user; password=$pass }
Invoke-RestMethod -Uri "$base/rest/login" -WebSession $session -Method Post -Body ($body|ConvertTo-Json) -ContentType "application/json" -SkipCertificateCheck

# System metrics
$sys = Invoke-RestMethod -Uri "$base/rest/monitor/system-metrics" -WebSession $session -SkipCertificateCheck
# Session metrics
$sess = Invoke-RestMethod -Uri "$base/rest/monitor/session-metrics" -WebSession $session -SkipCertificateCheck

# Emit Prometheus textfile format
$lines = @()
$lines += "# HELP horizon_active_sessions Current active sessions"
$lines += "# TYPE horizon_active_sessions gauge"
$lines += "horizon_active_sessions $($sess.activeSessions)"

$lines += "# HELP horizon_connection_server_healthy Built-in health flag"
$lines += "# TYPE horizon_connection_server_healthy gauge"
$healthy = if ($sys.overallStatus -eq "GREEN") {1} else {0}
$lines += "horizon_connection_server_healthy $healthy"

$lines | Set-Content -Encoding ASCII $out


(Adjust login/paths to match the actual API you’re using; the official docs list Get System Metrics Info and Get Session Metrics operations and their return structure.) 
developer.broadcom.com
+1

3) Prometheus scrape configs

Connection Servers (windows_exporter):

scrape_configs:
  - job_name: 'horizon_windows'
    static_configs:
      - targets:
          - conn1.company.lan:9182
          - conn2.company.lan:9182


Horizon exporter (if using Option A):

  - job_name: 'horizon_app'
    static_configs:
      - targets: ['utility-vm.company.lan:9105']


UAG blackbox probe (health over HTTPS):

  - job_name: 'uag_https_probe'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://uag1.company.lan/favicon.ico
          - https://uag2.company.lan/favicon.ico
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter.monitoring.svc.cluster.local:9115


(Any 2xx means “healthy”.) 
Mobile Jon's Blog

4) Grafana quick wins

Create a dashboard with panels like:

Active Sessions
Query: max by(instance) (horizon_active_sessions)

Connection Server Health (singlestat)
Query: max by(instance) (horizon_connection_server_healthy)

Windows OS Health (per CS)

CPU: avg by (instance) (rate(windows_cpu_time_total{mode!="idle"}[5m]))

Services: windows_service_state{service="WSBrokers",state="running"}

TCP connections: sum by(instance) (windows_net_tcp_connections_established)

UAG Availability
From blackbox: probe_success{job="uag_https_probe"}

5) Alerting rules (examples)
groups:
- name: horizon.rules
  rules:
  - alert: HorizonConnectionServerDown
    expr: horizon_connection_server_healthy == 0
    for: 5m
    labels: { severity: critical }
    annotations:
      summary: "Horizon CS unhealthy ({{ $labels.instance }})"
      description: "Built-in health monitor not green for 5m."

  - alert: HorizonNoSessionsWhileExpected
    expr: horizon_active_sessions == 0
    for: 30m
    labels: { severity: warning }
    annotations:
      summary: "Zero Horizon sessions ({{ $labels.instance }})"
      description: "No active sessions for 30m—check pools, brokers, UAG."

  - alert: UAGProbeFailed
    expr: probe_success{job="uag_https_probe"} == 0
    for: 2m
    labels: { severity: critical }
    annotations:
      summary: "UAG health probe failing ({{ $labels.instance }})"
      description: "HTTPS health endpoint not reachable."

6) Nice-to-have add-ons

vCenter metrics (infra layer under Horizon): add vmware_exporter for ESXi/VM/Datastore visibility. 
GitHub

OS-level Windows alerts (Connection Servers): use windows_exporter collectors for services (Broker, Blast Secure Gateway), memory pressure, TCP backlog. 
GitHub

Summary of the moving parts

Health checks

vdmadmin -H for CS component health. 
Omnissa Docs
+1

UAG HTTPS reachability (/favicon.ico) via LB/blackbox probe. 
Mobile Jon's Blog

Metrics

Horizon Monitor API → exporter (community or custom) → Prometheus. 
developer.broadcom.com
+1

OS metrics via windows_exporter. 
GitHub

Visualization/alerts in Grafana + Prometheus rules.

If you want, I can tailor the exporter option to your exact setup (air-gapped vs. connected, Windows-only vs. utility Linux VM, certificate requirements) and hand you a ready-to-drop service + Grafana JSON.




Great—here’s a straightforward way to turn those vdmadmin -H checks into something you can run automatically and graph/alert on.

Overview

Verify vdmadmin works.

Drop in a PowerShell script that:

Lists all monitors

Gets each monitor’s detailed status

Maps status → numeric (GREEN=1, YELLOW=0.5, RED/FAIL=0)

Writes a Prometheus textfile (horizon_health.prom) for scrape

Optionally logs warnings/errors to the Windows Event Log

Create a Scheduled Task (run as SYSTEM) to execute every minute.

1) Quick sanity check (run on each Connection Server)

Open an elevated PowerShell:

Set-Location "C:\Program Files\VMware\VMware View\Server\bin"
.\vdmadmin.exe -H -list
.\vdmadmin.exe -H -display -monitor "Event Database"


If those return data, you’re good.

2) PowerShell script (save as C:\Scripts\Horizon-Health.ps1)

This script:

Auto-discovers monitors from -list

Pulls details with -display

Emits Prometheus metrics to the Windows exporter textfile directory (change path if needed)

Writes Event Log entries if any monitor isn’t green

# C:\Scripts\Horizon-Health.ps1
# Runs on a Horizon Connection Server

$ErrorActionPreference = 'Stop'

# --- Paths ---
$VdmBin = "C:\Program Files\VMware\VMware View\Server\bin\vdmadmin.exe"
$TextfileDir = "C:\Program Files\windows_exporter\textfile_inputs"   # change if you use a different exporter
$OutFile = Join-Path $TextfileDir "horizon_health.prom"

# --- Ensure exporter textfile dir exists (safe if windows_exporter not installed yet) ---
New-Item -ItemType Directory -Force -Path $TextfileDir | Out-Null

# --- Helpers ---
function Map-StatusToValue {
    param([string]$s)
    $s = ($s -as [string]).ToLowerInvariant()
    if ($s -match 'green|ok|healthy|pass') { return 1 }
    if ($s -match 'yellow|warn|warning|degraded') { return 0.5 }
    if ($s -match 'red|fail|error|critical|down') { return 0 }
    return 'NaN'
}

function Get-Monitors {
    # Parse the output of: vdmadmin -H -list
    $raw = & $VdmBin -H -list 2>&1
    if ($LASTEXITCODE -ne 0) { throw "vdmadmin -H -list failed: $raw" }

    # Heuristic parse: one monitor per line; names can contain spaces.
    # We'll pick lines that look like monitor names, ignoring headers.
    $monitors = @()
    foreach ($line in $raw) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        # Skip obvious headers
        if ($trim -match '^(Monitors|Name|Status|----)') { continue }
        # Capture name up to a delimiter (if present)
        # Common formats: "Event Database : GREEN" or just "Event Database"
        $name = $trim -replace '\s*[:|-].*$', ''
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $monitors += $name.Trim()
        }
    }
    # De-dup
    $monitors | Select-Object -Unique
}

function Get-MonitorDetail {
    param([string]$MonitorName)
    $raw = & $VdmBin -H -display -monitor $MonitorName 2>&1
    # Do not throw on non-zero immediately; some versions still emit output.
    [PSCustomObject]@{
        Name   = $MonitorName
        Output = $raw -join "`n"
    }
}

# --- Main ---
$metrics = New-Object System.Collections.Generic.List[string]
$metrics.Add('# HELP horizon_monitor_status Health of Horizon built-in monitors (1=green, 0.5=yellow, 0=red)')
$metrics.Add('# TYPE horizon_monitor_status gauge')
$metrics.Add('# HELP horizon_monitor_details_info Raw status text as a label (use with care, high cardinality if many values)')
$metrics.Add('# TYPE horizon_monitor_details_info gauge')

$overallVals = @()
$nonGreen = @()

$monitors = Get-Monitors
foreach ($m in $monitors) {
    $detail = Get-MonitorDetail -MonitorName $m

    # Try to find a high-level status in the detail text
    # Look for a line like "Status: GREEN" or similar
    $statusLine = ($detail.Output -split "`n") | Where-Object { $_ -match '(?i)status\s*[:=]' } | Select-Object -First 1
    if (-not $statusLine) {
        # Fallback: scan entire detail for known words
        $statusText = $detail.Output
    } else {
        $statusText = ($statusLine -replace '.*[:=]\s*', '').Trim()
    }

    $val = Map-StatusToValue $statusText
    $labelName = $m.Replace('\','/').Replace('"','\"')
    $labelText = ($statusText -as [string]).Replace('\','/').Replace('"','\"')

    $metrics.Add(("horizon_monitor_status{monitor=""{0}""} {1}" -f $labelName, $val))
    $metrics.Add(("horizon_monitor_details_info{monitor=""{0}"",status_text=""{1}""} 1" -f $labelName, $labelText))

    if ($val -is [double]) { $overallVals += [double]$val }
    if (($val -is [double]) -and ($val -lt 1)) {
        $nonGreen += [PSCustomObject]@{ Monitor=$m; Status=$statusText }
    }
}

# Overall health metric (min of all monitors present)
$overall = if ($overallVals.Count -gt 0) { ($overallVals | Measure-Object -Minimum).Minimum } else { [double]::NaN }
$metrics.Add('# HELP horizon_connection_server_healthy Aggregate health across monitors (min of monitors)')
$metrics.Add('# TYPE horizon_connection_server_healthy gauge')
$metrics.Add("horizon_connection_server_healthy $overall")

# Write metrics file (ASCII for Prometheus text format)
$metrics | Set-Content -Path $OutFile -Encoding ASCII

# --- Optional: Windows Event Log entries when not green ---
$source = 'HorizonHealth'
if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
    New-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue
}

if ($nonGreen.Count -gt 0) {
    foreach ($n in $nonGreen) {
        Write-EventLog -LogName Application -Source $source -EventId 3001 -EntryType Warning `
            -Message ("Monitor '{0}' not green. Status='{1}'" -f $n.Monitor, $n.Status)
    }
}

# Exit non-zero if anything is RED (useful if you hook this to another checker)
if ($nonGreen | Where-Object { ($_ .Status) -match '(?i)red|fail|error|critical|down' }) {
    exit 2
}

What it produces (Prometheus metrics)

horizon_monitor_status{monitor="Event Database"} 1

horizon_monitor_details_info{monitor="Event Database",status_text="GREEN"} 1

horizon_connection_server_healthy 1

If you don’t use windows_exporter, the file is still created; you can pick it up with any Prometheus textfile-capable exporter/agent you prefer.

3) Schedule it to run every minute (as SYSTEM)

Run once (elevated PowerShell) on each Connection Server:

New-Item -ItemType Directory -Force C:\Scripts | Out-Null
# Save the script to C:\Scripts\Horizon-Health.ps1 first

$Action    = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Horizon-Health.ps1"'
$Trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::MaxValue)
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable)
Register-ScheduledTask -TaskName 'HorizonHealthToProm' -InputObject $Task | Out-Null

4) Prometheus scrape (windows_exporter textfile)

If you use windows_exporter on each Connection Server:

scrape_configs:
  - job_name: 'horizon_windows'
    static_configs:
      - targets:
          - conn1.yourdomain.lan:9182
          - conn2.yourdomain.lan:9182


In your windows_exporter install, make sure it was started with:

--collectors.enabled=default,textfile
--collector.textfile.directory="C:\Program Files\windows_exporter\textfile_inputs"

5) (Optional) Simple alerts
groups:
- name: horizon.local.rules
  rules:
  - alert: HorizonConnectionServerUnhealthy
    expr: horizon_connection_server_healthy == 0
    for: 5m
    labels: { severity: critical }
    annotations:
      summary: "Horizon CS unhealthy ({{ $labels.instance }})"
      description: "One or more built-in monitors are RED for 5m."

  - alert: HorizonMonitorDegraded
    expr: horizon_monitor_status < 1
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "Horizon monitor not green ({{ $labels.monitor }})"
      description: "Status below GREEN for 10m."

6) Troubleshooting

Access denied / no output: Run the script elevated on a Connection Server. Ensure the Horizon services are running.

Different monitor names: Run vdmadmin -H -display -monitor "<TAB>" to confirm exact names; the script is tolerant of spaces.

Exporter not picking up metrics: Confirm the textfile directory exactly matches the exporter’s --collector.textfile.directory.

TLS or path issues: Adjust $VdmBin if Horizon is installed in a non-default path.

If you want, tell me your exact Horizon version and whether you already have windows_exporter installed, and I’ll tweak the script/paths to match your environment.


Yep—that’s expected. On newer installs the CLI isn’t in ...\Server\bin. It lives under ...\Server\tools\bin (and with the Omnissa rebrand some folder names changed).

Quick ways to find it

PowerShell (fastest):

# Search typical locations
$paths = @(
  "C:\Program Files\VMware\VMware View\Server\tools\bin",
  "C:\Program Files\View\Server\tools\bin",
  "C:\Program Files\Omnissa\Horizon Connection Server\tools\bin"
)
Get-ChildItem -Path $paths -Filter vdmadmin.exe -ErrorAction SilentlyContinue

# Or search the disk (slower)
Get-ChildItem -Path 'C:\Program Files' -Recurse -Filter vdmadmin.exe -ErrorAction SilentlyContinue


If you see it (e.g., C:\Program Files\VMware\VMware View\Server\tools\bin\vdmadmin.exe), run your health checks from there:

cd "C:\Program Files\VMware\VMware View\Server\tools\bin"
.\vdmadmin.exe -H -list
.\vdmadmin.exe -H -display -monitor "Event Database"

Why the mismatch?

Official docs show the default path is ...\Server\tools\bin, not ...\Server\bin. 
docs.omnissa.com
+1

With Omnissa 2412+, many “VMware” paths were renamed to “Omnissa”, so your install might be under an Omnissa folder. 
techzone.omnissa.com
+1

If it’s still missing

Confirm you’re on a Connection Server (not just an Agent or UAG).

Make sure you installed the Admin/Connection Server component that includes tools.

Cross-check the doc page “Using the vdmadmin Command” to confirm availability for your version. 
docs.omnissa.com

Want me to tweak the Prometheus script to auto-detect vdmadmin.exe and cache the path it finds?
