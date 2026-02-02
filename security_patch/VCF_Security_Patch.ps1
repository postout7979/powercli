# ===========================================================================
# [Broadcom Security Advisory Downloader]
# Broadcom 공식 API를 통해 최신 vSphere 보안 권고를 조회하고 HTML/CSV로 저장합니다.
# 수정사항: Link 컬럼을 URL 문자열 대신 클릭 가능한 "View" 텍스트로 변환
# ===========================================================================

# --- [1] 기본 설정 ---
$Timestamp = Get-Date -Format "yyyyMMdd"
$CurrentDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CurrentDir)) { $CurrentDir = Get-Location }

$CsvPath  = Join-Path $CurrentDir "Broadcom_Advisories_$Timestamp.csv"
$HtmlPath = Join-Path $CurrentDir "Broadcom_Advisories_$Timestamp.html"

Write-Host "[1] Starting Data Collection from Broadcom API..." -ForegroundColor Cyan

# --- [2] 데이터 수집 로직 ---
try {
    $ApiUrl = "https://support.broadcom.com/web/ecx/security-advisory/-/securityadvisory/getSecurityAdvisoryList"
    
    $Payload = @{
        pageNumber = 0
        pageSize   = 100
        searchVal  = ""
        segment    = "VC"
        sortInfo   = @{ column = "published"; order = "DESC" }
    }
    $JsonPayload = $Payload | ConvertTo-Json -Depth 3

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $JsonPayload -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
    
    Write-Host "    -> API Connection Successful." -ForegroundColor Green

} catch {
    Write-Host " [!] API Connection Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# --- [3] 데이터 파싱 및 정렬 ---
$RawList = $Response.data.list
$ProcessedList = @()

foreach ($item in $RawList) {
    if ($item.title -match "ESXi|vCenter|vSphere|Cloud Foundation") {
        $SortDate = Get-Date -Date "1970-01-01"
        try {
            if (-not [string]::IsNullOrWhiteSpace($item.published)) {
                $SortDate = [DateTime]::ParseExact($item.published.Trim(), "dd MMMM yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {
            try { $SortDate = Get-Date $item.updated } catch {}
        }

        # 객체 생성 (Link로 이름 통일)
        $ProcessedList += [PSCustomObject][ordered]@{
            _SortDate        = $SortDate
            ID               = $item.documentId
            Published        = $item.published
            Severity         = $item.severity
            Status           = $item.status
            Title            = $item.title
            Updated          = $item.updated
            Link             = $item.notificationUrl # 이 값이 "View"로 변환됨
        }
    }
}

# 최신순 정렬 (상위 30개)
$Items = $ProcessedList | Sort-Object _SortDate -Descending | Select-Object -First 30

if ($Items.Count -eq 0) {
    Write-Host " [!] No relevant data found." -ForegroundColor Yellow
    exit
}

# --- [4] CSV 내보내기 ---
$Items | Select-Object * -ExcludeProperty _SortDate | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
Write-Host "[2] CSV Saved: $CsvPath" -ForegroundColor Green

# --- [5] HTML 내보내기 ---
try {
    $HtmlHead = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Broadcom Security Advisories</title>
<style>
    :root { --primary: #005bb7; --secondary: #1a202c; --success: #10b981; --danger: #ef4444; --warning: #f59e0b; --bg: #f8fafc; --card-bg: #ffffff; }
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg); color: #334155; padding: 40px; }
    h2 { color: var(--secondary); border-bottom: 2px solid var(--primary); padding-bottom: 10px; margin-bottom: 20px; }
    
    .card { background: var(--card-bg); border-radius: 12px; padding: 20px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 30px; }
    .card h3 { margin-top: 0; font-size: 1.25em; color: var(--secondary); border-left: 5px solid var(--primary); padding-left: 10px; margin-bottom: 20px; }

    .table-wrapper { width: 100%; overflow-x: auto; border-radius: 8px; border: 1px solid #e2e8f0; }
    table { width: 100%; border-collapse: collapse; text-align: left; background: white; }
    th { background-color: #f1f5f9; padding: 12px; font-size: 0.85em; text-transform: uppercase; color: #64748b; font-weight: 700; border-bottom: 2px solid #e2e8f0; }
    td { padding: 12px; border-bottom: 1px solid #f1f5f9; font-size: 0.9em; color: #334155; vertical-align: middle; }
    tr:hover { background-color: #f8fafc; }

    .badge { padding: 4px 8px; border-radius: 9999px; font-size: 0.75em; font-weight: 700; color: white; display: inline-block; text-transform: uppercase; }
    .status-ok { background-color: var(--success); }
    .status-crit { background-color: var(--danger); }
    .status-warn { background-color: var(--warning); color: #fff; }
    
    /* View 링크 버튼 스타일 */
    a.btn-view { color: var(--primary); text-decoration: none; font-weight: 700; border: 1px solid var(--primary); padding: 4px 12px; border-radius: 4px; transition: all 0.2s; }
    a.btn-view:hover { background-color: var(--primary); color: white; }
</style>
</head>
<body>
    <h2>VMware vSphere Security Advisories</h2>
"@

    $HtmlBody = ""
    $Key = "Security Advisories List (Latest 30)"
    $Anchor = "advisories"

    if ($Items.Count -gt 0) {
        # 1. 속성 헤더 추출
        $Props = $Items[0].psobject.Properties.Name | Select-Object -Unique | Where-Object { $_ -notmatch "ovf|psobject|extensiondata|_SortDate" }
        
        $HtmlBody += "<div class='card' id='$Anchor'><h3>$Key</h3><div class='table-wrapper'><table><thead><tr>"
        $HtmlBody += ($Props | ForEach-Object { "<th>$_</th>" }) -join ""
        $HtmlBody += "</tr></thead><tbody>"
        
        # 2. 데이터 반복 출력
        foreach ($i in $Items) {
            $HtmlBody += "<tr>"
            foreach ($p in $Props) {
                $v = [string]$i.$p
                
                # 기본값은 원본 텍스트
                $tdValue = $v
                
                # =========================================================
                # [수정됨] Link 또는 notificationUrl 컬럼인 경우 "View" 링크로 변환
                # =========================================================
                if (($p -eq "Link" -or $p -eq "notificationUrl") -and $v -match "^http") {
                    $tdValue = "<a href='$v' target='_blank' class='btn-view'>View</a>"
                }
                # 그 외: 상태 배지 로직 적용
                else {
                    $c = ""
                    if ($v -match "OK|SUCCESS|ACTIVE|READY|PoweredOn|CLOSED") { $c = "status-ok" }
                    elseif ($v -match "DOWN|CRITICAL|ERROR|FAILED|PoweredOff|OPEN") { $c = "status-crit" }
                    elseif ($v -match "WARN|PROGRESS|UNKNOWN|DEGRADED|Important") { $c = "status-warn" }
                    
                    if ($c) { $tdValue = "<span class='badge $c'>$v</span>" }
                }
                
                $HtmlBody += "<td>$tdValue</td>"
            }
            $HtmlBody += "</tr>"
        }
        $HtmlBody += "</tbody></table></div></div>"
    } else {
        $HtmlBody += "<div class='card' id='$Anchor'><h3>$Key</h3><p style='color:#94a3b8; font-style:italic;'>데이터가 존재하지 않습니다.</p></div>"
    }

    $FinalHtml = $HtmlHead + $HtmlBody + "</body></html>"
    $FinalHtml | Out-File -FilePath $HtmlPath -Encoding UTF8
    
    Write-Host "[3] HTML Saved: $HtmlPath" -ForegroundColor Green
    Invoke-Item $HtmlPath

} catch {
    Write-Warning "Failed to save HTML: $($_.Exception.Message)"
}

Write-Host "`nDone." -ForegroundColor Cyan