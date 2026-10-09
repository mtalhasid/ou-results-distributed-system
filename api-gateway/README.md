# API Gateway

Spring Cloud Gateway on `http://localhost:8080`. Forwards valid
`GET /api/results/{rollNo}` to `READ_SERVICE_URL` (default
`lb://result-read-service` via Eureka).

**Owns:** correlation ID, 12-digit roll validation against
`contracts/shard-map.yml` college codes, per-IP Redis rate limit
(`redis-state` on localhost:6380, default 10/s burst 30), Resilience4j
`readService` circuit breaker (10 s timeout, fallback HTTP 503
`ApiResponse` with `Retry-After: 5`).

Filter order: correlation ID, validation, `RequestRateLimiter`, then
forward. Invalid rolls never reach Redis or the read service. Errors use
the gateway `ApiResponse` envelope, not RFC 7807 ProblemDetail.

Start the full stack from the repository root
([docs/getting-started.md](../docs/getting-started.md)):

```powershell
.\scripts\start-stack.ps1 -Profile optimized
```

Override when needed: `READ_SERVICE_URL`, `REDIS_STATE_HOST`,
`REDIS_STATE_PORT`, `GATEWAY_RATE_LIMIT_REPLENISH_RATE`,
`GATEWAY_RATE_LIMIT_BURST_CAPACITY`, `GATEWAY_PORT`, `EUREKA_SERVER_URL`.
`-LoadTest` on the stack launcher sets 1000/s with burst 2000.

The resolved Spring Cloud Gateway version does not expose a configurable
`RedisRateLimiter` key prefix, so the built-in `request_rate_limiter`
prefix is used rather than a custom `rl:` prefix.

Request logs are DEBUG, invalid-roll rejections INFO, rate-limit
rejections WARN. Actuator: `http://localhost:8080/actuator/metrics`.
Responses include `X-Correlation-Id`.
