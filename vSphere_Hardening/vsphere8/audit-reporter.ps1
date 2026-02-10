<#
    Script Name: vSphere Audit Reporter (Standalone)
    Description: Generates JSON/HTML reports from existing audit logs without running new audits.
    Author: Gemini
#>

# ---------------------------------------------------------------------------
# 1. Check Modules (Minimal check for connection)
# ---------------------------------------------------------------------------
function Check-Modules {
    Write-Host "`n[1/5] Checking PowerShell modules..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name "VCF.PowerCLI")) {
        Write-Host "  ! Error: 'VCF.PowerCLI' module is missing. Please install it." -ForegroundColor Red
        exit
    }
    Write-Host "  - Modules verified." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. Connect to vCenter (Same logic as Main Script)
# ---------------------------------------------------------------------------
function Connect-To-vCenter {
    param ($CredPath)
    
    Write-Host "`n[2/5] Connecting to vCenter..." -ForegroundColor Cyan
    $vcAddress = Read-Host "  > Enter vCenter IP or FQDN"
    $credential = $null

    if (Test-Path $CredPath) {
        $response = Read-Host "  > Saved credentials found. Use them? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            try { $credential = Import-Clixml -Path $CredPath } catch {}
        }
    }

    if ($null -eq $credential) {
        $credential = Get-Credential
        $save = Read-Host "  > Save credentials? (Y/N)"
        if ($save -eq "Y" -or $save -eq "y") {
            $credential | Export-Clixml -Path $CredPath
        }
    }

    Write-Host "  - Connecting to $vcAddress..." -ForegroundColor Gray
    try {
        Connect-VIServer -Server $vcAddress -Credential $credential -ErrorAction Stop | Out-Null
        Write-Host "  - Connected successfully." -ForegroundColor Green
    } catch {
        Write-Host "  ! Connection failed." -ForegroundColor Red
        exit
    }
    return $vcAddress
}

# ---------------------------------------------------------------------------
# 3. Get Inventory (To map file names)
# ---------------------------------------------------------------------------
function Get-Inventory {
    Write-Host "`n[3/5] Fetching vCenter Inventory..." -ForegroundColor Cyan
    $inventory = @{
        vCenter = @($global:DefaultVIServers.Name)
        ESXi    = @(Get-VMHost | Sort-Object Name | Select-Object -ExpandProperty Name)
        VM      = @(Get-VM | Sort-Object Name | Select-Object -ExpandProperty Name)
    }
    Write-Host "  - Found: 1 vCenter, $($inventory.ESXi.Count) Hosts, $($inventory.VM.Count) VMs." -ForegroundColor Gray
    return $inventory
}

# ---------------------------------------------------------------------------
# 4. Select Audit Folder (Interactive)
# ---------------------------------------------------------------------------
function Select-Audit-Folder {
    Write-Host "`n[4/5] Select Audit Log Folder..." -ForegroundColor Cyan
    
    # Get subdirectories
    $subFolders = Get-ChildItem -Path $PSScriptRoot -Directory | Sort-Object LastWriteTime -Descending
    
    if ($subFolders.Count -eq 0) {
        Write-Host "  ! No subfolders found in current directory." -ForegroundColor Red
        exit
    }

    # List folders
    Write-Host "  Available Folders:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subFolders.Count; $i++) {
        Write-Host "    [$($i+1)] $($subFolders[$i].Name)  (Last Modified: $($subFolders[$i].LastWriteTime))"
    }

    # User Input
    while ($true) {
        $selection = Read-Host "  > Enter the number of the folder to process"
        if ($selection -match "^\d+$" -and [int]$selection -gt 0 -and [int]$selection -le $subFolders.Count) {
            $selectedFolder = $subFolders[[int]$selection - 1]
            Write-Host "  - Selected: $($selectedFolder.FullName)" -ForegroundColor Green
            return $selectedFolder.FullName
        } else {
            Write-Host "  ! Invalid selection. Please try again." -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Parse Logs
# ---------------------------------------------------------------------------
function Parse-Logs {
    param ($Inventory, $TargetDir)
    Write-Host "`n[5/5] Analyzing logs and creating report..." -ForegroundColor Cyan
    
    $results = @{
        Summary = @{ TotalPass = 0; TotalFail = 0; TotalInfo = 0 }
        Data = @{ vCenter = @(); ESXi = @(); VM = @() }
    }

    foreach ($type in $Inventory.Keys) {
        foreach ($objName in $Inventory[$type]) {
            # Try to match exact file name
            $logFile = Join-Path $TargetDir "$objName.txt"
            
            $objData = @{ Name = $objName; Type = $type; Pass = 0; Fail = 0; Info = 0; Details = @() }

            if (Test-Path $logFile) {
                $content = Get-Content $logFile
                foreach ($line in $content) {
                    if ($line -match "\[(PASS|FAIL|INFO|WARNING|ERROR)\]") {
                        $match = $matches[1]
                        switch ($match) {
                            "PASS" { $objData.Pass++; $results.Summary.TotalPass++ }
                            "FAIL" { $objData.Fail++; $results.Summary.TotalFail++ }
                            "INFO"    { $objData.Info++; $results.Summary.TotalInfo++ }
                            "WARNING" { $objData.Info++; $results.Summary.TotalInfo++ }
                            "ERROR"   { $objData.Fail++; $results.Summary.TotalFail++ }
                        }
                        
                        $cssClass = switch ($match) { "PASS"{"status-pass"} "FAIL"{"status-fail"} default{"status-info"} }
                        $objData.Details += @{ Status = $match; Message = ($line -replace "\[.*?\]\s*", ""); CssClass = $cssClass }
                    }
                }
            } else {
                # File not found
                $objData.Details += @{ Status = "ERROR"; Message = "Log file not found (Object exists in vCenter but no log file)"; CssClass = "status-fail" }
            }
            $results.Data[$type] += $objData
        }
    }
    return $results
}

# ---------------------------------------------------------------------------
# 6. Generate HTML
# ---------------------------------------------------------------------------
function Generate-Html {
    param ($Results, $FilePath)
    $jsonData = $Results | ConvertTo-Json -Depth 10 -Compress
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"><title>vSphere Security Audit Report</title>
    <style>
        :root { --bg: #f4f6f9; --card: #fff; --text: #333; --pass: #28a745; --fail: #dc3545; --info: #17a2b8; }
        body { font-family: sans-serif; background: var(--bg); color: var(--text); padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 30px; }
        .dashboard { display: flex; gap: 20px; justify-content: center; margin-bottom: 30px; }
        .card { background: var(--card); padding: 20px; border-radius: 8px; flex: 1; text-align: center; max-width: 200px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .count { font-size: 2.5em; font-weight: bold; }
        .c-pass { color: var(--pass); } .c-fail { color: var(--fail); } .c-info { color: var(--info); }
        .section-title { font-size: 1.5em; margin: 30px 0 15px; border-left: 5px solid #007bff; padding-left: 10px; }
        table { width: 100%; border-collapse: collapse; background: var(--card); border-radius: 8px; overflow: hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
        th { background: #e9ecef; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #eee; }
        .obj-row { cursor: pointer; } .obj-row:hover { background: #f8f9fa; }
        .detail-row { display: none; background: #fafafa; }
        .detail-content { max-height: 400px; overflow-y: auto; padding: 15px; }
        .log-line { border-bottom: 1px dashed #eee; padding: 4px 0; font-family: monospace; font-size: 0.9em; }
        .badge { padding: 2px 6px; border-radius: 4px; color: #fff; font-size: 0.8em; margin-right: 8px; width: 50px; display: inline-block; text-align: center; }
        .status-pass { background: var(--pass); } .status-fail { background: var(--fail); } .status-info { background: var(--info); }
        .fail-tag { background: var(--fail); color: white; padding: 2px 6px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .pass-tag { color: var(--pass); font-size: 0.8em; font-weight: bold; }
        button { border: none; background: none; color: #007bff; font-weight: bold; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <header><h1>vSphere 8 Security Hardening Audit Report</h1><p>Generated: $date</p></header>
        <div class="dashboard">
            <div class="card"><h3 class="c-pass">PASS</h3><div id="t-pass" class="count c-pass">0</div></div>
            <div class="card"><h3 class="c-fail">FAIL</h3><div id="t-fail" class="count c-fail">0</div></div>
            <div class="card"><h3 class="c-info">INFO</h3><div id="t-info" class="count c-info">0</div></div>
        </div>
        <div id="content"></div>
    </div>
    <script>
        const data = $jsonData;
        document.getElementById('t-pass').innerText = data.Summary.TotalPass;
        document.getElementById('t-fail').innerText = data.Summary.TotalFail;
        document.getElementById('t-info').innerText = data.Summary.TotalInfo;
        
        const content = document.getElementById('content');
        ['vCenter', 'ESXi', 'VM'].forEach(type => {
            if(!data.Data[type] || data.Data[type].length === 0) return;
            
            const title = document.createElement('div');
            title.className = 'section-title';
            title.innerText = type + ' Objects (' + data.Data[type].length + ')';
            content.appendChild(title);

            const table = document.createElement('table');
            let rows = '';
            data.Data[type].forEach((obj, idx) => {
                const id = type + idx;
                let score = '';
                if(obj.Fail > 0) score += ``<span class="fail-tag">`$`{obj.Fail} Issues</span> ``;
                score += ``<span class="pass-tag">`$`{obj.Pass} Passed</span>``;

                let logs = '';
                obj.Details.forEach(d => logs += ``<div class="log-line"><span class="badge `$`{d.CssClass}">`$`{d.Status}</span>`$`{d.Message}</div>``);

                rows += ``<tr class="obj-row" onclick="document.getElementById('d-`$`{id}').style.display = document.getElementById('d-`$`{id}').style.display === 'table-row' ? 'none' : 'table-row'">
                    <td><strong>`$`{obj.Name}</strong></td><td>`$`{score}</td><td style="width:80px"><button>Details</button></td></tr>
                    <tr id="d-`$`{id}" class="detail-row"><td colspan="3"><div class="detail-content">`$`{logs}</div></td></tr>``;
            });
            table.innerHTML = ``<thead><tr><th>Object</th><th>Status</th><th></th></tr></thead><tbody>`$`{rows}</tbody>``;
            content.appendChild(table);
        });
    </script>
</body>
</html>
"@
    $html | Out-File -FilePath $FilePath -Encoding UTF8
    Write-Host "  - HTML Report generated: $FilePath" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------------------
Check-Modules
$credFile = "$PSScriptRoot\cached_credential.xml"
Connect-To-vCenter -CredPath $credFile | Out-Null
$inventory = Get-Inventory

# Select Folder
$targetDir = Select-Audit-Folder

# Process
$data = Parse-Logs -Inventory $inventory -TargetDir $targetDir

# Save JSON
$jsonPath = Join-Path $targetDir "audit_data.json"
$data | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
Write-Host "  - JSON Data saved: $jsonPath" -ForegroundColor Green

# Save HTML
$htmlPath = Join-Path $targetDir "audit_report.html"
Generate-Html -Results $data -FilePath $htmlPath

Write-Host "`n★ Reporting Completed!" -ForegroundColor Green
Invoke-Item $targetDir
