# ==========================================================
# vSphere Total Health Check (v1.0 - Automated Credentials)
# By Insung Choi from Broadcom
# ==========================================================
$vCenterServer = Read-Host "Enter vCenter Server (FQDN or IP)"
if ([string]::IsNullOrWhiteSpace($vCenterServer)) { 
    Write-Host "Error: No vCenter address entered. Exiting." -ForegroundColor Red; exit 
}

$CredPath = Join-Path $PSScriptRoot "mycredential.xml"

if (Test-Path $CredPath) { $Creds = Import-CliXml $CredPath }
else { 
	Write-Host "[Auth] No saved credentials found. Please log in." -ForegroundColor Cyan
	$Creds = Get-Credential -UserName "readuser@vsphere.local" -Message "Enter vCenter Credentials"; $Creds
    
    # Save for next time
    $Creds | Export-CliXml -Path $CredPath
    Write-Host "[Auth] Credentials saved securely to: $CredPath" -ForegroundColor Green
}

# --- [기본 설정] ---
$ScriptPath = $PSScriptRoot
$Timestamp = Get-Date -Format 'yyyyMMdd'

# --- new plugin path ---
$PluginFolder = Join-Path $PSScriptRoot "plugins\vmplugins"
$ReportFolder = Join-Path $PSScriptRoot "reports\vsphere"

$TempFolder = Join-Path $ReportFolder "temp_$Timestamp"
$ReportPath = Join-Path $ReportFolder "VM_Report_$Timestamp.html"
$CsvPath = Join-Path $ReportFolder "VM_Report_$Timestamp.csv"

# 폴더가 없으면 생성
if (!(Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder }
if (!(Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder }

# 외부 함수 파일 로드 (Dot Sourcing)
. "$ScriptPath\Connect-Vcenter.ps1"
. "$ScriptPath\Disconnect-Vcenter.ps1"

# --- PowerCLI Login ---
#connect-viserver -server $vCenterServer -Credential $Creds

try {
    # PowerCLI 연결
    $Connection = connect-viserver -server $vCenterServer -Credential $Creds -ErrorAction Stop
    Write-Host " [OK] PowerCLI Connected to $Server" -ForegroundColor Green
}
catch {
    Write-Error "PowerCLI 연결 실패: $($_.Exception.Message)"
    exit
}

# --- [1] API vCenter 로그인 ---
$SessionId = Connect-Vcenter -Server $vCenterServer -Credential $Creds

if ($null -eq $SessionId) {
    Write-Host "Terminating script due to login failure." -ForegroundColor Red
    exit
}

$PluginFiles = Get-ChildItem -Path $PluginFolder -Filter "*.ps1" | Where-Object { !$_.PSIsContainer } | Sort-Object Name

$GlobalResults = [ordered]@{}

if ($PluginFiles.Count -eq 0) {
    Write-Host " [!] No .ps1 plugin files found in $PluginFolder" -ForegroundColor Yellow
}

$CurrentIndex = 0
$TotalPlugins = $PluginFiles.count

foreach ($File in $PluginFiles) {
	$CurrentIndex++
	$Percent = [Math]::Round(($CurrentIndex / $TotalPlugins) * 100)
		Write-Progress -Activity "Creating healthcheck report" `
					   -Status "Current task: $File ($CurrentIndex / $TotalPlugins)" `
					   -PercentComplete $Percent `
					   -CurrentOperation "Collecting API Data..."
    if ($File.Extension -eq ".ps1") {
        $ModuleName = $File.BaseName
        Write-Host " -> Executing: [$ModuleName]" -ForegroundColor White
        try {
            # 데이터 수집 (반드시 @()로 감싸서 배열임을 보장)
            $RawData = & $File.FullName -Server $vCenterServer -SessionId $SessionId
            # 데이터가 null이 아닐 때만 저장
            if ($null -ne $RawData) { $GlobalResults[$ModuleName] = $RawData }
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


# --- [3] HTML 생성 (데이터 파싱 및 섹션 구성) ---
Write-Host ">>> Building Dashboard with Modern UI Style..." -ForegroundColor Green

# 1. 헤더 및 사이드바 시작
$HtmlHead = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>vSphere Health Report</title>
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
    
    /* 요약 카드 그리드 */
    .summary-container { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 32px; }
    .summary-card { background: white; padding: 24px; border-radius: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border-top: 4px solid var(--primary); text-align: center; }
    .summary-card .label { font-size: 0.85em; color: #64748b; font-weight: 600; margin-bottom: 8px; }
    .summary-card .value { font-size: 2em; font-weight: 800; color: var(--secondary); }

    /* 데이터 카드 */
    .card { background: var(--card-bg); border-radius: 16px; padding: 24px; margin-bottom: 32px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); border: 1px solid #e2e8f0; scroll-margin-top: 30px; }
    .card h3 { margin-top: 0; font-size: 1.25em; margin-bottom: 20px; display: flex; align-items: center; gap: 10px; color: var(--secondary); }
    .card h3::before { content: ''; display: inline-block; width: 4px; height: 18px; background: var(--primary); border-radius: 2px; }

    /* 테이블 */
    .table-wrapper { width: 100%; overflow-x: auto; border-radius: 12px; border: 1px solid #f1f5f9; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th { background-color: #f8fafc; padding: 14px; font-size: 0.75em; text-transform: uppercase; color: #475569; letter-spacing: 0.05em; border-bottom: 2px solid #e2e8f0; }
    td { padding: 14px; border-bottom: 1px solid #f1f5f9; font-size: 0.9em; color: #334155; }
    tr:hover { background-color: #f1f5f9; }

    /* 배지 */
    .badge { padding: 6px 12px; border-radius: 9999px; font-size: 0.75em; font-weight: 700; color: white; display: inline-block; text-transform: uppercase; }
    .status-ok { background-color: var(--success); }
    .status-crit { background-color: var(--danger); }
    .status-warn { background-color: var(--warning); color: #78350f; }

    @media print {
        .sidebar { display: none; }
        .main-content { margin-left: 0; padding: 0; }
        .card { box-shadow: none; border: 1px solid #eee; page-break-inside: avoid; }
    }
</style>
</head>
<body>
<nav class='sidebar'>
    <h2>Sidebar MENU</h2>
    <ul class='nav-list'>
        <li><a href='#top'>Dashboard Home</a></li>
"@

# 사이드바 메뉴 동적 생성
foreach ($Key in $GlobalResults.Keys) {
    $Anchor = $Key -replace "[^a-zA-Z0-9]", "_"
    $HtmlHead += "<li><a href='#$Anchor'>$Key</a></li>"
}

$HtmlHead += "</ul></nav><div class='main-content' id='top'><div class='header-banner'>"
$HtmlHead += "<h1>vSphere 8 Healthcheck Report</h1>"
$HtmlHead += "<p>vCenter: $Server | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p></div>"

# 각 데이터 섹션 생성
foreach ($Key in $GlobalResults.Keys) {
    $Anchor = $Key -replace "[^a-zA-Z0-9]", "_"
    $Items = @($GlobalResults[$Key])
    
    if ($Items.Count -gt 0) {
        # 속성 헤더 추출
        $Props = $Items | ForEach-Object { $_.psobject.Properties.Name } | Select-Object -Unique | Where-Object { $_ -notmatch "ovf|psobject|extensiondata" }
        
        $HtmlBody += "<div class='card' id='$Anchor'><h3>$Key</h3><div class='table-wrapper'><table><thead><tr>"
        $HtmlBody += ($Props | ForEach-Object { "<th>$_</th>" }) -join ""
        $HtmlBody += "</tr></thead><tbody>"
        
        foreach ($i in $Items) {
            $HtmlBody += "<tr>"
            foreach ($p in $Props) {
                $v = [string]$i.$p
                # 상태 배지 매핑
                $c = ""
                if ($v -match "OK|SUCCESS|ACTIVE|READY|PoweredOn") { $c = "status-ok" }
                elseif ($v -match "DOWN|CRITICAL|ERROR|FAILED|PoweredOff") { $c = "status-crit" }
                elseif ($v -match "WARN|PROGRESS|UNKNOWN|DEGRADED") { $c = "status-warn" }
                
                $tdValue = if ($c) { "<span class='badge $c'>$v</span>" } else { $v }
                $HtmlBody += "<td>$tdValue</td>"
            }
            $HtmlBody += "</tr>"
        }
        $HtmlBody += "</tbody></table></div></div>"
    } else {
        $HtmlBody += "<div class='card' id='$Anchor'><h3>$Key</h3><p style='color:#94a3b8; font-style:italic;'>데이터가 존재하지 않습니다.</p></div>"
    }
}

# 최종 파일 합치기
$ExportHTML = $HtmlHead + $HtmlBody + "</div></body></html>"
$ExportHTML | Out-File $ReportPath -Encoding UTF8

Write-Host ">>> UI Style Report Created at: $ReportPath" -ForegroundColor Cyan

Invoke-Item $ReportPath

#API Session logout
Disconnect-Vcenter -Server $vCenterServer -SessionId $SessionId
# PowerCLI Logout
Disconnect-VIServer -server * -confirm:$False

Write-Host ">>> Process Complete." -ForegroundColor Cyan

# 변수 완전히 제거
Remove-Variable SessionId -ErrorAction SilentlyContinue
Remove-Variable Headers -ErrorAction SilentlyContinue
Remove-Variable Creds -ErrorAction SilentlyContinue


exit
