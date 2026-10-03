# Repository command reference

Run PowerShell from the repository root. Commands below do not assume that any
service or container is already running. Read the linked guides for detailed
data loading and test interpretation.

## 1. One-time setup

- Copy `.env.example` to `.env` only if `.env` does not already exist; fill in
  the local shard URLs in a private editor. Never print or commit `.env`.

  ```powershell
  if (Test-Path .\.env) {
      Write-Output ".env already exists; leaving it unchanged."
  } else {
      Copy-Item .\.env.example .\.env
  }
  ```

- Install and start Docker Desktop (**unverified**). Verify its engine with
  `docker info`.
- Use JDK 21; verify the selected Java with `java -version` (**unverified**).
  Both Java modules declare Java 21.
- The Maven wrapper is `.\api-gateway\mvnw.cmd`; check it with
  `.\api-gateway\mvnw.cmd -version`.
- Install k6 and verify it is on `PATH` with `k6 version` (**unverified**).
- Create the report-script virtual environment and install matplotlib (Python
  3.10+ is required by the report README; Python installation is
  **unverified**):

  ```powershell
  if (-not (Test-Path .\.venv\Scripts\python.exe)) { py -3 -m venv .venv }
  & .\.venv\Scripts\python.exe -m pip install matplotlib
  ```

Load-test runs also need `load-tests\seed\out\seed-manifest.json` and seeded
shard databases. Follow [seed setup](../load-tests/seed/README.md); their
presence and database contents are **unverified** here.
Whether `.env` contains valid local URLs and whether those databases are
reachable are **unverified**.

## 2. Docker

Compose defines `redis-cache` (host port 6379) and `redis-state` (host port
6380). Redis listens on container port 6379; both ports are bound to localhost.
The optional Compose read-service container uses the `read` profile; the
documented normal workflow runs services locally.

```powershell
# Start both Redis containers
docker compose up -d redis-cache redis-state

# Status
docker compose ps

# Restart either or both
docker compose restart redis-cache
docker compose restart redis-state
docker compose restart redis-cache redis-state

# Stop Redis containers without removing them
docker compose stop redis-cache redis-state

# Clear all keys in the cache's default Redis database
docker compose exec -T redis-cache redis-cli FLUSHDB

# Stop and remove all containers and the Compose network for this project
docker compose --profile read down

# Inspect disk use, then interactively remove reclaimable data
docker system df
docker image prune
docker builder prune
```

Do not add `--volumes` to cleanup commands unless you deliberately intend to
remove Docker volumes.

## 3. Build the JARs

These package the services without running tests:

```powershell
.\api-gateway\mvnw.cmd -B -f .\service-discovery\pom.xml -DskipTests package
.\api-gateway\mvnw.cmd -B -f .\result-read-service\pom.xml -DskipTests package
.\api-gateway\mvnw.cmd -B -f .\api-gateway\pom.xml -DskipTests package
```

## 4. Start and stop services

The recommended local workflow uses `start-stack.ps1`. It loads only the
selected shard URL variables from root `.env` without printing them, starts
both Redis containers, Eureka on port **8761**, the requested read instances
on ports **8082** and upward, then the API gateway on port **8080**.
`-Profile` is required; optimized reads use shard replicas and `redis-cache`
on port 6379. Naive reads use shard primaries.

```powershell
# Start one naive read instance and the gateway
.\scripts\start-stack.ps1 -Profile naive

# Start three optimized read instances and the gateway
.\scripts\start-stack.ps1 -Profile optimized -Instances 3

# Raise the gateway rate limit only for its process (1000/s, burst 2000)
.\scripts\start-stack.ps1 -Profile optimized -Instances 3 -LoadTest

# Demo/test tool: make database reads for shard1 fail in the optimized service
.\scripts\start-stack.ps1 -Profile optimized -FailShard shard1

# Stop the application processes; Redis containers stay up
.\scripts\stop-stack.ps1

# Demo/test tool: stop only read instances; Eureka, gateway, and Redis stay up
.\scripts\stop-stack.ps1 -ReadInstancesOnly

# Also stop the Redis containers
.\scripts\stop-stack.ps1 -StopContainers
```

The stack launcher is idempotent for the same settings: running it again does
not start duplicate Java processes. Process IDs and service logs are stored in
the ignored `logs/` folder. `stop-stack.ps1` stops only processes recorded by
the launcher. `-Instances` defaults to 1; read ports are assigned consecutively
starting at 8082. Each read response includes `X-Instance-Id` when started by
the stack launcher.

```powershell
# Normal stack startup uses Eureka/LoadBalancer routing
.\scripts\start-stack.ps1 -Profile optimized
```

For direct routing to one instance, set `READ_SERVICE_URL` before starting the
stack. Run one of these options, not both in the same stack:

```powershell
# Route directly to port 8082 instead of using Eureka/LoadBalancer
$env:READ_SERVICE_URL = "http://localhost:8082"
.\scripts\start-stack.ps1 -Profile optimized
Remove-Item Env:READ_SERVICE_URL
```

`READ_SERVICE_URL` defaults to `lb://result-read-service`, which uses Eureka
and Spring Cloud LoadBalancer. Set it to `http://localhost:8082` (or another
instance port) to target one instance directly. The gateway uses `redis-state`
on port 6380. Gateway setting names and defaults are `GATEWAY_PORT=8080`,
`READ_SERVICE_URL=lb://result-read-service`,
`EUREKA_SERVER_URL=http://localhost:8761/eureka/`, `REDIS_STATE_HOST=localhost`,
`REDIS_STATE_PORT=6380`, `GATEWAY_RATE_LIMIT_REPLENISH_RATE=10`, and
`GATEWAY_RATE_LIMIT_BURST_CAPACITY=30`.

Gateway filter order is: correlation-ID global filter
(`Ordered.HIGHEST_PRECEDENCE`), roll-number validation global filter
(`Ordered.HIGHEST_PRECEDENCE + 1`), route `RequestRateLimiter` (the first route
filter), then route forwarding. Thus invalid roll numbers are rejected before
the Redis rate limiter and read service.

For direct reads, target the instance port (`http://localhost:8082`,
`http://localhost:8083`, and so on); for load-balanced reads, target
`http://localhost:8080`. Naive direct reads need no Redis. Optimized reads use
`redis-cache` and require the replica URLs; if Redis is unavailable, the
service falls back to the replicas. Gateway reads use `redis-state`.

Check the Spring Boot startup log for the active profile name and confirm it
matches the `-Profile` supplied to the read launcher. The exact startup-log
wording is **unverified**. The legacy `start-read.ps1` remains available for a
single foreground instance on port 8082 and defaults to `naive`; press
**Ctrl+C** in its window to stop it. `start-read.ps1` also accepts
`-JarPath` (default `.\result-read-service\target\result-read-service-0.0.1-SNAPSHOT.jar`)
and `-MaxHeapMb` (default 512; minimum 256). `start-gateway.ps1` accepts
`-JarPath` (default `.\api-gateway\target\api-gateway-0.0.1-SNAPSHOT.jar`)
and `-MaxHeapMb` (default 512; minimum 256). `start-stack.ps1` accepts
`-Profile` (`naive` or `optimized`, required), `-Instances` (default 1), and
`-LoadTest`; the latter sets the gateway rate limit to 1000/s with a burst
capacity of 2000 for that gateway process. `-FailShard` accepts `shard1` or
`shard2` and is available only with `-Profile optimized`; it simulates a
technical database connection failure on that shard for breaker demos and
checks. The read service binds `APP_DEMO_FAILING_SHARD` to
`app.demo.failing-shard`; it defaults to `none`.
`stop-stack.ps1 -ReadInstancesOnly` stops only the read-service processes,
retains the stack state, and leaves Eureka, the gateway, and Redis running.
Both switches are demo/test tools, not production settings.

More detail: [read-service profiles](../result-read-service/README.md) and
[gateway](../api-gateway/README.md).

## 5. Quick health checks

```powershell
# Eureka and read-instance health/registration
curl.exe -i http://localhost:8761/actuator/health
curl.exe -i http://localhost:8761/eureka/apps/RESULT-READ-SERVICE
curl.exe -i http://localhost:8082/actuator/health
curl.exe -i http://localhost:8082/api/results/160423733001

# Read service metrics
curl.exe -i http://localhost:8082/actuator/metrics

# Gateway health and metrics
curl.exe -i http://localhost:8080/actuator/health
curl.exe -i http://localhost:8080/actuator/metrics

# Optimized-profile cache counters (requires optimized read service)
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.hit
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.miss
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.negative.hit
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.lock.wait

# Circuit-breaker state and events (optimized read service and gateway)
curl.exe -s http://localhost:8082/actuator/circuitbreakers
curl.exe -s http://localhost:8082/actuator/circuitbreakerevents
curl.exe -s http://localhost:8080/actuator/circuitbreakers
curl.exe -s http://localhost:8082/actuator/health/circuitBreakers
curl.exe -s http://localhost:8080/actuator/health/readServiceCircuitBreaker
curl.exe -s "http://localhost:8082/actuator/metrics/resilience4j.circuitbreaker.calls?tag=name:shard1Database"
curl.exe -s "http://localhost:8082/actuator/metrics/resilience4j.circuitbreaker.calls?tag=name:shard2Database"
curl.exe -s "http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.calls?tag=name:readService"
curl.exe -s "http://localhost:8082/actuator/metrics/resilience4j.circuitbreaker.state?tag=name:shard1Database"
curl.exe -s "http://localhost:8082/actuator/metrics/resilience4j.circuitbreaker.state?tag=name:shard2Database"
curl.exe -s "http://localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state?tag=name:readService"
```

Example gateway requests:

```powershell
# Seeded roll from the seed manifest/data (1604 -> shard1 in
# contracts/shard-map.yml); expect HTTP 200
curl.exe -i http://localhost:8080/api/results/160423733001

# Seeded roll from the seed manifest/data (1608 -> shard2 in
# contracts/shard-map.yml); expect HTTP 200
curl.exe -i http://localhost:8080/api/results/160823733001

# Invalid roll number; expect HTTP 400 ProblemDetail
curl.exe -i http://localhost:8080/api/results/not-a-roll

# If the gateway breaker is open, unavailable, or the read route times out,
# expect HTTP 503 ProblemDetail and Retry-After: 5.
curl.exe -i http://localhost:8080/api/results/160423733001

# 40 parallel requests from this client IP; expect some HTTP 429 responses
$url = "http://localhost:8080/api/results/160400000001"
$urls = 1..40 | ForEach-Object { $url }
& curl.exe --parallel --parallel-immediate --parallel-max 40 --silent --output NUL --write-out "%{http_code}`n" @urls
```

The 200 request depends on reachable, correctly seeded databases; that state is
**unverified**. Gateway rate limits default to 10 requests/second and a burst
of 30 per client IP. The gateway read route has a 10-second response timeout
and a Resilience4j breaker named `readService`, with the Resilience4j time
limiter also set to 10 seconds. Its fallback is HTTP 503 with
`Retry-After: 5`. The gateway breaker is limited to transport and timeout
failures; it does not count a shard-specific 503 returned by the read service,
so a shard's open breaker does not block reads routed to the other shard.

### Circuit-breaker demo/checks

The optimized read service has independent breakers named `shard1Database`
and `shard2Database`; the naive profile does not use them. Each uses a
20-call count window, waits for 10 calls before calculating a 50% failure
threshold, stays open for 10 seconds, then permits 3 half-open calls. Only
technical database connection failures and timeouts count as failures. An
empty result for a valid but unregistered student is a normal result, not a
failure. A cache hit is served without consulting the shard breaker.

To check that shard1 failure does not affect shard2, start the optimized demo
switch and send ten cold requests to shard1. Clear only the optimized cache
before this check; the switch does not write failed reads to cache.

```powershell
docker compose exec -T redis-cache redis-cli FLUSHDB
.\scripts\start-stack.ps1 -Profile optimized -FailShard shard1

# 10 cold shard1 reads: expect HTTP 503; the shard1Database state should open.
1..10 | ForEach-Object {
    curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8082/api/results/160423733001
}
curl.exe -s http://localhost:8082/actuator/circuitbreakers

# Shard2 remains independent and should return HTTP 200.
curl.exe -i http://localhost:8082/api/results/160823733001
```

To confirm cache hits remain available while shard1 is failing, clear Redis,
start a normal optimized stack, and prime `160423733001`. Leave
`160423733002` unrequested so it stays cold. Stop the normal stack with
`.\scripts\stop-stack.ps1`, then restart with `-FailShard shard1`. The primed
roll should still return HTTP 200 from cache. Send ten requests for the cold
roll `160423733002` to open the breaker; the primed cached roll should continue
to return HTTP 200 afterward. The stack-wide cache is retained when application
processes are stopped.

```powershell
docker compose exec -T redis-cache redis-cli FLUSHDB
.\scripts\start-stack.ps1 -Profile optimized
curl.exe -i http://localhost:8082/api/results/160423733001
.\scripts\stop-stack.ps1
.\scripts\start-stack.ps1 -Profile optimized -FailShard shard1
curl.exe -i http://localhost:8082/api/results/160423733001
1..10 | ForEach-Object {
    curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8082/api/results/160423733002
}
curl.exe -i http://localhost:8082/api/results/160423733001
```

To check the gateway-level fallback independently, stop only the read tier
while leaving the gateway and Eureka running, then call either seeded roll
through port 8080. The request should fail fast with HTTP 503 and
`Retry-After: 5`; the gateway breaker state is available at
`http://localhost:8080/actuator/circuitbreakers`.

```powershell
# Demo/test only: keep Eureka, the gateway, and Redis running
.\scripts\stop-stack.ps1 -ReadInstancesOnly
curl.exe -i http://localhost:8080/api/results/160423733001
```

## 6. Load tests

All load runners require k6 and a generated seed manifest. They write raw
measurements to `load-tests\results\<profile>\raw\`; reports are generated
after a run. Specify the service `-Profile` explicitly.

### Fixed-user (VU) run

Parameters: `-Profile` is required (`naive` or `optimized`); `-Vus` defaults
to `25,50,100`; `-Runs` defaults to 3 (range 1–100); `-Label` defaults to
`baseline` (letters, digits, `_`, `-`; must start with a letter or digit);
`-BaseUrl` defaults to `http://localhost:8082`.

```powershell
.\load-tests\k6\run-baseline.ps1 -Profile naive
```

Use `-BaseUrl http://localhost:8080` to send the same VU scenario through the
gateway. The default gateway limiter will apply; for a read-capacity test,
follow the higher-limit setup in “Same arrival runs through the gateway”. VU
summaries are named `<label>-<VUs>-run<run>.json`.

### Arrival-rate run

Parameters: `-Profile` is required (`naive` or `optimized`); `-Peaks` defaults
to `25,50,75` requests/second (positive integers); `-Runs` defaults to 3
(range 1–100); `-Label` defaults to `baseline` (letters, digits, `_`, `-`;
must start with a letter or digit); `-Mode` defaults to `uniform` (`uniform`
or `hot`); `-BaseUrl` defaults to `http://localhost:8082`; it is passed to k6 as
`BASE_URL`, so the default remains direct-to-read-service; `-StopOnBreak` is
off unless specified (stop testing higher peaks when error rate or dropped
iterations exceed 5%, or p95 exceeds 10 seconds); `-MaxVus` defaults to 300
(range 1–100000); `-Timeout` defaults to 30 seconds (whole seconds, with
optional `s`, range 1–3600).

```powershell
.\load-tests\k6\run-arrival.ps1 -Profile naive -Peaks 25,50,75 -Runs 3 -Label session2 -Mode hot -Timeout 10s
.\load-tests\k6\run-arrival.ps1 -Profile naive -Peaks 25,50,75 -Runs 3 -Label session2 -Mode uniform -Timeout 10s
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks 25,50,75 -Runs 3 -Label optimized -Mode hot -Timeout 10s
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks 25,50,75 -Runs 3 -Label optimized -Mode uniform -Timeout 10s
```

These labels are the labels the current comparison generator reads. They write
to matching filenames and will replace same-named raw files; choose distinct
labels to preserve existing runs. `-Mode hot` uses a repeated-key set and is
intended to warm the cache across the series; `uniform` uses new keys. The
comparison generator only selects naive label `session2` and optimized label
`optimized`.

For optimized uniform runs with a cache clear before **each peak**, run each
peak separately:

```powershell
foreach ($peak in @(25, 50, 75)) {
    docker compose exec -T redis-cache redis-cli FLUSHDB
    if ($LASTEXITCODE -ne 0) { throw "Could not flush redis-cache." }
    .\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks $peak -Runs 3 -Label optimized -Mode uniform -Timeout 10s
}
```

This replaces those optimized uniform raw files. The cache-clear operation
clears the cache database, not the result databases.

### Hikari observation

Parameters: `-Profile` is required (`naive` or `optimized`); `-BaseUrl`
defaults to `http://localhost:8082`. It runs the fixed-user scenario at 100 VUs
and writes `raw/hikari-100.csv`, replacing that CSV if it already exists. Use
the read service URL directly because the script queries its Hikari Actuator
metrics.

```powershell
.\load-tests\k6\run-hikari-observation.ps1 -Profile naive
```

More detail: [load-test guide](../load-tests/README.md) and
[result/report notes](../load-tests/report/README.md).

### Same arrival runs through the gateway

The gateway's default limiter (10 requests/second, burst 30) will throttle the
25/50/75 req/s scenarios. For an experiment that measures the read path rather
than the default gateway limit, start the gateway in its own window with
`-LoadTest`. This sets `GATEWAY_RATE_LIMIT_REPLENISH_RATE=1000` and
`GATEWAY_RATE_LIMIT_BURST_CAPACITY=2000` only for the gateway process; the
launcher restores the calling PowerShell process's previous values when the
gateway exits:

```powershell
.\scripts\start-gateway.ps1 -LoadTest
```

With the read service and required Redis containers running, use port 8080 and
gateway-specific labels so the gateway results do not overwrite direct-run
files:

```powershell
.\load-tests\k6\run-arrival.ps1 -Profile naive -Peaks 25,50,75 -Runs 3 -Label session2gw -Mode hot -BaseUrl http://localhost:8080 -Timeout 10s
.\load-tests\k6\run-arrival.ps1 -Profile naive -Peaks 25,50,75 -Runs 3 -Label session2gw -Mode uniform -BaseUrl http://localhost:8080 -Timeout 10s
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks 25,50,75 -Runs 3 -Label optimizedgw -Mode hot -BaseUrl http://localhost:8080 -Timeout 10s
```

For optimized uniform mode, clear the cache once per peak:

```powershell
foreach ($peak in @(25, 50, 75)) {
    docker compose exec -T redis-cache redis-cli FLUSHDB
    if ($LASTEXITCODE -ne 0) { throw "Could not flush redis-cache." }
    .\load-tests\k6\run-arrival.ps1 -Profile optimized -Peaks $peak -Runs 3 -Label optimizedgw -Mode uniform -BaseUrl http://localhost:8080 -Timeout 10s
}
```

The gateway labels above are not included by the current comparison generator.
Stop the gateway with Ctrl+C.

### Gateway protection proof

This runner needs the **optimized** read service running in the stack. It
samples cache counters from every UP read instance registered in Eureka and
sums them before and after each scenario. Instance ports must follow the
stack's 8082-upward sequence. It sends an invalid-input
scenario (50 req/s for 20 seconds) followed by a valid-roll burst (100 req/s
for 10 seconds) to the gateway. It does not use `.env`.
Flush `redis-cache` immediately before the run so the burst key starts cold;
the script then warms the separate roll numbers `160423733002` through
`160423733011` before its measured scenarios.

```powershell
docker compose exec -T redis-cache redis-cli FLUSHDB
.\load-tests\k6\run-gateway-protection.ps1
```

Optional parameters are `-GatewayBaseUrl` (default
`http://localhost:8080`), `-EurekaBaseUrl` (default
`http://localhost:8761`), and `-ValidRollNumber` (default `160423733001`, must
be 12 digits). It writes the k6 summary JSON files under
`load-tests\results\gateway\raw\` and a generated report to
`load-tests\results\gateway\summary.md`. The report includes observed HTTP
status-code counts, accepted/rejected p95, and per-scenario cache-counter
deltas.

## 7. Reports

These commands read raw files only; they do not run load tests:

```powershell
& .\.venv\Scripts\python.exe .\load-tests\report\make_report.py --profile naive
& .\.venv\Scripts\python.exe .\load-tests\report\make_report.py --profile optimized
& .\.venv\Scripts\python.exe .\load-tests\report\make_comparison.py
```

`make_report.py` also accepts repeatable `--alias OLD=NEW`, for example
`--profile naive --alias baseline-confirmation=baseline`. Profile summaries
remain in each profile folder; profile charts go to its `charts` folder;
comparison charts are written to `results\comparison`.

## 8. Recipes

### Compare naive vs optimized in one sitting

Start `redis-cache`, then run `start-read.ps1 -Profile naive` and the naive
hot/uniform commands. Stop it with Ctrl+C before starting
`start-read.ps1 -Profile optimized` on port 8082, then run the optimized
hot/uniform commands. Only one read profile can own port 8082 at a time. Use
the per-peak flush loop for optimized uniform. Then regenerate both profile
reports and the comparison.
For a gateway comparison, keep one read profile active at a time, run the
gateway with Redis state and the higher limiter settings described above, and
use the `*gw` commands instead. Gateway runs are not part of the current
comparison chart selection.

The documented comparison labels overwrite matching JSON files. Back them up
first if the existing baseline evidence must be preserved. Do not run naive
and optimized as if they were separate simultaneous services on port 8082.

### Quick smoke test before a session

Start only the naive read service, check Actuator health, and issue one request
directly. This does not run k6:

```powershell
.\scripts\start-read.ps1 -Profile naive
```

In another PowerShell window:

```powershell
curl.exe -i http://localhost:8082/actuator/health
curl.exe -i http://localhost:8082/api/results/160423733001
```

For a gateway smoke check, also start `redis-state` and the gateway, then
request the same roll through port 8080. The locally seeded data and expected
record are **unverified**.

## 9. Git

Review changes and stage only the intended hunks; do not use `git add -A`.
Check the staged file list and diff before committing, especially if other
changes were already staged:

```powershell
git status --short
git diff --check
git add -- docs/commands.md
git add -p -- docs/coding-standards.md README.md
git diff --cached --name-only
git diff --cached
```

Commit only after confirming the staged diff contains only the changes you
intend to include:

```powershell
git commit -m "docs: add repository command reference"
```

Check whether the frozen-baseline tag exists:

```powershell
git tag --list baseline-naive
```

The tag was absent when this reference was written; check again before creating
it.

Only when `HEAD` is the confirmed frozen naive-baseline commit, create the tag:

```powershell
git log -1 --oneline
git tag baseline-naive
```

The correct commit to tag is **unverified**; do not tag the current commit
unless you have confirmed it is the baseline.

Check that `.env` is not tracked without displaying its contents:

```powershell
git ls-files --error-unmatch .env *> $null
if ($LASTEXITCODE -eq 0) { throw ".env is tracked." } else { Write-Output ".env is not tracked." }
```

## 10. Troubleshooting

- **Docker engine not reachable:** start Docker Desktop, then run
  `docker info`; retry Compose only after the engine responds. Docker Desktop
  installation/state is **unverified**.
- **Port already in use:** inspect the listener and owning process before
  stopping anything:

  ```powershell
  Get-NetTCPConnection -State Listen -LocalPort 8080,8082,6379,6380 -ErrorAction SilentlyContinue |
      Select-Object LocalAddress, LocalPort, OwningProcess
  ```

- **Wrong read profile:** stop the current process with Ctrl+C; restart with
  `.\scripts\start-read.ps1 -Profile naive` or
  `.\scripts\start-read.ps1 -Profile optimized`. Check the startup profile
  message.
- **Results in the wrong folder:** pass the mandatory `-Profile` to the load
  runner; it writes to `load-tests\results\<profile>\raw\`. Reports also need
  `--profile`.
- **Actuator 404:** check the correct port (read service 8082, gateway 8080),
  verify that service is running, and use `/actuator/health` or
  `/actuator/metrics`. Cache counter names are available only in the
  optimized read profile.
- **Gateway load test gets 429:** the default 10 req/s refill and burst 30
  limit apply per client IP. For arrival tests, choose whether to measure that
  limit or override it for the gateway process as shown above.
