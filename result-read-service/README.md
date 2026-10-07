# Read service profiles

Start the cache container when using the optimized profile:

```powershell
docker compose up -d redis-cache
```

Build the service with the repository Maven wrapper, then start either profile
from the repository root. The launcher defaults to `naive`; optimized uses the
`SHARD_1_PRIMARY_REPLICA` and `SHARD_2_PRIMARY_REPLICA` values from the root
`.env` and reads from those replicas.

```powershell
.\api-gateway\mvnw.cmd -B -f .\result-read-service\pom.xml -DskipTests package
.\scripts\start-read.ps1
.\scripts\start-read.ps1 -Profile optimized
```

The naive profile reads shard primaries without caching. The optimized profile
uses Spring's standard `@Cacheable` with a `RedisCacheManager`; entries expire
after 10 minutes. If Redis is unavailable the service falls back to the replica
databases. Cache metrics are available via Spring's built-in `cache.gets` counter
under `/actuator/metrics/cache.gets?tag=name:result&tag=result:hit` and
`/actuator/metrics/cache.gets?tag=name:result&tag=result:miss`.

Concurrent requests for an uncached roll number each cause a separate database
read. The earlier implementation included a per-key Redis lock that collapsed
these into one; that lock was removed when the cache was replaced with
`@Cacheable`.
