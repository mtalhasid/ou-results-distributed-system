# Load Test Summary

Generated: 2026-10-01 17:26:58 India Standard Time

## VU baseline

Values are medians across matching `-run<i>.json` files. Latencies are milliseconds; errors are percentages.

| Label | VUs | Median p95 (ms) | Median avg (ms) | Requests/s | Error rate |
|---|---:|---:|---:|---:|---:|
| baseline | 25 | 624.00 | 371.45 | 33.37 | 0.000% |
| baseline | 50 | 1320.57 | 618.34 | 45.58 | 0.000% |
| baseline | 100 | 2682.29 | 1093.52 | 54.58 | 0.000% |

## Arrival-rate runs

Values are medians across matching `-arrival-<P>-run<i>.json` files. Achieved throughput is `http_reqs.count / 60 seconds`; dropped-iteration percentage uses expected arrivals from the configured rate stages.

| Label | Peak req/s | Median p95 (ms) | Median avg (ms) | Error rate | Dropped iterations | Max VUs |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 25 | 1393.03 | 548.61 | 0.000% | 0.000% (0) | 50 |
| baseline | 50 | 12546.76 | 1679.24 | 0.109% | 6.420% (126) | 176 |
| baseline-confirmation | 25 | 1182.17 | 560.35 | 0.000% | 0.000% (0) | 50 |
| baseline-confirmation | 50 | 3249.89 | 1050.30 | 0.000% | 2.650% (52) | 102 |
