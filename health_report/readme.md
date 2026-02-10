
# vSpherer, AVI, NSX-T 스크립트 사용법
<br>
Select-Plugins.ps1: 스크립트 실행 시, 수집 항목을 사전에 선택(체크/체크아웃)
<br>

### vSphere script
Get-VM-Report.ps1: 메인 스크립트 실행 파일
Connect-Vcenter.ps1: vSphere PowerCLI로 수집이 안되는 일부 항목은 Restful API 호출을 사용하기 위한 로그인 스크립트
Disconnect-Vcenter.ps1: API 호출한 로그인 세션에 대한 로그아웃 스크립트

### AVI script
Get-AVI-Report.ps1: AVI login(API)을 통한 정보 수집하는 스크립트
<br>
### NSX script
Get-NSX-Report.ps1: NSX login(API)을 통한 정보 수집하는 스크립트
<br>

하위 폴더
- plugins: 각 스크립트별 수행 플러그인 스크립트
- reports: 수집된 정보를 HTML 및 CSV 파일로 저장(날짜 기준 1개 파일 저장)
<br>

### 실행 순서(sample)
Select-Plugins.ps1 스크립트를 실행
- 수집 대상 기능을 선택 및 선택 해제합니다.
<br>
Get-VM-Report.ps1 스크립트를 실행
<br>
- vCenter 주소 입력
- 계정 정보 입력(한번 입력하면, 계정 정보는 xml 파일로 저장됩니다. 비밀번호가 변경될 경우, 해당 xml 파일을 삭제해야 합니다. 보안을 위해서 계정은 Read-Only 계정을 사용하며, 저장을 하지 않을 경우에는 스크립트에서 저장 항목을 # 처리 합니다. mycredential.xml 파일 export 하는 행)
<br>

# 수집 결과

## HTML output
<img width="1398" height="1182" alt="image" src="https://github.com/user-attachments/assets/2c86d5c2-4eb6-459d-8239-3aa5d9795855" />
<img width="1395" height="1105" alt="image" src="https://github.com/user-attachments/assets/3bd45d7d-1dcd-4d33-88a3-d5933ad88361" />


## CSV output
<img width="548" height="1073" alt="image" src="https://github.com/user-attachments/assets/ee77c81c-75f6-45bc-bd17-83a742f0e7f3" />


