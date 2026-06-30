# VCF 9 사전 점검 스크립트 (vcf9-precheck-script-cs.ps1)

vCenter에 접속해서 클러스터/호스트/VM/네트워크/스토리지 인벤토리를 수집하고,
수집된 하드웨어(서버 모델/CPU/NIC/스토리지 컨트롤러)를 VMware VCF 9 HCL(하드웨어 호환성 목록)과
비교해서 호환성 여부를 점검하는 PowerCLI 스크립트입니다.

---

## 1. 사전 준비사항

| 항목 | 내용 |
|---|---|
| PowerShell | Windows PowerShell 5.1 이상 (PowerShell 7도 가능) |
| VMware.PowerCLI 모듈 | 없으면 스크립트가 **자동 설치**를 시도합니다. 인터넷이 안 되는 폐쇄망이면 [8. 폐쇄망(오프라인) 환경 안내](#8-폐쇄망오프라인-환경-안내) 참고 |
| vCenter 접속 계정 | 클러스터/호스트 정보를 읽을 수 있는 권한 (읽기 전용 계정이면 충분) |
| HCL 비교용 CSV 4종 | VMware Compatibility Guide에서 내려받은 아래 4개 파일 (파일명은 자유롭게 바꿔도 무방) |

HCL CSV 4종:
- **CPU 정보**: CPU Series별 지원 ESXi 버전
- **IO Devices**: NIC / RAID / HBA 등 I/O 장치별 지원 ESXi 버전
- **Systems / Servers**: 서버 벤더·모델별 지원 CPU Series, GPU, ESXi 버전
- **vSAN I/O Controller**: vSAN용 스토리지 컨트롤러 지원 목록

> 파일을 어떻게 찾는지는 **파일명이 아니라 CSV 안의 컬럼(헤더)** 으로 자동 판별합니다.
> 즉 파일명을 무엇으로 바꾸든 상관없이 4종 모두 폴더 안에만 있으면 자동으로 인식됩니다.
>
> **단, ESXi 버전(9.0 / 9.1) 구분은 파일명으로 판별합니다.**
> 파일명에 `9_0` 또는 `9.0`이 포함되어 있으면 **ESXi 9.0 전용** 데이터, `9_1` 또는 `9.1`이 포함되어 있으면 **ESXi 9.1 전용** 데이터로 인식합니다.
> 버전 표시가 없는 파일은 9.0/9.1 공통 데이터로 취급합니다.
>
> 예) `CPU_Series_9_0.csv` → 9.0 전용 / `CPU_Series_9_1.csv` → 9.1 전용 / `CPU_Series.csv` → 9.0·9.1 공통

---

## 2. 파일 배치

```
C:\powercli\
 ├─ vcf9-precheck-script-cs.ps1
 └─ HCL\                          <- 이 폴더 이름이면 -HCLPath 안 줘도 자동 인식
     ├─ CPU_Series_9_0.csv         (ESXi 9.0 전용)
     ├─ CPU_Series_9_1.csv         (ESXi 9.1 전용)
     ├─ IO_Devices_9_0.csv
     ├─ IO_Devices_9_1.csv
     ├─ Systems_Servers_9_0.csv
     ├─ Systems_Servers_9_1.csv
     ├─ vSAN_IO_Controller_9_0.csv
     └─ vSAN_IO_Controller_9_1.csv
```

> 버전별로 파일이 나뉘어 있지 않고 4종만 있어도 동작합니다 (그 경우 9.0/9.1 공통 데이터로 처리됩니다).

HCL CSV를 다른 위치에 두고 싶다면 `-HCLPath` 옵션으로 경로를 직접 지정하면 됩니다.

---

## 3. 실행 방법

### 기본 실행 (가장 단순한 형태)

```powershell
.\vcf9-precheck-script-cs.ps1
```

실행하면 순서대로:
1. vCenter 주소 입력 요청 (`▶ vCenter IP 또는 FQDN을 입력하세요`)
2. 계정/비밀번호 입력 요청 (Windows 자격 증명 입력창)

### 옵션을 사용한 실행

```powershell
.\vcf9-precheck-script-cs.ps1 -HCLPath "C:\HCL"
```

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `-HCLPath` | HCL CSV 4종이 들어있는 폴더 경로 | 스크립트 위치의 `HCL` 폴더 → 없으면 스크립트가 있는 폴더 |

> ⚠ `-HCLPath` 경로 값 끝에 백슬래시(`\`)를 붙이지 마세요.
> `"C:\HCL"` (O) / `"C:\HCL\"` (X) — Windows 명령줄 인자 처리 방식상 뒤에 오는 옵션이 모두 인식되지 않는 문제가 생길 수 있습니다.

---

## 4. 실행 단계 (총 12단계)

| 단계 | 내용 | 생성 파일 |
|---|---|---|
| 0 | PowerCLI 설치 확인/자동 설치, vCenter 연결 | - |
| 1 | 클러스터 정보 수집 | `Clusters.csv` |
| 2 | 호스트 성능/하드웨어 정보 수집 (CPU 모델/벤더, 라이선스 키 포함) | `Hosts_Perf.csv`, `Hosts_Hardware.csv` |
| 3 | VM 상태/디스크/VMTools 정보 수집 | `VMs_Status.csv`, `Special_Disks(RDM_Shared_Thick).csv` |
| 4 | 스토리지/LUN 매핑 테이블 구성 | `Datastores.csv` |
| 5 | 가상 스위치/VDS 정보 수집 | `Virtual_Switches.csv` |
| 6 | ESXCLI 캐시 구성 (드라이버/펌웨어 조회용) | - |
| 7 | 물리 NIC 정보 수집 | `Physical_NICs.csv` |
| 8 | FC HBA 정보 수집 | `HBA_Cards.csv` (FC HBA가 없으면 생성 안 됨) |
| 9 | RAID 컨트롤러 정보 수집 | `RAID_Controllers.csv` |
| 10 | **HCL 호환성 검사** (Server/CPU/NIC/Storage Controller) | `Compatibility_Server.csv`, `Compatibility_CPU.csv`, `Compatibility_NIC.csv`, `Compatibility_StorageController.csv`, `Compatibility_Report.html` |
| 11 | vCenter 연결 해제 | - |
| 12 | 전체 결과 ZIP 압축 | `vSphere_Inventory_YYYYMMDD_HHMM.zip` |

최종적으로 위 모든 CSV/HTML 파일이 **하나의 ZIP**으로 압축되어 스크립트가 있는 폴더에 생성됩니다.

---

## 5. 호환성 검사 결과 해석 방법

### 판정 기준
- `Match_Score(%)`: 수집된 정보와 HCL 항목 간의 유사도 점수 (0~100)
- `ESXi_9.0` / `ESXi_9.1`: **두 버전을 각각 별도로 판정**합니다. 유사도가 50% 이상이면 `OK`, 미달이면 `MISMATCH`
  - (CPU는 유사도 대신 모델 시리즈/세대 일치 여부로 OK/MISMATCH를 판정)
- `MISMATCH`라도 가장 유사도가 높았던 HCL 후보를 항상 `HCL_Match` 컬럼에 표시합니다 (수동 확인용)
- 같은 장비라도 9.0 HCL에는 있고 9.1 HCL에는 없는 경우(또는 반대) `ESXi_9.0`과 `ESXi_9.1` 값이 서로 다르게 나올 수 있습니다

### 항목별 매칭 방식

| 항목 | 매칭 방식 |
|---|---|
| **Server** | 제조사+모델명 단어(토큰) 유사도. 숫자가 포함된 토큰(모델 번호)에 더 높은 가중치 부여 |
| **CPU** | 세부 SKU가 아니라 **모델 시리즈(세대)** 단위로 판정. Intel은 SKU 앞 2자리, AMD는 첫/끝자리로 세대를 구분해서 HCL Series 코드와 비교 |
| **NIC** | IO Devices HCL 중 `Device Type = Network` 항목과 모델명 유사도 비교 |
| **Storage Controller (HBA/RAID)** | IO Devices HCL(Network 제외) + vSAN I/O Controller HCL 둘 다 비교. vSAN 지원 여부는 비고(Note)에 별도 표기 |

위 매칭은 ESXi 9.0용 HCL 데이터와 9.1용 HCL 데이터에 대해 **각각 독립적으로 수행**됩니다.

> CPU/IO 장치 매칭은 **best-effort 유사도 기반**입니다. 최종 확인은 VMware Compatibility Guide에서 직접 재확인하는 것을 권장합니다.

---

## 6. HTML 리포트 (Compatibility_Report.html) 보는 법

브라우저로 열면 위에서부터 아래 순서로 구성되어 있습니다.

1. **전체 요약** — Server/CPU/NIC/Storage_Controller 각각의 총 개수 및 **ESXi 9.0 / 9.1 각각의** 일치(OK)·불일치(MISMATCH)·일치율
2. **클러스터별 호스트 호환성 요약** — 클러스터별로 "Server+CPU+NIC+Storage 전부 OK인 호스트(100% 일치)" 수와 "하나라도 MISMATCH가 있는 호스트(불일치)" 수를 **ESXi 9.0 기준, 9.1 기준 각각 따로** 집계 + 불일치 호스트 이름 목록
3. **클러스터별 상세 목록** — 가장 큰 분류 단위인 클러스터별로 구분되며, 그 안에서 Server → CPU → NIC → Storage_Controller 순서로 상세 표가 표시됩니다. 각 행에 `ESXi 9.0`, `ESXi 9.1` 배지가 따로 표시되며, 행 배경색으로 한눈에 구분됩니다: 흰색(둘 다 OK) / 노란색(한쪽만 OK) / 빨간색(둘 다 MISMATCH)

---

## 7. 폐쇄망(오프라인) 환경 안내

인터넷이 안 되는 서버에서 실행하면 PowerCLI 자동 설치가 실패하고 안내 메시지가 출력됩니다.

Verify that your system is compatible with PowerCLI. See the Compatibility Matrix .
Verify that PowerShell is available on your system. For Linux and macOS, you must install PowerShell. See how to install PowerShell on different platforms.
For Windows, if you have PowerCLI 6.5 R1 or earlier, uninstall it.
Download the PowerCLI ZIP file from the PowerCLI home page and transfer the ZIP file to your local machine.
You might need to install PowerCLI on a local machine with no Internet connectivity due to security reasons and deployment restrictions. If you are using such an environment, you can download the PowerCLI ZIP file on a computer with Internet access, transfer the ZIP file to your local machine and install PowerCLI.
Open PowerShell on your local machine.
To view the folder paths to which you can extract the PowerCLI ZIP file, run the command:
$env:PSModulePath
Extract the contents of the PowerCLI ZIP file to one of the listed folders.
For Windows, run the command to unblock the copied files.
Get-ChildItem -Path 'folder_path' -Recurse | Unblock-File
Replace folder_path with the path to the folder where you extracted the contents of the ZIP file.
Verify that the VMware PowerCLI modules have installed successfully.
Get-Module VMware* -ListAvailable
You can now run PowerCLI on your local machine.
Enable execution of local scripts. See Allow Execution of Local Scripts.
---

## 8. 자주 발생하는 문제

| 증상 | 원인 / 해결 방법 |
|---|---|
| `Cannot complete login due to an incorrect user name or password` | 계정/비밀번호 오류입니다. SSO 계정 형식(`user@vsphere.local`)인지, 비밀번호 만료/계정 잠김 여부를 확인하세요. |
| 옵션을 줬는데 다른 옵션이 같이 인식 안 됨 | 경로 값 끝에 `\`가 있는지 확인하세요. (`"C:\HCL\"` → `"C:\HCL"`) |
| `[WARN] HCL 호환성 데이터 파일을 찾을 수 없어 호환성 검사를 건너뜁니다` | HCL CSV 4종이 `-HCLPath` 경로(또는 스크립트 폴더의 `HCL` 폴더)에 실제로 있는지 확인하세요. 실행 시 `[INFO] ... 인식된 HCL 파일:` 메시지로 어떤 파일이 어떤 종류 / 어떤 버전(9.0·9.1·공통)으로 인식됐는지 확인할 수 있습니다. |
| `ESXi_9.0`은 OK인데 `ESXi_9.1`은 MISMATCH (또는 반대) | 정상입니다. 해당 장비가 한쪽 버전의 HCL에만 등록돼 있다는 뜻입니다. `[INFO] ... 인식된 HCL 파일:` 메시지로 9_0/9_1 파일이 둘 다 정상적으로 인식됐는지 먼저 확인하세요. |
| `HBA_Cards.csv`가 생성되지 않음 | 정상입니다. 해당 호스트에 FC(Fibre Channel) HBA가 없으면 파일 자체가 생성되지 않습니다. |
| `License_Key`가 일부만 보이고 나머지가 `*****`로 표시됨 | vCenter 라이선싱 API의 기본 보안 동작입니다. 접속 계정에 `Global.Licenses` 권한이 없으면 마지막 5자리만 보여주고 나머지는 마스킹합니다. 전체 키가 필요하면 해당 권한이 있는 계정으로 재실행하세요. |

---

## 9. 한계 / 주의사항

- 호환성 판정은 **모델명/시리즈 기반 best-effort 유사도 매칭**이며, VMware의 정식 Compatibility Guide 조회를 완전히 대체하지는 않습니다.
- CPU 세대 판정 시 일부 시리즈(예: Intel Xeon Gold 6300번대처럼 Cooper-Lake-SP와 Ice-Lake-SP가 같은 코드를 공유하는 경우)는 VMware HCL 데이터 자체의 모호성으로 인해 정확한 마이크로아키텍처까지는 구분하지 못할 수 있습니다.
- 본 스크립트는 읽기 전용 조회만 수행하며, vCenter/ESXi 설정을 변경하지 않습니다.

## 아웃풋(HTML)
전체 요약 페이지
<img width="1764" height="862" alt="image" src="https://github.com/user-attachments/assets/f33f95cc-6969-4d0f-b9d7-324005fa3344" />

각 클러스터별 페이지
<img width="1756" height="891" alt="image" src="https://github.com/user-attachments/assets/fb8470d2-80da-4b85-a3c2-8ec9dce103c9" />
<img width="1749" height="470" alt="image" src="https://github.com/user-attachments/assets/d1d250ce-e889-4bf1-8805-7e3248a0f2c2" />


