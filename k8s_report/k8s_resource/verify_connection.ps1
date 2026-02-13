# --- [디버그: 연결 상태 상세 점검] ---
# SSL 무시 설정
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

$scriptDir = $PSScriptRoot
$clustersFile = "$scriptDir\clusters.txt"

if (-not (Test-Path $clustersFile)) { Write-Host "clusters.txt 파일이 없습니다." -ForegroundColor Red; exit }

$lines = Get-Content -Path $clustersFile
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }

    $parts = $line -split ",", 2
    if ($parts.Count -lt 2) { continue }

    $apiUrl = $parts[0].Trim().Trim("'").Trim('"').TrimEnd("/")
    $tokenRaw = $parts[1].Trim().Trim("'").Trim('"')
    if (-not $apiUrl.StartsWith("http")) { $apiUrl = "https://" + $apiUrl }
    
    $headers = @{ "Authorization" = "Bearer $tokenRaw" }

    Write-Host "`n---------------------------------------------------"
    Write-Host "Target: $apiUrl" -ForegroundColor Yellow

    try {
        # 1. 네트워크 연결 테스트
        $uri = [System.Uri]$apiUrl
        $conn = Test-NetConnection -ComputerName $uri.Host -Port $uri.Port -WarningAction SilentlyContinue
        if ($conn.TcpTestSucceeded) {
            Write-Host " [OK] TCP Connection Successful" -ForegroundColor Green
        } else {
            Write-Host " [FAIL] TCP Connection Failed (Network/Firewall Issue)" -ForegroundColor Red
            continue
        }

        # 2. API 호출 테스트
        Write-Host " ... Attempting API Call (/api/v1/nodes) ..."
        $response = Invoke-RestMethod -Uri "$apiUrl/api/v1/nodes" -Headers $headers -Method Get -ErrorAction Stop
        Write-Host " [OK] API Call Successful. Node Count: $($response.items.Count)" -ForegroundColor Green

    } catch {
        # 3. 상세 에러 출력
        Write-Host " [ERROR] API Call Failed!" -ForegroundColor Red
        Write-Host " Type: $($_.Exception.GetType().Name)"
        Write-Host " Message: $($_.Exception.Message)"
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDesc = $_.Exception.Response.StatusDescription
            Write-Host " HTTP Status: $statusCode ($statusDesc)" -ForegroundColor Magenta
            
            if ($statusCode -eq 401) { Write-Host " -> 원인: 토큰 만료 또는 인증 실패 (Unauthorized)" -ForegroundColor Yellow }
            elseif ($statusCode -eq 403) { Write-Host " -> 원인: 권한 부족 (Forbidden)" -ForegroundColor Yellow }
        }
    }
}