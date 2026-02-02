param($Server, $SessionId)

# ---------------------------------------------------------------------------
# [INFO]
# REST API를 사용하여 vCenter Appliance(VCSA)의 스토리지 및 DB 상태를 점검합니다.
# API가 반환하는 색상 코드(green/red/yellow)를 리포트 호환 키워드(OK/CRITICAL/WARN)로 변환합니다.
# ---------------------------------------------------------------------------

# SSL 인증서 검증 무시 (필요 시 유지, 메인 스크립트에서 처리했다면 생략 가능)
if ([System.Net.ServicePointManager]::ServerCertificateValidationCallback -eq $null) {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
}

# REST API용 헤더 구성
$Headers = @{
    "vmware-api-session-id" = $SessionId
    "Content-Type"          = "application/json"
    "Accept"                = "application/json"
}

# 엔드포인트
$UrlStorage   = "https://$Server/api/appliance/health/storage"
$UrlDbStorage = "https://$Server/api/appliance/health/database-storage"

try {
    # 1. API 호출
    $RespStorage = Invoke-RestMethod -Uri $UrlStorage -Method Get -Headers $Headers
    $RespDB      = Invoke-RestMethod -Uri $UrlDbStorage -Method Get -Headers $Headers

    # 2. 상태 매핑 헬퍼 함수 (API 색상 -> 리포트 배지용 키워드)
    function Get-StatusKeyword ($ApiStatus) {
        switch ($ApiStatus) {
            "green"   { return "OK (Green)" }
            "yellow"  { return "WARN (Yellow)" }
            "red"     { return "CRITICAL (Red)" }
            "orange"  { return "WARN (Orange)" }
            "gray"    { return "UNKNOWN (Gray)" }
            default   { return $ApiStatus } # 에러 메시지 등 그대로 반환
        }
    }

    # 3. 상태 값 추출 및 변환
    # (API 버전에 따라 응답이 객체일 수도 있고 문자열일 수도 있음)
    $RawStorageStatus = if ($RespStorage.status) { $RespStorage.status } else { $RespStorage }
    $RawDbStatus      = if ($RespDB.status) { $RespDB.status } else { $RespDB }

    $StorageStatus = Get-StatusKeyword $RawStorageStatus
    $DbStatus      = Get-StatusKeyword $RawDbStatus

    # 4. 상세 메시지 추출
    $MsgStorage = if ($RespStorage.messages) { $RespStorage.messages.message.default_message -join ", " } else { "None" }
    $MsgDB      = if ($RespDB.messages) { $RespDB.messages.message.default_message -join ", " } else { "None" }

    # 5. 결과 반환 (컬럼명은 리포트 헤더용으로 직관적으로 설정)
    $Result = [PSCustomObject]@{
        "Appliance Storage" = $StorageStatus
        "DB Storage"        = $DbStatus
        "Storage Messages"  = $MsgStorage
        "DB Messages"       = $MsgDB
        "Last Checked"      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    return $Result

} catch {
    return $null
}