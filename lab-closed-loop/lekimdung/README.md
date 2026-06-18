# Ronki Closed-Loop Auto-Remediation

Hệ thống điều phối xử lý sự cố (Closed-Loop Orchestrator) viết bằng Python phục vụ tự động khắc phục các lỗi HighLatency, HighErrorRate và InstanceDown.

## Cấu trúc thư mục

```
lekimdung/
├── closed_loop.py          # Orchestrator chính, vòng lặp 5 checkpoints
├── config.yaml             # File cấu hình (runbooks, thresholds)
├── engine/                 # Các module hỗ trợ: logger, metrics, safety, verify
├── runbooks/               # Các Bash script (Dry-run và Execute)
│   ├── clear_cache.sh
│   ├── multi_step_deploy.sh
│   ├── restart_service.sh
│   └── scale_replicas.sh
├── DESIGN.md               # Kiến trúc thiết kế (Rule-based, Thresholds, Manual Reset...)
└── SUBMIT.md               # Nhật ký các Chaos Scenario test
```

## Cách chạy

1. **Start hệ thống giả lập:**
   ```bash
   # Trong thư mục lab-closed-loop
   bash data-pack/scripts/start_stack.sh
   ```
2. **Khởi động Orchestrator:**
   ```bash
   # Di chuyển vào thư mục lekimdung/
   cd lekimdung
   python closed_loop.py --config config.yaml
   ```
3. **Tiêm lỗi (Inject Fault):**
   ```bash
   # (Trong một terminal khác)
   bash ../data-pack/scripts/inject_fault.sh kill ronki-payment-svc
   ```
4. **Xem Prometheus Metrics của Orchestrator:**
   Truy cập `http://localhost:9100` để xem các metric `closed_loop_actions_total`, `closed_loop_circuit_breaker_state`...
