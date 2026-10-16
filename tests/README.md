# OU Results - Testing & Verification Guide

This directory (`tests/`) is the central hub for all testing, load verification, and manual API interaction in the OU Results distributed system.

---

## Directory Structure

```
tests/
├── api.http                         # Ready-to-run HTTP requests (VS Code REST Client / Postman)
├── read/                            # Read-path k6 scenarios & orchestration runners
│   ├── read-baseline.js             # k6 VU-ramp load test
│   ├── read-arrival.js              # k6 open-model ramping arrival-rate test
│   ├── gateway-protection.js        # k6 invalid roll & burst scenario
│   ├── run-baseline.ps1             # Runner for VU baseline comparison
│   ├── run-arrival.ps1              # Runner for arrival-rate tests (naive & optimized)
│   ├── run-gateway-protection.ps1   # Runner for gateway validation & rate limits
│   ├── run-hikari-observation.ps1   # Samples HikariCP active/pending connections
│   └── run-scaling.ps1              # Multi-instance scaling orchestrator (1/2/3 instances)
└── write/                           # Write-path pipeline & durability tests
    ├── test-write-pipeline.ps1      # End-to-end smoke test (CSV -> Shards verification)
    └── verify-write-path-scale.ps1  # 5k/10k scale, idempotency, atomicity, DLQ test suite
```

---

## 1. Interactive Manual Testing (`api.http`)

The `tests/api.http` file allows testing without writing commands.

### How to use:
* **VS Code:** Install the **REST Client** extension (`humao.rest-client`). Open `tests/api.http` and click the **"Send Request"** button above any request.
* **IntelliJ IDEA / WebStorm:** Built-in support; open `tests/api.http` and click the green run icon.
* **Postman:** You can import `tests/api.http` directly using **Import > Raw text / File**.

### Key Scenarios in `api.http`:
1. **Health Checks:** Gateway, Eureka, Read Service, Ingestion Service, and RabbitMQ.
2. **Student Result Lookups:**
   - Shard 1 College (`160423733001`)
   - Shard 2 College (`160823733001`)
   - Negative Cache Test (`160423733999` non-existent student)
   - Edge Rejection (`16042373` bad format -> HTTP 400 at gateway)
   - Unknown College Rejection (`999923733001` -> HTTP 400 at gateway)
   - Circuit Breaker Fallback endpoint (`/fallback/read`)
3. **Admin Write Path:**
   - Multipart CSV upload via Gateway (with `X-Admin-Api-Key`)
   - Direct Ingestion Service upload
   - Unauthorized upload attempt (HTTP 401)
4. **Metrics & Resilience:**
   - Cache hit/miss counters
   - Circuit breaker call counts per shard
   - HikariCP active/pending connections
5. **RabbitMQ Monitoring:**
   - `results.write` queue status & message backlog
   - `results.write.dlq` dead-letter queue count

---

## 2. Read Path Load Testing (`tests/read/`)

> [!NOTE]
> Ensure the stack is started before running these tests. Use `-LoadTest` when testing through the gateway so the rate limiter doesn't cap the test client.

### A. Quick Baseline Check (Naive vs. Optimized)
Compares direct-database queries against the cached read path:
```powershell
# Test Naive profile (Direct DB queries)
.\tests\read\run-baseline.ps1 -Profile naive -Vus 25,50,100

# Test Optimized profile (Redis cache-aside)
.\tests\read\run-baseline.ps1 -Profile optimized -Vus 25,50,100
```

### B. Standard Arrival-Rate Test (Realistic Result-Day Traffic)
Simulates realistic student arrivals with a ramping arrival rate:
```powershell
# 75 req/s spike test (Hot set mode: repeated lookups)
.\tests\read\run-arrival.ps1 -Profile optimized -Peaks 75 -Mode hot -BaseUrl http://localhost:8081

# High-throughput stress test (150, 300, 500 req/s)
.\tests\read\run-arrival.ps1 -Profile optimized -Peaks 150,300,500 -Runs 3 -Mode hot -BaseUrl http://localhost:8081 -MaxVus 2000
```

### C. Gateway Protection Test
Proves edge validation blocks bad requests and sheds cold bursts safely:
```powershell
# 1. Flush Redis cache first to test clean slate
docker compose exec -T redis-cache redis-cli FLUSHDB

# 2. Run protection scenario
.\tests\read\run-gateway-protection.ps1
```

### D. Horizontal Scaling Test (1 vs. 2 vs. 3 Instances)
Orchestrates 1, 2, and 3 read instances via Eureka and measures performance:
```powershell
.\tests\read\run-scaling.ps1
```

### E. HikariCP Connection Pool Observation
Monitors HikariCP thread pool starvation during load:
```powershell
.\tests\read\run-hikari-observation.ps1 -Profile naive
```

---

## 3. Write Path Verification (`tests/write/`)

> [!IMPORTANT]
> The write stack must be active:
> `.\scripts\start-stack.ps1 -Profile optimized -Write`

### A. Quick Smoke Test (`test-write-pipeline.ps1`)
Uploads a fresh synthetic exam (2 students for Shard 1, 2 for Shard 2) and verifies database insertion:
```powershell
.\tests\write\test-write-pipeline.ps1 -FreshExam
```

To test with the 5,000-row sample CSV:
```powershell
.\tests\write\test-write-pipeline.ps1
```

### B. Full Scale, Durability & Atomicity Suite (`verify-write-path-scale.ps1`)
Runs all 6 Phase 4 verification scenarios:
1. 5,000-Row upload & persistence time measurement
2. 10,000-Row upload & memory stability check
3. Upload size limit test (oversized file rejection)
4. Idempotency test (re-upload produces zero duplicate rows)
5. Atomicity & Rollback test (mid-batch failure routes to DLQ, 0 rows written)
6. Shard distribution validation (even 50/50 split across shards)

```powershell
.\tests\write\verify-write-path-scale.ps1
```

---

## 4. Test Results & Reports

- **Raw Results & JSON:** Located in `load-tests/results/` (`naive/`, `optimized/`, `gateway/`, `comparison/`).
- **Charts & Summaries:** Generated using Python in `load-tests/report/`:
  ```powershell
  python .\load-tests\report\make_report.py --profile optimized
  python .\load-tests\report\make_comparison.py
  python .\load-tests\report\make_scaling.py
  ```
