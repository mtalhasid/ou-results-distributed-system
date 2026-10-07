# Gateway protection proof

Generated: 2026-10-07 16:41:33 +05:30

Gateway: `http://localhost:8080`; Eureka: `http://localhost:8761`.
Cache metrics (cache.gets) and circuit-breaker call counts are summed across
all registered UP read instances on ports `8082`;
use the optimized profile.
Raw k6 summary exports: `raw/invalid.json` and `raw/burst.json`.

## Invalid roll-number scenario

Configured for 50 requests/second over 20 seconds; every response is expected
to be HTTP 400.

- Status-code counts: 400=1000
- Accepted-request p95: n/a ms
- Rejected-request p95: 9.74 ms

Cache metric delta (expected zero â€” invalid requests are rejected before the read service):

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| cache.gets (hit) | 0 | 0 | 0 |
| cache.gets (miss) | 10 | 10 | 0 |
| shard1 breaker calls | 10 | 10 | 0 |
| shard2 breaker calls | 0 | 0 | 0 |

## Valid-roll burst scenario

Configured for 100 requests/second over 10 seconds to roll number
`160423733001`. HTTP 200 responses are accepted; HTTP 429 responses
should be rate-limited before reaching the read service; HTTP 503 responses
indicate the bulkhead or circuit breaker rejected the request.

- Status-code counts: 200=947, 503=53
- Accepted-request p95: 68.07 ms
- Rejected-request p95: 56.15 ms

Cache metric delta (only accepted requests should affect the read service):

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| cache.gets (hit) | 0 | 922 | 922 |
| cache.gets (miss) | 10 | 88 | 78 |
| shard1 breaker calls | 10 | 88 | 78 |
| shard2 breaker calls | 0 | 0 | 0 |

The miss delta equals the number of cold keys that required a database read.
Cache hits are served without a database call. Compare the shard breaker call
delta with the miss delta; they should be equal for a single-instance stack.