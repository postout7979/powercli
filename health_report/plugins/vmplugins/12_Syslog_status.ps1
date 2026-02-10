param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# ESXi Host의 Syslog 설정(Syslog Server, Directory)을 점검합니다.
# 수정사항: Get-View 호출 시 중첩 속성 오류 방지를 위해 
# 'ConfigManager.SyslogSystem' 대신 'ConfigManager' 전체를 호출하여 안정성을 확보했습니다.
# ---------------------------------------------------------------------------

try {
    # [수정됨] Property 경로 단축 (ConfigManager.SyslogSystem -> ConfigManager)
    # API 파싱 에러를 방지하기 위해 상위 객체만 가져옵니다.
    $HostViews = Get-View -ViewType HostSystem -Property Name, ConfigManager, Runtime.ConnectionState -ErrorAction Stop
    
    # 2. SyslogSystem 객체들을 한 번에 로드 (Batch Query로 성능 최적화)
    #    연결된 호스트의 Syslog MoRef만 추출 (메모리 내에서 접근하므로 에러 없음)
    $SyslogMoRefs = $HostViews | Where-Object { 
        $_.Runtime.ConnectionState -eq "Connected" -and $_.ConfigManager.SyslogSystem 
    } | ForEach-Object { 
        $_.ConfigManager.SyslogSystem 
    }
    
    #    SyslogSystem 뷰 조회 (Configuration 속성 필요)
    #    MoRef가 하나라도 있을 경우에만 실행
    $SyslogViews = if ($SyslogMoRefs) { 
        Get-View -Id $SyslogMoRefs -Property Configuration.LogHostConfig, Configuration.GlobalLogHost -ErrorAction SilentlyContinue
    } else { @() }
    
    #    매핑 최적화 (MoRef Value -> View 객체)
    $SyslogMap = @{}
    foreach ($sv in $SyslogViews) {
        $SyslogMap[$sv.MoRef.Value] = $sv
    }

    $Data = foreach ($hv in $HostViews) {
        
        # 연결되지 않은 호스트 처리
        if ($hv.Runtime.ConnectionState -ne "Connected") {
            [PSCustomObject]@{
                HostName     = $hv.Name
                SyslogServer = "N/A"
                ConfigStatus = "DISCONNECTED"
                Protocol     = "N/A"
            }
            continue
        }

        # ConfigManager가 로드되지 않았거나 SyslogSystem이 없는 경우 방어 코드
        if (-not $hv.ConfigManager -or -not $hv.ConfigManager.SyslogSystem) {
             [PSCustomObject]@{
                HostName     = $hv.Name
                SyslogServer = "Unknown"
                ConfigStatus = "WARN: Check Host"
                Protocol     = "Unknown"
            }
            continue
        }

        # 해당 호스트의 Syslog 설정 매핑 확인
        $SyslogInfo = $SyslogMap[$hv.ConfigManager.SyslogSystem.Value]
        
        # LogHost 정보 추출
        $LogHostRaw = $SyslogInfo.Configuration.GlobalLogHost
        
        if ([string]::IsNullOrWhiteSpace($LogHostRaw)) {
            $LogHost = "Not Configured"
            $Status  = "CRITICAL: No Syslog" 
            $Protocol = "None"
        } else {
            $LogHost = $LogHostRaw -join ", "
            $Status  = "Configured"          
            
            if ($LogHost -match "udp:") { $Protocol = "UDP" }
            elseif ($LogHost -match "tcp:") { $Protocol = "TCP" }
            elseif ($LogHost -match "ssl:") { $Protocol = "SSL" }
            else { $Protocol = "UDP (Default)" }
        }

        [PSCustomObject]@{
            HostName     = $hv.Name
            SyslogServer = $LogHost
            ConfigStatus = $Status
            Protocol     = $Protocol
        }
    }
    
    return $Data

} catch {
    Write-Host " [!] Error querying Syslog Config: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}