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
.\api-gateway\mvnw.cmd -B -f .\result-read-service\pom.xml -DskipTests package
.\api-gateway\mvnw.cmd -B -f .\api-gateway\pom.xml -DskipTests package
```

## 4. Start and stop services

The read service listens on port **8082**. `start-read.ps1` defaults to the
`naive` profile; choose `optimized` explicitly to read from shard replicas and
use `redis-cache` on port 6379. The launcher reads only the selected shard URL
variables from root `.env` without printing them. Naive needs
`SHARD_1_PRIMARY` and `SHARD_2_PRIMARY`; optimized needs
`SHARD_1_PRIMARY_REPLICA` and `SHARD_2_PRIMARY_REPLICA`.

```powershell
# In its own PowerShell window; default is naive
.\scripts\start-read.ps1

# Or explicitly select optimized
.\scripts\start-read.ps1 -Profile optimized
```

The gateway listens on port **8080**, forwards `/api/results/**` to
`READ_SERVICE_URL` (default `http://localhost:8082`), and uses `redis-state` on
port 6380. Start `redis-state` before starting the gateway:

```powershell
docker compose up -d redis-state
.\scripts\start-gateway.ps1
```

Gateway setting names and defaults are `GATEWAY_PORT=8080`,
`READ_SERVICE_URL=http://localhost:8082`, `REDIS_STATE_HOST=localhost`,
`REDIS_STATE_PORT=6380`, `GATEWAY_RATE_LIMIT_REPLENISH_RATE=10`, and
`GATEWAY_RATE_LIMIT_BURST_CAPACITY=30`.

Gateway filter order is: correlation-ID global filter
(`Ordered.HIGHEST_PRECEDENCE`), roll-number validation global filter
(`Ordered.HIGHEST_PRECEDENCE + 1`), route `RequestRateLimiter` (the first route
filter), then route forwarding. Thus invalid roll numbers are rejected before
the Redis rate limiter and read service.

The read service and gateway run in separate PowerShell windows and can run
together. For direct reads, target `http://localhost:8082`; for gateway reads,
target `http://localhost:8080` while the read service is running. Naive direct
reads need no Redis. Optimized reads use `redis-cache` and require the replica
URLs; if Redis is unavailable, the service falls back to the replicas.
Optimized reads through the gateway use both Redis containers. Gateway reads
with either read profile use `redis-state`.

Check the Spring Boot startup log for the active profile name and confirm it
matches the `-Profile` supplied to the read launcher. The exact startup-log
wording is **unverified**. Press **Ctrl+C** in each foreground
service window to stop that service. `start-read.ps1` also accepts
`-JarPath` (default `.\result-read-service\target\result-read-service-0.0.1-SNAPSHOT.jar`)
and `-MaxHeapMb` (default 512; minimum 256). `start-gateway.ps1` accepts
`-JarPath` (default `.\api-gateway\target\api-gateway-0.0.1-SNAPSHOT.jar`)
and `-MaxHeapMb` (default 512; minimum 256).

More detail: [read-service profiles](../result-read-service/README.md) and
[gateway](../api-gateway/README.md).

## 5. Quick health checks

```powershell
# Read service health and exposed metrics
curl.exe -i http://localhost:8082/actuator/health
curl.exe -i http://localhost:8082/actuator/metrics

# Gateway health and metrics
curl.exe -i http://localhost:8080/actuator/health
curl.exe -i http://localhost:8080/actuator/metrics

# Optimized-profile cache counters (requires optimized read service)
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.hit
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.miss
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.negative.hit
curl.exe -s http://localhost:8082/actuator/metrics/result.cache.lock.wait
```

Example gateway requests:

```powershell
# Valid 12-digit roll number/known college; expect HTTP 200
curl.exe -i http://localhost:8080/api/results/160423733001

# Invalid roll number; expect HTTP 400 ProblemDetail
curl.exe -i http://localhost:8080/api/results/not-a-roll

# 40 parallel requests from this client IP; expect some HTTP 429 responses
$url = "http://localhost:8080/api/results/160400000001"
$urls = 1..40 | ForEach-Object { $url }
& curl.exe --parallel --parallel-immediate --parallel-max 40 --silent --output NUL --write-out "%{http_code}`n" @urls
```

The 200 request depends on reachable, correctly seeded databases; that state is
**unverified**. Gateway rate limits default to 10 requests/second and a burst
of 30 per client IP.

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
explicitly higher process-local limits; these values override the defaults for
that gateway process:

```powershell
$env:GATEWAY_RATE_LIMIT_REPLENISH_RATE = "100"
$env:GATEWAY_RATE_LIMIT_BURST_CAPACITY = "300"
.\scripts\start-gateway.ps1
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
Stop the gateway with Ctrl+C, then clear its process-local overrides in that
PowerShell window:

```powershell
Remove-Item Env:GATEWAY_RATE_LIMIT_REPLENISH_RATE, Env:GATEWAY_RATE_LIMIT_BURST_CAPACITY -ErrorAction SilentlyContinue
```

### Gateway protection proof

This runner needs the **optimized** read service on port 8082 so it can sample
the cache counters before and after each scenario. It sends an invalid-input
scenario (50 req/s for 20 seconds) followed by a valid-roll burst (100 req/s
for 10 seconds) to the gateway. It does not use `.env`.

```powershell
.\load-tests\k6\run-gateway-protection.ps1
```

Optional parameters are `-GatewayBaseUrl` (default
`http://localhost:8080`), `-ReadServiceBaseUrl` (default
`http://localhost:8082`), and `-ValidRollNumber` (default `160423733001`, must
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
