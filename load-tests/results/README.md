# Naive read baseline run record

## Environment used for the initial baseline

- Service launch: packaged JAR, started with `.\scripts\start-read.ps1` from the repository root.
- Effective Java command: `java -Xms128m -Xmx512m -jar .\result-read-service\target\result-read-service-0.0.1-SNAPSHOT.jar`
- JVM flags: `-Xms128m -Xmx512m`
- Java: Temurin OpenJDK `25.0.4.1`; the project compiles for Java 21.
- Spring profile: `naive`.
- Datasources: reads route to the two Neon shard primary URLs; the read replicas are not used.
- HikariCP: default configuration, no pool-size overrides. HikariCP's default `maximumPoolSize` is 10 per shard pool and, when unset, `minimumIdle` defaults to the maximum. The observation script reads and prints the effective `maximumPoolSize` from Actuator before its run; record that output with the measurements.
- Machine: Windows 11 Home Single Language, 12th Gen Intel Core i5-1235U, 15.7 GB RAM.
- k6: `v2.2.0 (commit/00a9a1b7f5, windows/amd64)`.
- Initial run date: 2026-10-01.

## How to reproduce

1. Ensure the root `.env` contains the two shard primary URLs. Do not print, commit, or share it.
2. Build the JAR from the repository root:

   ```powershell
   .\api-gateway\mvnw.cmd -B -f .\result-read-service\pom.xml -DskipTests package
   ```

3. Start the service and leave that PowerShell window open:

   ```powershell
   .\scripts\start-read.ps1
   ```

4. In another PowerShell window, run the controlled warmed repetitions:

   ```powershell
   .\load-tests\k6\run-baseline.ps1
   ```

   This warms one seeded roll number on each shard five times before every run,
   runs 25, 50, and 100 VUs three times each, waits 20 seconds between
   repetitions, and writes per-run k6 summaries plus `baseline-summary.md`.

The naive and optimized comparisons must use the same machine, Java runtime,
JVM flags, k6 version, shard database setup, load profile, warm-up procedure,
and test timing. Report those conditions with both result sets. The initial
`baseline-25.json`, `baseline-50.json`, and `baseline-100.json` are historical
unwarmed runs and are intentionally preserved separately from the repeated
warmed runs.

## Optional Hikari observation

The service exposes Actuator metrics read-only; no pool behavior or size is
changed. After rebuilding/restarting the service, run:

```powershell
.\load-tests\k6\run-hikari-observation.ps1
```

It samples `hikaricp.connections.pending` and
`hikaricp.connections.active` every two seconds during one 100-VU run and
writes `hikari-100.csv`.

## Fixed arrival-rate spike scenario

The separate `read-arrival.js` test offers a fixed request arrival rate:
20 seconds ramping to 25% of PEAK, 5 seconds to PEAK, 30 seconds holding
PEAK, then 5 seconds ramping to zero. The runner defaults to peaks of 25, 50,
75, and 100 requests/second, one run each. Unlike a VU-based test, the offered
request rate does not decrease just because the service slows down; this
models students continuing to arrive during a result-day spike. `MAXVUS`
(default 300) caps concurrent VUs and therefore the number of concurrent
in-flight requests k6 can sustain. At high latency, this cap can prevent k6
from starting all scheduled iterations; k6 reports those as
`dropped_iterations`. This is part of the measured result and is reported, not
hidden.

From the repository root, run the default repeated baseline:

```powershell
.\load-tests\k6\run-arrival.ps1
```

To choose peaks, repeat selected rates, or stop immediately after any run
crosses a breaking-point threshold:

```powershell
.\load-tests\k6\run-arrival.ps1 -Peaks 25,50,75,100 -Runs 1 -Label baseline -StopOnBreak
.\load-tests\k6\run-arrival.ps1 -Peaks 75,100 -Runs 3 -Label baseline -MaxVus 300 -StopOnBreak
```

Naive and optimized comparisons must use the same arrival script, PEAK values,
MAXVUS, machine, Java/JVM setup, k6 version, shard database setup, warm-up,
and run timing. The report is regenerated from the matching
`<label>-arrival-<peak>-run<run>.json` files by the runner.

## Reports and dashboard exports

Both load-test runners export a self-contained k6 dashboard HTML file under
`load-tests/results/html/` for each repeated run. They temporarily enable
`K6_WEB_DASHBOARD` and `K6_WEB_DASHBOARD_EXPORT` and restore their previous
values when the run finishes or fails. `load-tests/report/make_report.py`
reads only repeated JSON files matching `-run<i>.json`, then regenerates
`summary.md` and PNG comparisons under `load-tests/results/charts/`. The
historical unwarmed `baseline-25.json`, `baseline-50.json`, and
`baseline-100.json` files are left untouched and excluded.
