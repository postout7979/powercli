# 스크립트의 실제 경로로 수정하세요
$targetScript = "C:\powercli\vksreport\K8s_Daily_Check.ps1"

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$targetScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "K8s_Status_AutoCheck" -Action $action -Trigger $trigger -Principal $principal -Description "Daily K8s monitoring and email report"