# OU Results: Build Phases

Read path first. Each phase ends with a checkpoint you can demo. Do not start the next phase until the checkpoint passes.

## Rules for every phase

- Docs alongside, not at the end: update the root README, `docs/getting-started.md`, `docs/results.md`, the architecture diagram and the Postman collection as each phase lands.
- Correlation ID and the logging format from spec section 14 go in from the first service, not later.
- Every k6 run records: N users, p95 latency, error rate, requests per second, machine specs, date. Save results under `load-tests/results/<profile>/` (`naive` or `optimized`).
- Warm the database with a few requests before each k6 run, and run naive vs optimized at the same N.
- Use `mem_limit` in compose and compose profiles, so only the containers a test needs are running.
- Cut rule: if Phase 2 is not done in about 2 weeks, stop adding scope until it is. If time runs short later, drop Phase 6 first, then Kafka.

---

## Phase 1: Skeleton and baseline

**Goal:** a working naive read service and honest baseline numbers.

**Tasks**
- Repo skeleton from spec section 9, `.gitignore`, `.env.example`.
- `.env` with the two Neon shard primary URLs and direct connection strings for bulk loading. Replicas and account/notification DB credentials are added only in later phases when they are needed. Neon only, no local Postgres.
- Seed tooling in `load-tests/seed/` (schema, per-shard CSVs, manifest, credentials). Bulk load each shard CSV into its own Neon primary with `COPY` (direct connection string). Never seed the replicas.
- `result-read-service` (Spring Boot, Java 21, Spring Data JPA): `GET /api/results/{rollNo}` returns all rows for the roll number as one list. Shard routing by college code from `shard-map.yml` (two Hikari pools behind a routing datasource). Spring profile `naive`: no cache, no limits, reads the shard primaries directly, default Hikari pool.
- k6 script: generate valid roll numbers from `seed-manifest.json` (about 95%) plus invalid or non-existent ones (about 5%). Scenarios: ramp to N users, then a sudden spike.
- Run the baseline. Start with a few hundred users and raise N until the naive service degrades.

**Checkpoint:** a saved baseline showing latency and errors climbing as N rises.

**Watch out for:** do not sabotage the naive version. Default settings only, otherwise the comparison is not credible. Neon cold starts and compute hours: warm the DBs before each run, keep runs short, report relative results only.

---

## Phase 2: Protections (minimum shippable project)

**Goal:** the optimized read path survives the same load that broke the naive one.

**Tasks**
- `api-gateway` (Spring Cloud Gateway, the reactive one): static route to the read service for now. Roll number validation (`^\d{12}$` plus college code in the known list, from `shard-map.yml`).
- `redis-cache` container: `maxmemory` plus `allkeys-lru`, set in compose.
- Cache-aside in the read service with a TTL. Key: `result:{rollNo}`, one value holding the whole list.
- Negative caching with a short TTL for not-found.
- Stampede protection: per-key lock on cache miss (`lock:` prefix, `SET NX PX`), with a short wait and re-check.
- `redis-state` container (`noeviction`): per-IP token bucket rate limit in the gateway (`rl:` prefix).
- Micrometer counters for cache hit, miss and negative hit, visible through Actuator.
- Optimized profile reads the shard replicas; naive stays on primaries.
- Re-run k6 at the same N as the baseline.

**Checkpoint:** naive vs optimized graph at the same N, plus the cache hit ratio. Write the first README version and the LinkedIn post from this.

**Watch out for:** the k6 test needs a warm-up phase and a cold-cache run. Report both.

---

## Phase 3: Scale-out and resilience

**Goal:** show the read tier scales by adding instances, and degrades gracefully.

**Tasks**
- `service-discovery` (Eureka). Read service registers. Gateway route changes to `lb://result-read-service`.
- Run 3 read instances with no host ports.
- Resilience4j circuit breaker: gateway to read service, and read service to DB, with a fallback response.
- Waiting room in the gateway (spec section 4): active-user set capped at N, sorted set for the overflow, a token, `GET /queue/status`, atomic admission with INCR or Lua (`wr:` prefix).
- k6 with 1, 2 and 3 read instances at the same load.

**Checkpoint:** a graph of throughput or p95 against instance count, and a demo of the waiting room admitting users as slots free.

**Implementation note (Phase 3 landed):** Eureka, multi-instance stack launcher, gateway and per-shard circuit breakers/bulkheads, and 1/2/3-instance plus high-rate k6 runs are in place. The waiting-room checkpoint was not shipped.

**Watch out for:** Eureka registration delay (about 30 seconds) after startup, which can cause errors that are not real bugs.

---

## Phase 4: Write path and sharding

**Goal:** get data in through the real upload path, onto the right shard.

**Tasks**
- `contracts/`: message schemas and `shard-map.yml`. Node validates with zod.
- `result-ingestion-service` (Node/Express, TypeScript): multer upload, csv-parse, validation, split into batches of about 500 rows, publish to RabbitMQ `results.write` as plain JSON (`application/json`). Gateway route `/admin/**` with the static API key check.
- `result-persistence-service` (Spring Boot): consumes `results.write` with the JSON message converter. Shard routing by college code. Native `INSERT ... ON CONFLICT DO UPDATE` upsert, one JDBC batch per message, stale-message guard using `uploaded_at`. Rows saved with `published = false`. Retry, then `results.write.dlq`.
- RabbitMQ container and the `write` compose profile.

**Checkpoint:** uploading a 5,000-10,000 row file lands rows on the correct shard. A deliberately broken batch ends up in the DLQ. Re-uploading the same file changes nothing (idempotent).

---

## Phase 5: Publish saga and strong reads

**Goal:** publishing is safe across two shards, and the read side stays warm.

**Tasks**
- `results.publish` command from ingestion to persistence.
- Publish saga in the persistence service, exactly as in spec section 4: PUBLISHING, flip shard 1, flip shard 2, SHARDS_PUBLISHED, emit the event, PUBLISHED, then ack the command.
- Failure rules: retry with backoff, undo if still failing before SHARDS_PUBLISHED, never undo after it. Flips use `WHERE published = false`, status changes are conditional, the saga resumes from the current status.
- `GET /admin/exams/{id}/publish-status` reading both shards.
- Demo switch: a config flag that makes shard 2 fail.
- Strong-read endpoint: `GET /internal/results/{rollNo}?consistency=strong`, reading the primary. Not exposed through the gateway.
- Cache warm-up in the read service: consume the publish event, read the primary in pages, overwrite cache and negative entries. Decide at the start of this phase: RabbitMQ fanout (simpler) or Kafka (the spec's choice).

**Checkpoint:** (1) happy path publishes and results become readable. (2) With the demo switch on, logs show the rollback and status FAILED. (3) Kill the process after SHARDS_PUBLISHED, restart, and the command is redelivered and completes.

---

## Phase 6: Registration and email

**Goal:** registered students get their result by email, at a controlled rate.

**Tasks**
- `account-service` (Node/Express): `POST /api/register`, BCrypt check against `student_credentials`, failed-attempt counters in `redis-state` per roll number and IP, one email per roll number, internal paged list of registered students. Gateway route with a strict rate limit. Neon project 3.
- `notification-service` (Spring Boot): consumes the publish event, fetches registered students (paged, with a circuit breaker), creates jobs on `email.send` with an `email_log` row each (unique on roll no + exam). Jobs hold no result data. Neon project 4.
- Paced email worker: fetch the result via strong read (through Eureka, circuit breaker), build the email text, send at a controlled rate, retry with backoff on 429, DLQ, daily quota counter in `redis-state`.
- `EmailSender` interface: `SmtpSender` (Mailpit) by default, `MailjetSender` behind a Spring profile.
- Never log full email addresses.

**Checkpoint:** register, publish, and the email appears in Mailpit. Lowering the quota to a small number pauses the worker. Real Mailjet sends only to a few of your own Gmail addresses.

---

## After Phase 6

- Final load-test comparison, README, design decisions doc, diagram.
- Unit and integration tests (Testcontainers) come last and are optional.

Phases plan: 4 tweaks

Phase 1: add a Dockerfile and a compose service for the read service. Measure the baseline in a container with mem_limit, the same way as later runs, not from the IDE.
Phase 1 implementation note: use Spring Data JPA with a routing datasource selected by college code, and Java records for response DTOs. The baseline reads primaries, and does not require gateway, Redis, replicas, or write-path containers.
Phase 3 checkpoint: scaling to 3 instances on one laptop won't show linear throughput, because they share one CPU. A more credible demo is killing one instance under load and showing errors stay low. Keep the 1/2/3 graph as secondary.
Phase 6: load credentials.csv into the account DB and create the account tables there.