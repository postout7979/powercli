# Main.ps1

# --- [플러그인 실행] ---
$PluginFolder = Join-Path $PSScriptRoot "plugins\vksplugins"
$ReportFolder = Join-Path $PSScriptRoot "reports\vks"
$Timestamp = Get-Date -Format 'yyyyMMdd'
$TempFolder = Join-Path $ReportFolder "temp_$Timestamp"
$CsvPath = Join-Path $ReportFolder "VKS_Report_$Timestamp.csv"
$ReportPath = Join-Path $ReportFolder "VKS_Report_$Timestamp.html"

# 1. 입력 받기
#$apiServer = Read-Host "Kubernetes API Server 주소를 입력하세요 (예: https://1.2.3.4:6443)"
$apiServer = "10.200.30.202"
#$token = Read-Host "Input your K8s Token" -AsSecureString


# SecureString을 일반 문자열로 변환
#$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
#$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
$plaintoken = "eyJhbGciOiJSUzI1NiIsImtpZCI6IlJNWS1JM1YtRHBzcTBXNmx4bXgzZGVLT3dvaFhrWVdwS3RDWGt0Z1NSX2sifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmNsdXN0ZXIubG9jYWwiXSwiZXhwIjoxNzY4MzIwMjA2LCJpYXQiOjE3NjgzMTY2MDYsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5jbHVzdGVyLmxvY2FsIiwianRpIjoiOTRmNjZhZDgtNWQ5My00MWVkLWFkNTYtY2M3ZjdhZDQ2NWM4Iiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJkZWZhdWx0Iiwic2VydmljZWFjY291bnQiOnsibmFtZSI6InJlYWQtb25seS11c2VyIiwidWlkIjoiOTBhN2RlMTctYTM3Yy00N2UxLWJlZmEtYTNmZDU3OTFhMzM3In19LCJuYmYiOjE3NjgzMTY2MDYsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpkZWZhdWx0OnJlYWQtb25seS11c2VyIn0.Ph8ZOmrVHOT6gZLT1UtWGGT_QREqfon6RKjl-8i4coMafYXtI5UstgZN5RsF0AMpiuc8iI6vuWxGbC7b2BhjDxMClEB6J8OVa1eLndLYLsTbIC4dqCd_t84Il2INJpEunXTbpup_ZXatoYfWjt-9nv9DF3Ly8Z5z4ZX3Ro7ux7-kIkCtrjvvrf-efaIbXSG5dMl9EEqYeC_dDBgctTdHDnP625t_zbsFFpbNU_uDhhTRWEkRs_9RwcmL2iD8oUpwAURIntdc7R2OCDxUfqSbmW641Gnq2vDO7Q9Od_3JppzSqFfR9W6N0W2_qgn-0aJpFBK58SvUjyRBjL_KElmGIw"

Write-Host "`n[collect info...] try to connect api server" -ForegroundColor Cyan

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

    if ($File.Extension -eq ".ps1") {
        $ModuleName = $File.BaseName
        Write-Host " -> Executing: [$ModuleName]" -ForegroundColor White
        try {
            # 데이터 수집 (반드시 @()로 감싸서 배열임을 보장)
            $jsonResult = & $File.FullName -apiServer $apiServer -plainToken $plainToken
			if ($null -eq $data) {
				Write-Host "No data from server" -ForegroundColor Red
				exit
			}
			$Data = $jsonResult | ConvertFrom-Json
			
            # 데이터가 null이 아닐 때만 저장
            if ($null -ne $Data) { 
                $GlobalResults[$ModuleName] = $Data 
            }
        } catch {
            Write-Host " [!] Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}


if ($null -eq $data) {
    Write-Host "데이터를 가져오지 못했습니다. 설정을 확인하세요." -ForegroundColor Red
    exit
}

# 3. HTML 생성 (현대적인 UI 디자인)
$htmlRows = foreach ($item in $data) {
    "<tr><td>$($item.Name)</td><td><span class='badge'>$($item.Status)</span></td><td>$($item.CreationTimestamp)</td></tr>"
} -join ""

$htmlContent = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>K8s Cluster Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; display: flex; height: 100vh; background: #f4f7f9; }
        nav { width: 250px; background: #2c3e50; color: white; padding: 20px; flex-shrink: 0; }
        nav h2 { font-size: 1.2rem; border-bottom: 1px solid #555; padding-bottom: 10px; }
        nav ul { list-style: none; padding: 0; }
        nav li { padding: 10px 0; color: #bdc3c7; cursor: pointer; }
        nav li:hover { color: white; }
        main { flex-grow: 1; padding: 40px; overflow-y: auto; }
        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { text-align: left; background: #f8f9fa; padding: 12px; border-bottom: 2px solid #dee2e6; }
        td { padding: 12px; border-bottom: 1px solid #eee; }
        .badge { background: #27ae60; color: white; padding: 4px 8px; border-radius: 4px; font-size: 0.8rem; }
        h1 { color: #333; margin-top: 0; }
    </style>
</head>
<body>
    <nav>
        <h2>K8s Console</h2>
        <ul>
            <li>Dashboard</li>
            <li style="color:white; font-weight:bold;">Namespaces</li>
            <li>Nodes</li>
            <li>Pods</li>
        </ul>
    </nav>
    <main>
        <h1>Cluster Namespaces</h1>
        <div class="card">
            <table>
                <thead>
                    <tr><th>Name</th><th>Status</th><th>Created At</th></tr>
                </thead>
                <tbody>
                    $htmlRows
                </tbody>
            </table>
        </div>
    </main>
</body>
</html>
"@

$outputPath = "$PSScriptRoot\report\K8s_Report.html"
$htmlContent | Out-File -FilePath $outputPath -Encoding utf8

Write-Host "`n[완료] HTML 리포트가 생성되었습니다: $outputPath" -ForegroundColor Green
Invoke-Item $outputPath
