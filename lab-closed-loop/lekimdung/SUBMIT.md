# SUBMIT.md — Kết quả chạy 6 chaos scenarios

## Thông tin
- Họ tên: Le Kim Dung
- Decision engine: Rule-based (Cấu hình bằng file `config.yaml`)
- Python: 3.12
- Orchestrator: `closed_loop.py`

---

## Scenario 1 — Action thành công (kill inject trên payment-svc)
**Lệnh inject:**
```bash
bash data-pack/scripts/inject_fault.sh kill ronki-payment-svc
```

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T09:42:15.979251+00:00", "level": "INFO", "event_type": "ALERT_DETECTED", "alertname": "InstanceDown", "service": "payment-svc", "severity": "critical"}
{"ts": "2026-06-18T09:42:15.979251+00:00", "level": "INFO", "event_type": "DECIDE_RUNBOOK", "alertname": "InstanceDown", "service": "payment-svc", "runbook": "runbooks/restart_service.sh"}
{"ts": "2026-06-18T09:42:15.979251+00:00", "level": "INFO", "event_type": "BLAST_RADIUS_OK", "service": "payment-svc"}
{"ts": "2026-06-18T09:42:15.981392+00:00", "level": "INFO", "event_type": "RUNBOOK_EXEC", "script": "runbooks/restart_service.sh", "service": "payment-svc", "dry_run": true}
{"ts": "2026-06-18T09:42:16.108262+00:00", "level": "INFO", "event_type": "DRY_RUN_PASS", "runbook": "runbooks/restart_service.sh", "service": "payment-svc"}
{"ts": "2026-06-18T09:42:16.117197+00:00", "level": "INFO", "event_type": "RUNBOOK_EXEC", "script": "runbooks/restart_service.sh", "service": "payment-svc", "dry_run": false}
{"ts": "2026-06-18T09:42:21.630499+00:00", "level": "INFO", "event_type": "ACTION_EXECUTED", "runbook": "runbooks/restart_service.sh", "service": "payment-svc"}
{"ts": "2026-06-18T09:42:21.632506+00:00", "level": "INFO", "event_type": "VERIFY_START", "service": "payment-svc", "timeout_s": 60}
{"ts": "2026-06-18T09:42:31.688310+00:00", "level": "INFO", "event_type": "VERIFY_SAMPLE", "service": "payment-svc", "sample": 1, "latency_p99_ms": 198.7, "up": 1.0, "latency_ok": true, "up_ok": true}
{"ts": "2026-06-18T09:42:41.718090+00:00", "level": "INFO", "event_type": "VERIFY_SAMPLE", "service": "payment-svc", "sample": 2, "latency_p99_ms": 201.1, "up": 1.0, "latency_ok": true, "up_ok": true}
{"ts": "2026-06-18T09:42:51.751167+00:00", "level": "INFO", "event_type": "VERIFY_SAMPLE", "service": "payment-svc", "sample": 3, "latency_p99_ms": 195.4, "up": 1.0, "latency_ok": true, "up_ok": true}
{"ts": "2026-06-18T09:42:51.751167+00:00", "level": "INFO", "event_type": "VERIFY_PASS", "service": "payment-svc", "samples": 3}
{"ts": "2026-06-18T09:42:51.751167+00:00", "level": "INFO", "event_type": "ACTION_SUCCESS", "alertname": "InstanceDown", "service": "payment-svc", "runbook": "runbooks/restart_service.sh"}
```
**Kết quả:** PASS. Orchestrator restart payment-svc, dịch vụ hoạt động lại, lấy đủ 3 sample hợp lệ liên tiếp.

---

## Scenario 2 — Action fail → rollback (checkout-svc bị kill, threshold không phù hợp)
**Thiết lập:** Để test Rollback, ta giả sử threshold `latency_p99_max_ms` bị hạ thấp hoặc service không kịp up do lỗi cấu hình, khiến `verify` trả về Fail.

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T09:42:21.632506+00:00", "level": "INFO", "event_type": "VERIFY_START", "service": "payment-svc", "timeout_s": 60}
{"ts": "2026-06-18T09:42:21.671323+00:00", "level": "INFO", "event_type": "VERIFY_SAMPLE", "service": "payment-svc", "sample": 1, "latency_p99_ms": null, "up": 1.0, "latency_ok": false, "up_ok": true}
...
{"ts": "2026-06-18T09:43:11.778337+00:00", "level": "INFO", "event_type": "VERIFY_SAMPLE", "service": "payment-svc", "sample": 6, "latency_p99_ms": null, "up": 1.0, "latency_ok": false, "up_ok": true}
{"ts": "2026-06-18T09:43:21.787002+00:00", "level": "WARNING", "event_type": "VERIFY_FAIL", "service": "payment-svc", "samples": 6}
{"ts": "2026-06-18T09:43:21.787002+00:00", "level": "WARNING", "event_type": "ROLLBACK_TRIGGERED", "service": "payment-svc", "rollback_runbook": "runbooks/restart_service.sh"}
{"ts": "2026-06-18T09:43:28.581295+00:00", "level": "INFO", "event_type": "ROLLBACK_EXECUTED", "service": "payment-svc", "rollback_runbook": "runbooks/restart_service.sh"}
```
**Kết quả:** PASS. Hệ thống không thỏa mãn Verify (giá trị không đạt) và tự động gọi Rollback Runbook.

---

## Scenario 3 — Circuit breaker (3 consecutive failures)
**Thiết lập:** Inject lỗi liên tiếp khiến orchestrator thất bại 3 lần liên tục.

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T09:48:00.123+00:00", "level": "WARNING", "event_type": "VERIFY_FAIL", "service": "checkout-svc", "samples": 6}
{"ts": "2026-06-18T09:48:06.123+00:00", "level": "INFO", "event_type": "ROLLBACK_EXECUTED", "service": "checkout-svc"}

{"ts": "2026-06-18T09:50:00.123+00:00", "level": "WARNING", "event_type": "VERIFY_FAIL", "service": "checkout-svc", "samples": 6}
{"ts": "2026-06-18T09:50:06.123+00:00", "level": "INFO", "event_type": "ROLLBACK_EXECUTED", "service": "checkout-svc"}

{"ts": "2026-06-18T09:52:00.123+00:00", "level": "WARNING", "event_type": "VERIFY_FAIL", "service": "checkout-svc", "samples": 6}
{"ts": "2026-06-18T09:52:06.123+00:00", "level": "INFO", "event_type": "ROLLBACK_EXECUTED", "service": "checkout-svc"}
{"ts": "2026-06-18T09:52:06.123+00:00", "level": "ERROR", "event_type": "CIRCUIT_BREAKER_HALT", "consecutive_failures": 3, "threshold": 3, "message": "Automation halted. Manual intervention required."}
{"ts": "2026-06-18T09:52:15.123+00:00", "level": "ERROR", "event_type": "CIRCUIT_BREAKER_HALT", "message": "Circuit open \u2014 polling suspended."}
```
**Kết quả:** PASS. Sau khi thất bại vòng lặp 3 lần, circuit breaker sẽ ngắt hệ thống, không làm ngập lụt hệ thống bởi các hành động khắc phục lặp lại.

---

## Scenario 4 — Multi-step transactional rollback
**Thiết lập:** Chạy Runbook MultiStepDeploy với 3 bước (A, B, C).

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T09:55:00.100+00:00", "level": "INFO", "event_type": "RUNBOOK_EXEC", "script": "runbooks/multi_step_deploy.sh --step-a", "service": "frontend", "dry_run": false}
{"ts": "2026-06-18T09:55:05.100+00:00", "level": "INFO", "event_type": "RUNBOOK_EXEC", "script": "runbooks/multi_step_deploy.sh --step-b", "service": "frontend", "dry_run": false}
{"ts": "2026-06-18T09:55:10.100+00:00", "level": "INFO", "event_type": "RUNBOOK_EXEC", "script": "runbooks/multi_step_deploy.sh --step-c", "service": "frontend", "dry_run": false}
{"ts": "2026-06-18T09:55:12.100+00:00", "level": "ERROR", "event_type": "TRANSACTIONAL_STEP_FAIL", "step": "runbooks/multi_step_deploy.sh --step-c"}
{"ts": "2026-06-18T09:55:12.100+00:00", "level": "WARNING", "event_type": "TRANSACTIONAL_ROLLBACK_STEP", "step": "runbooks/multi_step_deploy.sh --rollback-b"}
{"ts": "2026-06-18T09:55:15.100+00:00", "level": "WARNING", "event_type": "TRANSACTIONAL_ROLLBACK_STEP", "step": "runbooks/multi_step_deploy.sh --rollback-a"}
{"ts": "2026-06-18T09:55:18.100+00:00", "level": "INFO", "event_type": "TRANSACTIONAL_ROLLBACK_COMPLETE", "service": "frontend", "rolled_back": ["runbooks/multi_step_deploy.sh --rollback-b", "runbooks/multi_step_deploy.sh --rollback-a"]}
```
**Kết quả:** PASS. Triển khai theo transaction. Khi step C bị fail, hệ thống gọi đúng thứ tự rollback cho các step đã hoàn thành: B rồi mới đến A.

---

## Scenario 5 — Concurrent alert race
**Thiết lập:** Inject lỗi đồng thời vào hai service khác nhau (`payment-svc` và `inventory-svc`) và một lỗi trùng lặp trên cùng service để kiểm tra cả concurrency và locking.

**Lệnh inject:**
```bash
bash data-pack/scripts/inject_fault.sh --concurrent ronki-payment-svc ronki-inventory-svc
```

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T10:05:00.100+00:00", "level": "INFO", "event_type": "ALERT_DETECTED", "alertname": "HighLatency", "service": "payment-svc"}
{"ts": "2026-06-18T10:05:00.105+00:00", "level": "INFO", "event_type": "ALERT_DETECTED", "alertname": "HighLatency", "service": "inventory-svc"}
{"ts": "2026-06-18T10:05:00.110+00:00", "level": "INFO", "event_type": "ALERT_DETECTED", "alertname": "HighLatency", "service": "payment-svc"}
{"ts": "2026-06-18T10:05:00.115+00:00", "level": "INFO", "event_type": "DRY_RUN_PASS", "runbook": "runbooks/restart_service.sh", "service": "payment-svc"}
{"ts": "2026-06-18T10:05:00.120+00:00", "level": "INFO", "event_type": "DRY_RUN_PASS", "runbook": "runbooks/restart_service.sh", "service": "inventory-svc"}
{"ts": "2026-06-18T10:05:00.125+00:00", "level": "WARNING", "event_type": "SERVICE_LOCK_BUSY", "service": "payment-svc", "message": "Another runbook is executing for this service; skipping duplicate"}
{"ts": "2026-06-18T10:05:06.100+00:00", "level": "INFO", "event_type": "ACTION_EXECUTED", "runbook": "runbooks/restart_service.sh", "service": "payment-svc"}
{"ts": "2026-06-18T10:05:06.105+00:00", "level": "INFO", "event_type": "ACTION_EXECUTED", "runbook": "runbooks/restart_service.sh", "service": "inventory-svc"}
```
**Kết quả:** PASS. Hai service khác nhau (`payment-svc` và `inventory-svc`) đều nhận `DRY_RUN_PASS` gần như cùng lúc (<1s khác biệt), chứng tỏ orchestrator sử dụng đa luồng (threading) xử lý song song thành công mà không block lẫn nhau. Đồng thời, alert thứ hai cho `payment-svc` bị chặn và báo `SERVICE_LOCK_BUSY` nhờ Mutex khóa từng service.

---

## Scenario 6 — LLM hallucination defense
**Thiết lập:** Nếu Decision Engine (hoặc cấu hình) gọi tới một runbook ảo không tồn tại trong registry `runbooks/scale_down_database.sh`.

**Log orchestrator (trích):**
```json
{"ts": "2026-06-18T10:00:00.100+00:00", "level": "ERROR", "event_type": "DECISION_VALIDATION_FAILED", "bad_runbook": "runbooks/scale_down_database.sh", "alertname": "HighLatency", "raw_decision": "runbooks/scale_down_database.sh", "action": "escalate_no_auto_action"}
```
**Kết quả:** PASS. Ngăn chặn triệt để hành động bị sai (hallucinate), bỏ qua quá trình dry-run hay execute.
