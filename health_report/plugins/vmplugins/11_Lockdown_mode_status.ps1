param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vSphere REST API(/api/vcenter/host)는 현재 Lockdown Mode 상태를 반환하지 않습니다.
# 따라서 vSphere Web Services API(SOAP)에 직접 접근하는 Get-View를 사용하여
# 호스트의 Config 객체에서 정확한 정보를 고속으로 추출합니다.
# ---------------------------------------------------------------------------

try {
    # 호스트의 설정(Config) 및 런타임 상태(Runtime) 정보만 선별하여 API 조회
    $HostViews = Get-View -ViewType HostSystem -Property Name, Config.LockdownMode, Runtime.ConnectionState, Config.Product.Version, Config.Product.Build -ErrorAction Stop

    $Data = foreach ($hv in $HostViews) {
        # Lockdown Mode 값이 null인 경우 'Disabled'로 처리
        $LockdownMode = if ($hv.Config.LockdownMode) { $hv.Config.LockdownMode } else { "disabled" }
        
        # HTML 리포트에서 상태 배지(Color Badge) 처리를 돕기 위해 텍스트 정규화
        # (disabled=Green/OK, normal/strict=Warn/Info 등 정책에 따라 해석 가능)
        
        [PSCustomObject]@{
            HostName        = $hv.Name
            ConnectionState = $hv.Runtime.ConnectionState
            LockdownMode    = $LockdownMode
            Version         = "ESXi $($hv.Config.Product.Version)"
            Build           = $hv.Config.Product.Build
        }
    }
    
    return $Data

} catch {
    Write-Host " [!] Error querying Host Lockdown Mode: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}