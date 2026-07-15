# Get-AriaOpsVMPerformance.ps1

Aria Operations (vROps) 8.x REST API를 통해 vCenter 하위 전체 VM의
**CPU / Memory / Disk / Network** 성능 지표(Peak, Avg)를 지정 기간에 대해 수집하여
CSV로 저장하는 PowerShell 스크립트입니다.

실행 결과로 CSV 2개가 생성됩니다.
1. `AriaOps_VM_Performance_<timestamp>.csv` — VM 단위 집계 지표 (CPU/Memory/Disk/Network)
2. `AriaOps_VM_Performance_<timestamp>_VirtualDiskDetail.csv` — VM의 **SCSI 컨트롤러:유닛별**
   (예: scsi0:0, scsi0:1, scsi1:0 ...) Virtual Disk 성능 상세

## 실행 방법

```powershell
# 기본값(직전 30일)으로 실행 - 실행 시 서버/계정 정보를 프롬프트로 입력
.\Get-AriaOpsVMPerformance.ps1

# 직전 7일 데이터만 수집
.\Get-AriaOpsVMPerformance.ps1 -Days 7

# 출력 파일 경로 지정
.\Get-AriaOpsVMPerformance.ps1 -Days 30 -OutputPath "D:\Reports\vm_perf.csv"

# 대규모 환경(VM 수천 대)에서 배치 크기 조정
.\Get-AriaOpsVMPerformance.ps1 -Days 30 -BatchSize 30
```

실행하면 아래 항목을 순서대로 프롬프트로 입력받습니다.

1. Aria Operations 서버 주소 (FQDN 또는 IP)
2. 계정(Username)
3. 비밀번호 (SecureString으로 입력, 화면에 표시 안 됨)
4. 인증 소스(AuthSource) — 로컬 계정이면 Enter만 눌러 `local` 사용

## 파라미터

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `-Days` | 30 | 조회할 직전 기간(일). 예: 7 = 직전 1주, 30 = 직전 1개월, 90 = 직전 3개월 |
| `-OutputPath` | `.\AriaOps_VM_Performance_<timestamp>.csv` | 결과 CSV 저장 경로 |
| `-PageSize` | 1000 | VM 목록 조회 시 페이지 크기 |
| `-BatchSize` | 50 | 한 번의 stats/query 호출에 포함할 VM 수 |

## 수집 항목 (CSV 컬럼)

> 2026-07-15 실제 수집 결과를 확인해 **완전히 비어 있던(0/172) statKey는 스크립트에서 제거**했습니다.
> 아래 표는 현재 실제로 수집되는(또는 부분적으로라도 값이 들어오는) 컬럼만 정리한 것입니다.

| 컬럼 | 의미 | 단위 | statKey |
|---|---|---|---|
| VMName | VM 이름 | - | - |
| ResourceId | Aria Ops 리소스 ID | - | - |
| **CPU** | | | |
| CPU_Pct_Avg / CPU_Pct_Peak | CPU 사용률 평균/최고 | % | `cpu\|usage_average` |
| CPU_MHz_Avg / CPU_MHz_Peak | CPU 사용량 평균/최고 | MHz | `cpu\|usagemhz_average` |
| CPU_ReadyPct_Avg / CPU_ReadyPct_Peak | CPU Ready(호스트 CPU 대기) 평균/최고 — 값이 높으면 CPU 경합(over-commit) 의심 | % | `cpu\|readyPct` |
| **Memory** | | | |
| Mem_Pct_Avg / Mem_Pct_Peak | Memory 사용률 평균/최고 | % | `mem\|usage_average` |
| Mem_Active_KB_Avg / Mem_Active_KB_Peak | Active Memory 평균/최고 | KB | `mem\|active_average` |
| Mem_Consumed_KB_Avg / Mem_Consumed_KB_Peak | 실제 소비된 호스트 물리 메모리 평균/최고 | KB | `mem\|consumed_average` |
| Mem_Swapped_KB_Avg / Mem_Swapped_KB_Peak | 스왑된 메모리 평균/최고 — 0보다 크면 메모리 부족 신호 | KB | `mem\|swapped_average` |
| **Disk** | | | |
| Disk_KBps_Avg / Disk_KBps_Peak | Disk 전체 처리량(읽기+쓰기) 평균/최고 (일부 VM만 값 존재) | KBps | `disk\|usage_average` |
| VD_ReadThroughput_KBps_Avg / _Peak | 가상 디스크 읽기 처리량 평균/최고 | KBps | `virtualDisk\|read_average` |
| VD_WriteThroughput_KBps_Avg / _Peak | 가상 디스크 쓰기 처리량 평균/최고 | KBps | `virtualDisk\|write_average` |
| **Network** | | | |
| Net_KBps_Avg / Net_KBps_Peak | Network 전체 처리량 평균/최고 | KBps | `net\|usage_average` |
| Net_DroppedRx_Total | 기간 내 수신 패킷 드롭 누적 건수 (SUM 롤업) | 건 | `net\|droppedRx_summation` |
| Net_DroppedTx_Total | 기간 내 송신 패킷 드롭 누적 건수 (SUM 롤업) | 건 | `net\|droppedTx_summation` |
| **Guest OS** | | | |
| GuestFS_UsagePct_Avg / GuestFS_UsagePct_Peak | Guest OS 전체 파일시스템 사용률 평균/최고 (VMware Tools 필요) | % | `guestfilesystem\|percentage_total` |

> - `_Avg` / `_Peak` 컬럼은 vROps `resources/stats/query` API 호출 시 `rollUpType`을
>   각각 `AVG`, `MAX`로 지정하고, `intervalType=MONTHS, intervalQuantity=1`로
>   설정하여 지정한 기간 전체를 하나의 롤업 구간으로 집계한 값입니다.
>   (일별/시간별 세부 추이가 아닌, 기간 전체의 단일 대표값입니다.)
> - `_Total` 컬럼(네트워크 드롭 패킷)은 summation 계열 카운터이므로 `rollUpType=SUM`으로
>   별도 조회하여 기간 전체 누적 발생 건수를 담습니다.
> - `Mem_Swapped_KB`, `CPU_ReadyPct`는 값이 0 또는 null이면 해당 기간 동안 경합/부족 현상이
>   거의 없었다는 뜻이며, 반대로 지속적으로 값이 잡히면 리소스 증설/재배치 검토가 필요한 신호입니다.
> - `guestfilesystem|percentage_total`은 VMware Tools가 설치·실행 중이어야 값이 수집됩니다.

### 제거된 컬럼 (2026-07-15 실측 결과 0/172 확인 후 제거)

이 환경에서는 아래 statKey가 전혀 수집되지 않아 스크립트에서 제거했습니다. (다른 환경에서는 수집될 수도
있으니, 필요하면 "참고/커스터마이징" 섹션을 참고해 다시 추가하세요.)

- `mem|vmmemctl_average` (Mem_Balloon_KB) — vROps 기본 정책상 Disabled Metric
- `disk|totalLatency_average`, `disk|totalReadLatency_average`, `disk|totalWriteLatency_average`, `disk|commandsAveraged_average` (Disk_TotalLatency_ms, Disk_ReadLatency_ms, Disk_WriteLatency_ms, Disk_IOPS)
- `virtualDisk|totalLatency_average`, `virtualDisk|totalReadLatency_average`, `virtualDisk|totalWriteLatency_average`, `virtualDisk|commandsAveraged_average`, `virtualDisk|numberReadAveraged_average`, `virtualDisk|numberWriteAveraged_average` (VD_TotalLatency_ms, VD_ReadLatency_ms, VD_WriteLatency_ms, VD_TotalIOPS, VD_ReadIOPS, VD_WriteIOPS)
- `net|droppedPct` (Net_DroppedPct)

## SCSI 컨트롤러별 상세 CSV (`_VirtualDiskDetail.csv`)

Aria Ops UI에서 VM의 "Virtual Disk" 메트릭 트리를 보면 아래처럼 **"Aggregate of all Instances"**(전체 집계)와
**scsi0:0, scsi0:1 등 개별 SCSI 컨트롤러:유닛**이 함께 표시됩니다. 이 스크립트는 각 VM에 실제로 존재하는
SCSI 인스턴스를 자동으로 탐색한 뒤, 인스턴스별로 아래 지표를 별도 CSV에 기록합니다.

| 컬럼 | 의미 | 단위 |
|---|---|---|
| VMName | VM 이름 | - |
| ResourceId | Aria Ops 리소스 ID | - |
| DiskInstance | SCSI 컨트롤러:유닛 (예: scsi0:0) | - |
| ReadThroughput_KBps_Avg / _Peak | 읽기 처리량 평균/최고 | KBps |
| WriteThroughput_KBps_Avg / _Peak | 쓰기 처리량 평균/최고 | KBps |

> 레이턴시/IOPS 계열은 이 환경에서 VM 집계 레벨에서도 수집되지 않는 것으로 확인되어(아래
> "제거된 컬럼" 참고) 인스턴스 레벨에서도 제외했습니다. 처리량(읽기/쓰기 KBps)만 유지합니다.

### 동작 방식
1. 각 VM에 대해 `GET /resources/{id}/stats/latest` 를 한 번씩 호출해서, 현재 수집 중인 모든 statKey 중
   `virtualDisk:<instance>|<metric>` 형태(예: `virtualDisk:scsi0:0|totalLatency_average`)를 찾아
   인스턴스명(`scsi0:0` 등)을 추출합니다. (VM 수만큼 가벼운 GET 호출이 추가되므로, VM이 매우 많은
   환경에서는 이 탐색 단계에 시간이 다소 걸릴 수 있습니다.)
2. 발견된 모든 인스턴스명을 모아 `virtualDisk:<instance>|<metric>` 형태의 statKey 목록을 만들고,
   기존 방식과 동일하게 `resources/stats/query`를 AVG/MAX로 호출합니다.
3. VM에 해당 인스턴스가 없으면(예: VM A에는 scsi0:0만 있는데 VM B의 scsi0:1을 조회) 그냥 빈 값으로
   남고 별도 오류는 발생하지 않습니다.

## 왜 일부 메트릭이 비어 있었을까요? (참고 — 이미 제거 조치됨)

2026-07-15 실제 수집 결과, 위 "제거된 컬럼" 목록의 statKey들은 172개 VM 전체에서 0건이었습니다.
아래는 그 원인으로 추정되는 사항이며, 참고용으로 남겨둡니다.

- **`disk|` 그룹 vs `virtualDisk|` 그룹**: 환경/정책 설정에 따라 둘 중 하나만 실제로 수집되는 경우가
  흔합니다. 이 환경에서는 두 그룹 모두 레이턴시/IOPS 계열은 수집되지 않았고, 처리량(KBps)만
  일부(`disk|usage_average`) 또는 대부분(`virtualDisk|read_average`, `write_average`) 수집되었습니다.
- **정책상 기본 비활성 메트릭**: VMware 공식 문서 기준으로 `mem|vmmemctl_average`(벌룬)는
  vROps의 **Disabled Metrics(기본 비활성 메트릭)** 목록에 포함되어 있습니다. 필요하다면
  Aria Ops의 **Policy → Metrics and Properties** 에서 활성화한 뒤 스크립트에 다시 추가하세요.
- **vCenter Statistics Level**: 디스크/네트워크의 상세 카운터(레이턴시, IOPS, 패킷 드롭률 등)는
  vCenter의 **Statistics Level**이 1(기본값)일 때는 수집되지 않고, Level 2 이상이어야 수집되는
  경우가 많습니다. vSphere Client → vCenter → Configure → General → Statistics 에서 레벨을
  확인해보세요. (레벨을 올리면 vCenter DB 용량/부하가 늘어나므로 신중히 적용하세요.)

## 동작 개요

1. TLS 1.2 강제 설정 + 자체서명 인증서 허용 (Windows PowerShell 5.1 호환)
2. `/suite-api/api/auth/token/acquire` 로 인증 토큰 획득
3. `/suite-api/api/resources?resourceKind=VirtualMachine&adapterKind=VMWARE` 로 전체 VM 목록 페이징 조회
4. 각 VM에 대해 `/resources/{id}/stats/latest` 로 SCSI 컨트롤러(Virtual Disk 인스턴스) 탐색
5. VM을 `BatchSize` 단위로 나눠 `/suite-api/api/resources/stats/query` 를
   AVG, MAX(, 인스턴스별 AVG/MAX), SUM 순으로 호출하여 statKey별 값 수집
6. VM별 집계 결과와 SCSI 인스턴스별 상세 결과를 각각 CSV로 Export (UTF8 BOM)

## 사전 요구사항

- Aria Operations 계정에 대상 vCenter/VM에 대한 조회 권한 필요
- Aria Operations 서버에서 REST API(`/suite-api`)가 활성화되어 있어야 함
- 방화벽에서 스크립트 실행 호스트 → Aria Ops 서버 443 포트 통신 허용 필요

## 참고 / 커스터마이징

- 현재 스크립트는 이 환경에서 **실제로 수집이 확인된 statKey만** 포함하고 있습니다 (CPU Ready,
  메모리 스왑, Disk/Virtual Disk 처리량, SCSI 컨트롤러별 처리량, 네트워크 드롭 건수, Guest OS
  파일시스템 사용률). 벌룬/디스크 레이턴시·IOPS/패킷 드롭률 등은 이 환경에서 비어 있어 제거했습니다.
- 다른 환경으로 옮기거나, Policy 활성화·Statistics Level 상향 후 다시 수집하고 싶은 지표가 있다면
  AVG/MAX 롤업 대상은 `$StatKeys_AvgMax` + `$StatColumnMap`에, SUM(누적 총합) 롤업이 필요한
  summation 계열은 `$StatKeys_Sum` + `$StatColumnMap_Sum`에 추가하면 됩니다. SCSI 인스턴스별
  상세 지표를 늘리려면 `$VirtualDiskInstanceMetrics`에 `<metric key> = <컬럼명>` 형태로
  추가하세요. 참고할 만한 statKey 예시:
  - `mem|vmmemctl_average` (벌룬, Policy에서 활성화 필요)
  - `disk|totalLatency_average`, `virtualDisk|totalLatency_average` 등 레이턴시/IOPS 계열
    (Statistics Level 상향 필요할 수 있음)
  - `net|droppedPct` (패킷 드롭률 %)
  - `cpu|costopPct` (Co-stop %, multi-vCPU VM의 CPU 스케줄링 지연)
  - `mem|swapinRate_average`, `mem|swapoutRate_average` (스왑 In/Out 속도, KBps)
  - `guestfilesystem|freespace_total` (Guest OS 전체 파일시스템 여유 공간, GB)
- 특정 클러스터/vCenter만 대상으로 하고 싶다면 리소스 목록 조회 시
  `resourceKind=VirtualMachine` 뒤에 `parentId=<ClusterResourceId>` 등의
  쿼리 파라미터를 추가하거나, 조회 후 이름/속성으로 필터링하면 됩니다.
- 인증서 검증을 실제로 수행하려면 `TrustAllCertsPolicy` 관련 블록을 제거하세요.
  (사내 CA로 발급된 인증서인 경우 보안상 권장)
