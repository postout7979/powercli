param([string]$Server, $SessionId, [string]$XsrfToken, [string]$version)

$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$Headers = @{ 
    "Accept"        = "application/json"
    "X-Avi-Version" = $version 
    "X-CSRFToken"   = $XsrfToken 
}

try {
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]
    
    # 1. 실제 생성된 백업 파일 리스트 조회 (/api/backup)
    $BackupListUri = "https://$Server/api/backup"
    $BackupListRes = Invoke-RestMethod -Method Get -Uri $BackupListUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    # 2. 백업 구성 설정 조회 (/api/backupconfiguration)
    $ConfigUri = "https://$Server/api/backupconfiguration"
    $ConfigRes = Invoke-RestMethod -Method Get -Uri $ConfigUri -Headers $Headers -WebSession $SessionId -ErrorAction Stop

    # 백업 구성이 없는 경우 처리
    if ($null -eq $ConfigRes.results -or $ConfigRes.results.Count -eq 0) {
        return $null
    }

	foreach ($cfg in $ConfigRes.results) {
		$CfgUuid = $cfg.uuid
		
		# 최신 백업 파일 찾기
		$LatestFile = $BackupListRes.results | 
					  Where-Object { $_.backup_config_ref -match $CfgUuid } | 
					  Sort-Object timestamp -Descending | 
					  Select-Object -First 1

		# --- [날짜 포맷 수정 구간] ---
		$LastTime = "N/A"
		if ($null -ne $LatestFile.timestamp) {
			try {
				# 소수점과 타임존을 제거하고 초까지만 표시
				$LastTime = ([DateTime]$LatestFile.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
			} catch {
				$LastTime = $LatestFile.timestamp # 변환 실패 시 원본 유지
			}
		}
		# ----------------------------

		$ReportEntries.Add([PSCustomObject]@{
			BackupConfig   = $cfg.name
			LastFileName   = if ($LatestFile) { $LatestFile.file_name } else { "No Backup Found" }
			LastBackupTime = $LastTime  # 초까지만 출력됨 (예: 2026-01-12 02:06:09)
			Status         = if ($cfg.save_local) { "RUNNING" } else { "STOPPED" }
			Health         = if ($null -ne $LatestFile) { "OK" } else { "CRITICAL" }
		})
	}

    return $ReportEntries | Sort-Object BackupConfig
} catch {
    Write-Warning "Avi Backup Plugin Error: $($_.Exception.Message)"
    return $null
}