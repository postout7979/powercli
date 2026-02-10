
audit_runner.ps1: 메인 실행 파일
<br>
audit-reporter.ps1: 폴더와 텍스트 파일 생성된 이후, 해당 텍스트 불러오기로 해서, html파일 생성
<br>
json_to_aop.ps1: parameter로 서버, 계정 정보 입력해서 VCF Operations에 메트릭 주입
<br>
aop_cleanup.ps1: VCF Operations에서 해당 리소스 제거
<br><br><br>

report 텍스트 파일
<br><br>
<img width="829" height="505" alt="image" src="https://github.com/user-attachments/assets/9f174e5c-ce36-41c2-bfef-6520004b2567" />
<br><br>
```
[2026-02-10 17:58:27] [INFO] VMware ESX Host Security Settings Audit Utility 8.0.3
[2026-02-10 17:58:27] [INFO] Audit of fu-01.vks.lab started at 2026-02-10 17:58:27 from HCSVDI-28 by broadcom
[2026-02-10 17:58:27] [INFO] EULA accepted.
[2026-02-10 17:58:27] [INFO] Safety checks skipped.
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: UserVars.HostClientSessionTimeout configured correctly (900)
[2026-02-10 17:58:31] [FAIL] fu-01.vks.lab: Syslog.global.auditRecord.storageEnable not configured correctly (False)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: UserVars.ESXiVPsDisabledProtocols configured correctly (sslv3,tlsv1,tlsv1.1)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: Security.AccountLockFailures configured correctly (5)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: UserVars.DcuiTimeOut configured correctly (600)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: Security.AccountUnlockTime configured correctly (900)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: Config.HostAgent.plugins.solo.enableMob configured correctly (False)
[2026-02-10 17:58:31] [PASS] fu-01.vks.lab: Net.DVFilterBindIpAddress configured correctly ()
```
<br><br>
report html 파일
<br><br>
<img width="1262" height="1156" alt="image" src="https://github.com/user-attachments/assets/8d7925bb-11ca-4e8f-a2db-e67ca7e6eece" />
<br><br>
VCF Operations view
<br><br>
<img width="1071" height="545" alt="image" src="https://github.com/user-attachments/assets/db01a917-df58-4d9c-b043-51b4f4df38f5" />
<br><br>
VCF Operations Inventory
<br><br>
<img width="2013" height="1080" alt="image" src="https://github.com/user-attachments/assets/21407a8a-5d96-4039-b59a-27470a3d1e1d" />
