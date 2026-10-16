# Running the OU Results Stack

This document details the operational commands for launching, configuring, testing, and stopping the OU Results platform.

---

## 1. Prerequisites & Environment

1. Ensure Docker Desktop is running (`docker info`).
2. Ensure JDK 21+ is available on PATH (`java -version`).
3. Ensure `.env` is configured in the repository root:
   ```powershell
   cp .env.example .env
   ```
   Set your Neon PostgreSQL connection URLs (`SHARD_1_PRIMARY`, `SHARD_2_PRIMARY`, etc.) and `ADMIN_API_KEY`. Optionally set `GATEWAY_PORT` (defaults to 8080) if another local service occupies 8080.

---

## 2. Building Services

Compile all Java services (Eureka, Read Service, API Gateway, Persistence Service) and Node TypeScript:

```powershell
.\scripts\build.ps1
```

*(Builds Maven JARs with `-DskipTests` and builds `result-ingestion-service` TypeScript).*

---

## 3. Starting the Stack

All services are orchestrated via `scripts\start-stack.ps1`.

### Read Stack (Default Mode)

```powershell
# Start the standard optimized stack (Eureka, Redis Cache, Redis State, 1 Read Service, Gateway)
.\scripts\start-stack.ps1 -Profile optimized

# Start with multiple read instances behind Eureka load balancing
.\scripts\start-stack.ps1 -Profile optimized -Instances 3

# Start for high-concurrency k6 load tests (raises gateway rate limit to 1000 req/s, burst 2000)
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
* `result-persistence-service` starts as a dedicated worker listening to `results.write`.
* `result-ingestion-service` starts on port 3000, streaming CSV uploads into college-grouped batches.
* The API Gateway routes `POST /admin/results/upload` to the ingestion service, enforcing `ADMIN_API_KEY`.

---

## 4. Verifying and Testing Services

### Public Read Path

```powershell
# Query student result through Gateway (Port 8081 / $env:GATEWAY_PORT)
curl.exe -i http://localhost:8081/api/results/160423733001

# Test roll number format validation (returns HTTP 400 immediately at perimeter)
curl.exe -i http://localhost:8081/api/results/INVALIDROLL
```

### Administrative Write Path

```powershell
# Run end-to-end write pipeline verification (generates fresh exam and queries shards)
.\load-tests\test-write-pipeline.ps1 -FreshExam

# Upload results CSV through API Gateway with Admin API Key (from environment variable)
curl.exe -i -X POST "http://localhost:8081/admin/results/upload" `
  -H "X-Admin-Api-Key: $env:ADMIN_API_KEY" `
  -F "file=@load-tests/seed/out/upload-sample.csv" `
  -F "title=July-August 2026 Examinations" `
  -F "resultDate=2026-08-15"
```

### Publishing & Failure Simulation Configuration Flags

For Phase 5 testing and demonstrations, `result-persistence-service` supports three fault-injection configuration properties. **All are OFF (disabled) by default and have zero effect in normal production operations**:

| Environment Variable | Property Key | Default | Description |
|---|---|---|---|
| `APP_DEMO_FAILING_PUBLISH_SHARD` | `app.demo.failing-publish-shard` | `none` | Simulates a failure on `shard1` or `shard2` before the point of no return to demonstrate transactional rollback to `FAILED`. |
| `APP_DEMO_CRASH_AFTER_SHARDS_PUBLISHED` | `app.demo.crash-after-shards-published` | `false` | Triggers an immediate JVM crash (`Runtime.halt(137)`) at `SHARDS_PUBLISHED` before RabbitMQ ACK to verify redelivery and forward recovery. |
| `APP_DEMO_FAILING_KAFKA_PUBLISH` | `app.demo.failing-kafka-publish` | `false` | Simulates Kafka broker outage past the point of no return to verify that retries exhaust to `results.publish.dlq` without rolling back. |

To run the automated suite verifying all three failure and recovery scenarios:
```powershell
.\load-tests\test-phase5-failure-demos.ps1
```

---

## 5. Stopping the Stack

```powershell
# Stop application processes while keeping Redis and RabbitMQ containers running
.\scripts\stop-stack.ps1

# Stop application processes AND shut down Docker containers
.\scripts\stop-stack.ps1 -StopContainers
```
