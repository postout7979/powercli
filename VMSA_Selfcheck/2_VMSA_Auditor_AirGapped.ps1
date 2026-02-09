# =============================================================================
# [Script 2] VMSA Auditor for Air-Gapped Environment (Major Version Match)
# -----------------------------------------------------------------------------
# Environment: Internal Network (vCenter access required, No Internet)
# Function:
# 1. Loads 'VMSA_Offline_Data.json'.
# 2. Connects to vCenter.
# 3. Matches VMSAs based on Title & Response Matrix Version (1st digit).
# 4. Generates CSV and HTML Reports (English).
#    - "Matched Assets" column moved to Details section in HTML.
# =============================================================================

# --- Configuration ---
$CurrentDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CurrentDir)) { $CurrentDir = Get-Location }

$JsonFile = Join-Path $CurrentDir "VMSA_Offline_Data.json"
$CredFile = Join-Path $CurrentDir "vCenter_Creds.xml"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$CsvPath  = Join-Path $CurrentDir "Audit_Report_$Timestamp.csv"
$HtmlPath = Join-Path $CurrentDir "Audit_Report_$Timestamp.html"

# --- 1. Load Offline Data ---
if (-not (Test-Path $JsonFile)) {
    Write-Error "Data file not found: $JsonFile"
    exit
}
try {
    $JsonData = Get-Content -Path $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $VmsaList = $JsonData.Advisories
    Write-Host "[1] Offline Data Loaded ($($VmsaList.Count) items)" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to parse JSON file."
    exit
}

# --- 2. Connect to vCenter ---
Write-Host "[2] Authentication..." -ForegroundColor Cyan
$vcServer = $null
$vcCred = $null
$IsCredLoaded = $false

if (Test-Path $CredFile) {
    if ((Read-Host "Use saved credentials? (Y/N)") -match "^[Yy]") {
        try {
            $SavedInfo = Import-Clixml $CredFile
            $vcServer = $SavedInfo.Server
            $vcCred = $SavedInfo.Credential
            $IsCredLoaded = $true
        } catch { Write-Warning "Failed to load credentials." }
    }
}

if (-not $IsCredLoaded) {
    $vcServer = Read-Host "Enter vCenter Server IP or FQDN"
    Write-Host "    (Enter credentials in popup)" -ForegroundColor Gray
    $vcCred = Get-Credential
    if ((Read-Host "Save credentials? (Y/N)") -match "^[Yy]") {
        [PSCustomObject]@{Server=$vcServer;Credential=$vcCred} | Export-Clixml $CredFile
    }
}

try {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session
    Connect-VIServer -Server $vcServer -Credential $vcCred -ErrorAction Stop
    Write-Host "    -> Connected to $vcServer" -ForegroundColor Green
} catch {
    Write-Error "Connection Failed: $($_.Exception.Message)"
    exit
}

# --- 3. Scan & Match Assets (Response Matrix Check) ---
Write-Host "[3] Analyzing environment (Matrix 1st Digit Matching)..." -ForegroundColor Cyan

$Report = @()

# 3-1. Get Local Versions
# vCenter
$VcInstance = $global:DefaultVIServer
$VcVerFull  = $VcInstance.Version # e.g. "8.0.2.00000"
# Extract 1st Digit (Major)
$VcMajorDigit = if ($VcVerFull -match "^(\d+)") { $matches[1] } else { "Unknown" }

# ESXi Hosts (List all)
$EsxiHosts = Get-VMHost
$HostList = @()
foreach ($h in $EsxiHosts) {
    $ver = $h.Version # "7.0.3"
    $majDigit = if ($ver -match "^(\d+)") { $matches[1] } else { "Unknown" }
    
    $HostList += [PSCustomObject]@{
        Name = $h.Name
        MajorDigit = $majDigit
        FullVer = $ver
    }
}

# 3-2. Matching Logic
$RowIdCounter = 0

foreach ($vmsa in $VmsaList) {
    
    # Store relevant assets for this VMSA
    $RelevantAssets = @() 
    $MatchedProductTypes = @()

    # Split FixedInfo (Response Matrix) into rows
    # Format from Downloader: "Product Name | Version <br> Product Name | Version"
    $MatrixRows = $vmsa.FixedInfo -split "<br>"

    # --- A. Check vCenter ---
    if ($vmsa.Title -match "vCenter") {
        $VcMatched = $false
        
        # 1. Check Response Matrix Columns
        foreach ($row in $MatrixRows) {
            $parts = $row -split "\|"
            if ($parts.Count -ge 2) {
                $prodName = $parts[0].Trim()
                $verStr   = $parts[1].Trim() # e.g. "8.0 U2", "7.0.3"

                if ($prodName -match "vCenter") {
                    # Extract 1st digit from matrix version string
                    if ($verStr -match "^(\d+)") {
                        $MatrixMajor = $matches[1]
                        # Compare with Local Major Digit
                        if ($MatrixMajor -eq $VcMajorDigit) {
                            $VcMatched = $true
                        }
                    }
                }
            }
        }

        # 2. Fallback: If Matrix didn't match specific rows, check general AffectedMajors tag
        if (-not $VcMatched -and $vmsa.AffectedMajors -match "$VcMajorDigit\.") {
            $VcMatched = $true
        }

        if ($VcMatched) {
            $RelevantAssets += "vCenter ($VcVerFull)"
            $MatchedProductTypes += "vCenter"
        }
    }

    # --- B. Check ALL ESXi Hosts ---
    if ($vmsa.Title -match "ESXi") {
        foreach ($hostItem in $HostList) {
            $HostMatched = $false
            
            # 1. Check Response Matrix Columns
            foreach ($row in $MatrixRows) {
                $parts = $row -split "\|"
                if ($parts.Count -ge 2) {
                    $prodName = $parts[0].Trim()
                    $verStr   = $parts[1].Trim()

                    if ($prodName -match "ESXi") {
                        if ($verStr -match "^(\d+)") {
                            $MatrixMajor = $matches[1]
                            # Compare with Host Major Digit
                            if ($MatrixMajor -eq $hostItem.MajorDigit) {
                                $HostMatched = $true
                            }
                        }
                    }
                }
            }

            # 2. Fallback
            if (-not $HostMatched -and $vmsa.AffectedMajors -match "$($hostItem.MajorDigit)\.") {
                $HostMatched = $true
            }

            if ($HostMatched) {
                $RelevantAssets += "$($hostItem.Name) ($($hostItem.FullVer))"
                $MatchedProductTypes += "ESXi"
            }
        }
    }

    # --- Add to Report if ANY asset matches ---
    if ($RelevantAssets.Count -gt 0) {
        $RowIdCounter++
        
        # Format the "My Version" info (unique assets)
        $AssetStr = ($RelevantAssets | Select-Object -Unique) -join ", "
        
        # Determine Severity Class for HTML
        $Report += [PSCustomObject]@{
            RowID           = "row_$RowIdCounter"
            Type            = ($MatchedProductTypes | Select-Object -Unique) -join ", "
            MatchedAssets   = $AssetStr
            AdvisoryID      = $vmsa.AdvisoryID
            Title           = $vmsa.Title
            Severity        = $vmsa.Severity
            CVSS            = $vmsa.CVSS
            FixedIn         = $vmsa.FixedInfo
            Link            = $vmsa.Link
        }
    }
}

# --- 4. Output Results ---
if ($Report.Count -gt 0) {
    # CSV (Keep MatchedAssets for CSV)
    $Report | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    
    # HTML (Remove MatchedAssets column, move to Details)
    $HtmlRows = ""
    foreach ($row in $Report) {
        $sevClass = if ($row.Severity -match "Critical") { "crit" } elseif ($row.Severity -match "Important") { "warn" } else { "ok" }
        
        $HtmlRows += "<tr>"
        $HtmlRows += "<td><b>$($row.Type)</b></td>"
        # MatchedAssets column removed from here
        $HtmlRows += "<td><a href='$($row.Link)' target='_blank'>$($row.AdvisoryID)</a></td>"
        $HtmlRows += "<td>$($row.Title)</td>"
        $HtmlRows += "<td><span class='badge $sevClass'>$($row.Severity)</span></td>"
        $HtmlRows += "<td>$($row.CVSS)</td>"
        $HtmlRows += "<td><button class='btn-toggle' onclick=`"toggleDetails('$($row.RowID)')`">Details</button></td>"
        $HtmlRows += "</tr>"
        
        $HtmlRows += "<tr id='$($row.RowID)' class='details-row'>"
        $HtmlRows += "<td colspan='6'>" # Adjusted colspan
        $HtmlRows += "<div class='details-box'>"
        
        # Add Matched Assets info here
        $HtmlRows += "<strong>Matched Local Assets:</strong><br><span class='asset-text'>$($row.MatchedAssets)</span><br><br>"
        
        $HtmlRows += "<strong>Response Matrix (Fixed Versions):</strong><br><span class='info-text'>$($row.FixedIn)</span>"
        $HtmlRows += "</div></td></tr>"
    }

$HtmlContent = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<style>
    body { font-family: 'Segoe UI', sans-serif; padding: 20px; background: #f8fafc; color: #333; }
    h2 { border-bottom: 2px solid #2563eb; padding-bottom: 10px; color: #1e293b; }
    .meta { color: #64748b; margin-bottom: 15px; font-size: 0.9em; }
    table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    th { background: #e2e8f0; padding: 12px; text-align: left; font-size: 0.85em; text-transform: uppercase; color: #475569; }
    td { padding: 10px 12px; border-bottom: 1px solid #f1f5f9; font-size: 0.9em; vertical-align: middle; }
    
    .badge { padding: 3px 8px; border-radius: 4px; color: white; font-weight: bold; font-size: 0.8em; display: inline-block; }
    .crit { background: #dc2626; } .warn { background: #d97706; } .ok { background: #10b981; }
    
    .btn-toggle { background-color: #3b82f6; color: white; border: none; padding: 5px 10px; border-radius: 4px; cursor: pointer; font-size: 0.85em; }
    .btn-toggle:hover { background-color: #2563eb; }
    
    .details-row { display: none; background-color: #f1f5f9; }
    .details-box { padding: 15px; border-left: 4px solid #3b82f6; margin: 5px; background: white; border-radius: 4px; }
    .info-text { font-family: Consolas, monospace; color: #334155; font-size: 0.9em; white-space: pre-wrap; }
    .asset-text { font-family: 'Segoe UI', sans-serif; color: #b91c1c; font-weight: bold; font-size: 0.95em; }
    
    a { color: #2563eb; text-decoration: none; font-weight: bold; } a:hover { text-decoration: underline; }
</style>
<script>
    function toggleDetails(rowId) {
        var row = document.getElementById(rowId);
        row.style.display = (row.style.display === 'table-row') ? 'none' : 'table-row';
    }
</script>
</head>
<body>
    <h2>vSphere Security Audit Report (Air-Gapped / Major Ver Check)</h2>
    <div class="meta">Target: $vcServer | Data Source Date: $($JsonData.Metadata.GeneratedAt)</div>
    <table>
        <thead><tr>
            <th>Product</th><th>ID</th><th>Title</th><th>Severity</th><th>CVSS</th><th>Action</th>
        </tr></thead>
        <tbody>
            $HtmlRows
        </tbody>
    </table>
</body></html>
"@

    $HtmlContent | Out-File -FilePath $HtmlPath -Encoding UTF8
    
    Write-Host "`n[DONE] Report Generated." -ForegroundColor Green
    Write-Host " - CSV: $CsvPath"
    Write-Host " - HTML: $HtmlPath"
    Invoke-Item $HtmlPath
} else {
    Write-Host "`n[DONE] No relevant advisories found for your Major Versions." -ForegroundColor Green
}

Disconnect-VIServer -Confirm:$false
