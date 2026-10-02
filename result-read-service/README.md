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
uses Redis cache-aside with 10-minute result entries, 30-second negative
entries, and per-result locks; Redis outages fall back to the replica
databases. Its counters are available under `/actuator/metrics/result.cache.hit`,
`result.cache.miss`, `result.cache.negative.hit`, and `result.cache.lock.wait`.
