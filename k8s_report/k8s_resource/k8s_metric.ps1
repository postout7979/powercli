# --- [0. SSL & Compatibility Setup] ---
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# --- [1. Paths and Variables] ---
$scriptDir = $PSScriptRoot
$reportDir = Join-Path $scriptDir "report"
$timestamp = Get-Date -Format "yyyyMMdd"
$reportDate = Get-Date -Format "yyyy-MM-dd"

$clustersFile = "$scriptDir\clusters.txt"
$reportPathHtml = Join-Path $reportDir "K8s_Report_$($timestamp).html"
$reportPathCsv  = Join-Path $reportDir "K8s_Data_$($timestamp).csv"

if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

# --- [2. Data Initialization] ---
$csvData = New-Object System.Collections.Generic.List[PSObject]

# --- [3. Resource Conversion Logic] ---
function Convert-K8sMemoryToMiB($val) {
    if ($null -eq $val) { return 0 }
    $num = [double]($val -replace "[^0-9]", "")
    if ($val -match "Ki$") { return [Math]::Round($num / 1024, 2) }
    if ($val -match "Mi$") { return $num }
    if ($val -match "Gi$") { return $num * 1024 }
    return [Math]::Round($num / 1048576, 2)
}

function Convert-K8sCpuToCores($val) {
    if ($null -eq $val) { return 0 }
    $num = [double]($val -replace "[^0-9]", "")
    if ($val -match "n$") { return [Math]::Round($num / 1000000000, 4) }
    if ($val -match "m$") { return [Math]::Round($num / 1000, 4) }
    return $num
}

# --- [4. Cluster Data Collection] ---
Write-Host "`n[PROCESS] Fetching Resources (HTML + CSV Output)..." -ForegroundColor Cyan
if (-not (Test-Path $clustersFile)) { Write-Host "Error: clusters.txt missing." -ForegroundColor Red; return }

$lines = Get-Content -Path $clustersFile
$htmlResults = ""

foreach ($line in $lines) {
    # Skip empty lines or comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }

    # Parse CSV format (URL, Token)
    $parts = $line -split ",", 2
    if ($parts.Count -lt 2) { 
        Write-Host " -> Skipping invalid format: $line" -ForegroundColor Gray
        continue 
    }

    # Trim whitespace and quotes
    $apiUrl = $parts[0].Trim().Trim("'").Trim('"').TrimEnd("/")
    $tokenRaw = $parts[1].Trim().Trim("'").Trim('"')
        
    # Set Headers
    $headers = @{ "Authorization" = "Bearer $tokenRaw" }

    Write-Host " -> Analyzing Cluster: $apiUrl" -ForegroundColor Yellow

    function Get-K8sResource($path) {
        try {
            $response = Invoke-RestMethod -Uri "$apiUrl$path" -Headers $headers -Method Get -ErrorAction Stop
            if ($null -ne $response -and $null -ne $response.items) { return $response.items }
            $response
			return @()
        } catch { return @() }
    }
	
    $nodeList = Get-K8sResource "/api/v1/nodes"
    if ($nodeList.Count -eq 0) { 
        Write-Host "    - Connection failed or no nodes found." -ForegroundColor Red
        continue 
    }
    
    $nodeMetrics = Get-K8sResource "/apis/metrics.k8s.io/v1beta1/nodes"
    $podList = Get-K8sResource "/api/v1/pods"
    $svcList = Get-K8sResource "/api/v1/services"
    $ingList = Get-K8sResource "/apis/networking.k8s.io/v1/ingresses"

    # 1. Node Status Section
    $nodeTableRows = ""
    foreach ($node in $nodeList) {
        $name = $node.metadata.name
        $readyCond = $node.status.conditions | Where-Object { $_.type -eq "Ready" }
        $status = if ($readyCond) { $readyCond.status } else { "Unknown" }
        $color = if ($status -eq "True") { "#28a745" } else { "#dc3545" }
        $role = if ($null -ne $node.metadata.labels.'node-role.kubernetes.io/control-plane') { "Control-Plane" } else { "Worker" }
        $esxi = if ($node.metadata.labels.'node.cluster.x-k8s.io/esxi-host') { $node.metadata.labels.'node.cluster.x-k8s.io/esxi-host' } else { "N/A" }
        
        $allocCpu = Convert-K8sCpuToCores $node.status.allocatable.cpu
        $m = $nodeMetrics | Where-Object { $_.metadata.name -eq $name }
        $usageCpu = if ($m) { Convert-K8sCpuToCores $m.usage.cpu } else { 0 }
        
        $allocMem = Convert-K8sMemoryToMiB $node.status.allocatable.memory
        $usageMem = if ($m) { Convert-K8sMemoryToMiB $m.usage.memory } else { 0 }

        # HTML Row
        $nodeTableRows += "<tr><td>$name</td><td style='color:$color;font-weight:bold;'>$status</td><td>$role</td><td>$esxi</td><td>$allocCpu / $usageCpu</td><td>$allocMem / $usageMem</td></tr>"
        
        # CSV Data
        $csvData.Add([PSCustomObject]@{
            Cluster = $apiUrl; Category = "Node"; Namespace = "-"; Name = $name; Status = $status; Details = "Role:$role, ESXi:$esxi, CPU:$allocCpu/$usageCpu, Mem:$allocMem/$usageMem"
        })
    }

    # 2. Pod Health Section
    $podTableRows = ""
    foreach ($pod in $podList) {
        $isIssue = $false; $reason = $pod.status.phase; $restarts = 0
        if ($null -ne $pod.status.containerStatuses) {
            foreach ($cs in $pod.status.containerStatuses) {
                $restarts += $cs.restartCount
                if ($cs.state.waiting.reason -eq "CrashLoopBackOff" -or $cs.restartCount -gt 5) { $isIssue = $true; $reason = $cs.state.waiting.reason }
            }
        }
        if ($isIssue -or $pod.status.phase -ne "Running") {
            $podTableRows += "<tr class='issue-row'><td>$($pod.metadata.namespace)</td><td>$($pod.metadata.name)</td><td>$reason</td><td>$restarts</td></tr>"
            
            $csvData.Add([PSCustomObject]@{
                Cluster = $apiUrl; Category = "PodIssue"; Namespace = $pod.metadata.namespace; Name = $pod.metadata.name; Status = $reason; Details = "Restarts:$restarts"
            })
        }
    }
    if ([string]::IsNullOrEmpty($podTableRows)) { $podTableRows = "<tr><td colspan='4' style='text-align:center;'>No issues detected.</td></tr>" }

    # 3. Service Section
    $svcTableRows = ""
    foreach ($svc in $svcList) {
        if ($svc.spec.type -eq "LoadBalancer" -or $null -ne $svc.spec.externalIPs) {
            $extIp = "Pending"; if ($null -ne $svc.status.loadBalancer.ingress) { $extIp = ($svc.status.loadBalancer.ingress.ip -join ", ") + ($svc.status.loadBalancer.ingress.hostname -join ", ") }
            $svcTableRows += "<tr><td>$($svc.metadata.namespace)</td><td>$($svc.metadata.name)</td><td>$($svc.spec.type)</td><td>$extIp</td></tr>"
            
            $csvData.Add([PSCustomObject]@{
                Cluster = $apiUrl; Category = "Service"; Namespace = $svc.metadata.namespace; Name = $svc.metadata.name; Status = $svc.spec.type; Details = "Endpoint:$extIp"
            })
        }
    }
    if ([string]::IsNullOrEmpty($svcTableRows)) { $svcTableRows = "<tr><td colspan='4' style='text-align:center;'>No LoadBalancer services found.</td></tr>" }

    # 4. Ingress Section
    $ingTableRows = ""
    foreach ($ing in $ingList) {
        $hosts = ($ing.spec.rules.host -join ", "); if ([string]::IsNullOrEmpty($hosts)) { $hosts = "*" }
        $address = "Pending"; if ($null -ne $ing.status.loadBalancer.ingress) { $address = ($ing.status.loadBalancer.ingress.ip -join ", ") + ($ing.status.loadBalancer.ingress.hostname -join ", ") }
        $ingTableRows += "<tr><td>$($ing.metadata.namespace)</td><td>$($ing.metadata.name)</td><td>$hosts</td><td>$address</td></tr>"
        
        $csvData.Add([PSCustomObject]@{
            Cluster = $apiUrl; Category = "Ingress"; Namespace = $ing.metadata.namespace; Name = $ing.metadata.name; Status = "Active"; Details = "Hosts:$hosts, Address:$address"
        })
    }
    if ([string]::IsNullOrEmpty($ingTableRows)) { $ingTableRows = "<tr><td colspan='4' style='text-align:center;'>No Ingress rules found.</td></tr>" }

    $htmlResults += @"
    <div class='card'>
        <h2>Cluster: $apiUrl</h2>
        <div class='section'>
            <h3>1. Infrastructure & Node Status</h3>
            <table>
                <thead><tr><th>Name</th><th>Status</th><th>Role</th><th>ESXi Host</th><th>CPU (Alloc/Used)</th><th>Mem (Alloc/Used)</th></tr></thead>
                <tbody>$nodeTableRows</tbody>
            </table>
        </div>
        <div class='section'>
            <h3>2. Pod Health Issues</h3>
            <table>
                <thead><tr><th>Namespace</th><th>Pod Name</th><th>Status/Reason</th><th>Restarts</th></tr></thead>
                <tbody>$podTableRows</tbody>
            </table>
        </div>
        <div class='section'>
            <h3>3. Service Exposure (LoadBalancer)</h3>
            <table>
                <thead><tr><th>Namespace</th><th>Service Name</th><th>Type</th><th>External Endpoint</th></tr></thead>
                <tbody>$svcTableRows</tbody>
            </table>
        </div>
        <div class='section'>
            <h3>4. Ingress Rules</h3>
            <table>
                <thead><tr><th>Namespace</th><th>Ingress Name</th><th>Hosts</th><th>Address</th></tr></thead>
                <tbody>$ingTableRows</tbody>
            </table>
        </div>
    </div>
"@
}

# --- [5. Save Reports] ---
$htmlFinal = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>K8s Health Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; padding: 40px; color: #333; }
        .card { background: white; border-radius: 12px; padding: 30px; margin-bottom: 40px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; text-align: center; }
        h2 { border-bottom: 3px solid #1a73e8; padding-bottom: 10px; margin-bottom: 25px; color: #1a73e8; }
        .section { margin-bottom: 30px; }
        h3 { background: #e8f0fe; padding: 10px 15px; border-radius: 6px; color: #1967d2; font-size: 18px; margin-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 5px; }
        th { text-align: left; background: #f8f9fa; padding: 12px; border-bottom: 2px solid #ddd; }
        td { padding: 10px; border-bottom: 1px solid #eee; font-size: 14px; word-break: break-all; }
        .issue-row { background-color: #fce8e6; font-weight: bold; }
    </style>
</head>
<body>
    <h1>K8s Performance & Health Dashboard</h1>
    <p style='text-align:center;'>Report Date: $reportDate</p>
    $htmlResults
</body>
</html>
"@

# Save HTML
$htmlFinal | Out-File -FilePath $reportPathHtml -Encoding utf8
Write-Host "[SUCCESS] HTML report generated: $reportPathHtml" -ForegroundColor Green

# Save CSV
$csvData | Export-Csv -Path $reportPathCsv -NoTypeInformation -Encoding utf8
Write-Host "[SUCCESS] CSV report generated: $reportPathCsv" -ForegroundColor Green

# --- [6. Auto-Open HTML Report] ---
Invoke-Item $reportPathHtml