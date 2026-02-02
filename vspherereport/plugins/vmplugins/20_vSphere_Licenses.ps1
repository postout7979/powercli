param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# vCenter에 등록된 라이선스 정보를 조회합니다.
# 수정사항: LicenseManager는 ViewType으로 조회할 수 없으므로, 
#           ServiceInstance -> Content -> LicenseManager 경로로 접근하도록 수정했습니다.
# ---------------------------------------------------------------------------

try {
    # 1. LicenseManager 접근 (수정된 방식)
    #    먼저 ServiceInstance를 가져오고, 그 안의 Content에서 LicenseManager 참조(MoRef)를 찾습니다.
    $ServiceInstance = Get-View ServiceInstance -ErrorAction Stop
    $LicMgrMoRef = $ServiceInstance.Content.LicenseManager
    
    #    찾은 참조값(MoRef)으로 실제 LicenseManager 뷰 객체를 로드합니다.
    $LicMgr = Get-View -Id $LicMgrMoRef -Property Licenses -ErrorAction Stop
    
    $Results = @()

    # 라이선스가 하나도 없는 경우 대비
    if ($null -eq $LicMgr.Licenses) {
        return $null
    }

    foreach ($lic in $LicMgr.Licenses) {
        # 2. 기본 정보 추출
        $ProdName = $lic.Name
        $LicKey   = $lic.LicenseKey
        $Used     = $lic.Used
        $Total    = $lic.Total
        $Unit     = $lic.CostUnit # 예: cpuPackage, vm 등

        # 용량 문자열 포맷팅
        if ($Total -gt 0) {
            $UsageStr = "$Used / $Total ($Unit)"
            $IsFull = ($Used -ge $Total)
        } else {
            $UsageStr = "$Used ($Unit) - Unlimited"
            $IsFull = $false
        }

        # 3. 만료일(Expiration) 확인 로직
        #    Properties 속성 내에 key="expirationDate"가 있는지 확인
        $ExpireProp = $lic.Properties | Where-Object { $_.Key -eq "expirationDate" }
        
        $ExpireDateStr = "Perpetual (Never)"
        $DaysRemaining = 9999
        $Status = "OK"

        if ($ExpireProp) {
            try {
                $ExpDate = Get-Date $ExpireProp.Value
                $ExpireDateStr = $ExpDate.ToString("yyyy-MM-dd")
                
                # 남은 일수 계산
                $TimeSpan = New-TimeSpan -Start (Get-Date) -End $ExpDate
                $DaysRemaining = $TimeSpan.Days
            } catch {
                $ExpireDateStr = "Unknown Date Format"
            }
        }

        # 4. 상태 배지(Color Badge) 결정 로직
        # (1) 기간 만료 체크
        if ($DaysRemaining -lt 0) {
            $Status = "CRITICAL: Expired"
        } elseif ($DaysRemaining -lt 30) {
            $Status = "CRITICAL: < 30 Days Left"
        } elseif ($DaysRemaining -lt 60) {
            $Status = "WARN: < 60 Days Left"
        } 
        # (2) 용량 초과 체크
        elseif ($IsFull) {
            $Status = "WARN: Capacity Full"
        } else {
            if ($ExpireDateStr -match "Perpetual") {
                $Status = "Active (Perpetual)"
            } else {
                $Status = "Active ($DaysRemaining Days)"
            }
        }

        $Results += [PSCustomObject]@{
            Product       = $ProdName
            LicenseKey    = $LicKey
            "Usage/Total" = $UsageStr
            Expiration    = $ExpireDateStr
            Status        = $Status
        }
    }

    return $Results

} catch {
    Write-Host " [!] Error querying Licenses: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}