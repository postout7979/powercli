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
    $Uri = "https://$Server/api/v1/management-plane-health"
    $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -WebSession $SessionId

    # 최종 결과를 담을 리스트
    $ReportEntries = New-Object System.Collections.Generic.List[PSCustomObject]

    if ($null -ne $Response) {
        
        # --- [STEP 1] 핵심 정보 추출 (consolidated_status, basic) ---
        $CoreKeys = @("consolidated_status", "basic")
        foreach ($Key in $CoreKeys) {
            if ($null -ne $Response.$Key) {
                $Data = $Response.$Key
                
                # basic 처럼 하위에 실제 컴포넌트(policy 등)가 있는 경우 처리
                if ($null -eq $Data.status) {
                    foreach ($subProp in $Data.psobject.Properties) {
                        $subVal = $subProp.Value
                        if ($null -ne $subVal.status) {
                            $Health = if ($subVal.status -match "UP|STABLE|GREEN") { "OK" } else { "WARNING" }
                            $ReportEntries.Add([PSCustomObject]@{
                                Component = "$Key > $($subProp.Name)"
                                Status    = $subVal.status
                                Reason    = if ($subVal.reason) { $subVal.reason } else { "-" }
                                Health    = $Health
                            })
                        }
                    }
                } 
                # consolidated_status 처럼 바로 데이터가 있는 경우
                else {
                    $Health = if ($Data.status -match "UP|STABLE|GREEN") { "OK" } else { "WARNING" }
					$ReportEntries.Add([PSCustomObject]@{
                        Component = $Key
                        Status    = $Data.status
                        Reason    = if ($Data.reason) { $Data.reason } else { "-" }
                        Health    = $Health
                    })
                }
            }
        }

        # --- [STEP 2] 통합 정보 추출 (integrated 하위 항목들) ---
        if ($null -ne $Response.integrated) {
            foreach ($prop in $Response.integrated.psobject.Properties) {
                $subVal = $prop.Value
                # status 필드가 있는 객체만 추출
                if ($null -ne $subVal -and $null -ne $subVal.status) {
                    $Health = if ($subVal.status -match "UP|STABLE|GREEN") { "OK" } else { "WARNING" }
                    $ReportEntries.Add([PSCustomObject]@{
                        Component = "integrated > $($prop.Name)"
                        Status    = $subVal.status
                        Reason    = if ($subVal.reason) { $subVal.reason } else { "-" }
                        Health    = $Health
                    })
                }
            }
        }
    }

    # 정렬하지 않고 추가된 순서(우선순위 순)대로 반환
    return $ReportEntries

} catch {
    Write-Warning "[$Server] Mgmt Health 단계별 추출 중 오류: $($_.Exception.Message)"
    return $null
}