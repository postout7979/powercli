param(
    [string]$Server, 
    $SessionId, 
    [string]$XsrfToken, 
    [string]$version
)

# SSL 인증서 검증 무시
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # -----------------------------------------------------------
    # [설정] 30일 기간 설정 (초 단위)
    # 30일 * 24시간 * 60분 * 60초 = 2,592,000 초
    # -----------------------------------------------------------
    $DurationSeconds = 2592000 
    
    # -----------------------------------------------------------
    # [API 호출 URL 구성]
    # Endpoint: /api/analytics/logs
    # type=2 : 시스템 이벤트
    # filter : VirtualService 객체만 필터링
    # duration : 현재 시점으로부터 과거 30일간 조회
    # page_size : 가져올 데이터 수 (limit 대신 사용 요청)
    # -----------------------------------------------------------
    $Uri = "https://$Server/api/analytics/logs?type=2&filter=eq(obj_type,VirtualService)&duration=$DurationSeconds&page_size=1000"
    
    Write-Host "[-] API Request: $Uri" -ForegroundColor Cyan
    
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    if ($null -ne $Response.results) {
        foreach ($log in $Response.results) {
            
            # API 필터가 적용되었지만, 명확한 이력 확인을 위해 생성/삭제 이벤트만 추출
            # (필요 없다면 이 if문을 제거하시면 모든 VS 관련 이벤트가 출력됩니다)
            if ($log.event_id -match "CONFIG_CREATE|CONFIG_DELETE") {
                
                # 사용자 정보 추출 (Analytics Log 구조에 맞춰 파싱)
                $User = "System"
                
                # event_details 파싱 시도
                if ($log.event_details) {
                    if ($log.event_details -is [string]) {
                        if ($log.event_details -match "User (.*?) ") { $User = $Matches[1] }
                    } elseif ($log.event_details.req_user) {
                        $User = $log.event_details.req_user
                    } elseif ($log.event_details.user_name) {
                        $User = $log.event_details.user_name
                    }
                }

                $ReportEntries.Add([PSCustomObject]@{
                    Time        = $log.report_timestamp
                    Event       = $log.event_id
                    VSName      = $log.obj_name
                    User        = $User
                    Message     = $log.event_description
                    Type        = "Analytics/Log"
                })
            }
        }
    }
    
    if ($ReportEntries.Count -gt 0) {
        Write-Host "[-] Search $($ReportEntries.Count) of VS was Created or Deleted in 30days." -ForegroundColor Green
    } else {
        Write-Warning "Virtual Service was not occured in 30days($DurationSeconds seconds)"
    }
    
    return $ReportEntries

} catch {
    Write-Error "API 호출 실패: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $Stream = $_.Exception.Response.GetResponseStream()
        $Reader = New-Object System.IO.StreamReader($Stream)
        Write-Error "서버 응답: $($Reader.ReadToEnd())"
    }
    return $null
}
