# Result read service

`GET /api/results/{rollNo}` returns all rows for that roll as one list.
Shard routing uses college code from `contracts/shard-map.yml` (two Hikari
pools). Instances listen on 8082 and upward when started by the stack
launcher and register with Eureka as `result-read-service`. Responses
include `X-Instance-Id` when `APP_EXPOSE_INSTANCE_ID=true`.

**naive:** shard primaries, no cache.

**optimized:** Spring `@Cacheable` with `RedisCacheManager` (`redis-cache`
localhost:6379, 10-minute TTL). Replica URLs
`SHARD_1_PRIMARY_REPLICA` / `SHARD_2_PRIMARY_REPLICA` from root `.env`. If
Redis is unavailable the service falls back to the replicas. Per-shard
Resilience4j `@Bulkhead` (cap 25, wait 0 ms) and `@CircuitBreaker`
(`shard1Database`, `shard2Database`). Concurrent uncached lookups each hit
the database; the old per-key Redis lock was removed with `@Cacheable`.

Cache metrics: `/actuator/metrics/cache.gets?tag=name:result&tag=result:hit`
and `...&tag=result:miss`.

Start from the repository root
([docs/getting-started.md](../docs/getting-started.md)):

```powershell
.\scripts\start-stack.ps1 -Profile naive
.\scripts\start-stack.ps1 -Profile optimized -Instances 3
```
