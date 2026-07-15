<#
.SYNOPSIS
    Get-VMSpecification.ps1 로 수집된 CSV 데이터를 읽어 클러스터별 HTML 리포트를 생성합니다.

.DESCRIPTION
    아래 4개 CSV가 위치한 폴더 경로를 입력받아 클러스터 단위로 개별 HTML 파일을 생성합니다.
    (외부 CDN 의존성 없음 - 폐쇄망에서도 그대로 사용 가능)
        - VM_Summary.csv
        - VM_NetworkAdapters.csv
        - VM_Disks.csv
        - VM_ISO.csv

    생성되는 파일:
        - index.html                              : 전체 요약 + 클러스터별 리포트 링크 모음
        - VM_Spec_Report_All.html                  : 전체 VM 통합 리포트 (클러스터 필터 포함)
        - VM_Spec_Report_<Cluster>.html            : 클러스터별 개별 리포트 (클러스터 수만큼 생성)

    각 리포트 구성:
        - 상단 KPI 카드 (VM 개수, 전원 On/Off, 총 vCPU/Memory, RDM 보유 VM, ISO 마운트 VM)
        - VM 이름 / Host / OS 검색창 + 전원상태 / RDM / ISO / Tools 상태 필터
        - VM 행 클릭 시 Network Adapter / Disk / ISO 상세 정보 펼침(Accordion)

.PARAMETER DataFolder
    VM_Summary.csv 등 4개 CSV가 위치한 폴더 경로 (미지정 시 프롬프트로 입력받음)

.PARAMETER OutputFolder
    HTML 파일들을 생성할 폴더 (미지정 시 DataFolder 하위에 HTML_Report 폴더를 생성)

.NOTES
    Windows PowerShell 5.1 호환
#>

param(
    [string]$DataFolder,
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " VM Specification HTML 리포트 생성 스크립트 (클러스터별)" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

#region 입력 폴더 확인
if ([string]::IsNullOrWhiteSpace($DataFolder)) {
    $DataFolder = Read-Host "CSV 파일이 위치한 폴더 경로를 입력하세요 (예: C:\powercli\posco\VM_Spec_Report_20260715_101500)"
}

if (-not (Test-Path -Path $DataFolder -PathType Container)) {
    Write-Host "[오류] 폴더를 찾을 수 없습니다: $DataFolder" -ForegroundColor Red
    exit 1
}

$summaryPath = Join-Path $DataFolder "VM_Summary.csv"
$networkPath = Join-Path $DataFolder "VM_NetworkAdapters.csv"
$diskPath    = Join-Path $DataFolder "VM_Disks.csv"
$isoPath     = Join-Path $DataFolder "VM_ISO.csv"

if (-not (Test-Path $summaryPath)) {
    Write-Host "[오류] VM_Summary.csv 파일이 없습니다: $summaryPath" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $OutputFolder = Join-Path $DataFolder "HTML_Report"
}
New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
#endregion

#region CSV 로드
Write-Host "`nCSV 파일을 읽는 중..." -ForegroundColor Yellow

$summaryData = Import-Csv -Path $summaryPath -Encoding UTF8

$networkData = @()
if (Test-Path $networkPath) { $networkData = Import-Csv -Path $networkPath -Encoding UTF8 }
else { Write-Host "[알림] VM_NetworkAdapters.csv 없음 - 네트워크 상세 정보는 생략됩니다." -ForegroundColor Yellow }

$diskData = @()
if (Test-Path $diskPath) { $diskData = Import-Csv -Path $diskPath -Encoding UTF8 }
else { Write-Host "[알림] VM_Disks.csv 없음 - 디스크 상세 정보는 생략됩니다." -ForegroundColor Yellow }

$isoData = @()
if (Test-Path $isoPath) { $isoData = Import-Csv -Path $isoPath -Encoding UTF8 }
else { Write-Host "[알림] VM_ISO.csv 없음 - ISO 상세 정보는 생략됩니다." -ForegroundColor Yellow }

Write-Host "VM_Summary : $($summaryData.Count) 건" -ForegroundColor Green
Write-Host "Network    : $($networkData.Count) 건" -ForegroundColor Green
Write-Host "Disk       : $($diskData.Count) 건" -ForegroundColor Green
Write-Host "ISO        : $($isoData.Count) 건" -ForegroundColor Green
#endregion

#region 헬퍼 함수
function ConvertTo-Bool {
    param([string]$Value)
    return ($Value -eq 'True' -or $Value -eq '1')
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $t = $Text
    $t = $t -replace '&', '&amp;'
    $t = $t -replace '<', '&lt;'
    $t = $t -replace '>', '&gt;'
    $t = $t -replace '"', '&quot;'
    $t = $t -replace "'", '&#39;'
    return $t
}

function Get-Badge {
    param(
        [string]$Text,
        [string]$Class
    )
    return "<span class='badge $Class'>$(HtmlEncode $Text)</span>"
}

function Get-SafeFileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "Unassigned" }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $pattern = "[{0}]" -f [System.Text.RegularExpressions.Regex]::Escape($invalid)
    $safe = [System.Text.RegularExpressions.Regex]::Replace($Name, $pattern, '_')
    $safe = $safe -replace '\s+', '_'
    return $safe
}
#endregion

#region 네트워크/디스크/ISO 데이터를 VMName 기준으로 그룹핑 (전체 데이터 대상, 1회만 수행)
Write-Host "`n데이터를 VM 기준으로 매핑하는 중..." -ForegroundColor Yellow

$networkByVM = @{}
foreach ($n in $networkData) {
    if (-not $networkByVM.ContainsKey($n.VMName)) { $networkByVM[$n.VMName] = New-Object System.Collections.Generic.List[Object] }
    $networkByVM[$n.VMName].Add($n)
}

$diskByVM = @{}
foreach ($d in $diskData) {
    if (-not $diskByVM.ContainsKey($d.VMName)) { $diskByVM[$d.VMName] = New-Object System.Collections.Generic.List[Object] }
    $diskByVM[$d.VMName].Add($d)
}

$isoByVM = @{}
foreach ($i in $isoData) {
    if (-not $isoByVM.ContainsKey($i.VMName)) { $isoByVM[$i.VMName] = New-Object System.Collections.Generic.List[Object] }
    $isoByVM[$i.VMName].Add($i)
}
#endregion

#region VM 행(Row) HTML 생성 함수 - 전달받은 VM 목록만 대상으로 렌더링
function Get-VMRowsHtml {
    param([Array]$VMs)

    $rowsSb = New-Object System.Text.StringBuilder
    $rowIndex = 0

    foreach ($vm in ($VMs | Sort-Object VMName)) {

        $rowIndex++
        $vmKey = $vm.VMName

        $hasRDM = ConvertTo-Bool $vm.HasRDM
        $hasISO = ConvertTo-Bool $vm.HasISOMounted
        $toolsStale = $vm.VMToolsStatus -in @('toolsOld', 'toolsNotInstalled', 'toolsNotRunning')

        $powerBadgeClass = if ($vm.PowerState -eq 'poweredOn') { 'badge-teal' } else { 'badge-gray' }
        $rdmBadgeClass   = if ($hasRDM) { 'badge-amber' } else { 'badge-gray-outline' }
        $isoBadgeClass   = if ($hasISO) { 'badge-amber' } else { 'badge-gray-outline' }
        $toolsBadgeClass = if ($toolsStale) { 'badge-amber' } else { 'badge-teal-outline' }
        $vnumaBadgeClass = if ($vm.vNUMA_Status -like 'Likely Enabled*') { 'badge-navy' } elseif ($vm.vNUMA_Status -like 'Manual*') { 'badge-amber' } else { 'badge-gray-outline' }

        $topology = "$($vm.NumCPU) vCPU ($($vm.NumSockets)S x $($vm.NumCoresPerSocket)C)"

        # ---- 상세 영역: Network Adapters ----
        $netHtml = "<p class='empty-note'>네트워크 어댑터 정보 없음</p>"
        if ($networkByVM.ContainsKey($vmKey)) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("<table class='detail-table'><thead><tr><th>어댑터</th><th>타입</th><th>포트그룹</th><th>MAC</th><th>연결상태</th></tr></thead><tbody>")
            foreach ($n in $networkByVM[$vmKey]) {
                $connBadge = if (ConvertTo-Bool $n.Connected) { Get-Badge "Connected" "badge-teal-outline" } else { Get-Badge "Disconnected" "badge-gray-outline" }
                [void]$sb.Append("<tr><td>$(HtmlEncode $n.AdapterLabel)</td><td>$(HtmlEncode $n.AdapterType)</td><td>$(HtmlEncode $n.PortGroup)</td><td class='mono'>$(HtmlEncode $n.MacAddress)</td><td>$connBadge</td></tr>")
            }
            [void]$sb.Append("</tbody></table>")
            $netHtml = $sb.ToString()
        }

        # ---- 상세 영역: Disks ----
        $diskHtml = "<p class='empty-note'>디스크 정보 없음</p>"
        if ($diskByVM.ContainsKey($vmKey)) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("<table class='detail-table'><thead><tr><th>디스크</th><th>크기(GB)</th><th>타입</th><th>데이터스토어</th><th>컨트롤러</th><th>Bus:Unit</th><th>RDM</th></tr></thead><tbody>")
            foreach ($d in $diskByVM[$vmKey]) {
                $isRdmDisk = ConvertTo-Bool $d.IsRDM
                $rdmCell = if ($isRdmDisk) { Get-Badge "$($d.RDM_CompatMode)" "badge-amber" } else { "-" }
                $diskTypeBadgeClass = if ($d.DiskType -like 'RDM*') { 'badge-amber' } elseif ($d.DiskType -eq 'Thin') { 'badge-teal-outline' } else { 'badge-gray-outline' }
                [void]$sb.Append("<tr><td>$(HtmlEncode $d.DiskLabel)</td><td>$(HtmlEncode $d.CapacityGB)</td><td>$(Get-Badge $d.DiskType $diskTypeBadgeClass)</td><td>$(HtmlEncode $d.Datastore)</td><td>$(HtmlEncode $d.ControllerLabel) ($(HtmlEncode $d.ControllerType))</td><td class='mono'>$(HtmlEncode $d.ControllerBusNum):$(HtmlEncode $d.UnitNumber)</td><td>$rdmCell</td></tr>")
            }
            [void]$sb.Append("</tbody></table>")
            $diskHtml = $sb.ToString()
        }

        # ---- 상세 영역: ISO ----
        $isoHtml = "<p class='empty-note'>마운트된 ISO 없음</p>"
        if ($isoByVM.ContainsKey($vmKey)) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("<table class='detail-table'><thead><tr><th>드라이브</th><th>ISO 경로</th><th>연결상태</th></tr></thead><tbody>")
            foreach ($i in $isoByVM[$vmKey]) {
                $connBadge = if (ConvertTo-Bool $i.Connected) { Get-Badge "Connected" "badge-amber" } else { Get-Badge "Disconnected" "badge-gray-outline" }
                [void]$sb.Append("<tr><td>$(HtmlEncode $i.CDDriveLabel)</td><td class='mono small'>$(HtmlEncode $i.ISOPath)</td><td>$connBadge</td></tr>")
            }
            [void]$sb.Append("</tbody></table>")
            $isoHtml = $sb.ToString()
        }

        $searchBlob = (HtmlEncode "$($vm.VMName) $($vm.ESXiHost) $($vm.Cluster) $($vm.GuestFullName)").ToLower()

        [void]$rowsSb.Append(@"
<tr class="vm-row" data-row="$rowIndex" data-search="$searchBlob" data-cluster="$(HtmlEncode $vm.Cluster)" data-power="$(HtmlEncode $vm.PowerState)" data-rdm="$hasRDM" data-iso="$hasISO" data-tools="$toolsStale" onclick="toggleDetail($rowIndex)">
    <td class="chevron-cell"><span class="chevron" id="chevron-$rowIndex">&#9656;</span></td>
    <td class="vm-name">$(HtmlEncode $vm.VMName)</td>
    <td>$(Get-Badge $vm.PowerState $powerBadgeClass)</td>
    <td>$(HtmlEncode $vm.GuestFullName)</td>
    <td>$(HtmlEncode $vm.ESXiHost)</td>
    <td>$(HtmlEncode $vm.Cluster)</td>
    <td class="mono">$topology</td>
    <td class="mono">$($vm.MemoryGB) GB</td>
    <td>$(Get-Badge $vm.vNUMA_Status $vnumaBadgeClass)</td>
    <td>$(Get-Badge $vm.VMToolsStatus $toolsBadgeClass)</td>
    <td>$(Get-Badge $(if($hasRDM){"RDM $($vm.RDMCount)"}else{"None"}) $rdmBadgeClass)</td>
    <td>$(Get-Badge $(if($hasISO){"ISO $($vm.ISOMountedCount)"}else{"None"}) $isoBadgeClass)</td>
</tr>
<tr class="detail-row" id="detail-$rowIndex" data-row="$rowIndex" style="display:none;">
    <td colspan="12">
        <div class="detail-grid">
            <div class="detail-section">
                <h4>Network Adapters ($($vm.NetworkAdapterCount))</h4>
                $netHtml
            </div>
            <div class="detail-section">
                <h4>Virtual Disks ($($vm.DiskCount))</h4>
                $diskHtml
            </div>
            <div class="detail-section">
                <h4>ISO Mount</h4>
                $isoHtml
            </div>
            <div class="detail-section detail-meta">
                <h4>추가 정보</h4>
                <table class="meta-table">
                    <tr><td>HW Version</td><td>$(HtmlEncode $vm.HWVersion)</td></tr>
                    <tr><td>CPU Hot Add</td><td>$(HtmlEncode $vm.CpuHotAddEnabled)</td></tr>
                    <tr><td>CPU Hot Remove</td><td>$(HtmlEncode $vm.CpuHotRemoveEnabled)</td></tr>
                    <tr><td>Memory Hot Add</td><td>$(HtmlEncode $vm.MemHotAddEnabled)</td></tr>
                    <tr><td>VM Tools Version</td><td>$(HtmlEncode $vm.VMToolsVersion)</td></tr>
                </table>
            </div>
        </div>
    </td>
</tr>
"@)
    }

    return $rowsSb.ToString()
}
#endregion

#region 리포트(HTML 문서 전체) 생성 함수
function Get-ReportHtml {
    param(
        [Array]$VMs,
        [string]$Title,
        [string]$SourceFolder,
        [bool]$ShowClusterFilter
    )

    $totalVMs      = $VMs.Count
    $poweredOn     = ($VMs | Where-Object { $_.PowerState -eq 'poweredOn' }).Count
    $poweredOff    = ($VMs | Where-Object { $_.PowerState -eq 'poweredOff' }).Count
    $totalVCPU     = ($VMs | Measure-Object -Property NumCPU -Sum).Sum
    $totalMemGB    = [Math]::Round((($VMs | Measure-Object -Property MemoryGB -Sum).Sum), 0)
    $rdmVMs        = ($VMs | Where-Object { ConvertTo-Bool $_.HasRDM }).Count
    $isoVMs        = ($VMs | Where-Object { ConvertTo-Bool $_.HasISOMounted }).Count
    $clusterList   = $VMs | Select-Object -ExpandProperty Cluster -Unique | Where-Object { $_ } | Sort-Object

    $rowsHtml = Get-VMRowsHtml -VMs $VMs

    $clusterFilterHtml = ""
    if ($ShowClusterFilter) {
        $clusterOptionsHtml = ($clusterList | ForEach-Object { "<option value='$(HtmlEncode $_)'>$(HtmlEncode $_)</option>" }) -join "`n"
        $clusterFilterHtml = @"
        <label>Cluster</label>
        <select id="clusterFilter" onchange="applyFilters()">
            <option value="">전체</option>
            $clusterOptionsHtml
        </select>
"@
    }

    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @"
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>VM Specification Report - $(HtmlEncode $Title)</title>
<style>
    :root {
        --navy: #0b2545;
        --navy-light: #13355e;
        --teal: #0f9b8e;
        --teal-light: #e4f7f5;
        --amber: #d98c1f;
        --amber-light: #fdf1de;
        --gray: #6b7280;
        --gray-light: #f1f3f5;
        --border: #e2e5e9;
        --bg: #f7f9fb;
        --text: #1f2937;
    }
    * { box-sizing: border-box; }
    body {
        margin: 0;
        font-family: 'Segoe UI', 'Malgun Gothic', -apple-system, sans-serif;
        background: var(--bg);
        color: var(--text);
    }
    header {
        background: linear-gradient(135deg, var(--navy) 0%, var(--navy-light) 100%);
        color: #fff;
        padding: 28px 36px;
    }
    header .back-link { display: inline-block; margin-bottom: 10px; color: #9fb6d1; font-size: 12px; text-decoration: none; }
    header .back-link:hover { color: #fff; }
    header h1 { margin: 0 0 6px 0; font-size: 22px; font-weight: 600; }
    header p { margin: 0; font-size: 13px; color: #c7d3e0; }

    .container { padding: 24px 36px 60px 36px; }

    .kpi-grid {
        display: grid;
        grid-template-columns: repeat(7, 1fr);
        gap: 14px;
        margin: -34px 0 24px 0;
    }
    .kpi-card {
        background: #fff;
        border-radius: 10px;
        padding: 16px 18px;
        box-shadow: 0 2px 10px rgba(11,37,69,0.08);
        border-top: 3px solid var(--teal);
    }
    .kpi-card.amber { border-top-color: var(--amber); }
    .kpi-card .value { font-size: 24px; font-weight: 700; color: var(--navy); }
    .kpi-card .label { font-size: 12px; color: var(--gray); margin-top: 4px; }

    .toolbar {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        align-items: center;
        margin-bottom: 16px;
        background: #fff;
        padding: 14px 16px;
        border-radius: 10px;
        box-shadow: 0 2px 10px rgba(11,37,69,0.06);
    }
    .toolbar input[type=text], .toolbar select {
        padding: 8px 12px;
        border: 1px solid var(--border);
        border-radius: 6px;
        font-size: 13px;
        background: #fff;
    }
    .toolbar input[type=text] { flex: 1; min-width: 220px; }
    .toolbar label { font-size: 12px; color: var(--gray); margin-right: 4px; }
    .result-count { font-size: 12px; color: var(--gray); margin-left: auto; }

    table.main-table {
        width: 100%;
        border-collapse: collapse;
        background: #fff;
        border-radius: 10px;
        overflow: hidden;
        box-shadow: 0 2px 10px rgba(11,37,69,0.06);
    }
    table.main-table thead th {
        background: var(--navy);
        color: #fff;
        text-align: left;
        padding: 10px 12px;
        font-size: 12px;
        font-weight: 600;
        position: sticky;
        top: 0;
    }
    table.main-table tbody td {
        padding: 10px 12px;
        font-size: 13px;
        border-bottom: 1px solid var(--border);
    }
    .vm-row { cursor: pointer; }
    .vm-row:hover { background: var(--teal-light); }
    .vm-name { font-weight: 600; color: var(--navy); }
    .chevron-cell { width: 20px; text-align: center; }
    .chevron { display: inline-block; transition: transform 0.15s ease; color: var(--gray); }
    .chevron.open { transform: rotate(90deg); color: var(--teal); }

    .detail-row td { background: var(--gray-light); padding: 18px 24px; }
    .detail-grid {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 18px;
    }
    .detail-section h4 {
        margin: 0 0 8px 0;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.03em;
        color: var(--navy);
        border-bottom: 2px solid var(--teal);
        padding-bottom: 6px;
    }
    table.detail-table, table.meta-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: #fff;
        border-radius: 6px;
        overflow: hidden;
    }
    table.detail-table thead th {
        background: #eef1f4;
        color: var(--navy);
        padding: 6px 8px;
        text-align: left;
        font-weight: 600;
    }
    table.detail-table tbody td, table.meta-table td {
        padding: 6px 8px;
        border-bottom: 1px solid var(--border);
    }
    table.meta-table td:first-child { color: var(--gray); width: 55%; }
    .mono { font-family: 'Consolas', monospace; font-size: 12px; }
    .mono.small { font-size: 11px; word-break: break-all; }
    .empty-note { font-size: 12px; color: var(--gray); font-style: italic; }

    .badge {
        display: inline-block;
        padding: 3px 9px;
        border-radius: 12px;
        font-size: 11px;
        font-weight: 600;
        white-space: nowrap;
    }
    .badge-teal { background: var(--teal); color: #fff; }
    .badge-teal-outline { background: var(--teal-light); color: var(--teal); border: 1px solid var(--teal); }
    .badge-amber { background: var(--amber); color: #fff; }
    .badge-amber-outline { background: var(--amber-light); color: var(--amber); border: 1px solid var(--amber); }
    .badge-navy { background: var(--navy); color: #fff; }
    .badge-gray { background: var(--gray); color: #fff; }
    .badge-gray-outline { background: #fff; color: var(--gray); border: 1px solid var(--border); }

    footer { text-align: center; padding: 20px; font-size: 11px; color: var(--gray); }
</style>
</head>
<body>

<header>
    <a class="back-link" href="index.html">&larr; 전체 클러스터 목록으로</a>
    <h1>VM Specification Report - $(HtmlEncode $Title)</h1>
    <p>생성 시각: $generatedAt &nbsp;|&nbsp; 데이터 소스: $(HtmlEncode $SourceFolder) &nbsp;|&nbsp; 총 VM: $totalVMs 대</p>
</header>

<div class="container">

    <div class="kpi-grid">
        <div class="kpi-card"><div class="value">$totalVMs</div><div class="label">전체 VM</div></div>
        <div class="kpi-card"><div class="value">$poweredOn</div><div class="label">Powered On</div></div>
        <div class="kpi-card"><div class="value">$poweredOff</div><div class="label">Powered Off</div></div>
        <div class="kpi-card"><div class="value">$totalVCPU</div><div class="label">총 vCPU</div></div>
        <div class="kpi-card"><div class="value">$totalMemGB GB</div><div class="label">총 Memory</div></div>
        <div class="kpi-card amber"><div class="value">$rdmVMs</div><div class="label">RDM 보유 VM</div></div>
        <div class="kpi-card amber"><div class="value">$isoVMs</div><div class="label">ISO 마운트 VM</div></div>
    </div>

    <div class="toolbar">
        <input type="text" id="searchBox" placeholder="VM 이름 / Host / OS 검색..." onkeyup="applyFilters()">
        $clusterFilterHtml
        <label>전원 상태</label>
        <select id="powerFilter" onchange="applyFilters()">
            <option value="">전체</option>
            <option value="poweredOn">Powered On</option>
            <option value="poweredOff">Powered Off</option>
        </select>
        <label>RDM</label>
        <select id="rdmFilter" onchange="applyFilters()">
            <option value="">전체</option>
            <option value="True">RDM 있음</option>
            <option value="False">RDM 없음</option>
        </select>
        <label>ISO</label>
        <select id="isoFilter" onchange="applyFilters()">
            <option value="">전체</option>
            <option value="True">마운트됨</option>
            <option value="False">없음</option>
        </select>
        <label>Tools</label>
        <select id="toolsFilter" onchange="applyFilters()">
            <option value="">전체</option>
            <option value="True">업데이트 필요</option>
            <option value="False">정상</option>
        </select>
        <span class="result-count" id="resultCount"></span>
    </div>

    <table class="main-table">
        <thead>
            <tr>
                <th></th>
                <th>VM Name</th>
                <th>Power</th>
                <th>Guest OS</th>
                <th>ESXi Host</th>
                <th>Cluster</th>
                <th>Topology</th>
                <th>Memory</th>
                <th>vNUMA (추정)</th>
                <th>VM Tools</th>
                <th>RDM</th>
                <th>ISO</th>
            </tr>
        </thead>
        <tbody id="vmTableBody">
$rowsHtml
        </tbody>
    </table>

</div>

<footer>Get-VMSpecification.ps1 / Generate-VMSpecReport.ps1 로 생성됨 &nbsp;|&nbsp; vNUMA 상태는 VMware 기본 동작 규칙 기반 추정치이며 확정값이 아닙니다.</footer>

<script>
function toggleDetail(rowId) {
    var detailRow = document.getElementById('detail-' + rowId);
    var chevron = document.getElementById('chevron-' + rowId);
    if (detailRow.style.display === 'none') {
        detailRow.style.display = 'table-row';
        chevron.classList.add('open');
    } else {
        detailRow.style.display = 'none';
        chevron.classList.remove('open');
    }
}

function applyFilters() {
    var search = document.getElementById('searchBox').value.toLowerCase();
    var clusterEl = document.getElementById('clusterFilter');
    var cluster = clusterEl ? clusterEl.value : '';
    var power = document.getElementById('powerFilter').value;
    var rdm = document.getElementById('rdmFilter').value;
    var iso = document.getElementById('isoFilter').value;
    var tools = document.getElementById('toolsFilter').value;

    var rows = document.querySelectorAll('.vm-row');
    var visibleCount = 0;

    rows.forEach(function(row) {
        var rowId = row.getAttribute('data-row');
        var detailRow = document.getElementById('detail-' + rowId);
        var matches = true;

        if (search && row.getAttribute('data-search').indexOf(search) === -1) { matches = false; }
        if (cluster && row.getAttribute('data-cluster') !== cluster) { matches = false; }
        if (power && row.getAttribute('data-power') !== power) { matches = false; }
        if (rdm && row.getAttribute('data-rdm') !== rdm) { matches = false; }
        if (iso && row.getAttribute('data-iso') !== iso) { matches = false; }
        if (tools && row.getAttribute('data-tools') !== tools) { matches = false; }

        if (matches) {
            row.style.display = 'table-row';
            visibleCount++;
        } else {
            row.style.display = 'none';
            detailRow.style.display = 'none';
            document.getElementById('chevron-' + rowId).classList.remove('open');
        }
    });

    document.getElementById('resultCount').innerText = visibleCount + ' / ' + rows.length + ' VM 표시 중';
}

document.addEventListener('DOMContentLoaded', applyFilters);
</script>

</body>
</html>
"@

    return $html
}
#endregion

#region 클러스터별 + 전체 리포트 생성
Write-Host "`n리포트 HTML을 생성하는 중..." -ForegroundColor Yellow

$clusterNames = $summaryData | Select-Object -ExpandProperty Cluster -Unique | Sort-Object
$indexEntries = New-Object System.Collections.Generic.List[Object]

# ---- 전체 통합 리포트 ----
$allHtml = Get-ReportHtml -VMs $summaryData -Title "전체" -SourceFolder $DataFolder -ShowClusterFilter $true
$allFileName = "VM_Spec_Report_All.html"
$allHtml | Out-File -FilePath (Join-Path $OutputFolder $allFileName) -Encoding UTF8

$indexEntries.Add([PSCustomObject]@{
    Title    = "전체 (All Clusters)"
    FileName = $allFileName
    VMCount  = $summaryData.Count
    RDMCount = ($summaryData | Where-Object { ConvertTo-Bool $_.HasRDM }).Count
    ISOCount = ($summaryData | Where-Object { ConvertTo-Bool $_.HasISOMounted }).Count
    IsAll    = $true
})

# ---- 클러스터별 개별 리포트 ----
foreach ($clusterName in $clusterNames) {

    $clusterVMs = $summaryData | Where-Object { $_.Cluster -eq $clusterName }
    $displayName = if ([string]::IsNullOrWhiteSpace($clusterName)) { "(Unassigned)" } else { $clusterName }
    $safeName = Get-SafeFileName -Name $displayName
    $fileName = "VM_Spec_Report_$safeName.html"

    Write-Host "  - $displayName : $($clusterVMs.Count) 대 -> $fileName"

    $clusterHtml = Get-ReportHtml -VMs $clusterVMs -Title $displayName -SourceFolder $DataFolder -ShowClusterFilter $false
    $clusterHtml | Out-File -FilePath (Join-Path $OutputFolder $fileName) -Encoding UTF8

    $indexEntries.Add([PSCustomObject]@{
        Title    = $displayName
        FileName = $fileName
        VMCount  = $clusterVMs.Count
        RDMCount = ($clusterVMs | Where-Object { ConvertTo-Bool $_.HasRDM }).Count
        ISOCount = ($clusterVMs | Where-Object { ConvertTo-Bool $_.HasISOMounted }).Count
        IsAll    = $false
    })
}
#endregion

#region 인덱스 페이지 생성
$cardsSb = New-Object System.Text.StringBuilder
foreach ($entry in $indexEntries) {
    $cardClass = if ($entry.IsAll) { "index-card highlight" } else { "index-card" }
    [void]$cardsSb.Append(@"
<a class="$cardClass" href="$(HtmlEncode $entry.FileName)">
    <div class="index-card-title">$(HtmlEncode $entry.Title)</div>
    <div class="index-card-stats">
        <span>VM $($entry.VMCount)</span>
        <span class="dot">&middot;</span>
        <span>RDM $($entry.RDMCount)</span>
        <span class="dot">&middot;</span>
        <span>ISO $($entry.ISOCount)</span>
    </div>
</a>
"@)
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$totalVMsAll = $summaryData.Count

$indexHtml = @"
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>VM Specification Report - Index</title>
<style>
    * { box-sizing: border-box; }
    body {
        margin: 0;
        font-family: 'Segoe UI', 'Malgun Gothic', -apple-system, sans-serif;
        background: #f7f9fb;
        color: #1f2937;
    }
    header {
        background: linear-gradient(135deg, #0b2545 0%, #13355e 100%);
        color: #fff;
        padding: 32px 36px;
    }
    header h1 { margin: 0 0 6px 0; font-size: 22px; }
    header p { margin: 0; font-size: 13px; color: #c7d3e0; }
    .container { padding: 28px 36px 60px 36px; }
    .index-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
        gap: 16px;
    }
    .index-card {
        display: block;
        background: #fff;
        border-radius: 10px;
        padding: 18px 20px;
        text-decoration: none;
        color: #1f2937;
        box-shadow: 0 2px 10px rgba(11,37,69,0.08);
        border-top: 3px solid #0f9b8e;
        transition: transform 0.1s ease;
    }
    .index-card:hover { transform: translateY(-2px); }
    .index-card.highlight { border-top-color: #d98c1f; }
    .index-card-title { font-size: 15px; font-weight: 700; color: #0b2545; margin-bottom: 8px; }
    .index-card-stats { font-size: 12px; color: #6b7280; }
    .index-card-stats .dot { margin: 0 6px; }
    footer { text-align: center; padding: 20px; font-size: 11px; color: #6b7280; }
</style>
</head>
<body>

<header>
    <h1>VM Specification Report</h1>
    <p>생성 시각: $generatedAt &nbsp;|&nbsp; 데이터 소스: $(HtmlEncode $DataFolder) &nbsp;|&nbsp; 총 VM: $totalVMsAll 대 &nbsp;|&nbsp; 클러스터: $($clusterNames.Count) 개</p>
</header>

<div class="container">
    <div class="index-grid">
$($cardsSb.ToString())
    </div>
</div>

<footer>Get-VMSpecification.ps1 / Generate-VMSpecReport.ps1 로 생성됨</footer>

</body>
</html>
"@

$indexHtml | Out-File -FilePath (Join-Path $OutputFolder "index.html") -Encoding UTF8
#endregion

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " HTML 리포트 생성 완료!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " - 출력 폴더   : $OutputFolder"
Write-Host " - 인덱스 파일 : $(Join-Path $OutputFolder 'index.html')"
Write-Host " - 클러스터 수 : $($clusterNames.Count)"
Write-Host " - 총 VM 개수  : $totalVMsAll"
Write-Host "=======================================================" -ForegroundColor Green
