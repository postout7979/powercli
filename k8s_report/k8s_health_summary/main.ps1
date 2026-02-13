# --- [Environment Setup] ---
$PPath = "$PSScriptRoot/plugin/request_handler.ps1"
$RDir = "$PSScriptRoot/report"
$IFile = "$PSScriptRoot/ips.txt"
# Format date to yyyyMMdd and yyyy-MM-dd as requested
$TS = Get-Date -Format "yyyyMMdd"
$ReportDate = Get-Date -Format "yyyy-MM-dd"
$ReportPath = Join-Path $RDir "K8s_Health_Summary_$TS.html"
$CsvPath = Join-Path $RDir "K8s_Health_Data_$TS.csv"

# Create report directory if it doesn't exist
if (!(Test-Path $RDir)) { New-Item -ItemType Directory -Path $RDir | Out-Null }

# Import external request handler
. $PPath

# Load target IP addresses
if (!(Test-Path $IFile)) { Write-Host "Error: ips.txt not found." -ForegroundColor Red; return }
$IPList = Get-Content $IFile | Where-Object { $_.Trim() -ne "" }
$HtmlContent = ""
$CsvData = New-Object System.Collections.Generic.List[PSObject]

# Initialize Counters for the Summary Dashboard
$Counts = @{ 
    "readyz_ok" = 0; "readyz_fail" = 0; 
    "healthz_ok" = 0; "healthz_fail" = 0; 
    "livez_ok" = 0; "livez_fail" = 0 
}

Write-Host "Executing Health Check and Calculating Summary..." -ForegroundColor Cyan

foreach ($ip in $IPList) {
    $ip = $ip.Trim()
    if (Test-NodeConnection -IP $ip) {
        Write-Host "Scanning Node: $ip" -ForegroundColor Green
        
        foreach ($ep in @("version", "readyz", "healthz", "livez")) {
            $details = Get-K8sParsedDetails -IP $ip -Endpoint $ep
            
            # Increment counters for health endpoints
            if ($ep -ne "version") {
                foreach ($item in $details) { 
                    if ($item.IsOk) { 
                        $Counts["$($ep)_ok"]++ 
                    } else { 
                        $Counts["$($ep)_fail"]++ 
                    }
                }
            }

            # Generate HTML Section for the Node
            $HtmlContent += @"
<div class='section-wrapper'>
    <div class='node-info'>Node: $ip</div>
    <div class='endpoint-title'>$($ep.ToUpper()) Inspection</div>
    <table class='detail-table'>
"@
            foreach ($item in $details) {
                # Add data to CSV list
                $CsvData.Add([PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Node      = $ip
                    Endpoint  = $ep
                    CheckName = $item.Name
                    Status    = $item.Status
                    IsOk      = $item.IsOk
                })

                $sClass = if ($item.IsOk) { "status-ok" } else { "status-fail" }
                $HtmlContent += "<tr><td class='c-name'>$($item.Name)</td><td class='c-val'><span class='$sClass'>$($item.Status)</span></td></tr>"
            }
            $HtmlContent += "</table></div>"
        }
    } else {
        # Handle Offline Nodes
        $CsvData.Add([PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Node      = $ip
            Endpoint  = "N/A"
            CheckName = "Ping"
            Status    = "Offline"
            IsOk      = $false
        })
        $HtmlContent += "<div class='section-wrapper offline'><h2>Node: $ip (Offline)</h2><p>ICMP Ping Failed</p></div>"
    }
}

# --- [HTML Template with FAIL/OK Combined Dashboard] ---
$HtmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <style>
        body { font-family: 'Segoe UI', system-ui, sans-serif; background-color: #f1f5f9; padding: 40px; color: #334155; }
        .dashboard { max-width: 900px; margin: 0 auto 40px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
        .stat-card { background: white; padding: 25px 15px; border-radius: 12px; text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border-bottom: 4px solid #3b82f6; }
        .stat-val { font-size: 1.6rem; font-weight: 800; display: block; margin-bottom: 5px; }
        .val-fail { color: #dc2626; }
        .val-sep { color: #94a3b8; margin: 0 5px; }
        .val-ok { color: #059669; }
        .stat-label { font-size: 0.75rem; font-weight: 700; color: #64748b; text-transform: uppercase; display: block; }
        
        .section-wrapper { max-width: 900px; margin: 0 auto 30px; background: white; border-radius: 16px; padding: 25px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border-top: 5px solid #3b82f6; }
        .offline { border-top: 5px solid #ef4444; }
        .node-info { font-size: 0.8rem; font-weight: 700; color: #94a3b8; text-transform: uppercase; margin-bottom: 5px; }
        .endpoint-title { font-size: 1.1rem; font-weight: 800; color: #1e293b; margin-bottom: 20px; }
        .detail-table { width: 100%; border-collapse: collapse; }
        .detail-table td { padding: 10px 0; border-bottom: 1px solid #f1f5f9; font-size: 0.85rem; }
        .c-name { color: #475569; } .c-val { text-align: right; }
        .status-ok { background: #dcfce7; color: #15803d; padding: 3px 10px; border-radius: 6px; font-weight: 700; font-size: 0.7rem; }
        .status-fail { background: #fee2e2; color: #b91c1c; padding: 3px 10px; border-radius: 6px; font-weight: 700; font-size: 0.7rem; }
    </style>
</head>
<body>
    <h1 style='text-align:center; color:#1e293b; margin-bottom:40px;'>K8s Infrastructure Health Dashboard</h1>
    
    <div class='dashboard'>
        <div class='stat-card'>
            <span class='stat-val'>
                <span class='val-fail'>$($Counts["readyz_fail"])</span><span class='val-sep'>/</span><span class='val-ok'>$($Counts["readyz_ok"])</span>
            </span>
            <span class='stat-label'>Readyz (FAIL / OK)</span>
        </div>
        <div class='stat-card'>
            <span class='stat-val'>
                <span class='val-fail'>$($Counts["healthz_fail"])</span><span class='val-sep'>/</span><span class='val-ok'>$($Counts["healthz_ok"])</span>
            </span>
            <span class='stat-label'>Healthz (FAIL / OK)</span>
        </div>
        <div class='stat-card'>
            <span class='stat-val'>
                <span class='val-fail'>$($Counts["livez_fail"])</span><span class='val-sep'>/</span><span class='val-ok'>$($Counts["livez_ok"])</span>
            </span>
            <span class='stat-label'>Livez (FAIL / OK)</span>
        </div>
    </div>

    $HtmlContent
</body>
</html>
"@

# Save HTML Report
$HtmlTemplate | Out-File $ReportPath -Encoding UTF8

# Save CSV Report
$CsvData | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

# Final Output to Console
Write-Host "`nHealth Check Process Completed." -ForegroundColor Green
Write-Host "Reports generated in: $RDir"
Write-Host " - HTML Dashboard: $(Split-Path $ReportPath -Leaf)"
Write-Host " - CSV Data: $(Split-Path $CsvPath -Leaf)"

# Open HTML Report automatically
Invoke-Item $ReportPath