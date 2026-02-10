param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    # 1. 사용자 기본 정보 조회 (/api/user)
    $UserUri = "https://$Server/api/user"
    $UserRes = Invoke-RestMethod -Method Get -Uri $UserUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    # 2. 사용자 활동 정보 조회 (/api/useractivity)
    $ActivityUri = "https://$Server/api/useractivity"
    $ActivityRes = Invoke-RestMethod -Method Get -Uri $ActivityUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $UserRes.results) {
        foreach ($user in $UserRes.results) {
            $UserUuid = $user.uuid
            
            # --- [데이터 결합] /api/useractivity에서 해당 사용자의 UUID와 일치하는 데이터 찾기 ---
            # 사용자 활동 기록은 user_ref 필드 등에 UUID가 포함되어 있습니다.
            $Activity = $ActivityRes.results | Where-Object { $_.uuid -eq $UserUuid -or $_.user_ref -match $UserUuid } | Select-Object -First 1

            # 날짜 형식 정리 (22.1.7 응답 구조 참고)
            # 마이크로초를 초로 변환한 뒤, Unix Epoch(1970-01-01) 기준으로 날짜 계산
			$JoinDate = if ($user._last_modified) { 
				[DateTimeOffset]::FromUnixTimeSeconds([int64]($user._last_modified / 1000000)).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
			} else { "N/A" }
            $IsActive = if ($null -ne $user.is_active) { $user.is_active } else { $true }

            # 활동 정보 필드 추출
            $Sessions = if ($null -ne $Activity.concurrent_sessions) { $Activity.concurrent_sessions } else { 0 }
            $LastIp   = if ($Activity.last_login_ip) { $Activity.last_login_ip } else { "No Record" }
            $LastTime = if ($Activity.last_login_timestamp) { $Activity.last_login_timestamp } else { "N/A" }

            $ReportEntries.Add([PSCustomObject]@{
                Username           = $user.username
                JoinDate           = $JoinDate
                AccountStatus      = if ($IsActive) { "ACTIVE" } else { "INACTIVE" }
                ConcurrentSessions = $Sessions
                LoginIP            = $LastIp
                LoginTimestamp     = $LastTime
                Status             = if ($IsActive -and $Sessions -gt 0) { "RUNNING" } elseif ($IsActive) { "ok" } else { "critical" }
            })
        }
    }
    return $ReportEntries | Sort-Object Username
} catch {
    Write-Warning "User Activity Data 수집 실패: $($_.Exception.Message)"
    return $null
}