param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# VM 설정(VMX)에 정의된 Guest OS와 실제 작동 중인 Guest OS를 비교합니다.
# VMware Tools가 실행 중일 때만 실제 OS 정보를 정확히 가져올 수 있습니다.
# 불일치 시 성능 저하 또는 VMware Tools 오작동의 원인이 될 수 있습니다.
# ---------------------------------------------------------------------------

try {
    # 1. 비교에 필요한 속성만 가져옵니다.
    #    Config.GuestFullName : 설정된 OS 이름
    #    Guest.GuestFullName  : Tools가 보고하는 실제 OS 이름
    #    Runtime.PowerState   : VM 전원 상태
    $VMViews = Get-View -ViewType VirtualMachine -Property Name, Config.GuestFullName, Guest.GuestFullName, Runtime.PowerState

    $Results = @()

    foreach ($vm in $VMViews) {
        # 전원이 꺼진 VM은 Tools 정보를 신뢰할 수 없으므로 제외하거나 별도 표시
        if ($vm.Runtime.PowerState -ne "poweredOn") {
            continue 
        }

        $ConfigOS = $vm.Config.GuestFullName
        $RealOS   = $vm.Guest.GuestFullName

        # 2. 실제 OS 정보가 없는 경우 (Tools 미설치 또는 미실행)
        if ([string]::IsNullOrWhiteSpace($RealOS)) {
            $ResultStatus = "WARN: Tools Issue"
            $RealOS = "Unknown (Tools not running)"
        }
        # 3. 문자열 비교 (정확히 일치하는지 확인)
        elseif ($ConfigOS -eq $RealOS) {
            $ResultStatus = "MATCH (OK)"
        }
        # 4. 불일치 감지
        else {
            # 윈도우 버전 차이 등 미세한 차이도 감지하여 알려줌
            $ResultStatus = "WARN: OS Mismatch"
        }

        # 불일치하거나 Tools 문제가 있는 경우, 또는 정상인 경우 모두 수집
        # (리포트가 너무 길어지는 것을 방지하려면 불일치($ResultStatus -match "WARN")만 남겨도 됨)
        
        # 여기서는 '불일치'하거나 'Tools 이슈'가 있는 경우만 리포트에 추가하여 집중도 높임
        if ($ResultStatus -match "WARN|Issue") {
            $Results += [PSCustomObject]@{
                VMName        = $vm.Name
                ConfiguredOS  = $ConfigOS
                RunningOS     = $RealOS
                Status        = $ResultStatus
                MatchCheck    = if ($ResultStatus -match "OK") { "True" } else { "False" }
            }
        }
    }

    return $Results

} catch {
    Write-Host " [!] Error querying Guest OS Info: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}