# SUBMIT.md — Reflection: MLOps Lifecycle Lab
**Tác giả: Le Kim Dung**

---

## Câu hỏi 1: Drift threshold bạn chọn là gì và tại sao? Bạn có validate threshold đó với dữ liệu thực không?

**Threshold đã chọn: 0.15** (15% của tổng số features bị drift).

Cách xác định: Chạy `drift_detector.py` trên chính `baseline.csv` chia 70/30 → drift score = 0.04 (noise floor khi không có drift thực). Threshold 0.15 = 3.75× noise floor, đủ xa để không bị false positive do seasonal fluctuation bình thường.

Validate với `drifted.csv` thực tế: drift score = **1.0000** (tất cả 3 features đều bị drift — latency tăng từ 128.9ms lên 162.4ms, error_rate gần gấp đôi từ 0.791 lên 1.482). Score vượt threshold rất rõ ràng, xác nhận threshold 0.15 hoạt động đúng.

Nếu threshold quá thấp (0.02): retrain triggered mỗi ngày do traffic fluctuation bình thường, gây alert fatigue. Nếu quá cao (0.80): bỏ sót drift score = 0.67 tương đương 2/3 features bị drift — đây là mức nguy hiểm trong payment domain.

---

## Câu hỏi 2: Điều gì xảy ra nếu model v2 sau retraining hoạt động tệ hơn v1 trong production? Pipeline xử lý trường hợp này như thế nào?

**Pipeline có cơ chế tự động rollback (Stress 3) để xử lý đúng trường hợp này.**

Cụ thể: sau khi v2 được promote lên `@production`, `post_deploy_monitor()` chạy 24 chu kỳ đánh giá precision trên `post_deploy_eval.csv`. Nếu precision < 0.65 → trigger auto-rollback.

**Kết quả thực tế từ lab:**
```
Cycle 01/24 — precision: 0.4000 < threshold 0.65 → AUTO-ROLLBACK triggered
client.set_registered_model_alias("anomaly-detector", "archived", "2")
client.set_registered_model_alias("anomaly-detector", "production", "1")
Rollback complete. v1 restored to @production. v2 → @archived.
```

v2 bị demote ngay ở cycle đầu tiên vì precision chỉ đạt 0.40 — cho thấy model v2 không học được pattern tốt do holdout validation cũng cho kết quả precision = 0.0000. Toàn bộ rollback < 5 giây, serve.py tự động reload v1 mà không cần downtime. Mọi sự kiện đều được ghi vào `outputs/audit_log.jsonl` với event `auto_rollback_v2_to_v1`.

---

## Câu hỏi 3: Sự khác biệt giữa data drift và concept drift là gì? Evidently phát hiện loại nào trong lab này?

**Data drift** — phân phối input thay đổi: P(X) thay đổi, trong khi P(Y|X) vẫn ổn định. Ví dụ: latency baseline tăng từ 120ms lên 156ms sau khi thêm 3rd-party integrations. Features shift nhưng rule "latency > 200ms là anomaly" vẫn đúng.

**Concept drift** — mối quan hệ input-output thay đổi: P(Y|X) thay đổi. Ví dụ: cùng latency 180ms nhưng với payment processor mới, đây là "bình thường mới" thay vì anomaly. Model train với rule cũ sẽ predict sai dù features không thay đổi nhiều.

**Evidently `DataDriftPreset` phát hiện: Data drift** — dùng Wasserstein distance để so sánh phân phối từng feature. Trong lab này, score = 1.0 vì tất cả 3 features bị shift rõ rệt.

**`--check-mode combined` phát hiện thêm: Concept drift (gián tiếp qua performance drift)** — đánh giá precision/recall của model trên tập có nhãn. Kết quả: `Perf precision: 0.2907 < threshold 0.70` → model v1 không còn phù hợp với pattern mới. `drifted.csv` có 252/1008 rows (25%) bị flip label, đây là nguồn gốc của concept drift trong lab.

---

## Câu hỏi 4: Tại sao blue-green swap quan trọng hơn việc chỉ replace model file trực tiếp?

**Blue-green swap đảm bảo zero-downtime và khả năng rollback ngay lập tức.**

Nếu chỉ replace model file trực tiếp, có các vấn đề sau:
1. **Race condition:** Requests đang được xử lý giữa chừng có thể bị interrupted khi file bị ghi đè.
2. **Không có rollback path:** Nếu model mới bị lỗi, phải copy lại file cũ — tốn thời gian và dễ xảy ra sai sót.
3. **Không verify được:** Không có cách nào verify model mới đã được load thành công trước khi traffic được route.

**Với blue-green swap trong lab này:**
- `@production` alias được swap từ v1 → v2 trong MLflow Registry (< 1 giây)
- `POST /reload` được gọi lên serve.py → load v2 vào memory trong khi serve.py vẫn đang handle requests
- `GET /health/active-version` cho phép verify v2 đã được load thành công trước khi cắt hoàn toàn
- Rollback chỉ cần swap alias ngược lại → `POST /reload` → toàn bộ < 5 giây

Đây là lý do `/health/active-version` endpoint tồn tại: để blue-green verification trước khi full cutover.

---

## Câu hỏi 5: Nếu phải tự động hóa hoàn toàn approval gate (không cần human), bạn sẽ dùng metric và threshold nào?

**Metric đề xuất: Holdout precision trên `holdout.csv` so sánh với v1 baseline.**

**Điều kiện auto-promote (tất cả phải đạt):**
1. `v2_holdout_precision >= v1_holdout_precision × 0.95` — v2 không được tệ hơn v1 quá 5% trên old pattern
2. `v2_drift_window_anomaly_rate` nằm trong khoảng `[v1_anomaly_rate × 0.5, v1_anomaly_rate × 2.0]` — anomaly rate không được thay đổi đột ngột
3. `drift_score > threshold` — chỉ retrain khi có drift thực, không phải noise

**Tại sao 95% threshold (không phải 100%):** Vì holdout là sample, có sampling error. 5% buffer tránh false rejection do statistical noise. Trong payment domain, không nên auto-promote nếu precision drop > 5% so với v1.

**Backup safeguard:** Giữ nguyên `post_deploy_monitor` với auto-rollback sau promote. Kể cả khi auto-promote hoạt động, nếu v2 fail trong production thực tế (precision < 0.65 trên post_deploy_eval), rollback vẫn xảy ra tự động. **Defense in depth** — không phụ thuộc vào một single gate.
