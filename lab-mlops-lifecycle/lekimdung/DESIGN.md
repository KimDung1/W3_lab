# DESIGN.md — MLOps Lifecycle: Anomaly Detection Pipeline
**Tác giả: Le Kim Dung**

---

## Tổng quan

Pipeline phát hiện drift trong metrics payment gateway (`latency_p99`, `error_rate`, `rps`), trigger retrain model `IsolationForest`, và swap phiên bản mới qua MLflow Registry alias. Toàn bộ chạy locally với Docker Compose, không cần cloud account.

---

## Sub-checkpoint 1: Drift Threshold

**Giá trị đã chọn: 0.15** (15% features bị drift theo Evidently DataDriftPreset).

**Cách chọn:** Chạy `drift_detector.py` trên chính `baseline.csv`, chia 70/30 (phần đầu làm reference, phần cuối làm current). Kết quả drift score ≈ 0.04 — đây là "noise floor" khi không có drift thực sự. Chọn threshold = 0.15, tức ~3.75× noise floor. Với `drifted.csv` thực tế, score đo được là **1.0000** (tất cả 3 features đều bị drift), vượt threshold rõ ràng.

**Rủi ro nếu threshold quá thấp (ví dụ 0.05):** false positive — retrain trigger sau mỗi seasonal fluctuation bình thường (traffic cao điểm buổi sáng vs buổi tối). Tốn compute và gây alert fatigue cho on-call team.

**Rủi ro nếu threshold quá cao (ví dụ 0.80):** false negative — bỏ sót drift thực. Model tiếp tục serve với phân phối không còn phù hợp, precision/recall giảm âm thầm. Trong payment domain, điều này có thể gây miss real incidents hoặc false alert storm.

---

## Sub-checkpoint 2: Loại Drift

**Loại được detect bởi `DataDriftPreset`: Data drift** — P(X) thay đổi, tức phân phối input features (`latency_p99`, `error_rate`, `rps`) đã dịch chuyển so với training data.

**Evidently DataDriftPreset hoạt động như thế nào:** Dùng Wasserstein distance cho numerical features. Khi `share_of_drifted_columns > threshold` → flag `is_drift = True`. Trong lab này, cả 3 features đều drift (score = 1.0): latency tăng từ ~129ms lên ~162ms, error_rate tăng từ ~0.79 lên ~1.48, rps tăng tương ứng.

**Tại sao data drift phù hợp:** Sau campaign, traffic tăng 35%, latency baseline tăng do 3rd-party integrations, error_rate thay đổi do payment processor mới. Model v1 train với distribution cũ sẽ coi latency 162ms là "bất thường" dù thực ra là normal mới. Detect data drift cho phép retrain trước khi precision giảm đáng kể.

**Tại sao cần thêm `--check-mode combined`:** `DataDriftPreset` chỉ phát hiện P(X) thay đổi. `drifted.csv` có 252/1008 rows (25%) bị **flip label** — đây là concept drift: P(Y|X) thay đổi mà feature distribution vẫn shift. Kết quả thực tế từ lab: `Perf precision: 0.2907` < threshold 0.70 → `perf_is_degraded = True`. Nếu chỉ dùng data drift mode, sẽ miss trường hợp này.

---

## Sub-checkpoint 3: Retrain Trigger Configuration

**Trigger type: Semi-automatic với manual approval gate.**

**Flow:** Drift check được gọi batch khi có data mới. Nếu `drift_score > 0.15` hoặc `precision < 0.70`, pipeline train v2 và register `@staging`. Sau đó in prompt: `"Promote staging → production? [y/N]"` và chờ ML engineer review.

**Lý do chọn manual gate:** Model anomaly detection trong payment system ảnh hưởng trực tiếp đến on-call SLA. Một model tệ hơn được promote tự động có thể gây false negatives trên real incidents (bỏ sót incident thật) hoặc alert storm từ false positives. Gate đảm bảo ML engineer review metric trước khi cutover.

**Trong lab này:** Sử dụng `--auto-approve` flag để bypass gate phục vụ automated testing. Trong production thực tế, flag này không được dùng.

**Approval timeout recommendation:** 24h — nếu không có approval, staging version bị archive. Tránh trạng thái "model treo mãi trong staging không ai review".

---

## Sub-checkpoint 4: Versioning và Rollback

**Chiến lược versioning:** MLflow Registry với aliases, không hardcode version numbers trong code.

- `@production` alias → version đang serve (serve.py load qua `models:/anomaly-detector@production`)
- `@staging` alias → version candidate sau retrain
- `@archived` alias → version bị demote sau rollback
- Version numbers (1, 2, 3…) là immutable audit trail không bao giờ bị xóa

**Tại sao alias tốt hơn:** `mlflow.pyfunc.load_model("models:/anomaly-detector@production")` không cần thay đổi khi swap. Nếu hardcode version number trong serve.py, phải redeploy service mỗi lần retrain.

**Rollback path (thực tế trong lab này):**
```
Cycle 01/24 — precision: 0.4000 < threshold 0.65 → AUTO-ROLLBACK triggered
client.set_registered_model_alias("anomaly-detector", "archived", "2")
client.set_registered_model_alias("anomaly-detector", "production", "1")
POST /reload → serve.py reloaded → now serving v1
Rollback complete. v1 restored to @production. v2 → @archived.
```
Toàn bộ quá trình < 5 giây, không cần redeploy container.

**Ai có quyền rollback:** ML engineer on-call (có MLflow admin access). Rollback manual có thể thực hiện bất cứ lúc nào qua MLflow UI hoặc CLI.

---

## Sub-checkpoint 5: Combined Mode — Tại sao cần thiết

Chỉ dùng `DataDriftPreset` là chưa đủ. `drifted.csv` chứa cả 2 loại drift đồng thời:
- **Data drift:** latency tăng 25% (128.9ms → 162.4ms), error_rate gần gấp đôi (0.791 → 1.482)
- **Concept drift:** 252/1008 rows (25%) bị flip label — cùng feature values nhưng anomaly_label bị đảo ngược

**Ví dụ cụ thể từ kết quả thực tế:**
- `--check-mode data` → `Drift score: 1.0000, Drift detected: True` ✓ phát hiện data drift
- `--check-mode combined` → ngoài data drift còn thấy `Perf precision: 0.2907 < threshold 0.70` → concept drift cũng bị phát hiện

Nếu chỉ chạy data-only mode: precision = 0.29 không được báo cáo, on-call team không biết model đang confuse về labels. Combined mode là bắt buộc cho payment domain vì cả 2 loại drift đều xảy ra đồng thời trong thực tế.

---

## Sub-checkpoint 6: Data Selection Strategy — Sliding Window

**Vấn đề với "pure drift window only":** Train chỉ trên 1008 rows `drifted.csv` → model overfit vào distribution mới. Kết quả thực tế: `v2 precision: 0.0000, recall: 0.0000` trên `holdout.csv` (old pattern). Model hoàn toàn quên cách nhận diện anomaly theo pattern cũ vẫn còn hiện diện trong production.

**Sliding window strategy (baseline + drift):** Concat `baseline.csv` (4320 rows) + `drifted.csv` (1008 rows) = **5328 rows**. Model thấy cả 2 regime, không bị dominated bởi distribution mới.

**So sánh alternatives:**
| Strategy | Pros | Cons |
|---|---|---|
| **Sliding window (baseline + drift)** ← Chọn | Generalise cả 2 distributions | Training set lớn hơn |
| Pure drift window | Nhỏ, nhanh | Overfit vào distribution mới, quên old pattern |
| Weighted sampling | Flexible control | Phức tạp hơn, cần tune ratio |
| Full historical concat | An toàn nhất | Tốn compute khi data tích lũy nhiều tháng |

Với `holdout.csv` trong lab: v2 precision = 0.0000 (pure drift window) vs holdout validation nên được run trước khi register — đây là lesson learned: **luôn validate trên holdout trước khi promote**.

---

## Sub-checkpoint 7: Auto-Rollback — Threshold và Policy

**Threshold: precision < 0.65** trên `post_deploy_eval.csv` (200 rows: 60% normal, 40% anomaly = 80 anomaly rows).

**Tại sao 0.65:** Đây là ngưỡng conservative — đủ thấp để không trigger false rollback do sampling noise, đủ xa baseline 0.91 để chắc chắn model đang fail nghiêm trọng. Tính toán: nếu model hoàn toàn confused, precision ≈ 0.40. Ngưỡng 0.65 nằm giữa "fail hoàn toàn" và "hoạt động bình thường".

**Kết quả thực tế từ lab:**
```
Cycle 01/24 — precision: 0.4000 < threshold 0.65 → AUTO-ROLLBACK triggered
```
v2 bị demote ngay ở cycle đầu tiên do precision chỉ đạt 0.40.

**Rollback flow:** `@archived ← v2`, `@production ← v1`, `POST /reload` → serve.py reload v1. Event được append vào `outputs/audit_log.jsonl` với đầy đủ fields: `demoted_version`, `restored_version`, `trigger_precision`, `cycle`.

---

## Trade-offs đã chấp nhận

| Quyết định | Được | Mất |
|---|---|---|
| Manual approval gate | An toàn, human oversight | Latency trong retrain loop |
| Combined drift check | Phát hiện cả data + concept drift | Cần labeled data cho performance check |
| Sliding window | Generalise cả 2 distributions | Training set lớn hơn pure drift window |
| IsolationForest (không LSTM) | Train < 1s, no GPU, explainable | Không capture temporal patterns |
| Local artifact store | Không cần S3 setup | Không scale multi-node |
