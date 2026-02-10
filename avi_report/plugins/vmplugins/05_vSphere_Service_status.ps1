param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# ESXi Host의 식별 정보(FQDN)와 핵심 관리 서비스(SSH, NTP)의 데몬 상태를 점검합니다.
# - FQDN: DNS 설정 기반의 전체 도메인 이름 조합
# - SSH/NTP: 서비스 데몬(Running/Stopped) 상태 확인
# ---------------------------------------------------------------------------

try {
    # 1. 필요한 속성만 골라서 고속 조회 (Runtime.ConnectionState 추가)
    $HostViews = Get-View -ViewType HostSystem -Property Name, Config.Network.DnsConfig, Config.DateTimeInfo, Config.Service.Service, Runtime.ConnectionState -ErrorAction Stop

    $Data = foreach ($hv in $HostViews) {
        
        # 2. 호스트 연결 상태 확인 (연결 끊긴 호스트는 스킵 또는 상태 표시)
        if ($hv.Runtime.ConnectionState -ne "Connected") {
            [PSCustomObject]@{
                HostName     = $hv.Name
                FQDN         = "N/A (Disconnected)"
                SSH_Running  = "UNKNOWN"
                NTPServers   = "N/A"
                NTP_Running  = "UNKNOWN"
            }
            continue
        }

        # 3. NTP 서버 목록 추출
        $ntpConfig = $hv.Config.DateTimeInfo.NtpConfig.Server
        $ntpServers = if ($ntpConfig) { $ntpConfig -join ", " } else { "Not Configured" }

        # 4. 서비스 상태 조회 (SSH, NTP)
        #    Config.Service.Service 배열에서 Key 값으로 검색
        $ServiceList = $hv.Config.Service.Service
        
        $ntpService = $ServiceList | Where-Object { $_.Key -eq "ntpd" }
        $sshService = $ServiceList | Where-Object { $_.Key -eq "TSM-SSH" }

        # 5. 상태값 변환 (HTML 리포트 배지 색상 적용을 위해 Running/Stopped 문자열로 변환)
        $ntpStatus = if ($ntpService.Running) { "Running" } else { "Stopped" }
        $sshStatus = if ($sshService.Running) { "Running" } else { "Stopped" }

        # 6. FQDN 조합 (DNS 설정이 비어있을 경우 대비)
        $DnsConfig = $hv.Config.Network.DnsConfig
        if ($DnsConfig) {
            $FQDN = "$($DnsConfig.HostName).$($DnsConfig.DomainName)"
        } else {
            $FQDN = "DNS Not Configured"
        }

        [PSCustomObject]@{
            HostName     = $hv.Name
            FQDN         = $FQDN
            SSH_Running  = $sshStatus
            NTPServers   = $ntpServers
            NTP_Running  = $ntpStatus
        }
    }
    
    return $Data

} catch {
    Write-Host " [!] Error querying Host Services: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}