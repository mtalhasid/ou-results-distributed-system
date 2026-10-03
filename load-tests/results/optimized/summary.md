# Load Test Summary

Generated: 2026-10-03 13:45:06 India Standard Time

## Arrival-rate runs

Values are grouped by label and mode, then medianed across matching runs. Latencies are in seconds; dropped-iteration percentage uses expected arrivals from the configured rate stages.

| Label | Mode | Peak req/s | Median p95 (s) | Median avg (s) | Error rate | Dropped iterations | Delivered | Max VUs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| optimized | hot | 25 | 0.89 | 0.34 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 50 | 0.85 | 0.15 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 75 | 0.76 | 0.09 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 25 | 0.91 | 0.51 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 50 | 0.72 | 0.35 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 75 | 9.51 | 3.40 | 0.938% | 15.828% (461) | 84.17% | 300 |
| optimized-gw | hot | 25 | 0.86 | 0.35 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 50 | 0.58 | 0.11 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 75 | 0.52 | 0.05 | 0.000% | 0.000% (0) | 100.00% | 50 |

### Individual arrival-rate runs

| Label | Mode | Peak req/s | Run | p95 (s) | Average (s) | Errors | Dropped iterations | Delivered | Max VUs |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| optimized | hot | 25 | 1 | 0.89 | 0.41 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 25 | 2 | 0.90 | 0.34 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 25 | 3 | 0.86 | 0.28 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 50 | 1 | 0.85 | 0.19 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 50 | 2 | 0.87 | 0.15 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 50 | 3 | 0.85 | 0.12 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 75 | 1 | 0.76 | 0.09 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 75 | 2 | 0.51 | 0.05 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | hot | 75 | 3 | 0.82 | 0.12 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 25 | 1 | 1.02 | 0.54 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 25 | 2 | 0.90 | 0.49 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 25 | 3 | 0.91 | 0.51 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 50 | 1 | 0.72 | 0.35 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 50 | 2 | 0.83 | 0.40 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 50 | 3 | 0.69 | 0.34 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized | uniform | 75 | 1 | 10.00 | 3.61 | 5.579% | 18.129% (528) | 81.87% | 300 |
| optimized | uniform | 75 | 2 | 3.43 | 1.22 | 0.000% | 2.953% (86) | 97.05% | 135 |
| optimized | uniform | 75 | 3 | 9.51 | 3.40 | 0.938% | 15.828% (461) | 84.17% | 300 |
| optimized-gw | hot | 25 | 1 | 0.70 | 0.35 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 25 | 2 | 1.58 | 0.53 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 25 | 3 | 0.86 | 0.25 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 50 | 1 | 0.77 | 0.17 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 50 | 2 | 0.58 | 0.11 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 50 | 3 | 0.57 | 0.07 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 75 | 1 | 0.52 | 0.05 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 75 | 2 | 0.27 | 0.03 | 0.000% | 0.000% (0) | 100.00% | 50 |
| optimized-gw | hot | 75 | 3 | 0.58 | 0.09 | 0.000% | 0.000% (0) | 100.00% | 50 |
