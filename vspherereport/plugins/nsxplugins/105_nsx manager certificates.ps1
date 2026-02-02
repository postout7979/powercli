param(
    [string]$Server,
    $SessionId, 
    [string]$XsrfToken
)

# 1. 출력 억제 및 보안 설정
$null = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$null = [Net.SecurityProtocolType]::Tls12

$Headers = @{ 
    "X-XSRF-TOKEN" = $XsrfToken
    "Accept"       = "application/json"
}

try {
    # 2. Trust Management API 호출
    $Uri = "https://$Server/api/v1/trust-management/certificates"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $Response -and $null -ne $Response.results) {
        foreach ($cert in $Response.results) {
            
            $DisplayName = if ($cert.display_name) { $cert.display_name } else { $cert.id }
            $ResourceType = $cert.resource_type
            
            # 3. used_by 처리 (구조적 접근)
            $UsedByArray = @()
            if ($null -ne $cert.used_by -and $cert.used_by.Count -gt 0) {
                foreach ($usage in $cert.used_by) {
                    $NodeId = if ($usage.node_id) { $usage.node_id } else { "Global" }
                    $Services = if ($usage.service_types) { $usage.service_types -join ", " } else { "Unknown" }
                    $UsedByArray += "$NodeId ($Services)"
                }
            }
            $UsedByDisplay = if ($UsedByArray.Count -gt 0) { $UsedByArray -join " | " } else { "Unused" }

            # 4. PEM 데이터를 활용한 날짜 파싱 (응답에 not_after가 없을 경우 대비)
            $ExpiryDate = "N/A"
            $DaysRemaining = -999
            $Health = "UNKNOWN"
            $Subject = "Unknown"

            if ($null -ne $cert.pem_encoded) {
                try {
                    # 첫 번째 인증서 블록 추출
                    $Pem = $cert.pem_encoded
                    if ($Pem -match "-----BEGIN CERTIFICATE-----([^\-]+)-----END CERTIFICATE-----") {
                        $Base64Cert = $Matches[1].Trim() -replace "\s", ""
                        $CertBytes = [System.Convert]::FromBase64String($Base64Cert)
                        $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $x509.Import($CertBytes)

                        $ExpiryDate = $x509.NotAfter
                        $Subject = $x509.Subject
                        $TimeSpan = $ExpiryDate - (Get-Date)
                        $DaysRemaining = [math]::Round($TimeSpan.TotalDays)

                        # 상태 결정 로직
                        if ($DaysRemaining -lt 0) { $Health = "CRITICAL" }
                        elseif ($DaysRemaining -lt 30) { $Health = "CRITICAL" }
                        elseif ($DaysRemaining -lt 60) { $Health = "WARNING" }
                        else { $Health = "OK" }
                    }
                } catch {
                    $Subject = "Parsing Error"
                }
            }

            # 5. 결과 개체 생성
            $ReportEntries.Add([PSCustomObject]@{
                DisplayName   = $DisplayName
                Type          = $ResourceType
                Subject       = $Subject
                Used_By       = $UsedByDisplay
                ExpiryDate    = if($ExpiryDate -is [DateTime]){ $ExpiryDate.ToString("yyyy-MM-dd") } else { "N/A" }
                DaysLeft      = $DaysRemaining
                Health        = $Health
            })
        }
    }

    return $ReportEntries | Sort-Object DaysLeft

} catch {
    Write-Warning "[$Server] 인증서 데이터 처리 중 오류: $($_.Exception.Message)"
    return $null
}