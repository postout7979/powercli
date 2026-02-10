param([string]$Server, $SessionId, [string]$XsrfToken)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12
$Headers = @{ "X-XSRF-TOKEN" = $XsrfToken; "Accept" = "application/json" }

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    # 1. 백업 설정 및 히스토리 API 호출
    $ConfigRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/cluster/backups/config" -Headers $Headers -WebSession $SessionId
    $HistoryRes = Invoke-RestMethod -Method Get -Uri "https://$Server/api/v1/cluster/backups/history" -Headers $Headers -WebSession $SessionId

    # 2. 값 존재 여부 체크 함수 (빈 값일 경우 명시적 텍스트 반환)
    function Get-SafeValue($Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return "<span style='color:#a0aec0;'>- (Empty) -</span>" }
        return $Value
    }

    # 3. 설정 데이터 가공
    $BackupTarget = if ($ConfigRes.remote_file_server.server) { $ConfigRes.remote_file_server.server } else { $null }
    $BackupPath = if ($ConfigRes.remote_file_server.directory_path) { $ConfigRes.remote_file_server.directory_path } else { $null }

    # 4. 히스토리 데이터 처리
    if ($null -ne $HistoryRes.cluster_backup_statuses -and $HistoryRes.cluster_backup_statuses.Count -gt 0) {
        foreach ($history in $HistoryRes.cluster_backup_statuses | Select-Object -First 5) {
            
            $StartTime = if($history.start_time) { [DateTimeOffset]::FromUnixTimeMilliseconds($history.start_time).DateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            $EndTime = if($history.end_time) { [DateTimeOffset]::FromUnixTimeMilliseconds($history.end_time).DateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            
            $ReportEntries.Add([PSCustomObject]@{
                BackupServer = Get-SafeValue $BackupTarget
                RemotePath   = Get-SafeValue $BackupPath
                StartTime    = Get-SafeValue $StartTime
                EndTime      = Get-SafeValue $EndTime
                BackupType   = Get-SafeValue $history.backup_type
                # Status는 Boolean이므로 별도 처리
                BackupStatus = if ($null -ne $history.success) { $history.success.ToString().ToUpper() } else { Get-SafeValue $null }
                ErrorCode    = Get-SafeValue $history.error_code
            })
        }
    } else {
        # 데이터가 아예 없는 경우 단일 행으로 표시
        $ReportEntries.Add([PSCustomObject]@{
            BackupServer = Get-SafeValue $BackupTarget
            RemotePath   = Get-SafeValue $BackupPath
            StartTime    = Get-SafeValue $null
            EndTime      = Get-SafeValue $null
            BackupType   = Get-SafeValue $null
            BackupStatus = "<span class='badge status-warn'>NO HISTORY</span>"
            ErrorCode    = Get-SafeValue $null
        })
    }

    return $ReportEntries
} catch { return $null }