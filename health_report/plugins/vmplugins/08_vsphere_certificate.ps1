param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# ESXi Host의 SSL 인증서 만료일을 점검합니다.
# HostSystem.Config.Certificate(Byte[]) 데이터를 .NET 클래스로 파싱하여 분석합니다.
# 남은 기간에 따라 경고(WARN/CRITICAL) 배지를 표시합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 호스트 인증서 정보 조회 (Config.Certificate 속성)
    $HostViews = Get-View -ViewType HostSystem -Property Name, Config.Certificate -ErrorAction Stop

    $Data = foreach ($hv in $HostViews) {
        # 변수 초기화 (루프 돌 때 이전 값 잔존 방지)
        $ExpiryDate = $null
        $DaysRemaining = 0
        $Issuer = "Unknown"
        $Status = "Unknown"
        $CertObj = $null

        # 인증서 데이터가 있는지 확인
        if ($hv.Config.Certificate) {
            try {
                # 2. Byte 배열을 X509Certificate2 객체로 변환
                $CertObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 @(,$hv.Config.Certificate)
                
                $ExpiryDate = $CertObj.NotAfter
                $Issuer = $CertObj.Issuer
                
                # 3. 남은 일수 계산
                $DaysRemaining = ($ExpiryDate - (Get-Date)).Days
                
                # 4. 상태 판단 로직 (HTML 리포트 색상 연동)
                if ($DaysRemaining -lt 0) {
                    $Status = "CRITICAL: Expired"
                } elseif ($DaysRemaining -lt 30) {
                    $Status = "CRITICAL: Expire < 30 Days"
                } elseif ($DaysRemaining -lt 60) {
                    $Status = "WARN: Expire < 60 Days"
                } else {
                    $Status = "GOOD"
                }

            } catch {
                $Status = "WARN: Parse Error"
                $Issuer = "Error parsing cert"
            }
        } else {
            $Status = "WARN: No Certificate"
        }

        # 5. 결과 객체 생성
        [PSCustomObject]@{
            HostName      = $hv.Name
            ExpiryDate    = if ($ExpiryDate) { $ExpiryDate.ToString("yyyy-MM-dd") } else { "N/A" }
            DaysRemaining = if ($Status -match "No|Error") { "N/A" } else { $DaysRemaining }
            Status        = $Status
            Issuer        = $Issuer
        }
    }
    
    # 남은 일수가 적은 순서대로 정렬 (급한 것부터 보이게)
    return $Data | Sort-Object DaysRemaining

} catch {
    Write-Host " [!] Error querying Host Certificates: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}