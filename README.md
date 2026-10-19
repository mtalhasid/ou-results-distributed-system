# OU Results - High-Concurrency Distributed System for Result-Day Traffic

A high-throughput, fault-tolerant distributed system combining a sub-10ms cached read path, sharded PostgreSQL databases, an asynchronous bulk CSV write pipeline, and an atomic multi-shard publishing saga.

---

## 1. The Problem: Result-Day Traffic Shock & Publishing Complexity

University examination portals face extreme operational challenges on result announcement day:

* **Massive Concurrency Spikes:** Tens of thousands of students, parents, and colleges refresh the portal simultaneously within minutes of an announcement.
* **Database Connection Starvation:** Traditional portals query relational databases directly on every HTTP request. Each query occupies a database connection pool thread (e.g., HikariCP) for hundreds of milliseconds.
* **Cascading Read Collapse:** At just 75 requests/sec, direct database connection pools saturate completely. Response times explode past **6.4 seconds**, and **1 in 5 students (19%) get dropped** with connection timeouts.
* **Bulk Write Ingestion Bottlenecks:** Uploading and parsing raw result CSV sheets containing 10,000+ student records can lock database tables, consume excessive application heap memory, and degrade the read path.
* **Multi-Shard Publishing Dilemma:** Flipping exam results from draft to published across physically isolated database shards without distributed two-phase locking (2PC) risks partial visibility, publisher crashes, or data inconsistency.

---

## 2. The Distributed System Solution

This project re-architects the portal using a layered, event-driven distributed architecture that isolates read and write workloads, shields the databases, and maintains sub-10ms response times under extreme load:

![OU Results Distributed System Architecture](./docs/diagrams/architecture.png)

### Architectural Pillars

#### A. Read Path: Perimeter Defense & Sub-10ms Serving
1. **Edge Perimeter Defense:** Malformed roll numbers and college codes are validated in memory at the **Spring Cloud Gateway** in under 10 ms with **zero backend CPU or database cost**.
2. **Distributed Token-Bucket Rate Limiting:** Abusive clients exceeding burst limits receive HTTP 429 via Redis State without touching internal microservices.
3. **Dynamic Round-Robin Load Balancing:** Read service instances register dynamically with **Eureka**, allowing horizontal scaling across instances on demand (`lb://result-read-service`).
4. **In-Memory Cache-Aside:** Successful queries are cached in **Redis** with a 10-minute TTL, serving 95%+ of repeated lookups in **~5–10 ms**.
5. **Database Sharding & Read Replicas:** Cache misses route to dedicated PostgreSQL read replicas, partitioned by college code across independent shards (`Shard 1` and `Shard 2`).
6. **Bulkhead & Circuit Breaker Isolation:** Resilience4j bulkheads strictly cap database queries to 25 concurrent slots per shard. Circuit breakers fast-fail within 25 ms if a database shard fails, protecting healthy shards.

#### B. Write Pipeline: Asynchronous Streaming & Batching
1. **Streaming CSV Ingestion:** The **Result Ingestion Service** (Node.js/Express/TypeScript) streams multipart CSV uploads using Fast-CSV, validating headers and batching student records into college-grouped chunks without memory bloat.
2. **Durable Asynchronous Queuing:** Batches are published to **RabbitMQ** (`results.write`), decoupling HTTP ingestion from database persistence with Dead-Letter Queue (`results.write.dlq`) safety.
3. **Idempotent Multi-Shard Persistence:** The **Result Persistence Service** (Spring Boot 3) consumes batches and performs idempotent batch upserts (`ON CONFLICT (exam_id, roll_no, semester) DO UPDATE`) across sharded PostgreSQL databases.

#### C. Publishing Saga: Multi-Shard Atomicity Without 2PC
1. **Local Transactional Flips:** Each shard independently executes `UPDATE results SET published = true WHERE exam_id = ? AND published = false`.
2. **Point of No Return (`SHARDS_PUBLISHED`):** Once both shards successfully flip rows, the exam crosses the point of no return-rollbacks are strictly prohibited to prevent data inconsistency.
3. **Broker-Acknowledged Event Emission:** Emits a `results.published` event to **Apache Kafka** with `acks=all`, synchronously verified before acknowledging the AMQP command.
4. **Gentle Cache Warm-Up:** The read service listens to the Kafka event log and warms Redis in 200-row pages with a 100ms pacing delay, preventing cache stampedes.

---

## 3. Tech Stack

| Layer / Service | Technologies | Key Responsibilities |
|---|---|---|
| **API Gateway** | Spring Cloud Gateway, Resilience4j, Project Reactor | Edge validation, token-bucket rate limiting (Redis state), Eureka routing, circuit breaker |
| **Service Discovery** | Spring Cloud Netflix Eureka | Dynamic service registry and client-side load balancing (`lb://`) |
| **Result Read Service** | Java 21, Spring Boot 3, Spring Data JPA, Virtual Threads | Optimized cache-aside, per-shard bulkheads, replica routing, Kafka cache warm-up |
| **Result Ingestion Service** | Node.js 22, Express, TypeScript, Fast-CSV, Multer, Pino | Admin CSV upload streaming, college grouping, RabbitMQ batch publishing |
| **Result Persistence Service**| Java 21, Spring Boot 3, Spring AMQP, Spring Kafka, JDBC | Batch persistence worker, multi-shard publishing saga, compensating rollbacks |
| **Message Broker (Job Queue)**| RabbitMQ 3.13 (Docker), AMQP 0-9-1 | Durable task queues (`results.write`, `results.publish`) and Dead-Letter Queues (DLQ) |
| **Event Streaming (Log)** | Apache Kafka (KRaft mode, Docker) | Replayable event log (`results.published`) for cache warm-up and notification consumers |
| **Caching & Rate Limit State**| Redis 7 (Alpine Docker), Spring Data Redis | LRU result cache (10-min TTL) and distributed token-bucket rate limiting state |
| **Sharded Databases** | PostgreSQL 16 (Neon Serverless Shards 1 & 2) | Physical sharding by college code; primary write and read-replica splitting |
| **Benchmarking & Testing** | k6, PowerShell, Python, Matplotlib | Arrival-rate load testing, fault-injection simulations, report generation |
| **Infrastructure** | Docker, Docker Compose, Windows PowerShell | Containerized dependencies and automated stack orchestration scripts |

---

## 4. Headline Benchmark & Verification Results

### A. Read-Path Performance (Single Laptop vs. Cloud PostgreSQL)

| Architecture | Load Tier | p95 Latency | Avg Latency | Dropped Requests | Success Rate |
|---|---:|---:|---:|---:|---:|
| **Naive (Direct DB)** | 50 req/s | 1,020 ms | 470 ms | 0.46% (9) | 99.54% |
| **Naive (COLLAPSE)** | **75 req/s** | **6,480 ms** | **3,190 ms** | **19.06% (555 / 2,912)** | **80.94%** |
| **Optimized Read** | 75 req/s | **10 ms** | **30 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test** | **150 req/s** | **9.1 ms** | **4.7 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test (Warm)** | **300 req/s** | **8.6 ms** | **20.2 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test** | **500 req/s** | **9.3 ms** | **6.0 ms** | **0.00% (0)** | **100.00%** |

> **Impact:** The optimized distributed read path handled **at least 9x the throughput** of the naive baseline (500 req/s with 100% completion vs naive 54.58 req/s saturation ceiling) while cutting steady-state p95 response times from **6.48 seconds down to 9.26 milliseconds** (a **99.8% latency reduction**).

![p95 Latency Comparison](./load-tests/results/comparison/hot-p95.png)

![Delivered Arrivals Comparison](./load-tests/results/comparison/hot-delivered.png)

---

### B. Write Pipeline & Publishing Saga Verification

| Test Scenario | Offer / Scale | Measured Outcome | Resilience Guarantee |
|---|---|---|---|
| **CSV Ingestion Scale** | 10,000 rows across 2 shards | Persisted in 90.08s (WAN), 0 DLQ drops, peak heap <22 MB | Streamed backpressure |
| **Upload Size Boundary** | 52.01 MB oversized CSV | Cleanly rejected at Gateway with HTTP 400 | Edge admission control |
| **Idempotent Re-Upload** | 5,000 duplicate rows | 0 duplicate rows created; existing records updated in place | SQL `ON CONFLICT DO UPDATE` |
| **Broker Crash Mid-Queue** | Hard restart of RabbitMQ with queued jobs | All messages persisted to disk; consumed upon broker restart | Queue disk durability |
| **Shard Failure Rollback** | Simulated Shard 2 failure before point of no return | Shard 1 rolled back to `published = false`; exam marked `FAILED` | Transactional rollback |
| **Crash at Point of No Return**| JVM killed (`halt(137)`) at `SHARDS_PUBLISHED` | Redelivered message resumed forward to `PUBLISHED` | Idempotent forward recovery |
| **Kafka Outage Recovery** | Kafka down past point of no return | Retried to DLQ; exam safely kept at `SHARDS_PUBLISHED` (no rollback) | Point of no return safety |

👉 **For complete run-by-run tables, failure traces, and scaling charts, see [docs/results.md](docs/results.md).**

---

## 5. Quickstart

### Prerequisites
* **Java:** JDK 21+ (`java -version`)
* **Node.js:** Node 20+ (`node -v`)
* **Docker:** Docker Desktop running (`docker info`)

### 1. Setup Environment
```powershell
cp .env.example .env
# Configure your Neon PostgreSQL connection strings and ADMIN_API_KEY in .env
```

### 2. Build Services
```powershell
.\scripts\build.ps1
```

### 3. Start the Stack

```powershell
# Read-only stack (Eureka, Redis Cache, Redis State, Read Service, API Gateway)
.\scripts\start-stack.ps1 -Profile optimized

# Full stack including Write Pipeline (starts RabbitMQ, Ingestion Service, Persistence Worker)
.\scripts\start-stack.ps1 -Profile optimized -Write

# Horizontal scaling with 3 read instances
.\scripts\start-stack.ps1 -Profile optimized -Instances 3
```

### 4. Verify & Interact

```powershell
# Check health of API Gateway (Port 8081)
curl.exe http://localhost:8081/actuator/health

# Query a student result through Gateway
curl.exe http://localhost:8081/api/results/160423733001

# Upload a results CSV through Gateway (Admin API key required)
curl.exe -i -X POST "http://localhost:8081/admin/results/upload" `
  -H "X-Admin-Api-Key: $env:ADMIN_API_KEY" `
  -F "file=@load-tests/seed/out/upload-sample.csv" `
  -F "title=July-August 2026 Examinations" `
  -F "resultDate=2026-08-15"

# Publish the examination across all shards
curl.exe -i -X POST "http://localhost:8081/admin/exams/EXAM_2026_01/publish" `
  -H "X-Admin-Api-Key: $env:ADMIN_API_KEY"
```

### 5. Stop the Stack
```powershell
# Stop services (keeps Docker containers running)
.\scripts\stop-stack.ps1

# Stop services AND tear down Docker containers
.\scripts\stop-stack.ps1 -StopContainers
```

👉 **For standalone server commands, Docker operations, and k6 benchmark guides, see [docs/getting-started.md](docs/getting-started.md).**

---

## 6. Repository Layout

```
├── api-gateway/                 # Reactive gateway: validation, rate limiting, circuit breaker
├── service-discovery/           # Eureka service registry
├── result-read-service/         # Read tier: naive & optimized profiles, Redis cache-aside, cache warmer
├── result-ingestion-service/    # Write tier: Express/TypeScript CSV upload, validation, RabbitMQ producer
├── result-persistence-service/  # Write tier: RabbitMQ batch consumer, multi-shard JDBC saga worker
├── contracts/                   # Shard map configuration and shared schemas
├── scripts/                     # Stack orchestration scripts (build, start, stop)
├── tests/                       # Automated test suites (read spike tests, write resilience, publish demos)
├── load-tests/                  # k6 benchmark artifacts, raw JSON reports, charts, and seed data
└── docs/                        # Detailed guides: results.md, system-design.md, getting-started.md, tradeoffs.md
```