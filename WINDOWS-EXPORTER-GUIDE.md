# Windows Exporter Textfile Collector Guide

## 🎯 Tại sao dùng Windows Exporter tốt hơn Pushgateway?

### ✅ Ưu điểm:
- **Full KB details** - Không giới hạn số lượng KBs
- **Mỗi KB = 1 metric riêng** với full labels (kb_id, classification, severity, install_date, title)
- **Không cần Pushgateway** - Prometheus scrape trực tiếp từ Windows Exporter
- **Scalable** - Hàng nghìn KBs không vấn đề gì
- **Real-time** - Metrics update mỗi lần Prometheus scrape

### ❌ So với Pushgateway:
- Pushgateway: Giới hạn KB details hoặc tạo quá nhiều jobs
- Windows Exporter: Không giới hạn, không tạo jobs

---

## 🚀 Setup

### Bước 1: Enable textfile collector trong Windows Exporter

Khi cài Windows Exporter, thêm flag:
```powershell
windows_exporter.exe --collectors.enabled="cpu,memory,logical_disk,textfile" --collector.textfile.directory="C:\Program Files\windows_exporter\textfile_inputs"
```

Hoặc nếu đã cài rồi, edit service:
```powershell
sc.exe config windows_exporter binPath= "\"C:\Program Files\windows_exporter\windows_exporter.exe\" --collectors.enabled=\"cpu,memory,logical_disk,textfile\" --collector.textfile.directory=\"C:\Program Files\windows_exporter\textfile_inputs\""

Restart-Service windows_exporter
```

### Bước 2: Tạo textfile directory
```powershell
New-Item -Path "C:\Program Files\windows_exporter\textfile_inputs" -ItemType Directory -Force
```

### Bước 3: Chạy script để generate metrics
```powershell
.\Generate-PatchMetrics-Textfile.ps1
```

Script sẽ tạo file: `C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom`

### Bước 4: Verify
```powershell
# Check metrics file
Get-Content "C:\Program Files\windows_exporter\textfile_inputs\windows_patch.prom"

# Check Windows Exporter endpoint
Invoke-WebRequest -Uri "http://localhost:9182/metrics" | Select-String "windows_patch"
```

---

## 📊 Metrics Exposed

### 1. Installed KB Info (mỗi KB = 1 metric)
```
windows_patch_installed_info{kb_id="KB5034441",classification="security",severity="critical",install_date="2026-01-10",title="2026-01 Security Update..."} 1
windows_patch_installed_info{kb_id="KB5034442",classification="security",severity="important",install_date="2026-01-09",title="2026-01 Cumulative Update..."} 1
```

### 2. Pending KB Info (mỗi KB = 1 metric)
```
windows_patch_pending_info{kb_id="KB5034444",classification="security",severity="critical",title="2026-01 Security Update..."} 1
windows_patch_pending_info{kb_id="KB5034445",classification="security",severity="important",title="2026-01 Cumulative Update..."} 1
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

## 🎨 Grafana Queries

### Xem tất cả KB đã cài
```promql
windows_patch_installed_info
```

**Grafana Table:**
| Server | KB ID | Classification | Severity | Install Date | Title |
|--------|-------|----------------|----------|--------------|-------|
| SERVER-01 | KB5034441 | security | critical | 2026-01-10 | 2026-01 Security Update... |
| SERVER-01 | KB5034442 | security | important | 2026-01-09 | 2026-01 Cumulative Update... |

### Xem KB đang pending
```promql
windows_patch_pending_info
```

### Xem KB cụ thể
```promql
windows_patch_installed_info{kb_id="KB5034441"}
```

### Servers đã cài KB cụ thể
```promql
count by (instance) (windows_patch_installed_info{kb_id="KB5034441"})
```

### Servers có Critical patches pending
```promql
windows_patch_pending_info{severity="critical"}
```

### Servers cần reboot
```promql
windows_patch_reboot_required == 1
```

### Count KBs by classification
```promql
sum by (classification) (windows_patch_installed_info)
```

### Latest installed KB per server
```promql
max by (instance) (windows_patch_installed_info)
```

---

## ⏰ Schedule Script

### Chạy mỗi 30 phút
```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File 'C:\Scripts\Generate-PatchMetrics-Textfile.ps1'"

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "GenerateWindowsPatchMetrics" -Action $action -Trigger $trigger -Principal $principal
```

---

## 🔄 Workflow

1. **Script chạy mỗi 30 phút** (scheduled task)
2. **Generate file .prom** với latest KB data
3. **Windows Exporter đọc file** và expose metrics
4. **Prometheus scrape** Windows Exporter (mỗi 15s)
5. **Grafana query** Prometheus và hiển thị

---

## 💡 So sánh với Pushgateway

| Feature | Windows Exporter | Pushgateway |
|---------|------------------|-------------|
| KB Details | ✅ Full (unlimited) | ⚠️ Limited hoặc nhiều jobs |
| Scalability | ✅ Excellent | ⚠️ Job explosion |
| Setup | ✅ Simple (textfile) | ⚠️ Cần push script |
| Real-time | ✅ Yes (scrape interval) | ⚠️ Depends on push frequency |
| Query flexibility | ✅ Full PromQL | ⚠️ Limited by labels |

---

## ✅ Recommended Setup

**Cho hàng trăm servers:**
1. ✅ Dùng **Windows Exporter textfile collector**
2. ✅ Script `Generate-PatchMetrics-Textfile.ps1` chạy mỗi 30 phút
3. ✅ Prometheus scrape Windows Exporter
4. ✅ Grafana query trực tiếp

**Không cần Pushgateway cho KB details!**

---

## 🎯 Tóm tắt

**Windows Exporter = BEST solution cho KB details!**
- ✅ Full details từng KB
- ✅ Scalable cho hàng nghìn KBs
- ✅ Đơn giản, dễ maintain
- ✅ Real-time updates

**Chạy ngay:**
```powershell
.\Generate-PatchMetrics-Textfile.ps1
```

**Perfect!** 🚀
