# run_all_lifecycle.ps1 - Tu dong hoa toan bo quy trinh bai Lab MLOps Lifecycle

Write-Host "=== Bat dau chay tu dong toan bo bai Lab MLOps Lifecycle ===" -ForegroundColor Green

# 1. Dam bao docker compose da khoi chay
Write-Host "1. Kiem tra va khoi dong Docker container..." -ForegroundColor Cyan
docker compose -f data-pack/configs/docker-compose.yml up -d

# 2. Sinh du lieu
Write-Host "2. Sinh du lieu mo phong..." -ForegroundColor Cyan
$env:PYTHONIOENCODING="utf-8"
python data-pack/data/generate_data.py

# 3. Huan luyen va dang ky model v1
Write-Host "3. Chay pipeline.py huan luyen va dang ky model v1..." -ForegroundColor Cyan
$env:MLFLOW_TRACKING_URI="http://localhost:5000"
python lekimdung/pipeline.py --data data-pack/data/baseline.csv

# 4. Kiem tra Model Server, khoi chay neu chua chay
Write-Host "4. Kiem tra Model Server (port 8000)..." -ForegroundColor Cyan
$serverRunning = $false
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8000/health/active-version" -UseBasicParsing -TimeoutSec 2
    if ($response.StatusCode -eq 200) {
        $serverRunning = $true
        Write-Host "   Model Server dang chay san." -ForegroundColor Yellow
    }
} catch {
    # Server chua chay
}

if (-not $serverRunning) {
    Write-Host "   Khoi chay Model Server trong tien trinh nen..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$env:MLFLOW_TRACKING_URI='http://localhost:5000'; `$env:PYTHONIOENCODING='utf-8'; python lekimdung/serve.py" -WindowStyle Minimized
    # Cho server khoi dong
    Start-Sleep -Seconds 5
}

# 5. Cau hinh Grafana Datasource tu dong
Write-Host "5. Tu dong them Prometheus Datasource (uid: prometheus) vao Grafana..." -ForegroundColor Cyan
try {
    $body = @{
        name = "prometheus"
        type = "prometheus"
        url = "http://prometheus:9090"
        access = "proxy"
        uid = "prometheus"
        isDefault = $true
    } | ConvertTo-Json
    
    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin"))
    }
    
    $res = Invoke-RestMethod -Method Post -Uri "http://localhost:3000/api/datasources" -Headers $headers -ContentType "application/json" -Body $body
    Write-Host "   Them datasource thanh cong!" -ForegroundColor Green
} catch {
    Write-Host "   Datasource da ton tai hoac co loi (neu da tao roi thi co the bo qua)" -ForegroundColor Yellow
}

# 6. Chay retrain + auto-rollback
Write-Host "6. Chay retrain.py tu dong kiem tra drift, train v2, promote va rollback..." -ForegroundColor Cyan
python lekimdung/retrain.py `
  --reference data-pack/data/baseline.csv `
  --current data-pack/data/drifted.csv `
  --holdout data-pack/data/holdout.csv `
  --post-deploy-eval data-pack/data/post_deploy_eval.csv `
  --serve-url http://localhost:8000 `
  --auto-approve

Write-Host "=== Hoan thanh chay tu dong toan bo bai Lab! ===" -ForegroundColor Green
Write-Host "Ban co the kiem tra ket qua tai:"
Write-Host "- Grafana Dashboard: http://localhost:3000/d/aiops-mlops-lifecycle/aiops-mlops-lifecycle"
Write-Host "- MLflow UI: http://localhost:5000"
Write-Host "- Nhat ky hoat dong: outputs/audit_log.jsonl"
