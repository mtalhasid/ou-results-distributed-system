# Results

This comparison uses the `session2` naive runs and the `optimized` runs. Latency and dropped-arrival figures below are copied from the individual profile summaries; the charts show medians and individual-run points.

## Hot mode

Hot mode repeats lookups from a fixed key set, so the cache warms across the series.

| Peak | Naive p95 / avg / dropped | Optimized p95 / avg / dropped |
|---:|---:|---:|
| 50 req/s | 1.02 s / 0.47 s / 0.459% | 0.85 s / 0.15 s / 0.000% |
| 75 req/s | 6.48 s / 3.19 s / 19.056% | 0.76 s / 0.09 s / 0.000% |

![Hot-mode p95 latency](hot-p95.png)
![Hot-mode average latency](hot-average.png)
![Hot-mode delivered arrivals](hot-delivered.png)
![Hot-mode summary table](hot-summary-table.png)

The naive 75 req/s hot result reproduced across sessions: the baseline summary reports 6.38 s p95 and 19.708% dropped, and session2 reports 6.48 s p95 and 19.056% dropped.

Hot mode assumes lookups repeat: students refresh and check friends' results. The 3,000-key hot set is an assumption, not measured OU data. The 75 req/s runs came after six earlier hot runs, so the cache was already warm; a single cold run would see fewer hits. The hot-mode cache hit ratio was not measured. At 25 and 50 req/s, p95 is similar for both profiles (the slowest requests are most likely cache misses that still reach the database); the improvement shows in average latency and at 75 req/s.

## Uniform mode

Uniform mode makes each lookup use a new key, so the cache provides no consistent improvement. The measured cache counters for the uniform runs were 795 hits, 232 negative hits, 15,881 misses, and 20 lock waits. At 50 req/s the session2 p95 was 0.73 s naive versus 0.72 s optimized, while average latency was 0.34 s versus 0.35 s. At 75 req/s, the naive session2 summary reports 1.34 s p95, 0.60 s average, and 0.549% dropped; optimized reports 9.51 s p95, 3.40 s average, and 15.828% dropped. Individual 75 req/s p95 values varied widely: 1.34, 0.62, and 8.09 s naive; 10.00, 3.43, and 9.51 s optimized.

![Uniform-mode p95 latency](uniform-p95.png)
![Uniform-mode average latency](uniform-average.png)
![Uniform-mode delivered arrivals](uniform-delivered.png)
![Uniform-mode summary table](uniform-summary-table.png)

At 75 req/s the optimized profile was not better than naive and may be worse, though the runs overlap (p95 across runs: naive 0.62-8.09 s, optimized 3.43-10.00 s). The cause was not isolated; candidates are extra Redis round trips on misses, replica read capacity, and run-to-run noise.

**Test conditions:** same Windows 11 laptop (12th Gen Intel Core i5-1235U, 15.7 GB RAM), Temurin OpenJDK 25.0.4.1 with `-Xms128m -Xmx512m`, k6 v2.2.0, and the same Neon shard databases; 10 s timeout; runs interleaved the same night.

## How to regenerate

From the repository root, run:

```powershell
.\.venv\Scripts\python.exe .\load-tests\report\make_comparison.py
```
