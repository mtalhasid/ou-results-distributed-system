# OU Results - Testing & Verification Guide

This directory (`tests/`) contains all load testing, resilience verification, and API interaction scripts for the OU Results platform.

> [!NOTE]
> **Naive vs. Optimized Profiles:** In the read load tests, direct database queries (`naive`) versus Redis cache-aside (`optimized`) is controlled via the `-Profile` parameter on `run-spike-test.ps1`, not through separate test files.

---

## 1. Read Tests (Measure Speed & Report Numbers)

These benchmarks test latency, throughput, and saturation under synthetic student traffic:

| Script & Runner | What It Proves | Example Command |
|---|---|---|
| **`tests/read/run-spike-test.ps1`**<br>*(scenario: `spike-test.js`)* | Measures read throughput and p95 latency under ramping student arrival rates (75 to 500 req/s) simulating result-day spikes across `naive` and `optimized` profiles. | `.\tests\read\run-spike-test.ps1 -Profile optimized -Peaks 75 -Mode hot -BaseUrl "http://localhost:8081"` |
| **`tests/read/run-user-ramp.ps1`**<br>*(scenario: `user-ramp.js`)* | Measures direct-database connection pool saturation and throughput ceilings under fixed concurrent users (25, 50, 100 VUs), producing the baseline figures in `docs/results.md` (Section 1.B). | `.\tests\read\run-user-ramp.ps1 -Profile naive -Vus 25,50,100` |
| **`tests/read/run-gateway-protection.ps1`**<br>*(scenario: `gateway-protection.js`)* | Measures edge format rejection speed (HTTP 400 in <5ms) and token-bucket rate limiting (HTTP 429) to prove backend shielding during bursts. | `.\tests\read\run-gateway-protection.ps1` |
| **`tests/read/run-scaling.ps1`** | Orchestrates Eureka discovery to measure horizontal throughput scaling and latency reduction across 1, 2, and 3 read instances. | `.\tests\read\run-scaling.ps1` |

---

## 2. Write & Publish Tests (Check Behaviour & Report Pass / Fail)

These suites verify transactional safety, fault tolerance, and multi-shard coordination:

| Script | What It Proves | Example Command |
|---|---|---|
| **`tests/write/upload-smoke.ps1`** | Verifies asynchronous CSV upload, RabbitMQ batch queueing, and multi-shard database insertion end-to-end with a minimal batch. | `.\tests\write\upload-smoke.ps1 -FreshExam` |
| **`tests/write/upload-resilience.ps1`** | Verifies 5k/10k row scaling, 50MB upload limits, duplicate re-upload idempotency, and transactional atomicity rollback with DLQ routing. Generates required test files dynamically and cleans up automatically. | `.\tests\write\upload-resilience.ps1` |
| **`tests/publish/publish-happy-path.ps1`** | Verifies the complete examination publishing saga: draft isolation, atomic shard status flip, Kafka event emission, Redis gentle cache warm-up, and strong read consistency. | `.\tests\publish\publish-happy-path.ps1` |
| **`tests/publish/publish-failure-demos.ps1`** | Verifies the three failure & self-healing demonstrations: rollback before point of no return, forward recovery after JVM crash, and DLQ routing during Kafka outages. | `.\tests\publish\publish-failure-demos.ps1` |

---

## 3. Interactive Manual Testing

* **`tests/api.http`**: Collection of ready-to-run HTTP requests for VS Code REST Client, IntelliJ HTTP Client, or Postman covering health checks, result queries, administrative uploads, metrics, and queue inspection.
