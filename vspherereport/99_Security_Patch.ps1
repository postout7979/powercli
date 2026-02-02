# ===========================================================================
# [Broadcom Security Advisory Downloader]
# Broadcom 공식 API를 통해 최신 vSphere 보안 권고를 조회하고 HTML/CSV로 저장합니다.
# ===========================================================================

# --- [1] 기본 설정 ---
$Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$CurrentDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CurrentDir)) { $CurrentDir = Get-Location } # ISE/Console 호환

$CsvPath  = Join-Path $CurrentDir "Broadcom_Advisories_$Timestamp.csv"
$HtmlPath = Join-Path $CurrentDir "Broadcom_Advisories_$Timestamp.html"

Write-Host "[1] Starting Data Collection from Broadcom API..." -ForegroundColor Cyan

# --- [2] 데이터 수집 로직 ---
try {
    # Broadcom 내부 API 엔드포인트
    $ApiUrl = "https://support.broadcom.com/web/ecx/security-advisory/-/securityadvisory/getSecurityAdvisoryList"
    
    # 요청 본문 (Payload) - "VC" 세그먼트 (vSphere 포함)
    $Payload = @{
        pageNumber = 0
        pageSize   = 50
        searchVal  = ""
        sortInfo   = @{
            column = "published"
            order  = "DESC"
        }
    }
    $JsonPayload = $Payload | ConvertTo-Json -Depth 3

    # TLS 1.2 설정 (필수)
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # API 호출 (POST)
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $JsonPayload -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
    
    Write-Host "    -> API Connection Successful." -ForegroundColor Green

} catch {
    Write-Host " [!] API Connection Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# --- [3] 데이터 파싱 및 정렬 ---
$RawList = if ($Response.data -and $Response.data.list) { $Response.data.list } else { @() }
$ProcessedList = @()

foreach ($item in $RawList) {
    # 제품 필터링 (vCenter, ESXi, vSphere 등)
    if ($item.title -match "NSX") {
        
        # 날짜 정렬용 파싱
        $SortDate = Get-Date -Date "1970-01-01"
        try {
            if (-not [string]::IsNullOrWhiteSpace($item.published)) {
                $SortDate = [DateTime]::ParseExact($item.published.Trim(), "dd MMMM yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {
            try { $SortDate = Get-Date $item.updated } catch {}
        }

        # 객체 생성
        $ProcessedList += [PSCustomObject]@{
            _SortDate        = $SortDate
            documentId       = $item.documentId
            "published date" = $item.published
            status           = $item.status
            title            = $item.title
            "update date"    = $item.updated
            notificationUrl  = $item.notificationUrl
        }
    }
}

# 최신순 정렬 (상위 30개만 추출)
$FinalData = $ProcessedList | Sort-Object _SortDate -Descending | Select-Object -First 30 -Property documentId, "published date", status, title, "update date", notificationUrl

if ($FinalData.Count -eq 0) {
    Write-Host " [!] No relevant data found." -ForegroundColor Yellow
    exit
}

# --- [4] CSV 내보내기 ---
try {
    $FinalData | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "[2] CSV Saved: $CsvPath" -ForegroundColor Green
} catch {
    Write-Warning "Failed to save CSV: $($_.Exception.Message)"
}

# --- [5] HTML 내보내기 (스타일 적용) ---
try {
    $HtmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Broadcom Security Advisories</title>
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f4f4; padding: 20px; }
    h2 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
    table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-size: 14px; }
    td { padding: 12px; border-bottom: 1px solid #ddd; font-size: 13px; color: #333; }
    tr:hover { background-color: #f1f1f1; }
    a { color: #0078d4; text-decoration: none; font-weight: bold; }
    a:hover { text-decoration: underline; }
    .badge { padding: 4px 8px; border-radius: 4px; color: white; font-size: 11px; font-weight: bold; }
    .status-open { background-color: #d13438; } /* Red */
    .status-closed { background-color: #107c10; } /* Green */
</style>
</head>
<body>
    <h2>VMware vSphere Security Advisories (Latest 20)</h2>
    <p>Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th style="width: 120px;">Published</th>
                <th>Status</th>
                <th>Title</th>
                <th style="width: 150px;">Updated</th>
                <th>Link</th>
            </tr>
        </thead>
        <tbody>
"@
    
    $HtmlRows = ""
    foreach ($row in $FinalData) {
        # Status에 따른 색상 처리
        $StatusClass = if ($row.status -eq "OPEN") { "status-open" } else { "status-closed" }
        
        $HtmlRows += "<tr>"
        $HtmlRows += "<td><strong>$($row.documentId)</strong></td>"
        $HtmlRows += "<td>$($row.'published date')</td>"
        $HtmlRows += "<td><span class='badge $StatusClass'>$($row.status)</span></td>"
        $HtmlRows += "<td>$($row.title)</td>"
        $HtmlRows += "<td>$($row.'update date')</td>"
        $HtmlRows += "<td><a href='$($row.notificationUrl)' target='_blank'>View</a></td>"
        $HtmlRows += "</tr>"
    }

    $HtmlFooter = @"
        </tbody>
    </table>
</body>
</html>
"@

    # HTML 파일 저장
    $FinalHtml = $HtmlHeader + $HtmlRows + $HtmlFooter
    $FinalHtml | Out-File -FilePath $HtmlPath -Encoding UTF8
    
    Write-Host "[3] HTML Saved: $HtmlPath" -ForegroundColor Green
    
    # 생성된 파일 바로 실행
    Invoke-Item $HtmlPath

} catch {
    Write-Warning "Failed to save HTML: $($_.Exception.Message)"
}

Write-Host "`nDone." -ForegroundColor Cyan