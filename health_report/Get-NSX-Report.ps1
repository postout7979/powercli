# ==========================================================
# NSX Manager Login
# ==========================================================
$NsxManager = Read-Host "Enter NSX Manager (FQDN or IP)"
if ([string]::IsNullOrWhiteSpace($NsxManager)) {
    Write-Host "Error: No NSX Manager address entered. Exiting." -ForegroundColor Red; exit 
}

# Define the credential file path (same directory as the script) - Default Disabled
$CredPath = Join-Path $PSScriptRoot "NSXCreds.xml"

if (Test-Path $CredPath) { $Creds = Import-CliXml $CredPath }
else { $Creds = Get-Credential; $Creds | Export-CliXml $CredPath }

################################################################################
# --- Temporary test login ---
# $NsxManager = "172.18.10.102" # NSX Manager IP/FQDN
# $Pass = "EtsTanzu1!2@3#"
# $User = "admin"
# $SecPass = ConvertTo-SecureString $Pass -AsPlainText -Force
# $Creds = New-Object System.Management.Automation.PSCredential($User, $SecPass)
################################################################################

# --- [플러그인 실행] ---
$PluginFolder = Join-Path $PSScriptRoot "plugins\nsxplugins"
$ReportFolder = Join-Path $PSScriptRoot "reports\nsxt"
$TempFolder = Join-Path $ReportFolder "temp_$Timestamp"
$Timestamp = Get-Date -Format 'yyyyMMdd'
$CsvPath = Join-Path $ReportFolder "NSX_Report_$Timestamp.csv"
$ReportPath = Join-Path $ReportFolder "NSX_Report_$Timestamp.html"

# 폴더가 없으면 생성
if (!(Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder }
if (!(Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder }

if (Test-Path $CredPath) { $Creds = Import-CliXml $CredPath }
else { $Creds = Get-Credential; $Creds | Export-CliXml $CredPath }

# If no credentials loaded (file missing or corrupted), prompt user
if ($null -eq $Creds) {
    Write-Host "[Auth] No saved credentials found. Please log in." -ForegroundColor Cyan
    $Creds = Get-Credential -UserName "admin" -Message "Enter NSX Credentials"
    
    # Save for next time
    $Creds | Export-CliXml -Path $CredPath
    Write-Host "[Auth] Credentials saved securely to: $CredPath" -ForegroundColor Green
}
# Login Function
function Connect-NSXmanager {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NsxManager,
        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    # SSL 인증서 검증 무시
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

	#$AuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("{$User}:{$Pass}"))
    $user = $Credential.UserName
    $pass = $Credential.GetNetworkCredential().Password
    $authBody = "j_username=$user&j_password=$pass"
    $Url = "https://$NsxManager/api/session/create"

    try {
        # 1. 로그인 시도 (Invoke-WebRequest 사용 - 헤더 접근 용이)
        $response = Invoke-WebRequest -Uri $Url -Method Post -Body $authBody -SessionVariable "nsxSession" -Headers @{"Content-Type" = "application/x-www-form-urlencoded"}

        # 2. 응답 헤더에서 X-NSX-XSRF-TOKEN 추출
        $xsrfToken = ""
        if ($response.Headers.ContainsKey("X-XSRF-TOKEN")) {
            $xsrfToken = $response.Headers["X-XSRF-TOKEN"]
        }

        # 3. 세션과 토큰을 포함한 객체 반환
        return [PSCustomObject]@{
            WebSession = $nsxSession
            XsrfToken  = $xsrfToken
        }
    }
    catch {
        Write-Error "Error during login: $_"
        return $null
    }
}

# Logout Function
function Disconnect-NSXmanager {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NsxManager,
        #[Parameter(Mandatory=$true)]
        #$WebSession,
        [Parameter(Mandatory=$true)]
		[string]$XsrfToken
    )

		$Headers = @{ 
			"X-XSRF-TOKEN" = $XsrfToken
			"Accept"       = "application/json"
		}

    # SSL 인증서 검증 무시
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
	
    if ($WebSession) {
        try {
			# API Session logout
            $Uri = "https://$NsxManager/api/session"
            $response = Invoke-RestMethod -Method POST -Uri $Uri -Headers $Headers
            return $response
        } catch {
            Write-Host ">>> Logout Warning: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }
}

### --- Connect NSX Manager login --- ###
$Results = Connect-NSXmanager -NsxManager $NsxManager -Credential $Creds
$Results.WebSession

if ($null -eq $Results) {
    Write-Host "Terminating script due to login failure." -ForegroundColor Red
    exit
}

$PluginFiles = Get-ChildItem -Path $PluginFolder -Filter "*.ps1" | Where-Object { !$_.PSIsContainer } | Sort-Object Name
if ($PluginFiles.Count -eq 0) {
    Write-Host " [!] No .ps1 plugin files found in $PluginFolder" -ForegroundColor Yellow
}

### All ps1 files run ###
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

    if ($File.Extension -eq ".ps1" -and $File.Name -ne "00_Summary.ps1") {
        $ModuleName = $File.BaseName
        Write-Host " -> Executing: [$ModuleName]" -ForegroundColor White
        try {
            # 데이터 수집 (반드시 @()로 감싸서 배열임을 보장)
            $Data = & $File.FullName -Server $NsxManager -SessionId $Results.WebSession -XsrfToken $Results.XsrfToken
            
            # 데이터가 null이 아닐 때만 저장
            if ($null -ne $Data) { 
                $GlobalResults[$ModuleName] = $Data 
            }
        } catch {
            Write-Host " [!] Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# csv file 
foreach ($Key in $GlobalResults.Keys) {
    $Items = @($GlobalResults[$Key])
    if ($Items.Count -gt 0) {
        # 각 섹션별 개별 CSV 생성 (임시 폴더)
        $CleanKey = $Key -replace "[^a-zA-Z0-9]", "_"
        $TempFile = Join-Path $TempFolder "$CleanKey.csv"
        
        # 1차 저장 (컬럼 충돌 방지)
        $Items | Export-Csv -Path $TempFile -NoTypeInformation -Encoding UTF8
    }
}

# 모든 CSV를 하나의 통합 파일로 병합
Write-Host "Merging reports into: $CsvPath" -ForegroundColor Cyan

# 통합 파일 헤더 작성
$HeaderInfo = @"
=====================================================
 NSX INFRASTRUCTURE HEALTH CHECK - COMBINED REPORT
 Generated At : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
 Target Server: $Server
=====================================================
"@
$HeaderInfo | Out-File -FilePath $CsvPath -Encoding UTF8

# 임시 파일들을 하나씩 읽어서 병합
$TempFiles = Get-ChildItem -Path $TempFolder -Filter "*.csv"
foreach ($File in $TempFiles) {
    # 섹션 구분선 및 이름 추가
    "`n[ SECTION : $($File.BaseName) ]" | Out-File -FilePath $CsvPath -Append -Encoding UTF8
    "-----------------------------------------------------" | Out-File -FilePath $CsvPath -Append -Encoding UTF8
    
    # CSV 내용 병합
    Get-Content -Path $File.FullName | Out-File -FilePath $CsvPath -Append -Encoding UTF8
}

# 3. 임시 폴더 삭제 (정리)
if (Test-Path $TempFolder) { Remove-Item -Path $TempFolder -Recurse -Force }

Write-Host "Success! Final CSV saved at: $CsvPath" -ForegroundColor Green


# 헤더 및 스타일 정의 (유동적 폭 + 네비게이션 바)
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
</style>
<script>
    function showIp(el) { el.innerText = el.getAttribute('data-ip'); }
    function hideIp(el) { el.innerText = '***.***.***.***'; }
</script>
</head>
<body>
<nav class='sidebar'>
    <h2>Sidebar Menu</h2>
    <ul class='nav-list'>
"@

# 2. 네비게이션 리스트 생성
foreach ($Key in $GlobalResults.Keys) {
    $Anchor = $Key -replace "[^a-zA-Z0-9]", "_"
    $HtmlHead += "<li><a href='#$Anchor'>$Key</a></li>"
}

# 3. 메인 배너 및 대시보드 요약
$HtmlHead += @"
</ul></nav><div class='main-content'><div class='header-banner'>
<h1 style='margin:0;'>NSX Manager Healthcheck Report</h1>
<p>Controller: $NsxManager | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p></div>
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
                #$c = if($v -match "UP|RUNNING|OK|SUCCESS") { "status-ok" } elseif($v -match "DOWN|CRITICAL|ERROR|FAILED|STOPPED") { "status-crit" } elseif($v -match "WARN|WARNING|PROGRESS") { "status-warn" } else { "" }
                #$tdValue = if($c) { "<span class='badge $c'>$v</span>" } else { $v }
                $HtmlBody += "<td>$v</td>"
            }
            $HtmlBody += "</tr>"
        }
        $HtmlBody += "</tbody></table></div>"
    }
}

$HtmlFoot = "</div></body></html>"
$HtmlHead + $HtmlBody + $HtmlFoot | Out-File $ReportPath -Encoding UTF8
Write-Host "[3/3] Report Generated: $ReportPath" -ForegroundColor Green
# --- pop-up browser --- #
Invoke-Item $ReportPath
# --- Close NSX Session --- #
$Close_Results = Disconnect-NSXmanager -NsxManager $NsxManager -XsrfToken $Results.XsrfToken
# $Close_Results = Disconnect-NSXmanager -NsxManager $NsxManager -XsrfToken $Results.XsrfToken -WebSession $Results.WebSession
exit


