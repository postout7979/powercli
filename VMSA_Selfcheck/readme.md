# 이 스크립트는 에어갭 환경에서 사전에 다운로드한 vCenter, ESXi에 대한 security patch를 위한 VMSA 항목 리스트를 보유한 JSON 파일을 가지고서, VMware PowerCLI 모듈을 사용한 Security Advisories의 버전에 해당 여부를 체크하는 스크립트입니다.
# 이 스크립트의 완전한 신뢰성을 제공하지는 않으며, Broadcom Security Advisory 사이트의 API 호출 방식 혹은 구문 배치 변경에 따라, downloader 스크립트에서 웹페이지 크롤링이 정상적으로 이뤄지지 않는 경우에는 더 이상 이 스크립트를 사용한 체크는 제한됩니다.

## 파일 순서
1. Readme.md: 설명서
2. downloader script: JSON 파일을 생성하기 위한 스크립트 -> 인터넷 연결 윈도우에서 사전에 JSON 파일을 생성 요구됨.
3. auditoer script: 에어갭 환경에서 JSON 파일을 동일 폴더에 위치하고서, 스크립트를 실행하여 vCenter에 접속합니다.(Read only 계정 강력 권장)
<br><br><br>
스크립트를 실행하면, vCenter에 접속 후 vCenter 및 ESXi host 버전을 수집하여, 버전의 첫 번째 메이저 버전을 기준으로 비교 검토합니다.(복잡성을 제거하기 위해서 build 버전등 세밀한 버전을 확인하지 않음으로 메이저 버전이 일치할 경우, 사용중인 상세 버전과 일치 여부를 matrix 정보를 보고서 확인합니다.)
CvSS 스코어가 표시가 되지 않는 VMSA는 오래된 페이지로 현재의 제공되는 VMSA 페이지와 노출 방식이 달라서 공백으로 표시됩니다.
<br><br><br>
auditor 스크립트 실행 화면
<br>
<img width="862" height="507" alt="image" src="https://github.com/user-attachments/assets/5a682dd9-ba4c-4e9e-8538-4eb373946cc2" />
<br>
스크립트 실행 시, 계정 저장 여부를 확인합니다. xml 파일로 저장되며, 암호를 변경 시에는 xml 파일 삭제를 권장합니다.(read only 계정 사용)
<br><br><br>
출력 웹페이지 화면
- 웹페이지는 다음과 같이 출력됩니다.
<br>
<img width="2081" height="744" alt="image" src="https://github.com/user-attachments/assets/b1cf740f-8708-4028-a76f-7267791cb928" />
<br><br><br>
ACTION 열의 Details 버튼을 클릭하면, 현재 matrix 정보를 확인할 수 있으며, ID열의 VCDSAxxx 를 클릭하면, 브로드컴 페이지를 오픈합니다.(에어갭 환경에서는 Details에 있는 URL 링크를 참고합니다.)
<br>
<img width="2046" height="698" alt="image" src="https://github.com/user-attachments/assets/0feb5811-fddd-4897-8513-624eb21df193" />
