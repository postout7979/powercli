
## vcf9-nvme-tiering-analysis.ps1  -  NVMe Memory Tiering Benefit Analysis
<br>
vcf9-precheck-script-cs.ps1 이 생성한 인벤토리 폴더를 입력받아 NVMe 메모리 티어링 전환 시 호스트별 VM 밀도 증가 효과를 분석합니다.<br>
사용 예시:<br>
  .\vcf9-nvme-tiering-analysis.ps1 -InventoryPath "C:\inventory\vSphere_Inventory_20260707_1430"<br>

옵션:<br>
  -InventoryPath    : 인벤토리 폴더 경로 (필수)<br>
  -MaxCpuPct        : CPU 사용률 상한 (기본값: 80%)<br>
  -MaxActiveRatioPct: VM 총 할당 메모리 대비 Active 메모리 최대 비율 (기본값: 40%)<br>
  -PhysMemFactor    : 물리 메모리 / Active 메모리 최소 배율 (기본값: 2.0배)<br>

## NVMe_sizing screenshot
<img width="1924" height="1178" alt="image" src="https://github.com/user-attachments/assets/93309b3b-3347-4726-9633-b76a0b7d4fe8" />
