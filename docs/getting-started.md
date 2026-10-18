# Getting Started & Operator Guide

This guide covers setup, building, running individual services or the full stack, Docker operations, write path verification, exam publishing sagas, failure simulations, and k6 load testing benchmarks.

## Table of Contents

- [1. Setup & Configuration](#1-setup--configuration)
- [2. Building Services](#2-building-services)
- [3. Running the Stack (Stack Launcher)](#3-running-the-stack-stack-launcher)
- [4. Stopping the Stack](#4-stopping-the-stack)
- [5. Docker & Redis Operations](#5-docker--redis-operations)
- [6. Verifying & Querying Results](#6-verifying--querying-results)
- [7. Administrative Write Pipeline & Resilience Testing](#7-administrative-write-pipeline--resilience-testing)
- [8. Exam Publishing Saga & Failure Simulations (Phase 5)](#8-exam-publishing-saga--failure-simulations-phase-5)
- [9. Running Load Tests (k6)](#9-running-load-tests-k6)
- [10. Generating Reports & Charts](#10-generating-reports--charts)

---

## 1. Setup & Configuration

### Prerequisites
* **Java:** JDK 21+ (`java -version`)
* **Docker:** Docker Desktop running (`docker info`)
* **k6:** (Optional, for load testing) k6 installed and on PATH (`k6 version`)
* **Python 3:** (Optional, for chart generation) Python 3 installed (`python --version`)

### Environment File
Copy `.env.example` to `.env` and configure your database URLs:
```powershell
cp .env.example .env
```
Ensure your Neon PostgreSQL connection strings are set in `.env` (`SHARD_1_PRIMARY`, `SHARD_2_PRIMARY`, etc.) along with `ADMIN_API_KEY`. Optionally set `GATEWAY_PORT` (defaults to 8080 or 8081).

---

## 2. Building Services

Compile all Java services (Eureka, Read Service, API Gateway, Persistence Service) and Node TypeScript:

```powershell
.\scripts\build.ps1
```

*(Runs `mvnw package -DskipTests` for each Maven module and builds `result-ingestion-service` TypeScript).*

---

## 3. Running the Stack (Stack Launcher)

The automated script manages Eureka, Redis containers, Read instances, and API Gateway together:

```powershell
# Start the standard optimized stack (Eureka, Redis Cache, Redis State, 1 Read Service, Gateway)
.\scripts\start-stack.ps1 -Profile optimized

# Start with multiple read instances behind Eureka load balancing (e.g., 3 instances)
.\scripts\start-stack.ps1 -Profile optimized -Instances 3

# Start for high-rate load testing (raises gateway rate limit to 1000 req/s, burst 2000)
.\scripts\start-stack.ps1 -Profile optimized -LoadTest

# Start naive baseline (bypasses Redis cache, queries database directly)
.\scripts\start-stack.ps1 -Profile naive
```

### Full Stack Including Write Path (`-Write` Switch)

To include the bulk ingestion write pipeline (RabbitMQ broker, Result Ingestion Service on port 3000, Result Persistence Service worker), pass the `-Write` switch:

```powershell
# Start full optimized read stack + write ingestion pipeline
.\scripts\start-stack.ps1 -Profile optimized -Write
```

When `-Write` is provided:
* RabbitMQ starts via Docker Compose with pre-loaded queue and DLQ definitions.
* `result-persistence-service` starts as a dedicated worker listening to `results.write` and `results.publish`.
* `result-ingestion-service` starts on port 3000, streaming CSV uploads into college-grouped batches.
* The API Gateway routes `POST /admin/results/upload` to the ingestion service, enforcing `ADMIN_API_KEY`.

---

## 4. Stopping the Stack

```powershell
# Stop application processes while keeping Redis and RabbitMQ containers running
.\scripts\stop-stack.ps1

# Stop application processes AND shut down Docker containers
.\scripts\stop-stack.ps1 -StopContainers
```

---

## 5. Docker & Redis Operations

The project uses two Redis containers:
* `redis-cache` (Port 6379) - Stores cached query results (LRU eviction).
* `redis-state` (Port 6380) - Stores gateway token-bucket rate limits.

```powershell
# Start Redis containers standalone
docker compose up -d redis-cache redis-state

# Check container status
docker compose ps

# Flush the result cache (clears cached query results)
docker compose exec -T redis-cache redis-cli FLUSHDB

# View Redis keys in cache
docker compose exec -T redis-cache redis-cli KEYS "*"

# Stop Redis containers
docker compose stop redis-cache redis-state

# Remove containers
docker compose down
```

---

## 6. Verifying & Querying Results

### Health Checks
```powershell
# API Gateway health (Port 8081 / $env:GATEWAY_PORT)
curl.exe -i http://localhost:8081/actuator/health

# Read Service health
curl.exe -i http://localhost:8082/actuator/health

# Eureka discovery health
curl.exe -i http://localhost:8761/actuator/health
```

### Querying Student Results (Read Path)
```powershell
# Query through the API Gateway (Port 8081)
curl.exe -i http://localhost:8081/api/results/160423733001

# Query Read Service directly (Port 8082)
curl.exe -i http://localhost:8082/api/results/160423733001

# Test roll format validation (invalid format returns HTTP 400 immediately at gateway)
curl.exe -i http://localhost:8081/api/results/INVALIDROLL
```

---

## 7. Administrative Write Pipeline & Resilience Testing

Make sure the stack is running with `-Write` before testing the write pipeline:
```powershell
.\scripts\start-stack.ps1 -Profile optimized -Write
```

### End-to-End Write Verification
```powershell
# Run smoke verification (generates fresh exam and queries shards)
.\tests\write\upload-smoke.ps1 -FreshExam

# Run full write resilience suite (5k/10k scaling, size limits, idempotency, atomicity/DLQ)
.\tests\write\upload-resilience.ps1
```

### Manual CSV Upload via Gateway
```powershell
# Upload results CSV through API Gateway with Admin API Key (from environment variable)
curl.exe -i -X POST "http://localhost:8081/admin/results/upload" `
  -H "X-Admin-Api-Key: $env:ADMIN_API_KEY" `
  -F "file=@load-tests/seed/out/upload-sample.csv" `
  -F "title=July-August 2026 Examinations" `
  -F "resultDate=2026-08-15"
```

---

## 8. Exam Publishing Saga & Failure Simulations (Phase 5)

Once results are ingested, an administrator publishes the exam to make it visible to students across all shards.

### Happy-Path Publishing Verification
Verifies draft isolation, multi-shard atomic commit, Kafka event emission, Redis gentle cache warm-up, and strong read consistency:
```powershell
.\tests\publish\publish-happy-path.ps1
```

### Fault-Injection & Recovery Demonstrations
To verify that the system survives crashes, rollbacks, and message broker outages without data corruption:
```powershell
.\tests\publish\publish-failure-demos.ps1
```

### Publishing Configuration Flags (Simulation Hooks)
For Phase 5 testing and demonstrations, `result-persistence-service` supports three fault-injection configuration properties. **All are OFF (disabled) by default and have zero effect in normal production operations**:

| Environment Variable | Property Key | Default | Description |
|---|---|---|---|
| `APP_DEMO_FAILING_PUBLISH_SHARD` | `app.demo.failing-publish-shard` | `none` | Simulates a failure on `shard1` or `shard2` before the point of no return to demonstrate transactional rollback to `FAILED`. |
| `APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED` | `app.demo.crash-after-shards-published` | `false` | Triggers an immediate JVM crash (`Runtime.halt(137)`) at `SHARDS_PUBLISHED` before RabbitMQ ACK to verify redelivery and forward recovery. |
| `APP_DEMO_FAILING_KAFKA_PUBLISH` | `app.demo.failing-kafka-publish` | `false` | Simulates Kafka broker outage past the point of no return to verify that retries exhaust to `results.publish.dlq` without rolling back. |

---

## 9. Running Load Tests (k6)

Make sure the stack is running with `-LoadTest` enabled before running heavy tests:
```powershell
.\scripts\start-stack.ps1 -Profile optimized -LoadTest
```

### Standard Arrival-Rate Test (Realistic Result Day)
```powershell
# Run 75 req/s arrival test (Hot mode: repeated lookups)
.\tests\read\run-spike-test.ps1 -Profile optimized -Peaks 75 -Mode hot -BaseUrl "http://localhost:8081"

# Run high-rate stress test (150, 300, 500 req/s)
.\tests\read\run-spike-test.ps1 -Profile optimized -Peaks 150,300,500 -Runs 3 -Mode hot -BaseUrl "http://localhost:8081" -MaxVus 2000

# Phase 5 warm-cache read load test (300 req/s regression verification)
.\tests\read\run-spike-test.ps1 -Profile optimized -Peaks 300 -Mode hot -BaseUrl "http://localhost:8081" -MaxVus 300
```

### Gateway Protection Test
Tests that invalid roll numbers are blocked (HTTP 400) and cold bursts are safely shed:
```powershell
docker compose exec -T redis-cache redis-cli FLUSHDB
.\tests\read\run-gateway-protection.ps1
```

### Horizontal Scaling Test (1 vs 2 vs 3 Instances)
Automatically runs tests with 1, 2, and 3 instances and generates comparison charts:
```powershell
.\tests\read\run-scaling.ps1
```

---

## 10. Generating Reports & Charts

To regenerate charts from test results:
```powershell
# Generate profile reports
python .\load-tests\report\make_report.py --profile naive
python .\load-tests\report\make_report.py --profile optimized

# Generate naive vs optimized comparison charts
python .\load-tests\report\make_comparison.py

# Generate horizontal scaling charts
python .\load-tests\report\make_scaling.py --mode hot
```
Charts are output to `load-tests/results/comparison/`.
