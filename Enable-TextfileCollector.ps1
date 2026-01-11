<#
.SYNOPSIS
    Enable textfile collector for existing Windows Exporter installation

.DESCRIPTION
    Adds textfile collector to running Windows Exporter without reinstalling
    Safe to run - only modifies service arguments

.EXAMPLE
    .\Enable-TextfileCollector.ps1
#>

[CmdletBinding()]
param()

Write-Host "=== Enable Windows Exporter Textfile Collector ===" -ForegroundColor Cyan
Write-Host ""

# Check if Windows Exporter service exists
$service = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Host "✗ Windows Exporter service not found!" -ForegroundColor Red
    Write-Host "Please install Windows Exporter first." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Found Windows Exporter service" -ForegroundColor Green
Write-Host "  Status: $($service.Status)"
Write-Host ""

# Get current service configuration
$serviceConfig = Get-WmiObject Win32_Service -Filter "Name='windows_exporter'"
$currentPath = $serviceConfig.PathName

Write-Host "Current configuration:" -ForegroundColor Cyan
Write-Host $currentPath
Write-Host ""

# Check if textfile collector already enabled
if ($currentPath -match "textfile") {
    Write-Host "✓ Textfile collector already enabled!" -ForegroundColor Green
    
    # Extract textfile directory
    if ($currentPath -match '--collector\.textfile\.directory[=\s]+"?([^"]+)"?') {
        $textfileDir = $Matches[1]
        Write-Host "  Textfile directory: $textfileDir" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "You can now run:" -ForegroundColor Yellow
    Write-Host "  .\Generate-PatchMetrics-Textfile.ps1"
    exit 0
}

# Prepare new configuration
$exePath = $currentPath -replace '"', '' -replace ' --.*', ''
$textfileDir = "C:\Program Files\windows_exporter\textfile_inputs"

# Create textfile directory
if (-not (Test-Path $textfileDir)) {
    New-Item -Path $textfileDir -ItemType Directory -Force | Out-Null
    Write-Host "✓ Created textfile directory: $textfileDir" -ForegroundColor Green
}

# Build new service path with textfile collector
$newPath = "`"$exePath`" --collectors.enabled=`"cpu,cs,logical_disk,net,os,service,system,textfile`" --collector.textfile.directory=`"$textfileDir`""

Write-Host "New configuration:" -ForegroundColor Cyan
Write-Host $newPath
Write-Host ""

# Confirm with user
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Stop Windows Exporter service"
Write-Host "  2. Update service configuration to enable textfile collector"
Write-Host "  3. Start Windows Exporter service"
Write-Host ""

$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit 0
}

Write-Host ""
Write-Host "Updating service..." -ForegroundColor Yellow

try {
    # Stop service
    Write-Host "  [1/3] Stopping service..."
    Stop-Service -Name "windows_exporter" -Force
    Start-Sleep -Seconds 2
    
    # Update service configuration
    Write-Host "  [2/3] Updating configuration..."
    sc.exe config windows_exporter binPath= $newPath | Out-Null
    
    # Start service
    Write-Host "  [3/3] Starting service..."
    Start-Service -Name "windows_exporter"
    Start-Sleep -Seconds 3
    
    # Verify service is running
    $service = Get-Service -Name "windows_exporter"
    if ($service.Status -eq "Running") {
        Write-Host ""
        Write-Host "✓ SUCCESS!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Textfile collector enabled!" -ForegroundColor Cyan
        Write-Host "  Textfile directory: $textfileDir" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Run: .\Generate-PatchMetrics-Textfile.ps1"
        Write-Host "  2. Verify: Invoke-WebRequest http://localhost:9182/metrics | Select-String 'windows_patch'"
        Write-Host "  3. Check Grafana for new metrics!"
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "⚠ Service started but status is: $($service.Status)" -ForegroundColor Yellow
        Write-Host "Check service logs for errors" -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "✗ FAILED!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Trying to restore service..." -ForegroundColor Yellow
    
    try {
        Start-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
    }
    catch {}
    
    exit 1
}
