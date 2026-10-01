# Load Test Summary

Generated: 2026-10-02 03:01:43 India Standard Time

## VU baseline

Values are medians across matching `-run<i>.json` files. Latencies are seconds; errors are percentages.

| Label | VUs | Median p95 (s) | Median avg (s) | Requests/s | Error rate |
|---|---:|---:|---:|---:|---:|
| baseline | 25 | 0.62 | 0.37 | 33.37 | 0.000% |
| baseline | 50 | 1.32 | 0.62 | 45.58 | 0.000% |
| baseline | 100 | 2.68 | 1.09 | 54.58 | 0.000% |

### Individual VU runs

| Label | VUs | Run | p95 (s) | Average (s) | Requests/s | Errors |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 25 | 1 | 0.87 | 0.43 | 30.08 | 0.000% |
| baseline | 25 | 2 | 0.62 | 0.36 | 34.60 | 0.000% |
| baseline | 25 | 3 | 0.61 | 0.37 | 33.37 | 0.000% |
| baseline | 50 | 1 | 1.25 | 0.62 | 45.58 | 0.000% |
| baseline | 50 | 2 | 1.50 | 0.62 | 44.23 | 0.000% |
| baseline | 50 | 3 | 1.32 | 0.54 | 49.79 | 0.000% |
| baseline | 100 | 1 | 2.56 | 1.02 | 58.02 | 0.000% |
| baseline | 100 | 2 | 2.68 | 1.09 | 54.58 | 0.000% |
| baseline | 100 | 3 | 4.17 | 1.51 | 40.49 | 0.000% |

## Arrival-rate runs

Values are grouped by label and mode, then medianed across matching runs. Latencies are in seconds; dropped-iteration percentage uses expected arrivals from the configured rate stages.

| Label | Mode | Peak req/s | Median p95 (s) | Median avg (s) | Error rate | Dropped iterations | Delivered | Max VUs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| baseline | hot | 25 | 0.89 | 0.50 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | hot | 50 | 1.21 | 0.71 | 0.000% | 0.611% (12) | 99.39% | 59 |
| baseline | hot | 75 | 6.38 | 3.14 | 0.000% | 19.708% (574) | 80.29% | 300 |
| baseline | uniform | 25 | 0.59 | 0.39 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 50 | 0.60 | 0.34 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 75 | 6.91 | 2.07 | 0.148% | 7.039% (205) | 92.96% | 255 |
| baseline-confirmation | uniform | 25 | 1.18 | 0.56 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline-confirmation | uniform | 50 | 3.25 | 1.05 | 0.000% | 2.650% (52) | 97.35% | 102 |
| baseline-legacy | uniform | 25 | 1.39 | 0.55 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline-legacy | uniform | 50 | 12.55 | 1.68 | 0.109% | 6.420% (126) | 93.58% | 176 |

### Individual arrival-rate runs

| Label | Mode | Peak req/s | Run | p95 (s) | Average (s) | Errors | Dropped iterations | Delivered | Max VUs |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | hot | 25 | 1 | 1.22 | 0.59 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | hot | 25 | 2 | 0.86 | 0.49 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | hot | 25 | 3 | 0.89 | 0.50 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | hot | 50 | 1 | 1.40 | 0.71 | 0.000% | 0.968% (19) | 99.03% | 68 |
| baseline | hot | 50 | 2 | 1.21 | 0.72 | 0.000% | 0.611% (12) | 99.39% | 59 |
| baseline | hot | 50 | 3 | 0.77 | 0.47 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | hot | 75 | 1 | 5.81 | 3.14 | 0.000% | 19.708% (574) | 80.29% | 300 |
| baseline | hot | 75 | 2 | 6.43 | 3.45 | 0.044% | 22.627% (659) | 77.37% | 300 |
| baseline | hot | 75 | 3 | 6.38 | 2.87 | 0.000% | 17.064% (497) | 82.93% | 300 |
| baseline | uniform | 25 | 1 | 0.64 | 0.41 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 25 | 2 | 0.59 | 0.39 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 25 | 3 | 0.58 | 0.39 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 50 | 1 | 0.57 | 0.34 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 50 | 2 | 0.60 | 0.35 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 50 | 3 | 0.62 | 0.32 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline | uniform | 75 | 1 | 3.15 | 1.17 | 0.000% | 2.884% (84) | 97.12% | 134 |
| baseline | uniform | 75 | 2 | 6.91 | 2.07 | 0.148% | 7.039% (205) | 92.96% | 255 |
| baseline | uniform | 75 | 3 | 10.00 | 3.64 | 13.814% | 19.948% (581) | 80.05% | 300 |
| baseline-confirmation | uniform | 25 | 1 | 0.80 | 0.40 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline-confirmation | uniform | 25 | 2 | 2.26 | 0.76 | 0.000% | 0.889% (9) | 99.11% | 59 |
| baseline-confirmation | uniform | 25 | 3 | 1.18 | 0.56 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline-confirmation | uniform | 50 | 1 | 7.41 | 3.78 | 0.000% | 9.376% (184) | 90.62% | 234 |
| baseline-confirmation | uniform | 50 | 2 | 2.42 | 0.73 | 0.000% | 1.529% (30) | 98.47% | 80 |
| baseline-confirmation | uniform | 50 | 3 | 3.25 | 1.05 | 0.000% | 2.650% (52) | 97.35% | 102 |
| baseline-legacy | uniform | 25 | 1 | 1.39 | 0.55 | 0.000% | 0.000% (0) | 100.00% | 50 |
| baseline-legacy | uniform | 50 | 1 | 12.55 | 1.68 | 0.109% | 6.420% (126) | 93.58% | 176 |
