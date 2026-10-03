# Gateway protection proof

Generated: 2026-10-03 13:19:06 +05:30

Gateway: `http://localhost:8080`; read-service Actuator: `http://localhost:8082/actuator/metrics`.
The read service must use the optimized profile for cache counters.
Raw k6 summary exports: `raw/invalid.json` and `raw/burst.json`.

## Invalid roll-number scenario

Configured for 50 requests/second over 20 seconds; every response is expected
to be HTTP 400.

- Status-code counts: 400=1001
- Accepted-request p95: n/a ms
- Rejected-request p95: 5.78 ms

Cache counter delta (expected zero):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
| result.cache.hit | 0 | 0 | 0 |
| result.cache.miss | 10 | 10 | 0 |
| result.cache.negative.hit | 0 | 0 | 0 |
| result.cache.lock.wait | 0 | 0 | 0 |

## Valid-roll burst scenario

Configured for 100 requests/second over 10 seconds to roll number
`160423733001`. HTTP 200 responses are accepted; HTTP 429 responses
should be rate-limited before reaching the read service.

- Status-code counts: 200=130, 429=871
- Accepted-request p95: 1904.49 ms
- Rejected-request p95: 9.32 ms

Cache counter delta (only accepted requests should affect the read service):

| Counter | Before | After | Delta |
|---|---:|---:|---:|
| result.cache.hit | 0 | 100 | 100 |
| result.cache.miss | 10 | 40 | 30 |
| result.cache.negative.hit | 0 | 0 | 0 |
| result.cache.lock.wait | 0 | 29 | 29 |

Negative hits are also included in the hit counter. Compare the hit and miss
deltas with the HTTP 200 count; external concurrent traffic can affect these
Actuator deltas.