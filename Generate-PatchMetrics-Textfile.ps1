<#
.SYNOPSIS
    Generate Windows Update metrics for Windows Exporter textfile collector

.DESCRIPTION
    Creates .prom file with KB metrics for Windows Exporter to expose
    No Pushgateway needed - Prometheus scrapes directly from Windows Exporter

.PARAMETER TextfilePath
    Path to Windows Exporter textfile directory (default: C:\Program Files\windows_exporter\textfile_inputs)

.EXAMPLE
    .\Generate-PatchMetrics-Textfile.ps1

.EXAMPLE
    .\Generate-PatchMetrics-Textfile.ps1 -TextfilePath "C:\custom\path"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TextfilePath = "C:\Program Files\windows_exporter\textfile_inputs"
)

Write-Host "=== Windows Patch Metrics for Windows Exporter ===" -ForegroundColor Cyan
Write-Host "Textfile path: $TextfilePath"
Write-Host ""

# Ensure textfile directory exists
if (-not (Test-Path $TextfilePath)) {
    New-Item -Path $TextfilePath -ItemType Directory -Force | Out-Null
    Write-Host "Created textfile directory: $TextfilePath" -ForegroundColor Yellow
}

# Get installed KBs
function Get-InstalledKBs {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()
        $maxRecords = [Math]::Min(200, $historyCount)
        $history = $searcher.QueryHistory(0, $maxRecords)
        
        $kbList = @()
        $kbSeen = @{}
        
        foreach ($update in $history) {
            if ($update.Title -match 'KB(\d+)') {
                $kbId = "KB$($Matches[1])"
                if ($kbSeen.ContainsKey($kbId)) { continue }
                $kbSeen[$kbId] = $true
                
                if ($update.ResultCode -eq 2) {
                    $classification = if ($update.Title -match 'Security|Cumulative|Defender') { "security" } else { "non_security" }
                    $severity = "moderate"
                    if ($update.Title -match 'Critical') { $severity = "critical" }
                    elseif ($update.Title -match 'Important') { $severity = "important" }
                    
                    $kbList += [PSCustomObject]@{
                        KB = $kbId
                        Classification = $classification
                        Severity = $severity
                        InstallDate = $update.Date.ToString("yyyy-MM-dd")
                        Title = $update.Title -replace '"', "'"
                    }
                }
            }
        }
        return $kbList
    }
    catch {
        Write-Warning "Failed to get installed KBs: $_"
        return @()
    }
}

# Get pending KBs
function Get-PendingKBs {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searchResult = $searcher.Search("IsInstalled=0")
        
        $kbList = @()
        foreach ($update in $searchResult.Updates) {
            if ($update.Title -match 'KB(\d+)') {
                $kbId = "KB$($Matches[1])"
                $classification = if ($update.Title -match 'Security|Cumulative') { "security" } else { "non_security" }
                $severity = if ($update.MsrcSeverity) { $update.MsrcSeverity.ToLower() } else { "moderate" }
                
                $kbList += [PSCustomObject]@{
                    KB = $kbId
                    Classification = $classification
                    Severity = $severity
                    Title = $update.Title -replace '"', "'"
                }
            }
        }
        return $kbList
    }
    catch {
        Write-Warning "Failed to get pending KBs: $_"
        return @()
    }
}

# Get reboot status
function Get-RebootRequired {
    $rebootPending = 0
    try {
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) { $rebootPending = 1 }
        if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) { $rebootPending = 1 }
    }
    catch {}
    return $rebootPending
}

Write-Host "[1/3] Collecting installed KBs..." -ForegroundColor Yellow
$installedKBs = Get-InstalledKBs
Write-Host "  Found $($installedKBs.Count) installed KBs"

Write-Host "[2/3] Collecting pending KBs..." -ForegroundColor Yellow
$pendingKBs = Get-PendingKBs
Write-Host "  Found $($pendingKBs.Count) pending KBs"

Write-Host "[3/3] Generating Prometheus metrics..." -ForegroundColor Yellow

$rebootRequired = Get-RebootRequired

# Build Prometheus metrics in .prom format
$metrics = @()

# HELP and TYPE declarations
$metrics += "# HELP windows_patch_reboot_required Whether the system requires a reboot after updates"
$metrics += "# TYPE windows_patch_reboot_required gauge"
$metrics += "windows_patch_reboot_required $rebootRequired"
$metrics += ""

$metrics += "# HELP windows_patch_installed_info Installed Windows Update KB with metadata"
$metrics += "# TYPE windows_patch_installed_info gauge"
foreach ($kb in $installedKBs) {
    $title = $kb.Title.Substring(0, [Math]::Min(100, $kb.Title.Length))
    $metrics += "windows_patch_installed_info{kb_id=`"$($kb.KB)`",classification=`"$($kb.Classification)`",severity=`"$($kb.Severity)`",install_date=`"$($kb.InstallDate)`",title=`"$title`"} 1"
}
$metrics += ""

$metrics += "# HELP windows_patch_pending_info Pending Windows Update KB with metadata"
$metrics += "# TYPE windows_patch_pending_info gauge"
foreach ($kb in $pendingKBs) {
    $title = $kb.Title.Substring(0, [Math]::Min(100, $kb.Title.Length))
    $metrics += "windows_patch_pending_info{kb_id=`"$($kb.KB)`",classification=`"$($kb.Classification)`",severity=`"$($kb.Severity)`",title=`"$title`"} 1"
}
$metrics += ""

# Aggregate counts
$securityInstalled = @($installedKBs | Where-Object { $_.Classification -eq "security" }).Count
$criticalInstalled = @($installedKBs | Where-Object { $_.Severity -eq "critical" }).Count
$securityPending = @($pendingKBs | Where-Object { $_.Classification -eq "security" }).Count
$criticalPending = @($pendingKBs | Where-Object { $_.Severity -eq "critical" }).Count

$metrics += "# HELP windows_patch_installed_total Total installed Windows Updates by classification"
$metrics += "# TYPE windows_patch_installed_total gauge"
$metrics += "windows_patch_installed_total{classification=`"security`"} $securityInstalled"
$metrics += "windows_patch_installed_total{classification=`"non_security`"} $($installedKBs.Count - $securityInstalled)"
$metrics += ""

$metrics += "# HELP windows_patch_pending_total Total pending Windows Updates by classification"
$metrics += "# TYPE windows_patch_pending_total gauge"
$metrics += "windows_patch_pending_total{classification=`"security`"} $securityPending"
$metrics += "windows_patch_pending_total{classification=`"non_security`"} $($pendingKBs.Count - $securityPending)"
$metrics += ""

# Write to .prom file
$promFile = Join-Path $TextfilePath "windows_patch.prom"
$metricsText = $metrics -join "`n"

try {
    $metricsText | Out-File -FilePath $promFile -Encoding ASCII -Force
    
    Write-Host ""
    Write-Host "✓ SUCCESS!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Metrics file created: $promFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Installed KBs: $($installedKBs.Count) (Security: $securityInstalled, Critical: $criticalInstalled)"
    Write-Host "  Pending KBs: $($pendingKBs.Count) (Security: $securityPending, Critical: $criticalPending)"
    Write-Host "  Reboot required: $(if ($rebootRequired -eq 1) { 'YES' } else { 'NO' })"
    Write-Host ""
    Write-Host "Windows Exporter will automatically expose these metrics!" -ForegroundColor Green
    Write-Host "Check: http://localhost:9182/metrics" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Grafana queries:" -ForegroundColor Yellow
    Write-Host "  - Installed KBs: windows_patch_installed_info"
    Write-Host "  - Pending KBs: windows_patch_pending_info"
    Write-Host "  - Reboot status: windows_patch_reboot_required"
    
    exit 0
}
catch {
    Write-Host ""
    Write-Host "✗ FAILED to write metrics file!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
