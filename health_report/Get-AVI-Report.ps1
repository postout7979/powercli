# Current path
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define the credential file path (same directory as the script) - Default Disabled
$CredPath = Join-Path $PSScriptRoot "AviCreds.xml"

# Default path
$PluginFolder = Join-Path $PSScriptRoot "plugins\aviplugins"
$ReportFolder = Join-Path $PSScriptRoot "reports\avi"
$TempFolder = Join-Path $ReportFolder "temp_$Timestamp"
$CsvPath = Join-Path $ReportFolder "Avi_Report_$Timestamp.csv"
$ReportPath = Join-Path $ReportFolder "Avi_Report_$Timestamp.html"

# Skip TLS Verify
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12

# --- [기본 설정 및 환경 정의] ---
# --- Temporary test login ---
# $Avi_IP = "172.18.10.220" # Avi Controller IP/FQDN
# $User = "admin"
# $Pass = "VMware1!"
$Timestamp = Get-Date -Format 'yyyyMMdd'
################################################################################

# ==========================================================
# Avi Controller Login
# ==========================================================
$Avi_IP = Read-Host "Enter Avi Controller (FQDN or IP)"
if ([string]::IsNullOrWhiteSpace($Avi_IP)) {
    Write-Host "Error: Avi Controller address entered. Exiting." -ForegroundColor Red; exit 
}

if (Test-Path $CredPath) { $Creds = Import-CliXml $CredPath }
else { $Creds = Get-Credential; $Creds | Export-CliXml $CredPath }

# If no credentials loaded (file missing or corrupted), prompt user
if ($null -eq $Creds) {
    Write-Host "[Auth] No saved credentials found. Please log in." -ForegroundColor Cyan
    $Creds = Get-Credential -UserName "admin" -Message "Enter Avi Credentials"
    
    # Save for next time
    $Creds | Export-CliXml -Path $CredPath
    Write-Host "[Auth] Credentials saved securely to: $CredPath" -ForegroundColor Green
}

# 폴더 생성
if (!(Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder -Force }
if (!(Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder -Force }

# 
$User = $Creds.UserName
$Pass = $Creds.GetNetworkCredential().Password

# --- [Avi Controller 로그인 및 세션 획득] ---
Write-Host "Avi Controller login progress... ($Avi_IP)" -ForegroundColor Cyan

$LoginUrl = "https://$Avi_IP/login"
$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$Body = @{ username = $User; password = $Pass }

try {
    # 1차 로그인 시도 (Cookie 및 CSRF Token 획득)
    $LoginRes = Invoke-RestMethod -Method Post -Uri $LoginUrl -Body $Body -WebSession $Session -ErrorAction Stop
	# $node.version이 객체 형태일 때 'version number'만 추출하여 저장
	$NodeVersion = if ($LoginRes.version.Version) { $LoginRes.version.Version } else { "22.1.7" }	
    $Cookies = $Session.Cookies.GetCookies($LoginUrl)
    $XsrfToken = ($Cookies | Where-Object { $_.Name -eq "csrftoken" }).Value
    
    if (-not $XsrfToken) { throw "CSRF Token을 찾을 수 없습니다." }
    Write-Host " -> Login Successed!" -ForegroundColor Green
} catch {
    Write-Host " [!] Login Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# --- [플러그인 실행] ---
Write-Host "Collect plugin data..." -ForegroundColor Cyan

# Summary 데이터 우선 실행 (00_Summary.ps1)
$Summary = $null
$SummaryFile = Join-Path $PluginFolder "00_Summary.ps1"
if (Test-Path $SummaryFile) {
    Write-Host " -> Executing Summary Dashboard..." -ForegroundColor White
    $Summary = & $SummaryFile -Server $Avi_IP -SessionId $Session -XsrfToken $XsrfToken -version $NodeVersion
}

$PluginFiles = Get-ChildItem -Path $PluginFolder -Filter "*.ps1" | Where-Object { $_.Name -ne "00_Summary.ps1" } | Sort-Object Name

$GlobalResults = [ordered]@{}
$CurrentIndex = 0
$TotalPlugins = $PluginFiles.count

foreach ($File in $PluginFiles) {
	$CurrentIndex++
	$Percent = [Math]::Round(($CurrentIndex / $TotalPlugins) * 100)
		Write-Progress -Activity "Creating healthcheck report" `
					   -Status "Current task: $File ($CurrentIndex / $TotalPlugins)" `
					   -PercentComplete $Percent `
					   -CurrentOperation "Collecting API Data..."

    $ModuleName = $File.BaseName
    Write-Host " -> Executing: [$ModuleName]" -ForegroundColor White
    try {
        $Data = & $File.FullName -Server $Avi_IP -SessionId $Session -XsrfToken $XsrfToken -version $NodeVersion
        if ($null -ne $Data) { $GlobalResults[$ModuleName] = $Data }
    } catch {
        Write-Host "    [!] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- [CSV 리포트 생성 및 병합] ---
foreach ($Key in $GlobalResults.Keys) {
    $Items = @($GlobalResults[$Key])
    if ($Items.Count -gt 0) {
        $CleanKey = $Key -replace "[^a-zA-Z0-9]", "_"
        $Items | Export-Csv -Path (Join-Path $TempFolder "$CleanKey.csv") -NoTypeInformation -Encoding UTF8
    }
}

# CSV 병합 로직
"AVI INFRASTRUCTURE HEALTH REPORT`nGenerated At: $(Get-Date)" | Out-File $CsvPath -Encoding UTF8
Get-ChildItem $TempFolder -Filter "*.csv" | ForEach-Object {
    "`n[ SECTION : $($_.BaseName) ]`n" + ("-"*50) | Out-File $CsvPath -Append -Encoding UTF8
    Get-Content $_.FullName | Out-File $CsvPath -Append -Encoding UTF8
}
Remove-Item $TempFolder -Recurse -Force

# --- [HTML 리포트 생성] ---
$HtmlHead = @"
<html>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<style>
    :root {
        --primary: #005bb7;
        --secondary: #1a202c;
        --success: #10b981;
        --danger: #ef4444;
        --warning: #f59e0b;
        --bg: #f8fafc;
        --card-bg: #ffffff;
    }
    body { font-family: 'Inter', -apple-system, sans-serif; background-color: var(--bg); margin: 0; display: flex; height: 100vh; overflow: hidden; color: #334155; }
    
    /* 좌측 사이드바 */
    .sidebar { width: 260px; background-color: var(--secondary); color: white; padding: 24px; overflow-y: auto; flex-shrink: 0; box-shadow: 4px 0 10px rgba(0,0,0,0.1); }
    .sidebar h2 { font-size: 1.1em; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 24px; border-bottom: 1px solid #2d3748; padding-bottom: 12px; }
    .nav-list { list-style: none; padding: 0; }
    .nav-list li { margin-bottom: 8px; }
    .nav-list a { color: #cbd5e0; text-decoration: none; font-size: 0.95em; display: block; padding: 10px 14px; border-radius: 8px; transition: all 0.2s; }
    .nav-list a:hover { background-color: #2d3748; color: white; transform: translateX(5px); }

    /* 메인 영역 */
    .main-content { flex-grow: 1; padding: 40px; overflow-y: auto; scroll-behavior: smooth; }
    .header-banner { display: flex; justify-content: space-between; align-items: center; margin-bottom: 32px; background: white; padding: 24px; border-radius: 16px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); }
    .header-banner h1 { margin: 0; font-size: 1.8em; color: var(--primary); font-weight: 800; }
    
    /* 요약 카드 */
    .summary-container { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 32px; }
    .summary-card { background: white; padding: 24px; border-radius: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border-top: 4px solid var(--primary); text-align: center; }
    .summary-card .label { font-size: 0.85em; color: #64748b; font-weight: 600; margin-bottom: 8px; }
    .summary-card .value { font-size: 2em; font-weight: 800; color: var(--secondary); }

    /* 데이터 카드 */
    .card { background: var(--card-bg); border-radius: 16px; padding: 24px; margin-bottom: 32px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); border: 1px solid #e2e8f0; }
    .card h3 { margin-top: 0; font-size: 1.25em; margin-bottom: 20px; display: flex; align-items: center; gap: 10px; color: var(--secondary); }
    .card h3::before { content: ''; display: inline-block; width: 4px; height: 18px; background: var(--primary); border-radius: 2px; }

    /* 테이블 */
    .table-wrapper { width: 100%; overflow-x: auto; border-radius: 12px; border: 1px solid #f1f5f9; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th { background-color: #f8fafc; padding: 14px; font-size: 0.75em; text-transform: uppercase; color: #475569; letter-spacing: 0.05em; border-bottom: 2px solid #e2e8f0; }
    td { padding: 14px; border-bottom: 1px solid #f1f5f9; font-size: 0.9em; color: #334155; }
    tr:hover { background-color: #f1f5f9; }

    /* 배지 & 특수 효과 */
    .badge { padding: 6px 12px; border-radius: 9999px; font-size: 0.75em; font-weight: 700; color: white; display: inline-block; text-transform: uppercase; }
    .status-ok { background-color: var(--success); }
    .status-crit { background-color: var(--danger); }
    .status-warn { background-color: var(--warning); color: #78350f; }

	/* PDF 인쇄 시 사이드바 숨김 처리 */
	@media print {
		.sidebar { display: none; }
		.main-content { margin-left: 0; padding: 0; }
		.section-cards { box-shadow: none; border: 1px solid #eee; page-break-inside: avoid; }
	}
</style>
<script>
    function showIp(el) { el.innerText = el.getAttribute('data-ip'); }
    function hideIp(el) { el.innerText = '***.***.***.***'; }
</script>
</head>
<body>
<nav class='sidebar'>
    <h2>Sidebar MENU</h2>
    <ul class='nav-list'>
		<li><a href='#top'>Dashboard Home</a></li>
"@

foreach ($Key in $GlobalResults.Keys) {
    $Anchor = $Key -replace "[^a-zA-Z0-9]", "_"
    $HtmlHead += "<li><a href='#$Anchor'>$Key</a></li>"
}

$HtmlHead += "</ul></nav><div class='main-content'><div class='header-banner'>"
$HtmlHead += "<h1 style='margin:0;'>Avi Vantage Healthcheck Report</h1>"
$HtmlHead += "<p>Controller: $Avi_IP | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p></div>"

# 대시보드 요약 (00_Summary 데이터 사용)
$HtmlBody = @"
<div style='display: flex; justify-content: space-around; background: #2d3748; color:white; padding: 20px; border-radius: 10px; margin-bottom: 25px;'>
    <div style='text-align: center;'><div>Service Engines</div><div style='font-size: 1.8em; font-weight: bold;'>$($Summary.ServiceEngines)</div></div>
    <div style='text-align: center;'><div>Virtual Services</div><div style='font-size: 1.8em; font-weight: bold;'>$($Summary.VirtualServices)</div></div>
    <div style='text-align: center;'><div>Pools</div><div style='font-size: 1.8em; font-weight: bold;'>$($Summary.Pools)</div></div>
</div>
"@

foreach ($Key in $GlobalResults.Keys) {
    $Anchor = $Key -replace "[^a-zA-Z0-9]", "_"
    $Items = @($GlobalResults[$Key])
    if ($Items.Count -gt 0) {
        $Props = $Items | ForEach-Object { $_.psobject.Properties.Name } | Select-Object -Unique
        $HtmlBody += "<div class='card' id='$Anchor'><h3>$Key</h3><table><thead><tr>"
        $HtmlBody += ($Props | ForEach-Object { "<th>$_</th>" }) -join ""
        $HtmlBody += "</tr></thead><tbody>"
        foreach ($i in $Items) {
            $HtmlBody += "<tr>"
            foreach ($p in $Props) {
                $v = [string]$i.$p
                $c = if($v -match "UP|RUNNING|OK|ACTIVE") { "status-ok" } elseif($v -match "DOWN|CRITICAL|ERROR|FAILED") { "status-crit" } elseif($v -match "WARN|PROGRESS") { "status-warn" } else { "" }
                $tdValue = if($c) { "<span class='badge $c'>$v</span>" } else { $v }
                $HtmlBody += "<td>$tdValue</td>"
            }
            $HtmlBody += "</tr>"
        }
        $HtmlBody += "</tbody></table></div>"
    }
}

$ExportHTML = $HtmlHead + $HtmlBody + "</div></body></html>"
$ExportHTML | Out-File $ReportPath -Encoding UTF8

# HTML 파일 경로
Write-Host "Report Generated: $ReportPath" -ForegroundColor Green
Invoke-Item $ReportPath

# ==========================================================
# Avi Controller Logout
# ==========================================================
Write-Host "Logging out from Avi Controller..." -ForegroundColor Cyan

if ($Session -and $XsrfToken) {
    $LogoutUrl = "https://$Avi_IP/logout"
    
    # 로그아웃 시 X-CSRFToken과 Referer 헤더가 필수적으로 요구됨
    $LogoutHeaders = @{
        "X-CSRFToken" = $XsrfToken
        "Referer"     = "https://$Avi_IP/"
    }

    try {
        Invoke-RestMethod -Method Post -Uri $LogoutUrl -Headers $LogoutHeaders -WebSession $Session -ErrorAction Stop
        Write-Host " -> Logout Success!" -ForegroundColor Green
    } catch {
        # 이미 세션이 만료되었거나 네트워크 이슈가 있어도 스크립트 종료에는 영향 없도록 Warning 처리
        Write-Host " [!] Logout Failed or Session already expired: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host " [!] No active session found to logout." -ForegroundColor Yellow
}

exit

exit