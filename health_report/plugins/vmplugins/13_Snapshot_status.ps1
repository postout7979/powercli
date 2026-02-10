param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# Snapshot이 존재하는 VM을 탐지하고 상세 정보(용량, 경과 기간)를 조회합니다.
# 수정사항: 
# 1. 'Get-VM -Id' 오류 해결을 위해 'Get-VIObjectByVIView'를 사용하여 객체 변환 안정성 확보
# 2. 변환 실패 시 '이름(Name)'으로 재조회하는 2차 안전장치(Fallback) 추가
# ---------------------------------------------------------------------------

try {
    

    # 1. 스냅샷이 있는 VM만 빠르게 필터링 (Get-View 사용)
    #    Snapshot 속성이 null이 아닌 객체만 가져옵니다.
    $VMViews = Get-View -ViewType VirtualMachine -Property Name, Snapshot -Filter @{"Snapshot"=""} -ErrorAction Stop

    # 위 필터가 간혹 동작하지 않는 환경을 대비해 로컬 필터링을 한 번 더 수행
    $TargetVMs = $VMViews | Where-Object { $_.Snapshot -ne $null }

    if ($null -eq $TargetVMs -or $TargetVMs.Count -eq 0) {
        return $null 
    }

    $Results = @()

    foreach ($vmView in $TargetVMs) {
        try {
            # [수정됨] VM 객체 변환 로직 강화
            $VMObj = $null
            
            # 방법 A: View 객체를 바로 VIObject(VM)로 변환 (가장 정확함, ID 조회 오류 방지)
            try {
                $VMObj = $vmView | Get-VIObjectByVIView -ErrorAction Stop
            } catch {
                # 방법 B: 변환 실패 시, ID(MoRef)를 사용하여 명시적으로 조회
                try {
                    $VMObj = Get-VM -Id $vmView.MoRef -Server $Server -ErrorAction Stop
                } catch {
                    # 방법 C: 최후의 수단 - 이름으로 조회 (동명이인이 있을 수 있으나 에러보다는 나음)
                    Write-Host " [!] Retry finding VM by Name: $($vmView.Name)" -ForegroundColor DarkGray
                    $VMObj = Get-VM -Name $vmView.Name -Server $Server -ErrorAction Stop
                }
            }

            # VM 객체를 찾지 못했으면 스킵
            if ($null -eq $VMObj) { continue }

            # 스냅샷 조회
            $Snaps = $VMObj | Get-Snapshot
            
            foreach ($snap in $Snaps) {
                # 3. 경과 기간 계산
                $TimeSpan = New-TimeSpan -Start $snap.Created -End (Get-Date)
                $DaysOld = $TimeSpan.Days
                
                # 4. 상태(Color Badge) 판단 로직
                if ($DaysOld -ge 7) {
                    $Status = "CRITICAL: Old ($DaysOld days)"
                } elseif ($DaysOld -ge 3) {
                    $Status = "WARN: Check ($DaysOld days)"
                } else {
                    $Status = "ACTIVE (Recent)"
                }

                # 5. 기간 표시 포맷
                $DurationStr = "$($DaysOld) Days, $($TimeSpan.Hours) Hours"
                
                # 용량 반올림 (SizeGB가 없을 경우 0 처리)
                $SizeGB = if ($snap.SizeGB) { [Math]::Round($snap.SizeGB, 2) } else { 0 }

                $Results += [PSCustomObject]@{
                    VMName        = $vmView.Name
                    SnapshotName  = $snap.Name
                    CreatedTime   = $snap.Created.ToString("yyyy-MM-dd HH:mm")
                    Duration      = $DurationStr
                    SizeGB        = $SizeGB
                    Status        = $Status
                    Description   = if ($snap.Description) { $snap.Description } else { "-" }
                }
            }
        } catch {
            # 특정 VM 조회 실패 시 로그만 남기고 다음 VM으로 진행 (스크립트 중단 방지)
            Write-Host " [!] Skip VM '$($vmView.Name)': $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }

    return $Results

} catch {
    Write-Host " [!] Error querying VM Snapshots: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}