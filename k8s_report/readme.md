# 폴더 구조<br>
- k8s_health_summary<br>
- k8s_resource<br>
<br><br>
k8s_health_summary: kubernetes 공개 API URL인 version, healthz, readyz등을 호출하여, 해당 정보를 출력<br>
k8s_resource: token 정보를 사용해서, K8s내 node, pod, service에 대한 정보를 조회<br>
  - node: 노드 정보 표시<br>
  - pod: 문제가 있는 대상만 표시<br>
  - service: 서비스 현황 표시<br>
  - ingress: ingress 현황 표시<br>
<p></p><br><br>
k8s_health_summary
- ips.txt에 호출 대상 cluster API 주소를 기재합니다.(line by line으로 다수 기입)
- main.ps1을 실행합니다.
<br><br>
k8s_resource
- clusters.txt: cluster api IP 주소와 token을 기재합니다. "," 콤마로 구분(line by line으로 다수 기입)
- create_k8s_user.sh: supervisor & vks cluster 접속 linux OS에서 login 상태에서 스크립트 실행 시, 사용자 계정과 토큰을 생성합니다.
- make_clusters.sh: supervisor & vks cluster 접속 linux OS에서 현재 접속 상태의 config 정보를 조회해서 cluster API IP주소와 현재 토큰을 수집합니다.(vSphere SSO로 로그인한 토큰은 제한 시간이 존재합니다.)
- k8s_runner.ps1: 스크립트를 실행하면, 정보를 수집하고 html 및 csv 파일을 생성합니다.
  
