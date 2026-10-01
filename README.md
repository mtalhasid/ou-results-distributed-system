# OU Results

An educational backend system-design project for a result-day traffic spike.
The project starts with a deliberately naive read path, measures its limits,
then adds protections in later phases. All result data is synthetic; this is
not a production OU portal.

## Phase 1: naive read baseline

Phase 1 consists of deterministic synthetic data, two Postgres shards, a
containerized Spring Boot read service, and a k6 ramp-and-spike test. The
baseline reads shard primaries directly with default Hikari settings. It has
no cache, gateway, rate limit, or waiting room. The read service uses Spring
Data JPA, college-code shard routing, Lombok constructor injection, and a
response record.

### Generate the data

Install Python 3 and the one extra package, `bcrypt`:

```powershell
python -m pip install bcrypt
python .\load-tests\seed\generate.py --upload-sample 5000
```

The generator creates schemas, seed CSVs, a manifest, credentials and the
shard map. `--upload-sample` is optional; its rows are reserved for the later
write-path phase. Outputs live in the ignored `load-tests/seed/out/` folder.

### Configure and load Neon

Copy the variable names from `.env.example` into your local `.env` without
overwriting any existing local settings. Fill in the two JDBC primary URLs and
the two direct Postgres URLs locally. Do not send or commit credentials.

For each shard, set the direct URL in your terminal environment, then apply
`schema_shard.sql`, `exams.csv`, and its matching results CSV using the `psql \copy` commands in
[load-tests/seed/README.md](./load-tests/seed/README.md). Do not seed replicas.

### Build and run the read demo locally

Docker is not required for the normal local run. Build the JAR using the
existing Maven wrapper:

```powershell
.\api-gateway\mvnw.cmd -B -f .\result-read-service\pom.xml -DskipTests package
```

Then run the launcher. It reads the two primary URLs from the root `.env`
without printing them, sets the naive profile and shard-map path for this
process, and caps the Java heap at 512 MiB. Press Ctrl+C to stop the service.

```powershell
.\scripts\start-read.ps1
```

The project targets Java 21. The detected `java` command on the development
machine was Java 25; use Java 21 for the most representative supported runtime
when available. The script accepts `-MaxHeapMb` if you need a different
documented heap cap.

Warm it with a few requests, then run the load test (install k6 separately):

```powershell
curl.exe http://localhost:8082/api/results/160423733001
k6 run -e VUS=100 -e BASE_URL=http://localhost:8082 `
  --summary-export=load-tests/results/baseline-100.json `
  .\load-tests\k6\read-baseline.js
```

Repeat at increasing `VUS` values, saving each summary under
`load-tests/results/`. Record VUs, p95, error rate, requests/second, machine
specifications, and date. The 5% non-existent roll numbers use valid known
college codes and should return an empty list, not an HTTP error. Stop the
service with Ctrl+C in the launcher window.

The baseline is not complete until the generator checks pass, the CSVs load
successfully into both shards, and the read/load test works against those
databases. No write-path, cache, gateway, Redis, RabbitMQ, or Kafka containers
are needed for this phase. The Dockerfile and Compose service remain as an
optional alternate way to run the read service.
