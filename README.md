# Windows Patching Metrics for Prometheus

> **Monitor Windows Update status across hundreds of servers using Windows Exporter textfile collector**

## 📋 Tổng quan

Solution này cho phép bạn:
- ✅ **Xem KB đã cài** - Full details với KB ID, classification, severity, install date
- ✅ **Xem KB đang pending** - Tất cả updates chưa cài
- ✅ **Track reboot status** - Servers nào cần reboot
- ✅ **Scalable** - Hàng trăm servers, hàng nghìn KBs
- ✅ **Real-time** - Metrics update mỗi lần Prometheus scrape

---

## 🚀 Quick Start

### Bước 1: Enable Windows Exporter Textfile Collector

```powershell
# Chạy script để enable textfile collector
.\Enable-TextfileCollector.ps1
```

Script sẽ:
- Tạo folder `C:\Program Files\windows_exporter\textfile_inputs`
- Update Windows Exporter service để enable textfile collector
- Restart service

### Bước 2: Generate KB Metrics

```powershell
# Tạo file metrics
.\Generate-PatchMetrics-Textfile.ps1
```

Script sẽ tạo file: `C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom`

### Bước 3: Verify

```powershell
# Check metrics trong Windows Exporter
Invoke-WebRequest -Uri "http://localhost:9182/metrics" | Select-String "windows_patch"
```

Bạn sẽ thấy:
```
windows_patch_installed_info{kb_id="KB5034441",classification="security",severity="critical",install_date="2026-01-10",...} 1
windows_patch_pending_info{kb_id="KB5034444",classification="security",severity="critical",...} 1
windows_patch_reboot_required 0
```

### Bước 4: Schedule Auto-Update

```powershell
# Chạy script mỗi 30 phút để update metrics
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File 'C:\Scripts\Generate-PatchMetrics-Textfile.ps1'"

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "GenerateWindowsPatchMetrics" `
    -Action $action -Trigger $trigger -Principal $principal
```

---

## 📊 Grafana Queries

### Xem tất cả KB đã cài

```promql
windows_patch_installed_info
```

**Grafana Table sẽ hiển thị:**

| Server | KB ID | Classification | Severity | Install Date | Title |
|--------|-------|----------------|----------|--------------|-------|
| SERVER-01 | KB5034441 | security | critical | 2026-01-10 | 2026-01 Security Update... |
| SERVER-01 | KB5034442 | security | important | 2026-01-09 | 2026-01 Cumulative Update... |

### Xem KB đang pending

```promql
windows_patch_pending_info
```

### Servers cần reboot

```promql
windows_patch_reboot_required == 1
```

### Servers có Critical patches pending

```promql
windows_patch_pending_info{severity="critical"}
```

### Count KBs by classification

```promql
sum by (classification) (windows_patch_installed_info)
```

---

## 📁 Files

### Scripts chính:

- **Enable-TextfileCollector.ps1** - Enable textfile collector cho Windows Exporter
- **Generate-PatchMetrics-Textfile.ps1** - Generate KB metrics file

### Scripts phụ (optional):

- **Send-PatchReport.ps1** - Gửi email report (nếu cần)
- **Deploy-PatchMetrics.ps1** - Deploy lên nhiều servers từ Jumphost

### Documentation:

- **WINDOWS-EXPORTER-GUIDE.md** - Chi tiết về Windows Exporter setup
- **EMAIL-REPORT-GUIDE.md** - Hướng dẫn email report (optional)
- **QUICKSTART.md** - Quick reference commands

### Archive:

- **archive/** - Các scripts cũ cho Pushgateway (không dùng nữa)

---

## 🎯 Metrics Available

### 1. Installed KB Info (mỗi KB = 1 metric)

```
windows_patch_installed_info{
  kb_id="KB5034441",
  classification="security",
  severity="critical",
  install_date="2026-01-10",
  title="2026-01 Security Update for Windows Server 2019"
} 1
```

### 2. Pending KB Info (mỗi KB = 1 metric)

```
windows_patch_pending_info{
  kb_id="KB5034444",
  classification="security",
  severity="critical",
  title="2026-01 Security Update for Windows Server 2019"
} 1
```

### 3. Reboot Required

```
windows_patch_reboot_required 0
```

### 4. Aggregate Counts

```
windows_patch_installed_total{classification="security"} 25
windows_patch_installed_total{classification="non_security"} 10
windows_patch_pending_total{classification="security"} 2
windows_patch_pending_total{classification="non_security"} 0
```

---

## 🔧 Troubleshooting

### Không thấy metrics trong Prometheus?

```powershell
# 1. Check file .prom có tồn tại không
Test-Path "C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom"

# 2. Check Windows Exporter service
Get-Service windows_exporter

# 3. Check textfile collector có enable không
$svc = Get-WmiObject Win32_Service -Filter "Name='windows_exporter'"
$svc.PathName  # Phải có "--collector.textfile"

# 4. Restart service
Restart-Service windows_exporter

# 5. Check metrics
Invoke-WebRequest -Uri "http://localhost:9182/metrics" | Select-String "windows_patch"
```

### File .prom bị lỗi format?

```powershell
# Xem nội dung file
Get-Content "C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom"

# Chạy lại script
.\Generate-PatchMetrics-Textfile.ps1
```

---

## 📈 Deployment cho nhiều servers

### Từ Jumphost, deploy lên tất cả servers:

```powershell
$servers = Get-Content "servers.txt"

foreach ($server in $servers) {
    # Copy scripts
    Copy-Item "Enable-TextfileCollector.ps1" "\\$server\C$\Scripts\" -Force
    Copy-Item "Generate-PatchMetrics-Textfile.ps1" "\\$server\C$\Scripts\" -Force
    
    # Enable textfile collector
    Invoke-Command -ComputerName $server -ScriptBlock {
        C:\Scripts\Enable-TextfileCollector.ps1
    }
    
    # Generate initial metrics
    Invoke-Command -ComputerName $server -ScriptBlock {
        C:\Scripts\Generate-PatchMetrics-Textfile.ps1
    }
    
    # Setup scheduled task
    Invoke-Command -ComputerName $server -ScriptBlock {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -File C:\Scripts\Generate-PatchMetrics-Textfile.ps1"
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 30) `
            -RepetitionDuration ([TimeSpan]::MaxValue)
        
        Register-ScheduledTask -TaskName "GenerateWindowsPatchMetrics" `
            -Action $action -Trigger $trigger -Force
    }
    
    Write-Host "✓ Deployed to $server" -ForegroundColor Green
}
```

---

## 💡 Best Practices

1. **Schedule frequency**: Chạy script mỗi 30 phút (đủ cho patching monitoring)
2. **Prometheus scrape interval**: 15-30 seconds (default Windows Exporter)
3. **Retention**: Metrics tự động cleanup khi KB được uninstall
4. **Backup**: Không cần - metrics được generate lại mỗi lần chạy script

---

## 🎉 Kết luận

**Windows Exporter Textfile Collector = Best solution!**

- ✅ Full KB details (unlimited)
- ✅ Scalable cho hàng trăm servers
- ✅ Đơn giản, dễ maintain
- ✅ Real-time updates
- ✅ Không cần Pushgateway

**Chúc bạn monitoring vui vẻ!** 🚀

---

## 📞 Support

Xem thêm documentation:
- `WINDOWS-EXPORTER-GUIDE.md` - Chi tiết setup
- `EMAIL-REPORT-GUIDE.md` - Email report (optional)
- `QUICKSTART.md` - Quick commands

Archive (Pushgateway solutions - không dùng nữa):
- `archive/` - Các scripts cũ


- Phát triển ý tưởng bởi THDIEP16 - tranhoangdiepbp@gmail.com
