param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# 전체 VM의 상태 및 하드웨어 구성 정보를 점검합니다.
# 최적화: REST API 루프 대신 Get-View를 사용하여 수천 대의 VM도 수 초 내에 조회합니다.
# ---------------------------------------------------------------------------

try {
    # 1. 필요한 속성만 지정하여 전체 VM 일괄 조회 (가장 빠름)
    #    Runtime.PowerState: 전원 상태
    #    Config.GuestFullName: 설정된 OS 이름
    #    Config.Hardware: CPU/Memory 정보
    #    Config.Version: 하드웨어 버전 (vmx-xx)
    $VMViews = Get-View -ViewType VirtualMachine -Property Name, Runtime.PowerState, Config.GuestFullName, Config.Hardware, Config.Version -ErrorAction Stop

    if ($null -eq $VMViews -or $VMViews.Count -eq 0) {
        return $null
    }

    $Results = foreach ($vm in $VMViews) {
        
        # 2. 데이터 가공
        # 메모리 변환 (MB -> GB)
        $MemMB = if ($vm.Config.Hardware.MemoryMB) { $vm.Config.Hardware.MemoryMB } else { 0 }
        $vMemGB = [Math]::Round($MemMB / 1024, 1)

        # 전원 상태 (poweredOn, poweredOff)
        $PwrState = $vm.Runtime.PowerState

        # Guest OS (Config 정보가 없으면 Unknown 처리)
        $GuestOS = if ($vm.Config.GuestFullName) { $vm.Config.GuestFullName } else { "Unknown" }

        # 3. 결과 객체 생성
        [PSCustomObject]@{
            VMName     = $vm.Name
            PowerState = $PwrState
            GuestOS    = $GuestOS
            vCPU       = "$($vm.Config.Hardware.NumCPU) vCPU"
            vMEM       = "$vMemGB GB"
            Hardware   = $vm.Config.Version
        }
    }

    # VM 이름순 정렬 후 반환
    return $Results | Sort-Object VMName

} catch {
    Write-Host " [!] Error querying VM Info: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}