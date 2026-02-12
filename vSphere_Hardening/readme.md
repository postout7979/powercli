

### 주요 파일 리스트
audit_runner.ps1: 메인 실행 파일
<br>
audit-reporter.ps1: 폴더와 텍스트 파일 생성된 이후, 해당 텍스트 불러오기로 해서, html파일 생성
<br>
json_to_aop.ps1: parameter로 서버, 계정 정보 입력해서 VCF Operations에 메트릭 주입
<br>
aop_cleanup.ps1: VCF Operations에서 해당 리소스 제거
<br>
audit-all.ps1: vCenter, ESXi, VM 스크립트를 모두 수행
<br>
audit-esxi-8.ps1: esxi에 확인이 필요한 명령어 수행
<br>
audit-vcenter-8.ps1: vCenter에 확인이 필요한 명령어 수행
<br>
audit-vm-8.ps1: VM에 확인이 필요한 명령어 수행
<br>
connect.ps1: vCenter 연결
<br>
scg-common.psm1: SCG에 필요한 공통 기능 추가
<br><br>

### 사용 방법
1. audit_runner.ps1 파일을 실행하여, vCenter 접속 정보를 입력하면 자동으로 실행됩니다.
- 하위 폴더로 출력 결과가 텍스트 파일로 생성됩니다.
2. audit-reporter.ps1 파일을 실행하고서, 폴더를 선택
- HTML 파일과 JSON 파일을 생성합니다.
3. json_to_aop.ps1 파일을 실행<br>
```json_to_aop.ps1 --AopServer="VCF operations fqdn" --AopUser="user name" --AopPassword="user password"```
<br>
- 파일을 실행하고서 -> 폴더 선택 -> JSON 파일 선택을 하면, VCF Operations에 메트릭 값을 전송합니다. VCF Operation에서는 최대 5분(VCF Ops의 메트릭 수집 주기) 이후에 반영될 수 있습니다.
- 인벤토리 항목에서 좌측 사이드 바 상단의 가장 우측(네 번째)의 객체 탭을 클릭하고서, 하위 트리에서 생성된 리소스 어답터를 확인합니다.
<br>
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
Security Hardening에 대한 소스 github: https://github.com/vmware/vcf-security-and-compliance-guidelines/tree/main/security-configuration-hardening-guide/vsphere
* 해당 github는 브로드컴에서 제공하는 Repository이며, vSphere를 포함한 다른 제품에 대한 SCG 가이드를 제공하고 있습니다.
* 각 버전별 스크립트에 따라 일부 차이가 발생할 수 있으며, 해당 버전의 powerCLI script tool을 사용을 권장하나, 기본적으로 version check 없이 진행하도록 명령어 수행 시, 옵션이 기재되어 있습니다.
* 다른 vSphere 버전을 사용중인 경우에는 현재 제공되는 vSphere 8 버전으로 우선 수행을 해보고, 해당 버전의 스크립트 파일을 다운로드한 후, 아래 4개의 파일만을 가져와 동일 위치에 복사한 후 실행을 권장합니다.
audit_runner.ps1
<br>
audit-reporter.ps1
<br>
json_to_aop.ps1
<br>
aop_cleanup.ps1
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
<br><br>
<img width="1892" height="795" alt="image" src="https://github.com/user-attachments/assets/947e550e-e668-45eb-ac9a-334eb20d697d" />

