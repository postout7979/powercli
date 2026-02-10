param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# Host별 pCPU 대비 vCPU 할당 비율(Overcommitment Ratio)을 점검합니다.
# 수정사항: 물리적 CPU 소켓 수(Sockets) 정보를 추가로 표시합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 호스트 정보 가져오기 (NumCpuPkgs 속성 추가)
    #    NumCpuCores: 전체 코어 수 / NumCpuPkgs: 물리 소켓 수
    $HostViews = Get-View -ViewType HostSystem -Property Name, Summary.Hardware.NumCpuCores, Summary.Hardware.NumCpuPkgs, Runtime.ConnectionState -ErrorAction Stop
    
    # VM 정보 가져오기 (PoweredOn 상태만)
    $VMViews   = Get-View -ViewType VirtualMachine -Filter @{"Runtime.PowerState"="poweredOn"} -Property Config.Hardware.NumCPU, Runtime.Host

    # 2. [최적화] 호스트별 vCPU 합계 미리 계산 (Mapping)
    $vCpuMap = @{}
    foreach ($vm in $VMViews) {
        $HostId = $vm.Runtime.Host.Value
        if (-not $vCpuMap.ContainsKey($HostId)) {
            $vCpuMap[$HostId] = 0
        }
        $vCpuMap[$HostId] += $vm.Config.Hardware.NumCPU
    }

    $Data = foreach ($hv in $HostViews) {
        # 연결 안 된 호스트 제외
        if ($hv.Runtime.ConnectionState -ne "Connected") { continue }

        $pCores   = $hv.Summary.Hardware.NumCpuCores
        $pSockets = $hv.Summary.Hardware.NumCpuPkgs  # [추가됨] 소켓 수
        
        # 맵에서 해당 호스트의 vCPU 합계 조회 (없으면 0)
        $HostId = $hv.MoRef.Value
        $vCPUSum = if ($vCpuMap.ContainsKey($HostId)) { $vCpuMap[$HostId] } else { 0 }
        
        # 비율 계산
        if ($pCores -gt 0) {
            $RawRatio = $vCPUSum / $pCores
            $RatioStr = "1:{0:N2}" -f $RawRatio # 소수점 2자리 포맷
        } else {
            $RawRatio = 0
            $RatioStr = "N/A"
        }

        # 상태 배지 로직 (HTML 리포트 색상 연동)
        if ($RawRatio -ge 5) {
            $Status = "CRITICAL: High ($RatioStr)"
        } elseif ($RawRatio -ge 3) {
            $Status = "WARN: Elevated ($RatioStr)"
        } else {
            $Status = "OK"
        }

        [PSCustomObject]@{
            HostName = $hv.Name
            Sockets  = $pSockets # [추가됨]
            pCores   = $pCores
            vCPUs    = $vCPUSum
            Ratio    = $RatioStr
            Status   = $Status
        }
    }

    # 비율이 높은 순서대로 정렬하여 반환
    return $Data | Sort-Object @{Expression={ [double]($_.Ratio -replace "1:","") }; Descending=$true}

} catch {
    Write-Host " [!] Error calculating CPU Overcommit: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}