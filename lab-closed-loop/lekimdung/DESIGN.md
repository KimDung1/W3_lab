# DESIGN.md — Ronki Closed-Loop Orchestrator

## 1. Decision engine: Rule-based hay LLM-based?

**Chọn: Rule-based.**

Lý do: Hệ thống hiện tại có 3 loại cảnh báo cố định là `HighLatency`, `HighErrorRate`, `InstanceDown` và các kịch bản khắc phục (runbook) tương ứng đã được xác định rất rõ ràng. Việc sử dụng Rule-based giúp tốc độ phản hồi cực kỳ nhanh, gần như tức thời so với việc phải chờ đợi API LLM xử lý ngôn ngữ. Thêm vào đó, Rule-based mang lại tính chắc chắn (deterministic) cao, đảm bảo 100% cảnh báo được map với runbook đúng chuẩn mà không lo ngại về vấn đề hallucination. Nó cũng giúp tiết kiệm chi phí API và giảm bớt sự phức tạp khi không cần phải xây dựng fallback mechanism cho trường hợp API LLM không khả dụng. Trade-off duy nhất là chúng ta cần cập nhật file cấu hình thủ công mỗi khi có thêm loại cảnh báo mới, nhưng với quy mô bài toán hiện tại thì đây là sự đánh đổi hoàn toàn hợp lý để đảm bảo độ tin cậy tuyệt đối trong môi trường auto-remediation.

## 2. Blast-radius config

```yaml
blast_radius:
  max_actions_per_minute: 3
  max_restarts_per_service_per_hour: 5
```

**Lý do chọn giá trị:**
Hệ thống tổng cộng có 5 services hoạt động liên đới với nhau. Nếu có quá nhiều hành động được thực hiện trong một phút (ví dụ khởi động lại toàn bộ hệ thống cùng lúc), tải trên cơ sở hạ tầng có thể bị tăng đột biến và tạo ra hiệu ứng thundering herd gây thêm lỗi cục bộ. Do đó, giới hạn `max_actions_per_minute: 3` giúp hệ thống có thời gian "thở" và dần phục hồi sau mỗi hành động thay vì bị quá tải. Đối với giới hạn `max_restarts_per_service_per_hour: 5`, việc phải restart một service quá 5 lần trong một giờ chứng tỏ service đó đang bị lỗi nghiêm trọng từ bên trong (ví dụ: lỗi logic code, crash do thiếu bộ nhớ). Việc tiếp tục restart mù quáng lúc này là vô nghĩa và có thể làm mất logs quan trọng, do vậy cần ngừng ngay vòng lặp tự động hóa và thông báo để kỹ sư trực tiếp vào cuộc xử lý (escalation).

## 3. Verify step

**Metric kiểm tra:** p99 latency (ms) VÀ trạng thái `up` (1/0).

**Threshold & Timeout:**
Ngưỡng giới hạn (Threshold) được thiết lập là `latency_p99_max_ms: 500` và `up_required: 1`. Mức 500ms là đủ an toàn vì theo baseline, các service có độ trễ p99 ở trạng thái bình thường cao nhất cũng chỉ đạt khoảng 230ms (điển hình như checkout-svc). Nếu độ trễ sau khi khắc phục vẫn vượt 500ms, điều đó chứng tỏ sự cố cốt lõi chưa thực sự được giải quyết. Timeout được cấu hình là 60 giây vì việc khởi động lại service và chờ Prometheus cập nhật metrics cần thời gian trễ nhất định (do scrape interval của Prometheus là 10s). Mức 60s này cho phép Prometheus kịp scrape dữ liệu khoảng 3-4 lần, đồng thời kết hợp với `verify_min_samples: 3` yêu cầu ít nhất 3 mẫu đạt chuẩn liên tiếp để loại bỏ hoàn toàn các sai lệch đo lường ngẫu nhiên (false positive) trước khi kết luận action thành công.

## 4. Circuit breaker reset

**Reset mode: manual.**

Lý do: Khi Circuit Breaker chuyển sang trạng thái mở (open), điều đó có nghĩa là hệ thống đã ghi nhận 3 lần thất bại liên tiếp, có thể do runbook không chạy được hoặc quá trình verify thất bại dẫn đến rollback. Lúc này, hệ thống tự động hóa không còn khả năng kiểm soát và khắc phục được tình trạng của service đó nữa. Nếu cho phép hệ thống tự động reset (auto-reset) sau một khoảng thời gian, sự cố gốc (root cause) có thể vẫn đang tồn tại, dẫn đến orchestrator lại tiếp tục thực hiện hành động sai lầm và tạo ra các "vòng lặp chết" gây hại cho production. Việc yêu cầu manual reset bắt buộc kỹ sư hệ thống phải xem xét kỹ lưỡng, tìm ra root cause và khắc phục triệt để bằng tay rồi mới khởi động lại orchestrator, qua đó đảm bảo an toàn tối đa cho hệ thống.
