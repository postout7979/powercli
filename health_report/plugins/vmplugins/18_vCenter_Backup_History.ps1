param($Server, $SessionId)
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$Headers = @{"vmware-api-session-id" = $SessionId; "Accept" = "application/json"}

try {
    # 1. 최근 백업 목록 조회
    $Uri = "https://$Server/api/appliance/recovery/backup/job"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
    
    # 데이터 존재 여부 체크 (exit 대신 조건문 사용)
    $JobList = if ($null -ne $Response.value) { $Response.value } else { @() }

    # 백업 작업이 하나도 없을 경우 처리
    if ($JobList.Count -eq 0) {
        Write-Host " -> No backup jobs found in history." -ForegroundColor Yellow
        return [PSCustomObject]@{
            JobID     = "N/A"
            StartTime = "No History"
            EndTime   = "N/A"
            Status    = "NONE"
            Duration  = "0 min"
            Location  = "No backup configured or performed"
        }
    }

    # 2. 작업 상세 정보 수집 (최근 5개)
    $Results = foreach ($jobSummary in ($JobList | Select-Object -First 5)) {
        try {
            $id = if ($jobSummary.job) { $jobSummary.job } else { $jobSummary }
            $DetailUri = "https://$Server/api/appliance/recovery/backup/job/$id"
            
            $DetailResponse = Invoke-RestMethod -Method Get -Uri $DetailUri -Headers $Headers
            $data = if ($null -ne $DetailResponse.value) { $DetailResponse.value } else { $DetailResponse }

            # 시간 형식 변환 (선택 사항: 가독성을 위해 초까지만 표시하도록 처리)
            $S_Time = if($data.start_time) { ([DateTime]$data.start_time).ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
            $E_Time = if($data.end_time) { ([DateTime]$data.end_time).ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }

            [PSCustomObject]@{
                JobID     = $id
                StartTime = $S_Time
                EndTime   = $E_Time
                Status    = if ($data.state) { $data.state } else { "UNKNOWN" }
                Duration  = "$([Math]::Round($data.duration / 60, 1)) min"
                Location  = $data.location
            }
        } catch { 
            Write-Host "    -> Error fetching details for Job $id" -ForegroundColor Gray
            continue 
        }
    }

    return $Results

} catch {
    Write-Host " -> Backup Query Error: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}