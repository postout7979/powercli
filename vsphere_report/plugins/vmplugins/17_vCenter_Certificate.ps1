param($Server, $SessionId)
$Headers = @{"vmware-api-session-id" = $SessionId; "Accept" = "application/json"}

try {
	# vSphere 8.0 머신 SSL 인증서 엔드포인트
	$Uri = "https://$Server/api/vcenter/certificate-management/vcenter/tls"
	$Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
	
	# 8.0의 응답 구조는 .value 안에 상세 정보가 바로 들어있습니다.
	$cert = if ($null -ne $Response.value) { $Response.value } else { $Response }

	if ($null -eq $cert.valid_to) {
		Write-Host " -> Error: Certificate data structure is unexpected." -ForegroundColor Red
		return $null
	}

	# 날짜 파싱 (ISO 8601 형식 대응)
	$ExpiryDate = [DateTime]::Parse($cert.valid_to)
	$Today = Get-Date
	$DaysLeft = ($ExpiryDate - $Today).Days

	# 결과 객체 생성
	$Results = @()
	$Results += [PSCustomObject]@{
		CertName       = "Machine SSL (TLS) Certificate"
		ExpirationDate = $ExpiryDate.ToString("yyyy-MM-dd")
		DaysRemaining  = $DaysLeft
		Status         = if ($DaysLeft -lt 30) { "critical" } elseif ($DaysLeft -lt 90) { "warning" } else { "ok" }
	}

	# (선택 사항) 루트 인증서 체인 정보도 추가하려면 아래 경로를 사용합니다.
	# $RootUri = "https://$Server/api/vcenter/certificate-management/vcenter/trusted-root-chains"
	return $Results
} catch {
	Write-Host " -> Certificate API Error: $($_.Exception.Message)" -ForegroundColor Red
	return $null
}