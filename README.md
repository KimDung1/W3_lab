# Lab W3 — MLOps Lifecycle & Closed-Loop Auto-Remediation

Repository này chứa bài nộp cho 2 bài lab thực hành chuyên sâu:
1. **Lab MLOps Lifecycle (`lab-mlops-lifecycle/`)**: Xây dựng một MLOps pipeline hoàn chỉnh từ train model, register, serve, giám sát data drift và concept drift, tự động retrain và blue-green swap.
2. **Lab Closed-Loop Auto-Remediation (`lab-closed-loop/`)**: Xây dựng orchestrator tự động hóa việc phục hồi dịch vụ (auto-remediation) dựa trên cảnh báo từ Prometheus/Alertmanager, với các cơ chế bảo vệ an toàn như blast-radius, circuit breaker và auto-rollback.

**Tác giả**: Lê Kim Dung

## Cấu trúc thư mục

```text
├── lab-mlops-lifecycle/
│   └── lekimdung/        # Chứa pipeline.py, serve.py, drift_detector.py, retrain.py, DESIGN.md, SUBMIT.md
└── lab-closed-loop/
    └── lekimdung/        # Chứa closed_loop.py, engine/, runbooks/, DESIGN.md, SUBMIT.md
```

Tất cả các kịch bản thử nghiệm (stress scenarios) và tài liệu thiết kế (DESIGN.md) đều đã được thực thi và chứng minh kết quả trong SUBMIT.md của từng bài.
