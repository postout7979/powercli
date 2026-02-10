이 스크립트는 VMware PowerCLI module이 Windows OS에 배포되어 있어야합니다.
PowerCLI module을 공식 브로드컴 고객 지원 사이트에서 다운로드합니다.
스크립트의 사용 계정은 Read-Only 사용을 권장합니다.

# PowerCLI module Deployment
ZIP 파일을 사용하여 모든 VMware PowerCLI 모듈을 오프라인 모드로 설치할 수 있습니다.
시스템이 PowerCLI와 호환되는지 확인하십시오. 호환성 매트릭스를 참조하십시오.
시스템에 PowerShell이 설치되어 있는지 확인하십시오. Linux 및 macOS의 경우 PowerShell을 설치해야 합니다. 다른 플랫폼에 PowerShell을 설치하는 방법을 참조하십시오.

Windows의 경우 PowerCLI 6.5 R1 이하 버전이 설치되어 있으면 제거하십시오.

PowerCLI 홈페이지에서 PowerCLI ZIP 파일을 다운로드하여 로컬 컴퓨터로 전송하십시오.

[VCF PowerCLI](https://developer.broadcom.com/tools/vcf-powercli/latest/)

VMware-PowerCLI-13.3.0-24145081.zip: PowerCLI 오프라인 설치 파일

보안상의 이유 및 배포 제한으로 인해 인터넷 연결이 없는 로컬 컴퓨터에 PowerCLI를 설치해야 할 수도 있습니다. 이러한 환경을 사용하는 경우 인터넷에 연결된 컴퓨터에서 PowerCLI ZIP 파일을 다운로드하고 로컬 컴퓨터로 전송한 다음 PowerCLI를 설치할 수 있습니다.

로컬 컴퓨터에서 PowerShell을 엽니다.

PowerCLI ZIP 파일의 압축을 풀 수 있는 폴더 경로를 보려면 다음 명령을 실행하십시오.

```bash
$env:PSModulePath
```

```bash
PS C:\vmcode> $env:PSModulePath
C:\Users\broadcom\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules
```

다음과 같이 folder_path를 표시된 경로중 하나로 변경하여, 파일을 압축 해제합니다.

```bash
Get-ChildItem -Path 'folder_path' -Recurse | Unblock-File

Get-ChildItem -Path 'C:\Program Files\WindowsPowerShell\Modules' -Recurse | Unblock-File
```

설치된 모듈 목록을 확인합니다.

```bash
Get-Module VMware* -ListAvailable
```

**Allow Execution of Local Scripts**

PowerCLI를 사용하여 스크립트를 실행하고 구성 파일을 로드하려면 PowerShell의 실행 정책을 RemoteSigned로 설정해야 합니다.
보안상의 이유로 PowerShell은 실행 정책 기능을 지원합니다. 
이 정책은 스크립트 실행 허용 여부와 디지털 서명 필요 여부를 결정합니다. 기본적으로 실행 정책은 가장 안전한 정책인 Restricted로 설정되어 있습니다. PowerShell의 실행 정책 및 스크립트 디지털 서명에 대한 자세한 내용은 Get-Help About_Signing을 실행하십시오.
Set-ExecutionPolicy cmdlet을 사용하여 실행 정책을 변경할 수 있습니다

현재 규칙 리스트 확인

```bash
Get-ExecutionPolicy -List
```

디지털 서명 규칙 변경

```bash
Set-ExecutionPolicy RemoteSigned
```

---

디지털 서명 규칙 적용 후, 실행 시 추가 권한 오류 발생하는 경우 아래 규칙 적용

사용자 실행 규칙 변경

```bash
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

프로세스 실행 규칙 변경

```bash
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

변경된 규칙 리스트 확인

```bash
Get-ExecutionPolicy -List
```

비보안 인증서 처리 적용

```bash
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```



