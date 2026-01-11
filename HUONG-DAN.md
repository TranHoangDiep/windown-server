# Hướng dẫn sử dụng - Windows Patching Metrics

## 🎯 Mục đích

Monitor Windows Update status (KB đã cài, KB pending, reboot status) trong Grafana sử dụng Windows Exporter.

---

## 📋 Yêu cầu

- ✅ Windows Exporter đã cài đặt và đang chạy
- ✅ PowerShell với quyền Administrator
- ✅ Prometheus đang scrape Windows Exporter
- ✅ Grafana đã kết nối với Prometheus

---

## 🚀 Cách chạy (3 bước)

### **Bước 1: Enable Textfile Collector**

Chạy script này **1 lần duy nhất** trên mỗi server:

```powershell
.\Enable-TextfileCollector.ps1
```

**Script sẽ:**
- Tạo folder `C:\Program Files\windows_exporter\textfile_inputs`
- Cập nhật Windows Exporter service để enable textfile collector
- Restart service

**Kết quả:** Windows Exporter giờ có thể đọc file `.prom` và expose metrics.

---

### **Bước 2: Generate Metrics**

Chạy script để tạo metrics:

```powershell
.\Generate-PatchMetrics-Textfile.ps1
```

**Script sẽ:**
- Query Windows Update để lấy KB đã cài
- Query Windows Update để lấy KB pending
- Tạo file `C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom`

**Kết quả:** File `.prom` chứa metrics về KB status.

---

### **Bước 3: Verify**

Kiểm tra metrics đã có trong Windows Exporter:

```powershell
Invoke-WebRequest -Uri "http://localhost:9182/metrics" | Select-String "windows_patch"
```

**Bạn sẽ thấy:**
```
windows_patch_installed_info{kb_id="KB5034441",...} 1
windows_patch_pending_info{kb_id="KB5034444",...} 1
windows_patch_reboot_required 0
```

---

## ⏰ Setup Auto-Update (Optional)

Để metrics tự động update **mỗi ngày 1 lần** (lúc 4:00 sáng):

```powershell
# Tạo Scheduled Task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\Scripts\Generate-PatchMetrics-Textfile.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 4:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "GenerateWindowsPatchMetrics" `
    -Action $action -Trigger $trigger -Principal $principal
```

**Kết quả:** Script tự động chạy mỗi ngày lúc 4:00 sáng, không ảnh hưởng giờ làm việc.

---

## 📊 Xem trong Grafana

### Query cơ bản:

**Tất cả KB đã cài:**
```promql
windows_patch_installed_info
```

**KB đang pending:**
```promql
windows_patch_pending_info
```

**Servers cần reboot:**
```promql
windows_patch_reboot_required == 1
```

**Critical patches pending:**
```promql
windows_patch_pending_info{severity="critical"}
```

---

## 🔧 Troubleshooting

### Không thấy metrics?

```powershell
# 1. Check file .prom có tồn tại không
Test-Path "C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom"

# 2. Check Windows Exporter service
Get-Service windows_exporter

# 3. Restart service
Restart-Service windows_exporter

# 4. Chạy lại script
.\Generate-PatchMetrics-Textfile.ps1

# 5. Check lại
Invoke-WebRequest -Uri "http://localhost:9182/metrics" | Select-String "windows_patch"
```

### Script báo lỗi?

Chạy với quyền **Administrator** và đảm bảo Windows Update service đang chạy:

```powershell
Get-Service wuauserv
Start-Service wuauserv
```

---

## 📁 Files

- **Enable-TextfileCollector.ps1** - Enable textfile collector (chạy 1 lần)
- **Generate-PatchMetrics-Textfile.ps1** - Generate metrics (chạy định kỳ)
- **README.md** - Documentation đầy đủ
- **WINDOWS-EXPORTER-GUIDE.md** - Chi tiết kỹ thuật
- **HUONG-DAN.md** - File này

---

## 💡 Tips

1. **Chạy script thủ công** lần đầu để test
2. **Setup scheduled task** sau khi confirm metrics hoạt động
3. **Frequency**: Mỗi ngày 1 lần là đủ cho patching monitoring
4. **Prometheus scrape interval**: Giữ mặc định (15-30s)

---

## ✅ Checklist

- [ ] Chạy `Enable-TextfileCollector.ps1` (1 lần)
- [ ] Chạy `Generate-PatchMetrics-Textfile.ps1` (test)
- [ ] Verify metrics trong Windows Exporter
- [ ] Check metrics trong Prometheus
- [ ] Tạo Grafana dashboard
- [ ] Setup scheduled task (auto-update)
- [ ] Deploy lên các servers khác

---

**Chúc bạn monitoring vui vẻ!** 🚀
