하나의 메인 스크립트를 작성할거야.
다음 요건을 확인하고, 실행을 해줘.

1. 모듈 설치 확인
다음에 대한 모듈 설치를 확인하고, 미설치되어 있을 경우에는 설치하도록 코드를 작성

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name VCF.PowerCLI -MinimumVersion 9.0.0 -Scope AllUsers
Install-Module -Name VMware.vSphere.SsoAdmin -MinimumVersion 1.4.0 -Scope AllUsers

2. vCenter 연결
vCenter에 연결은 connect.ps1을 사용해서 접속
사전에 계정 정보를 Windows Credential을 사용해서 입력 받고, xml 파일로 저장해서 다음에 다시 사용합니다.
계정 입력 시, 저장 여부를 선택하도록 하고, 재 실행시에는 저장된 계정을 사용 여부를 선택하도록 합니다.
계정이 연결이 실패할 경우에는 powershell error를 표시 하지 말고, 계정 실패 메시지를 보여줍니다.

3. audit-all.ps1 파일로 audit 진행
audit-all.ps1 파일을 실행하여, 후속 작업을 실행합니다.
