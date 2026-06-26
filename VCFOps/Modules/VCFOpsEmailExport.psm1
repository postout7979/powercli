# VCFOpsEmailExport.psm1
# -----------------------------------------------------------------------------
# 생성된 리포트(HTML/Excel/CSV/PDF)를 SMTP로 이메일 발송합니다.
# Send-MailMessage는 마이크로소프트가 더 이상 사용을 권장하지 않는(향후 제거 예정)
# cmdlet이라, .NET의 System.Net.Mail.SmtpClient/MailMessage를 직접 사용합니다.
# -----------------------------------------------------------------------------

function Send-VCFOpsReportEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SmtpServer,
        [int]$SmtpPort = 587,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string[]]$To,
        [string[]]$Cc = @(),
        [Parameter(Mandatory)][string]$Subject,
        [string]$Body = "",
        [bool]$IsBodyHtml = $false,
        [string[]]$AttachmentPaths = @(),
        [string]$Username = "",
        [string]$Password = "",
        [bool]$UseSsl = $true,
        [int]$TimeoutSec = 60
    )

    $mail = $null
    $smtp = $null
    $attachments = @()
    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $From
        foreach ($t in $To) { if ($t) { $mail.To.Add($t) } }
        foreach ($c in $Cc) { if ($c) { $mail.CC.Add($c) } }
        if ($mail.To.Count -eq 0) {
            Write-Warning "수신자(-SmtpTo)가 없어 이메일을 보내지 않습니다."
            return $false
        }
        $mail.Subject = $Subject
        $mail.Body = $Body
        $mail.IsBodyHtml = $IsBodyHtml

        foreach ($path in $AttachmentPaths) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                $att = New-Object System.Net.Mail.Attachment($path)
                $attachments += $att
                $mail.Attachments.Add($att)
            }
            elseif ($path) {
                Write-Warning "첨부 파일을 찾지 못해 건너뜁니다: $path"
            }
        }

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = $UseSsl
        $smtp.Timeout = $TimeoutSec * 1000
        if ($Username) {
            $smtp.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
        }

        $smtp.Send($mail)
        return $true
    }
    catch {
        Write-Warning "이메일 발송 실패: $($_.Exception.Message)"
        return $false
    }
    finally {
        foreach ($att in $attachments) { try { $att.Dispose() } catch { } }
        if ($mail) { try { $mail.Dispose() } catch { } }
        if ($smtp) { try { $smtp.Dispose() } catch { } }
    }
}

Export-ModuleMember -Function Send-VCFOpsReportEmail
