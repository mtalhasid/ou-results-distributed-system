# Gateway protection proof

Generated: 2026-10-03 04:56:15 +05:30

Gateway: `http://localhost:8080`; read-service Actuator: `http://localhost:8082/actuator/metrics`.
The read service must use the optimized profile for cache counters.
Raw k6 summary exports: `raw/invalid.json` and `raw/burst.json`.

## Invalid roll-number scenario

Configured for 50 requests/second over 20 seconds; every response is expected
to be HTTP 400.

- Status-code counts: 400=1001
- Accepted-request p95: n/a ms
- Rejected-request p95: 3.55 ms

Cache counter delta (expected zero):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
| result.cache.hit | 0 | 0 | 0 |
| result.cache.miss | 0 | 0 | 0 |
| result.cache.negative.hit | 0 | 0 | 0 |

## Valid-roll burst scenario

Configured for 100 requests/second over 10 seconds to roll number
`160423733001`. HTTP 200 responses are accepted; HTTP 429 responses
should be rate-limited before reaching the read service.

- Status-code counts: 200=129, 429=871
- Accepted-request p95: 9414.31 ms
- Rejected-request p95: 6.67 ms

Cache counter delta (only accepted requests should affect the read service):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
| result.cache.hit | 0 | 50 | 50 |
| result.cache.miss | 0 | 79 | 79 |
| result.cache.negative.hit | 0 | 0 | 0 |

Negative hits are also included in the hit counter. Compare the hit and miss
deltas with the HTTP 200 count; external concurrent traffic can affect these
Actuator deltas.