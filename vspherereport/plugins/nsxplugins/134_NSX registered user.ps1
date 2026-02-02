param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    # 1. User Info API 호출
    $Uri = "https://$Server/policy/api/v1/aaa/user-info"
    try {
        $UserRes = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop
    } catch {
        $ReportEntries.Add([PSCustomObject]@{
            Username = "<span style='color:red;'>조회 실패</span>"
            UserType = "-"
            Roles    = "에러: $($_.Exception.Message)"
            Health   = "CRITICAL"
        })
        return $ReportEntries
    }

    # 2. 데이터 분석 및 분류
    $UserName = $UserRes.user_name
    $RoleList = New-Object System.Collections.Generic.List[string]
    $UserType = "Local"

    if ($null -ne $UserName) {
        # 이메일 형식(@ 포함) 여부에 따른 분기 처리
        if ($UserName -like "*@*") {
            $UserType = "LDAP"
            # LDAP 구조: roles_for_paths -> roles -> role 추출
            if ($null -ne $UserRes.roles_for_paths) {
                foreach ($pathObj in $UserRes.roles_for_paths) {
                    if ($null -ne $pathObj.roles) {
                        foreach ($r in $pathObj.roles) {
                            if ($null -ne $r.role) { $RoleList.Add($r.role) }
                        }
                    }
                }
            }
        } else {
            $UserType = "Local"
            # 로컬 구조: roles -> role 추출
            if ($null -ne $UserRes.roles) {
                foreach ($r in $UserRes.roles) {
                    if ($null -ne $r.role) { $RoleList.Add($r.role) }
                }
            }
        }
    }

    # 중복 제거 및 문자열 합치기
    $FinalRoles = if ($RoleList.Count -gt 0) { 
        ($RoleList | Select-Object -Unique) -join ", " 
    } else { 
        "<span style='color:orange;'>No Roles Assigned</span>" 
    }

    # 3. 결과 추가
    $ReportEntries.Add([PSCustomObject]@{
        Username = $UserName
        UserType = $UserType
        Roles    = $FinalRoles
        Health   = "OK"
    })

    return $ReportEntries
} catch {
    return $null
}