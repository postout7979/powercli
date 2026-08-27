### 스크립트 수행 예제 및 결과

```
PS C:\powercli\vcf upgrade> .\vcf9-precheck-toolkit.ps1                                                                 
===============================================================================                                                             
VCF 9 Pre-check Integrated Tool                                                                     
===============================================================================                                          
 [1] Inventory collection + HCL compatibility check (run automatically in sequence)
 [2] Run inventory collection only (vCenter connection, CSV output only)
 [3] Specify an existing inventory folder -> run HCL compatibility check only
 [4] Specify an existing inventory folder -> generate a performance report only
===============================================================================
> Enter a menu number (1/2/3/4): 1

[MENU 1] Starting inventory collection...
===============================================================================
          vSphere Inventory Report - Initial Environment Setup & Module Check
===============================================================================
[OK] VMware.PowerCLI module is already installed.
[INIT] Configuring PowerCLI connection security settings...

===============================================================================
                  vSphere Inventory Report - vCenter Connection
===============================================================================
> Enter the vCenter IP or FQDN: vcsa.vmware.local

> Enter the vCenter login account (e.g. administrator@vsphere.local) and password...

cmdlet Get-Credential(명령 파이프라인 위치 1)
다음 매개 변수에 대한 값을 제공하십시오.
Credential

Connecting to vCenter (epavcsa.epa.com)...
Fetching Base Infrastructure Data (This may take a moment)...
Building Memory Lookup Tables for Fast Processing...
Extracting vCenter Server Details...
[1/12] Extracting Cluster info...
[INFO] License key bulk query complete (10 entries)
[2/12] Extracting Host Performance & Hardware Info...
[3/12] Extracting VM Status & Disks (with VMTools Versions)...
[4/12] Building Advanced Storage/LUN Mapping Lookup Tables...
Fetching Bulk Datastore IOPS Performance Counters (Past 2 Hours)...
Extracting All Datastores with Comprehensive Storage & IOPS Details...
[5/12] Extracting Virtual Switches & VDS Versions...
[6/12] Building Advanced ESXCLI Cache for Driver/Firmware Versions (Takes time)...
[7/12] Extracting Physical NICs...
[8/12] Extracting Physical HBAs (FibreChannel)...
[9/12] Extracting Physical RAID Controllers...
[10/12] Collecting ESX Memory Page Info (NVMe Memory Tiering assessment)...
[11/12] Disconnecting from vCenter...
===============================================================================
[12/12] SUCCESS: All inventory reports have been saved.
Output Folder: C:\powercli\vcf upgrade\vSphere_Inventory_20260827_1517

===============================================================================                                                                                                                                                                 [MENU 1] Running the HCL compatibility check against the collected inventory (C:\powercli\vcf upgrade\vSphere_Inventory_20260827_1517)...                                                                                                       ===============================================================================                                           VCF9 Standalone Hardware Compatibility Checker
===============================================================================
[INFO] Loading inventory data from: C:\powercli\vcf upgrade\vSphere_Inventory_20260827_1517
       Hosts: 6  |  NICs: 60  |  HBAs: 0  |  RAID Controllers: 24
[INFO] Results will be saved to: C:\powercli\vcf upgrade\compatibility_20260827_1518
[INFO] HCL folder auto-detected: C:\powercli\vcf upgrade\hcl
[1/3] Loading HCL data from: C:\powercli\vcf upgrade\hcl
[INFO] CPU All Models: CPU_All_Models_Single_Sheet.csv (608 models, applied to both 9.0/9.1)
[INFO] Recognized HCL files:
       - IO Devices_vcf_9_0.csv -> IODevice / ESXi 9.0
       - IO Devices_vcf_9_1.csv -> IODevice / ESXi 9.1
       - Systems _ Servers_vcf_9_0.csv -> Server / ESXi 9.0
       - Systems _ Servers_vcf_9_1.csv -> Server / ESXi 9.1
       - vSAN I_O Controller_vcf_9_0.csv -> vSAN / ESXi 9.0
       - vSAN I_O Controller_vcf_9_1.csv -> vSAN / ESXi 9.1
[2/3] Building HCL index...
       Index build complete. (CPU models: 608, index keys: 603)
[3/3] Running compatibility checks...
       Server  : 6 rows -> 1 unique models
       CPU     : 6 rows -> 1 unique models
       NIC     : 60 rows -> 4 unique models (USB excluded)
       Storage : 24 rows -> 3 unique models (USB excluded)
       Pre-batch matching complete.

===============================================================================
 VCF9 Hardware Compatibility Check Summary (ESXi 9.0 / 9.1)
===============================================================================
 Total checked: 96  |  ESXi 9.0 MISMATCH: 0  |  ESXi 9.1 MISMATCH: 0  |  Threshold: 50%
 All items match the HCL for both ESXi 9.0 and 9.1.
===============================================================================
 NOTE: CPU matching is based on model series (generation), not exact SKU.
 NOTE: All other parts use weighted token similarity scoring (best-effort).
 CSV files: Compatibility_Server / CPU / NIC / StorageController.csv
 HTML summary: Compatibility_Report.html
 Cluster detail HTML (1 files): Compatibility_Cluster_epa-cl01.html
 Source inventory: C:\powercli\vcf upgrade\vSphere_Inventory_20260827_1517
 Output folder:    C:\powercli\vcf upgrade\compatibility_20260827_1518
===============================================================================

[MENU 1] Completed.
  Inventory folder             : C:\powercli\vcf upgrade\vSphere_Inventory_20260827_1517
  Compatibility results folder : C:\powercli\vcf upgrade\compatibility_20260827_1518
  Zip archive                  : C:\powercli\vcf upgrade\VCF9_Precheck_20260827_1519.zip
PS C:\powercli\vcf upgrade>
```
### ZIP 파일 및 폴더 생성
<img width="702" height="186" alt="image" src="https://github.com/user-attachments/assets/3168ff0c-6e59-4be4-b0db-f658c6f69f65" />
### compatibility folder
<img width="670" height="185" alt="image" src="https://github.com/user-attachments/assets/311fd128-2d2d-4d03-8f48-9e8cbd5b9517" />
### Summary html 파일
<img width="1969" height="931" alt="image" src="https://github.com/user-attachments/assets/14d4a88d-6c07-4554-8136-4369c26be7e0" />
### 클러스터 html 파일
<img width="1980" height="1097" alt="image" src="https://github.com/user-attachments/assets/4cb27479-e131-4b0d-b28d-11a3e84ab396" />



