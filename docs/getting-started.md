# Getting Started & Operator Guide

This guide covers setting up, building, running individual services or the full stack, Docker operations, and running load tests.

---

## 1. Setup & Configuration

### Prerequisites
* **Java:** JDK 21+ (`java -version`)
* **Docker:** Docker Desktop running (`docker info`)
* **k6:** (Optional, for load testing) k6 installed and on PATH (`k6 version`)

### Environment File
Copy `.env.example` to `.env` and configure your database URLs:
```powershell
cp .env.example .env
```
Ensure your Neon PostgreSQL connection strings are set in `.env` (`SHARD_1_PRIMARY`, `SHARD_2_PRIMARY`, etc.).

---

## 2. Build Services

Build all three Spring Boot services (Eureka, Read Service, API Gateway) from the repository root:

```powershell
.\scripts\build.ps1
```

*(This runs `mvnw package -DskipTests` for each module).*

---

## 3. Running the System (Stack Launcher)

The automated script manages Eureka, Redis containers, Read instances, and API Gateway together:

```powershell
# Start the full stack with Optimized read service (1 instance)
.\scripts\start-stack.ps1 -Profile optimized

# Start with multiple read instances (e.g., 3 instances behind Eureka)
.\scripts\start-stack.ps1 -Profile optimized -Instances 3

# Start for high-rate load testing (raises gateway rate limit to 1000 req/s)
.\scripts\start-stack.ps1 -Profile optimized -LoadTest

# Start with Naive profile (bypasses Redis, hits DB directly)
.\scripts\start-stack.ps1 -Profile naive

# Stop the stack and cleanup processes
.\scripts\stop-stack.ps1

# Stop everything including Redis Docker containers
.\scripts\stop-stack.ps1 -StopContainers
```

---

## 4. Running the Write Path Services

The write path services (RabbitMQ, Result Persistence Service, Result Ingestion Service) are managed through the `-Write` switch in `start-stack.ps1` (off by default):

```powershell
# Start full read stack plus write ingestion and persistence pipeline
.\scripts\start-stack.ps1 -Profile optimized -Write

# Test the write pipeline end-to-end
.\load-tests\scripts\test-write-pipeline.ps1 -FreshExam

# Stop the full stack including write services
.\scripts\stop-stack.ps1 -StopContainers
```

---

## 5. Docker & Redis Commands

The project uses two Redis containers:
* `redis-cache` (Port 6379) - Stores cached query results (LRU eviction).
* `redis-state` (Port 6380) - Stores gateway token-bucket rate limits.

```powershell
# Start Redis containers
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
# API Gateway health
curl.exe http://localhost:8080/actuator/health

# Read Service health
curl.exe http://localhost:8082/actuator/health

# Eureka discovery health
curl.exe http://localhost:8761/actuator/health
```

### Querying Student Results
```powershell
# Query through the API Gateway (Port 8080)
curl.exe -i http://localhost:8080/api/results/160423733001

# Query Read Service directly (Port 8082)
curl.exe -i http://localhost:8082/api/results/160423733001

# Test roll validation (invalid format returns HTTP 400 immediately)
curl.exe -i http://localhost:8080/api/results/INVALIDROLL
```

### Ingesting Results via Admin Upload (Write Path)
```powershell
# Upload results CSV through API Gateway with Admin API Key
curl.exe -i -X POST "http://localhost:8080/admin/results/upload" `
  -H "X-Admin-Api-Key: <ADMIN_API_KEY>" `
  -F "file=@load-tests/seed/out/upload-sample.csv" `
  -F "title=July-August 2026 Examinations" `
  -F "resultDate=2026-08-15"
```

---

## 7. Running Load Tests (k6)

Make sure the stack is running with `-LoadTest` enabled before running heavy tests:
```powershell
.\scripts\start-stack.ps1 -Profile optimized -LoadTest
```

### Standard Arrival-Rate Test (Realistic Result Day)
```powershell
# Run 75 req/s arrival test (Hot mode: repeated lookups)
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks 75 -Mode hot -BaseUrl http://localhost:8080

# Run high-rate stress test (150, 300, 500 req/s)
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks 150,300,500 -Runs 3 -Mode hot -BaseUrl http://localhost:8080 -MaxVus 2000
```

### Gateway Protection Test
Tests that invalid roll numbers are blocked (HTTP 400) and cold bursts are safely shed:
```powershell
docker compose exec -T redis-cache redis-cli FLUSHDB
.\load-tests\k6\run-gateway-protection.ps1
```

### Horizontal Scaling Test (1 vs 2 vs 3 Instances)
Automatically runs tests with 1, 2, and 3 instances and generates comparison charts:
```powershell
.\load-tests\k6\run-scaling.ps1
```

---

## 8. Generating Reports & Charts

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
