# API Gateway

The gateway serves `http://localhost:8080` and forwards valid
`/api/results/{rollNo}` requests to `READ_SERVICE_URL` (default
`http://localhost:8082`). It validates the 12-digit roll number and college code
before forwarding, and applies a per-client-IP Redis rate limit of 10 requests
per second with a burst capacity of 30.

## Start locally

From the repository root, start only the rate-limit Redis instance:

```powershell
docker compose up -d redis-state
```

Start the read service in a separate PowerShell window. For the optimized
profile, ensure the local `.env` has its required shard settings; do not print or
share that file.

```powershell
.\scripts\start-read.ps1 -Profile optimized
```

Build the gateway without running tests, then start it in another window:

```powershell
.\api-gateway\mvnw.cmd -B -f .\api-gateway\pom.xml -DskipTests package
.\scripts\start-gateway.ps1
```

The gateway connects to Redis at `localhost:6380`. Override its environment
settings when needed: `READ_SERVICE_URL`, `REDIS_STATE_HOST`,
`REDIS_STATE_PORT`, `GATEWAY_RATE_LIMIT_REPLENISH_RATE`,
`GATEWAY_RATE_LIMIT_BURST_CAPACITY`, and `GATEWAY_PORT`.

## Example requests

A syntactically valid college code and roll number returns the read service's
normal result (HTTP 200, including an empty list when no result is published):

```powershell
curl.exe -i http://localhost:8080/api/results/160400000001
```

Malformed roll numbers and unknown college prefixes are rejected with HTTP 400
and an RFC 7807 response without being forwarded:

```powershell
curl.exe -i http://localhost:8080/api/results/not-a-roll
```

To demonstrate HTTP 429, send 40 parallel requests from the same client IP so
they exceed the default burst capacity:

```powershell
$url = "http://localhost:8080/api/results/160400000001"
$urls = 1..40 | ForEach-Object { $url }
& curl.exe --parallel --parallel-immediate --parallel-max 40 --silent --output NUL --write-out "%{http_code}`n" @urls
```

The gateway includes `X-Correlation-Id` on every response. Supply that header
on a request to reuse an ID; otherwise the gateway creates one. Gateway
request logs are DEBUG, invalid-roll rejections are INFO, and rate-limit
rejections are WARN. Actuator metrics are available at
`http://localhost:8080/actuator/metrics`.

The resolved Spring Cloud Gateway version does not expose a configurable
`RedisRateLimiter` key prefix, so its built-in `request_rate_limiter` prefix is
used rather than a custom `rl:` prefix.
