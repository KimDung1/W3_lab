# README — MLOps Lifecycle: Anomaly Detection Pipeline
**Tác giả: Le Kim Dung**

## Cách chạy pipeline từ đầu đến cuối (Tự động)

Bạn có thể chạy toàn bộ quy trình pipeline từ đầu đến cuối (khởi động hạ tầng, sinh dữ liệu, huấn luyện model v1, khởi chạy API server, cấu hình Grafana datasource tự động, và chạy orchestrator retrain + auto-rollback) chỉ bằng **một câu lệnh duy nhất**. Hãy mở PowerShell tại thư mục gốc của dự án và chạy:
```powershell
powershell -ExecutionPolicy Bypass -File .\lekimdung\run_all_lifecycle.ps1
```
Sau khi script hoàn tất, bạn có thể kiểm tra giao diện Grafana (http://localhost:3000), MLflow UI (http://localhost:5000), và file nhật ký `outputs/audit_log.jsonl` để xem kết quả.

---

## Cách chạy từng bước (Thủ công)

### Bước 1 — Khởi động stack hạ tầng
```powershell
docker compose -f data-pack/configs/docker-compose.yml up -d
```
Sau khoảng 30 giây, các services sẽ sẵn sàng:
- MLflow UI: http://localhost:5000
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Pushgateway: http://localhost:9091

### Bước 2 — Sinh dữ liệu
```powershell
$env:PYTHONIOENCODING="utf-8"
python data-pack/data/generate_data.py
```

### Bước 3 — Huấn luyện và đăng ký model v1
```powershell
$env:MLFLOW_TRACKING_URI="http://localhost:5000"
python lekimdung/pipeline.py --data data-pack/data/baseline.csv
```
Kết quả: `anomaly-detector v1` được đăng ký với alias `@production` trên MLflow Registry.

### Bước 4 — Khởi chạy Model Server (terminal riêng)
```powershell
$env:MLFLOW_TRACKING_URI="http://localhost:5000"
python lekimdung/serve.py
```
Kiểm tra: `curl http://localhost:8000/health/active-version`

### Bước 5 — Kiểm tra Drift (optional, standalone)
```powershell
python lekimdung/drift_detector.py `
  --reference data-pack/data/baseline.csv `
  --current data-pack/data/drifted.csv `
  --check-mode combined `
  --labeled-current data-pack/data/drifted.csv `
  --model-uri "models:/anomaly-detector@production" `
  --log-mlflow
```

### Bước 6 — Chạy toàn bộ pipeline Retrain + Auto-Rollback
```powershell
python lekimdung/retrain.py `
  --reference data-pack/data/baseline.csv `
  --current data-pack/data/drifted.csv `
  --holdout data-pack/data/holdout.csv `
  --post-deploy-eval data-pack/data/post_deploy_eval.csv `
  --serve-url http://localhost:8000
```
*(Bỏ `--auto-approve` để có manual approval gate. Nhập `y` khi được hỏi.)*

### Bước 7 — Xem kết quả
- **MLflow UI:** http://localhost:5000 — xem experiments, model versions, aliases
- **Grafana:** http://localhost:3000 — dashboard "AIOps MLOps Lifecycle"
- **Audit log:** `outputs/audit_log.jsonl` — nhật ký toàn bộ sự kiện lifecycle

### Bước 8 — Dừng hệ thống
```powershell
docker compose -f data-pack/configs/docker-compose.yml down
```
