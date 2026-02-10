param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# Thick Provisioning(고정 할당)으로 설정된 VMDK를 탐지합니다.
# Thin Provisioning이 아닌 디스크를 찾아내어 스토리지 공간 확보 대상을 식별합니다.
# PowerCLI 객체 루프 대신 Get-View를 사용하여 대량 조회 속도를 최적화했습니다.
# ---------------------------------------------------------------------------

try {
    # 1. 모든 VM의 하드웨어 설정 정보를 가져옵니다.
    $VMViews = Get-View -ViewType VirtualMachine -Property Name, Config.Hardware.Device -Filter @{"Config.Template"="False"}

    $Results = @()

    foreach ($vm in $VMViews) {
        # VM의 장치 목록 중 'VirtualDisk' 타입만 필터링
        $Disks = $vm.Config.Hardware.Device | Where-Object { $_ -is [VMware.Vim.VirtualDisk] }

        foreach ($disk in $Disks) {
            # Backing 정보 확인 (RDM이나 기타 방식 제외하고 일반 Flat 파일 백킹만 확인)
            if ($disk.Backing -is [VMware.Vim.VirtualDiskFlatVer2BackingInfo]) {
                
                # ThinProvisioned 속성이 $false이면 Thick 모드입니다.
                if ($disk.Backing.ThinProvisioned -eq $false) {
                    
                    # Thick 중에서도 Eager Zeroed인지 Lazy Zeroed인지 구별
                    # EagerlyScrub: $true(Eager), $false/null(Lazy)
                    $IsEager = $disk.Backing.EagerlyScrub

                    # 용량 계산 (KB -> GB)
                    $SizeGB = [Math]::Round($disk.CapacityInKB / 1MB, 2)

                    $Results += [PSCustomObject]@{
                        VMName    = $vm.Name
                        DiskName  = $disk.DeviceInfo.Label
                        DiskType  = $TypeStr
                        SizeGB    = $SizeGB
                        FilePath  = $disk.Backing.FileName # 데이터스토어 위치 확인용
                    }
                }
            }
        }
    }

    return $Results

} catch {
    Write-Host " [!] Error querying Thick Disks: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}