# OU Results - Distributed Read-Path Architecture for Result-Day Traffic

A high-throughput, resilient distributed system prototype designed to survive extreme result-day traffic surges on university portals.

---

## 1. The Problem: The Result-Day Traffic Shock

University examination portals face a unique, violent traffic pattern on result publication day:
* **Massive Concurrency Spike:** Tens of thousands of students, parents, and colleges refresh the portal simultaneously within minutes of an announcement.
* **Database Connection Starvation:** Traditional portals query relational databases directly on every HTTP request. Each query occupies a database connection pool thread (e.g., HikariCP) for hundreds of milliseconds.
* **Cascading Failure:** At just 75 requests/sec, direct database connection pools saturate completely. Queues overflow, response times explode past **6.4 seconds**, and **1 in 5 students (19%) get dropped** with connection timeouts.
* **Abusive Traffic:** Frustrated users aggressively hammer the refresh button, compounding the backlog and knocking the entire portal offline.

---

## 2. The Distributed System Solution

This project re-architects the portal using a layered, resilient distributed architecture that shields the database and maintains sub-10ms response times under extreme load:

```
[Students / Clients]
         │
         ▼
[API Gateway (Reactive, Port 8081)]
  ├── Correlation ID Tracking
  ├── Edge Roll Number Validation (Rejects invalid traffic at port 8081)
  ├── Distributed Rate Limiting (Token-Bucket via Redis State)
  └── Circuit Breaker (Fail-fast fallback when downstream is degraded)
         │
         ▼ (Dynamic Round-Robin Load Balancing)
[Service Discovery (Eureka, Port 8761)]
  ├── Read Service Instance 1 (Port 8082)
  ├── Read Service Instance 2 (Port 8083)
  └── Read Service Instance N...
         │
         ├──► [Redis Cache (Port 6379)] ──► Serves 95%+ of repeated lookups in ~5-10ms
         │
         └──► (Cache Miss Only)
              ├── Per-Shard Bulkhead (Caps concurrent DB queries at 25)
              ├── Per-Shard Circuit Breaker (Isolates database failures)
              └──► [PostgreSQL Read Replicas (Neon Shards 1 & 2)]
```

### Key Architectural Pillars:
1. **Edge Perimeter Defense:** Malformed requests are validated and rejected at the API Gateway in under 10 ms with **zero backend CPU or database cost**.
2. **Distributed Token-Bucket Rate Limiting:** Abusive clients exceeding burst limits receive HTTP 429 without touching internal microservices.
3. **In-Memory Cache-Aside:** Result queries exhibit strong spatial locality (popular roll numbers are viewed repeatedly). Successful queries are cached in Redis with a 10-minute TTL, serving lookups in **~5–10 ms**.
4. **Database Sharding & Read/Write Splitting:** Read traffic targets dedicated PostgreSQL read replicas, routed by college code across two separate shards.
5. **Bulkhead & Circuit Breaker Isolation:** Resilience4j bulkheads strictly cap database concurrency to 25 queries per shard, preventing connection pool exhaustion. Circuit breakers fast-fail within 25 ms if a database shard fails, protecting other shards.
6. **Dynamic Service Discovery:** Read service instances register with Eureka, allowing the read tier to scale horizontally on demand.

---

## 3. Tech Stack

| Layer | Technologies |
|---|---|
| **API Gateway** | Spring Cloud Gateway (Reactive / Project Reactor), Resilience4j Circuit Breaker |
| **Service Discovery** | Spring Cloud Netflix Eureka |
| **Read Microservice** | Java 21, Spring Boot 3, Spring Data JPA, Hibernate, HikariCP, Virtual Threads |
| **Caching & State** | Redis 7 (Alpine Docker), Spring Data Redis (Jedis / Lettuce) |
| **Databases** | PostgreSQL 16 (Neon Serverless Shards: Shard 1 & Shard 2 with Read Replicas) |
| **Load Testing & Benchmarks** | k6 (Distributed Virtual Users & Ramping Arrival Rates), Python, Matplotlib |
| **Infrastructure** | Docker, Docker Compose, PowerShell Orchestration Scripts |

---

## 4. Headline Benchmark Results

Tested on a single commodity laptop against remote PostgreSQL cloud databases:

| Architecture | Load Tier | p95 Latency | Avg Latency | Dropped Requests | Success Rate |
|---|---:|---:|---:|---:|---:|
| **Naive (Direct DB)** | 50 req/s | 1,020 ms | 470 ms | 0.46% (9) | 99.54% |
| **Naive (COLLAPSE)** | **75 req/s** | **6,480 ms** | **3,190 ms** | **19.06% (555 / 2,912)** | **80.94%** |
| **Optimized Read** | 75 req/s | **10 ms** | **30 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test** | **150 req/s** | **9.1 ms** | **4.7 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test (Warm)** | **300 req/s** | **8.6 ms** | **20.2 ms** | **0.00% (0)** | **100.00%** |
| **Optimized Stress Test** | **500 req/s** | **9.3 ms** | **6.0 ms** | **0.00% (0)** | **100.00%** |

> **Impact:** The optimized distributed read path handled **at least 9x the throughput** of the naive baseline (handling 500 req/s with 100% completion vs the naive architecture's 54.58 req/s saturation ceiling) while cutting steady-state p95 response time from **6.48 seconds down to 9.26 milliseconds** (a **99.8% latency reduction**).

![p95 Latency Comparison](load-tests/results/comparison/hot-p95.png)

![Delivered Arrivals Comparison](load-tests/results/comparison/hot-delivered.png)

👉 **For complete run-by-run tables, failure analysis, and scaling charts, see [docs/results.md](docs/results.md).**

---

## 5. Quickstart

### Prerequisites
* JDK 21+ (`java -version`)
* Docker Desktop running (`docker info`)

### Run in 5 Commands:
```powershell
# 1. Setup environment file (configure Neon database URLs)
cp .env.example .env

# 2. Build all microservice JARs
.\scripts\build.ps1

# 3. Start the entire distributed stack (Eureka, Redis, Read Service, API Gateway)
.\scripts\start-stack.ps1 -Profile optimized

# 4. Verify health and query a student result
curl.exe http://localhost:8081/actuator/health
curl.exe http://localhost:8081/api/results/160423733001

# 5. Stop the stack
.\scripts\stop-stack.ps1
```

👉 **For standalone server commands, Docker operations, and k6 benchmark guides, see [docs/getting-started.md](docs/getting-started.md).**

---

## 6. Repository Layout & Architecture Status

```
├── api-gateway/                 # Reactive gateway: validation, rate limiting, circuit breaker
├── service-discovery/           # Eureka service registry
├── result-read-service/         # Read tier: naive & optimized profiles, Redis cache-aside
├── result-ingestion-service/    # Write tier: Admin CSV upload, validation, RabbitMQ batch producer
├── result-persistence-service/  # Write tier: RabbitMQ batch consumer, multi-shard JDBC persistence & publish saga
├── contracts/                   # Shard map configuration and shared schemas
├── scripts/                     # Stack orchestration scripts (build, start, stop)
├── load-tests/                  # k6 test scenarios, seed generators, reports & charts
└── docs/                        # Documentation: results.md, getting-started.md, spec, phases
```

### Roadmap:
* ✅ **Phase 1: Skeleton & Baseline** - Naive direct-DB read path, k6 baseline proving 75 req/s collapse.
* ✅ **Phase 2: Read Protections** - Redis cache-aside, replica routing, rate limiting, validation.
* ✅ **Phase 3: Scale-Out & Resilience** - Eureka discovery, Resilience4j bulkheads/breakers, 500 req/s stress verification.
* ✅ **Phase 4: Write Path & Ingestion** - Admin CSV upload, RabbitMQ asynchronous batching, idempotent JDBC upserts across Neon shards.
* ✅ **Phase 5: Publishing Saga** - Multi-shard publish saga, point of no return, Kafka broker-ack event emission, gentle cache warm-up, gateway isolation.
* ⏳ **Phase 6: Registration & Email** - Student registration, BCrypt authentication, paced email notifications via Mailpit.
