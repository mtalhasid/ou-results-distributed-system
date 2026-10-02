This is a bit inconsistent im not usig Docker everywhere.

# OU Results: Microservices Project Spec

Backend-only project that keeps a university results site alive when tens of thousands of students check at the same moment. Roll number in, result out.

## 1. Goal and scope

**Problem:** on result day, thousands of students hit the site at once. It crashes, then stays slow.

**Goal:** show core backend and system design skills, with proof from load tests (naive version vs optimized version).

**In scope**

- Result lookup by roll number under spike load
- Admin upload of results, then a publish step
- Student registration for the result email (roll number + college-issued password + email)
- Email with the result itself (text in the body, not a link), sent once to registered students each time results are published (about every 5 months)
- Load tests with k6

**Out of scope (non-goals)**

- No frontend, no deployment, no real student data (synthetic only)
- No student login. Admin endpoints use a static API key checked at the gateway.
- No observability stack (Actuator only). No unit tests until the very end.

**Future requirements (not now)**

- Result PDF download, and the result as a PDF attachment in the email

## 2. Roll number format

Example: 160423737017 (12 digits, same pattern for all OU affiliated colleges)

| Digits | Meaning | Example |
|---|---|---|
| 1-4 | College code | 1604 |
| 5-6 | Batch year | 23 |
| 7-9 | Department code | 737 |
| 10-12 | Roll number | 017 |

Validation at the gateway: `^\d{12}$` and college code in the known list. Junk never reaches Redis or the DB.

## 3. Services

| Service | Stack | Port | Job | Data |
|---|---|---|---|---|
| api-gateway | Spring Boot | 8080 | Routing, validation, rate limit, waiting room, circuit breaker | redis-state |
| service-discovery | Spring Boot | 8761 | Eureka registry | none |
| account-service | Node/Express | 8081 | Student registration, college-password check, brute-force protection | Neon account DB, redis-state |
| result-read-service (x3) | Spring Boot | 8082 (internal) | Read path, internal strong-read call | redis-cache, shard replicas (primaries for strong reads) |
| result-ingestion-service | Node/Express | 8083 | Admin upload, parse, split into batches, publish command | none |
| result-persistence-service | Spring Boot | 8084 | Only writer to shard primaries, upserts, publish saga, emits Kafka event | Neon shard primaries |
| notification-service | Spring Boot | 8085 | Email jobs, paced email worker, quota, email sending | Neon notification DB, redis-state |

Scaled instances get no host port. Only the gateway is exposed.

The two Node services are small, stateless and I/O-bound. They do not register with Eureka. The gateway and notification-service reach them by fixed Docker names from env vars (for example ACCOUNT_SERVICE_URL=http://account-service:8081).

## 3A. What belongs to which service

One place to look up where each concept lives. Folder names match section 9.

Account-service = who is this student. Notification-service = how do we tell them.

### api-gateway

- **Owns:** routing, roll number validation, per-IP rate limiting, waiting room, admin API key check, correlation ID creation, circuit breaker to the read service, load balancing (via Eureka)
- **Routes:** `/api/results/**` to lb://result-read-service, /api/register to account-service (strict rate limit), `/admin/**` to result-ingestion-service, and `/admin/exams/*/publish-status` to lb://result-persistence-service. The Node services are reached by URL from env vars, the Spring ones through Eureka.
- **Redis:** redis-state: rl: (rate limits), wr: (waiting room)
- **DB and messaging:** none
- **Note:** Spring Cloud Gateway is reactive (WebFlux)

### service-discovery

- **Owns:** the Eureka registry only
- **DB, messaging, secrets:** none

### account-service (Node/Express, TypeScript)

- **Owns:** registration, college-issued password check (BCrypt via bcryptjs), brute-force protection, one email per roll number, an internal paged list of registered students for the notification service
- **DB (Neon project 3, account DB):** registrations, student_credentials
- **Redis:** redis-state: failed-attempt counters (rl:), via ioredis
- **Messaging:** none
- **Reached by:** fixed Docker name (ACCOUNT_SERVICE_URL), not Eureka

### result-read-service (x3)

- **Owns:** the whole read path, cache-aside, negative caching, stampede lock, shard routing for reads, reads from replicas, circuit breaker to DB, the naive profile for load tests, the internal strong-read endpoint (primary reads), the CQRS read side
- **DB:** reads exams and results from the shard read replicas (from the primaries for strong reads)
- **Redis:** redis-cache: result: (cache), lock: (per-key lock). Eviction is set in compose, not here.
- **Kafka:** consumes results.published to pre-warm the cache (reads the primary, in pages)

### result-ingestion-service (Node/Express, TypeScript)

- **Owns:** admin upload API, file parsing and validation, splitting into batches, the publish command
- **RabbitMQ:** produces to results.write and results.publish (amqplib, JSON messages)
- **DB:** none
- **Reached by:** fixed Docker name from the gateway, not Eureka

### result-persistence-service

- **Owns:** the only writes to shard primaries, idempotent upserts, batch writes, stale-message guard, shard routing for writes, the publish saga, the publish status endpoint, the demo failure switch
- **DB:** writes exams and results on both shard primaries (2 DataSources, JPA plus native queries)
- **RabbitMQ:** consumes results.write and results.publish, with retry and `*.dlq`
- **Kafka:** produces results.published

### notification-service

- **Owns:** creating email jobs on publish, the paced email worker, daily quota counter, idempotency via email_log, the EmailSender interface (Mailpit or Mailjet), building the email text from the result
- **DB (Neon project 4, notification DB):** email_log
- **Redis:** redis-state: quota: (daily email count)
- **Kafka:** consumes results.published
- **RabbitMQ:** produces and consumes email.send, with `*.dlq`
- **Calls:** account-service (registered students, paged, by fixed Docker name) and result-read-service (strong read, via Eureka), both internal, with circuit breakers

### Not in a service folder

- **contracts/:** event schemas and shard-map.yml (each service gets a copy of the config)
- **docker-compose.yml:** redis-cache and redis-state (eviction settings), Kafka, RabbitMQ, Mailpit, profiles, .env
- **load-tests/:** k6 scripts and seed scripts
- **docs/:** HLD, diagrams, Postman collection
- **Neon:** projects 1 and 2 (shards), project 3 (account DB), project 4 (notification DB)

### In every service

Logging with the correlation ID (SLF4J in Java, pino in Node), `${VAR}` or environment config, its own Dockerfile

Spring Boot services also have Actuator and a pom.xml. Node services have a package.json and a /health endpoint.

## 4. Flows

### Read path (student)

1. Student calls gateway with roll number
2. Gateway: validate, rate limit per IP, waiting room check
3. Gateway load-balances (Eureka) to one of 3 read-service instances
4. Read service checks redis-cache (result:{rollNo})
5. Miss: find shard by college code, read from that shard's replica, store in Redis with TTL
6. Not found: cache a short-lived "not found" (negative caching). Keep this TTL short, and the post-publish cache warm-up overwrites these entries, so a student who looked before publish is not stuck with "not found".

### Internal strong read

- GET /internal/results/{rollNo}?consistency=strong on the read service reads the shard primary, not the replica
- Used by the email worker and by the cache warm-up, because the replica can lag right after publish
- Student reads stay on replicas (eventual consistency)
- Not exposed through the gateway
- The warm-up reads the primary in pages, so it does not hammer it

### Write path (admin)

1. Admin uploads results file to result-ingestion-service
2. Ingestion validates, splits into batches (about 500 rows), sends each to RabbitMQ results.write
3. Persistence service consumes each batch and upserts into the right shard. Key: (exam_id, roll_no, semester), so redelivery is harmless.
4. Failed batches retry, then go to results.write.dlq
5. Rows are saved with published = false

### Registration (student)

A simple "register your email" form. No login page, no sessions.

1. Student sends roll number, college-issued password and email to POST /api/register (through the gateway: roll number validation, strict per-IP rate limit)
2. Account service checks the password against student_credentials (BCrypt)
3. Wrong password: rejected. A failed-attempt counter in redis-state (per roll number and per IP) blocks brute-force guessing.
4. Right password: saves (roll_no, email). One email per roll number. Registering again replaces the email and needs the password again.
5. The password proves the roll number belongs to the student, so nobody can register a friend's roll number.

### Publish and notify

1. Admin calls publish. Ingestion sends a results.publish command to the persistence service.
2. Persistence service runs the publish saga (below), emits Kafka results.published, and only then acknowledges the command
3. Read service consumes the event and pre-warms redis-cache (reads the primary, overwrites negative entries)
4. Notification service consumes the event, fetches the registered students from account-service (paged, internal call), and creates email jobs on RabbitMQ email.send (with an email_log row per job). Only students who registered before publish get an email, never everyone. The job holds only roll no, email and exam, never the result.
5. For each job, the email worker fetches the result from result-read-service (internal strong read via Eureka, with a circuit breaker), builds the email text, then sends at a controlled rate, set below the provider limit (prefetch + rate limiter, batches of up to 50 messages per call on Mailjet v3.1). A daily quota counter in redis-state pauses the worker at the plan's daily cap (free plan: 200 per day), because mail queued past the cap at the provider is dropped after 3 days. Retry with backoff on 429, DLQ, and idempotency key (roll no + exam). Pacing also spreads student arrivals over time instead of one spike.
6. Sending sits behind an EmailSender interface: SmtpSender (Mailpit, local fake inbox) for load demos, MailjetSender for real sends to a few Gmail addresses. Chosen by Spring profile.

### Publish saga (in the persistence service)

1. Set exams.publish_status = PUBLISHING on both shards
2. Flip shard 1 (results.published = true)
3. Flip shard 2. Both flipped: status becomes SHARDS_PUBLISHED (data is live, event not yet sent).
4. Emit Kafka results.published, set status PUBLISHED, then acknowledge the RabbitMQ command

**Failure rules**

- Step 2 or 3 fails: retry with backoff (the flips are idempotent)
- Still failing: undo the flips already done (published = false), set status FAILED, log it
- Once both shards are flipped (SHARDS_PUBLISHED), never undo. The results are valid, so only move forward.
- Step 4 fails, or the process dies at any point: the command is not acknowledged, so RabbitMQ redelivers it and the saga runs again
- Every step can be re-run: flips use WHERE published = false, status changes are conditional, and the saga resumes from the current status
- The Kafka event may go out twice. Consumers are idempotent (the warm-up overwrites, email_log is unique), so that is safe.
- A publish stuck in SHARDS_PUBLISHED means the event has not gone out yet
- GET /admin/exams/{id}/publish-status reads both shards and shows the state. The admin can retry publish.
- Demo switch: a config flag makes shard 2 fail, to show the rollback in the logs

### Waiting room (in the gateway)

- redis-state keeps a set of active users, capped at N
- Extra users go into a sorted set (score = join time) and get a token
- Client polls GET /queue/status, and gets admitted when a slot frees
- Not a message queue: the student needs the answer now, so this is admission control

## 5. Data

Built from the real OU result page. Fields shown there: exam title and date, hall ticket no, gender, name, father's name, course, medium, subjects (code, name, credits, grade), semester, result with SGPA, overall CGPA. Only grades are shown, no numeric marks.

**Design choice:** one row per student per semester, subjects stored as a JSONB array in that row. No join on the read path, one index lookup, and the whole row fits as one Redis value. Published results never change, so denormalized data is safe.

### Results (per shard)

| Column | Example |
|---|---|
| exam_id | 2026-jul-aug |
| roll_no | 160423737017 |
| semester | 6 |
| college_code, batch_year, dept_code | 1604, 23, 737 (parsed from roll_no) |
| name, father_name, gender | synthetic |
| course, medium | B.E. (AICTE), ENGLISH |
| subjects (JSONB) | [{"code":"602H","name":"CLOUD COMPUTING","credits":3,"grade":"S"}, ...] |
| result_status | PASSED |
| sgpa | 8.36 |
| cgpa | null (shown as "-") |
| published | false until publish |
| uploaded_at | time of the upload batch, used to ignore older redelivered batches |

Primary key: (exam_id, roll_no, semester)

One roll number can have several rows in one exam (backlog semesters). Lookup returns all of them as one list, cached under one Redis key.

### Exams (copied to each shard)

exam_id, title, result_date, publish_status (DRAFT, PUBLISHING, SHARDS_PUBLISHED, PUBLISHED, FAILED)

- results.exam_id can be a foreign key here, because both tables live on the same shard
- Foreign keys cannot cross shards, so all of a student's data stays in one shard

### Registrations (account DB)

- Columns: roll_no (primary key), email, created_at
- One email per roll number. Registration is standing: register once, get every semester's result.

### Student credentials (account DB)

- Columns: roll_no (primary key), password_hash (BCrypt)
- Stands in for the college-issued passwords. In real life this check would call the college's own system.
- This is the college-issued password, never the email account's password (never ask for that).

### Email log (notification DB)

- Columns: roll_no, exam_id, email, status (PENDING, SENT, FAILED), attempts, sent_at
- Unique: (roll_no, exam_id). This is the idempotency record, and it shows what happened to each email.

**Sharding:** 2 shards. A shard map assigns each of the 8-9 college codes to a shard, balanced by student count. Map lives in contracts/shard-map.yml, passed to the read and persistence services as config.

## 6. Messaging

| Tool | Name | Use |
|---|---|---|
| RabbitMQ | results.write | Batches from ingestion to the persistence service |
| RabbitMQ | results.publish | Publish command, acknowledged only after the Kafka event is sent |
| RabbitMQ | email.send | Email jobs (roll no, email, exam; no result data), paced to the email API limit |
| RabbitMQ | `*.dlq` | Failed messages |
| Kafka | results.published | Event to the read service (cache warm-up) and the notification service |
| Kafka | result.viewed (optional) | Analytics stream |

**Why both:** RabbitMQ is for jobs that need retries and a DLQ. Kafka is for events many services react to. If this split can't be explained in the HLD, drop one.

**Message format:** ingestion (Node) sends plain JSON with content type application/json, and the persistence service (Java) reads it. Configure the Java side with the JSON message converter, because Spring's default expects Java-style messages. The schemas live in contracts/, and Node validates them with zod.

## 7. Infrastructure

### Neon (Postgres, no local DB)

- Project 1: shard 1 (primary + read replica). Tables: exams, results
- Project 2: shard 2 (primary + read replica). Same tables.
- Project 3: account DB. Tables: registrations, student_credentials
- Project 4: notification DB. Table: email_log
- Use Neon's pooled connection string and small HikariCP pools
- Each shard needs two connection strings in .env: primary and replica (for example SHARD1_PRIMARY_URL, SHARD1_REPLICA_URL). The persistence service uses primaries only. The read service uses replicas, and primaries for strong reads.

### Docker containers: about 14

- Apps: gateway, service-discovery, account, ingestion, persistence, notification, read x3 = 9
- Infra: Kafka (KRaft), RabbitMQ, redis-cache, redis-state, Mailpit = 5

### Redis: two instances (same image, different config)

- **redis-cache:** result:, lock:. Used by the read service. Eviction is Redis config, not code: maxmemory + maxmemory-policy allkeys-lru.
- **redis-state:** rl: (rate limits, failed-attempt counters), wr: (waiting room), quota: (daily email count). Used by the gateway, account-service and notification-service. maxmemory-policy noeviction, because losing this state would break the waiting room, the limits and the quota.
- Local Docker vs Upstash is still open (see section 11). Upstash would need two databases.

### Compose (docker-compose.yml at the repo root)

- Profiles let you start only what a test needs: read (service-discovery, gateway, read service x3, redis-cache, redis-state), write (RabbitMQ, ingestion, persistence), events (Kafka, account-service, notification-service, Mailpit)
- Profiles add up: docker compose --profile read --profile write up
- One .env at the repo root, not committed. Commit .env.example instead.
- Compose reads it, and each service's environment: block passes only what that service needs (for example, the email key goes only to notification-service)
- Each application.yml uses `${VAR}` placeholders. When running from the IDE, set the same variables in the run configuration.

## 8. System design concepts

| Concept | Where |
|---|---|
| Cache-aside, TTL | Read service + redis-cache |
| Negative caching | Not-found results, short TTL, overwritten by the warm-up |
| Cache eviction | redis-cache maxmemory + allkeys-lru, configured not coded |
| Cache vs control state | Two Redis instances: cache (LRU) and state (noeviction) |
| Cache pre-warming | Kafka results.published consumer in the read service |
| Stampede protection | Per-key Redis lock on cache miss |
| Rate limiting | Gateway, Redis token bucket |
| Waiting room / admission control | Gateway + redis-state |
| Load balancing, service discovery | Gateway + Eureka, 3 read-service instances (the Node services are reached by fixed Docker names) |
| Read replicas | Read service reads |
| Consistency modes | Students read replicas (eventual). Email worker and cache warm-up read the primary (consistency=strong). |
| Sharding | Route by college code |
| Async work queue, retry, DLQ | RabbitMQ |
| Rate-limited consumer, backpressure | Paced email worker on email.send, daily quota counter in redis-state |
| Event-driven | Kafka |
| CQRS (light) | Read side: redis-cache + replicas. Write side: ingestion + persistence to primaries. The Kafka event keeps the read side warm. |
| Saga (orchestrated) | Publish across 2 shards: retry, undo, re-runnable steps, SHARDS_PUBLISHED as the point of no return |
| Idempotent consumers | Upsert key (exam_id, roll_no, semester), email idempotency key (roll no + exam) |
| Atomic upsert, stale-message guard | INSERT ... ON CONFLICT DO UPDATE as a native query in the persistence service (JPA save() selects first, then inserts), ignore older redelivered batches |
| Batch writes | One JDBC batch per queue message, not row-by-row inserts (the write-side N+1) |
| Atomic counters | Redis INCR or Lua script for waiting room admission |
| Unique constraints | Duplicate registrations, double publish (UPDATE ... WHERE published = false) |
| Password hashing, brute-force protection | BCrypt (bcryptjs) for student credentials, failed-attempt counter in redis-state per roll number and IP |
| Circuit breaker, fallback | Resilience4j (gateway to read service, read service to DB, notification to read service and account-service) |
| Input validation | Roll number format |
| Load testing | k6, naive vs optimized |

## 9. Folder structure

```
ou-results/
├── docker-compose.yml
├── .env.example
├── .env             (not committed)
├── .gitignore
├── README.md
├── docs/            (HLD, diagrams, design decisions, Postman collection)
├── contracts/       (event schemas, shard-map.yml)
├── load-tests/      (k6 scripts, seed data script)
├── service-discovery/
├── api-gateway/
├── account-service/             (Node/Express)
├── result-read-service/
├── result-ingestion-service/    (Node/Express)
├── result-persistence-service/
└── notification-service/
```

Each service is its own project with its own Dockerfile. Spring Boot services have a pom.xml, Node services have a package.json. No shared code between services. There is one .env at the repo root, none inside service folders, and none for service-discovery (it needs no secrets).

## 10. Seed data and load testing

### Seed data

- Synthetic students only, roll numbers built from the real pattern (college code + year + department + 3-digit roll)
- Fake name, father's name and gender per student. Subjects come from a small catalog per department and semester. Grades are random (S, A, B, C, plus a few fails).
- SGPA is computed from credits and grade points (S=10, A=9, B=8, C=7 reproduces the sample result of 8.36). Check how fails are scored before seeding them.
- Target: about 100,000 result rows across the 2 shards (about 50,000 each). More rows do not make the demo stronger, because the problem is concurrency, not data size.
- Check size on Neon: the Free plan allows 0.5 GB per project (verify current limit)
- Generate a CSV with a script (load-tests/seed/) and bulk load with COPY
- Also push a small batch (5,000-10,000 rows) through the real upload path to test ingestion, RabbitMQ and the persistence service
- Credentials (account DB): give all synthetic students one precomputed BCrypt hash of a known test password. BCrypt is slow by design, so hashing 100,000 passwords one by one would take hours.

### k6 (free, open source)

- Scripts in JavaScript, run from CLI or Docker. No huge JSON file of students.
- The script generates valid roll numbers with the same pattern (about 95%) plus some non-existent or invalid ones (about 5%) to exercise negative caching and validation
- Scenarios: ramp to N users, then a sudden spike
- Baseline: Spring profile naive (no cache, no limits, direct DB reads)
- Optimized: all protections on
- Run both with the same N. Start with a few hundred users and raise it.
- Metrics from k6: p95 latency, error rate, requests per second. Cache hit ratio from Actuator/Micrometer counters.
- Report relative results only (same N, naive fails, optimized survives). k6 shares the laptop CPU.
- Keep runs short: load on Neon uses compute hours
- Load tests send emails to Mailpit (local fake SMTP inbox), never to the real provider
- Manual demo: a Postman collection (exported to docs/) covers the full flow: upload, publish, lookup, register. k6 is for load only.

**Tests:** unit and integration tests (Testcontainers) are optional and done last.

## 11. Open decisions

- Redis: local Docker (fair load tests, no quota) or Upstash (free-tier limits, network latency, two databases needed)
- Email provider: Mailjet (free plan: 6,000 emails per month, 200 per day, verify current limits).
- Neon read replicas: one per shard on the Free plan. Each replica uses compute hours, so watch the monthly CU-hours.
- Neon cold start: verify during the first load test (scale to zero after idle)
- Shards: 2 (the publish saga depends on this)
- Kafka result.viewed analytics: include or skip
- Publish saga across the 2 shards: included
- Optional stretch: transactional outbox for the Kafka event (skipped by default, redelivery plus SHARDS_PUBLISHED covers it)
- Observability: skipped for now, Spring Boot Actuator only (Prometheus and Grafana are free when self-hosted, but cost laptop RAM)
- account-service split out of notification-service
- Two Redis instances: cache and state
- Service names: result-read-service, result-ingestion-service, result-persistence-service, service-discovery
- Node/Express (TypeScript) for account-service and result-ingestion-service, Spring Boot for the rest

## 12. Build phases

1. **Skeleton:** service-discovery, gateway, read service (naive, direct DB), Neon shard 1, seed script, baseline k6 numbers
2. **Protections:** validation, redis-cache, negative caching, rate limit, read replica
3. **Write path:** ingestion, RabbitMQ, persistence service, DLQ, second shard and routing
4. **Events:** Kafka publish, cache warming, account-service (registration), notification-service, email jobs
5. **Resilience:** waiting room, circuit breaker, 3 read-service instances via Eureka, publish saga, strong-read path
6. **Proof:** load test comparison, README, design decisions doc, diagram
7. **Optional, last:** unit and integration tests

## 13. Decisions and why

- **Monorepo:** one folder, independent services. Easier to review, one compose file.
- **Persistence service:** single owner of shard writes. Keeps routing, idempotency and retries in one place.
- **Ingestion vs persistence:** ingestion is the admin-facing API. It accepts, validates, queues and returns fast. The persistence service does the DB work at a controlled pace and scales separately. They could be merged, but the split shows a queue-based write path.
- **Account vs notification:** account-service answers "who is this student" (registration, password check). Notification-service answers "how do we tell them" (jobs, pacing, quota, sending). Each has its own DB and a clear job.
- **No exam-service:** the exam lifecycle (DRAFT to PUBLISHED) is tied to publishing, which the persistence service owns. A separate service would add a boundary without adding value.
- **Node for two small services:** account-service and ingestion are small, stateless and I/O-bound, and Node uses much less RAM than a JVM (helpful with 14 containers). The services that carry the system-design substance (gateway, discovery, read, persistence, notification) stay in Spring Boot. Costs: no Eureka for the Node services (fixed Docker names), a JSON message contract with the Java side, and a second toolchain. In the HLD: "right tool per service".
- **Publish saga, not a distributed transaction:** two shards can't share one DB transaction. The saga uses idempotent local steps, an undo for the flips, and SHARDS_PUBLISHED as the point of no return. The RabbitMQ command is acknowledged only after the Kafka event is sent, so a crash means redelivery, not a lost event.
- **Outbox skipped:** with two shards an outbox row can only join one shard's transaction, so it would not close the gap by itself. Redelivery plus the status field does.
- **Reads skip the persistence service:** the read path stays short and fast.
- **Strong read for internal calls:** the replica can lag right after publish, so the email worker and the cache warm-up read the primary. Students read replicas.
- **Sharding is optional in value:** the data is small, so one DB would hold it. It is a scaling demo, and the README should say so.
- **Waiting room in Redis, not a queue:** the student needs an answer, not a background job.
- **Static admin key:** auth is not the point of this project.
- **Two Redis instances:** cache data can be evicted, but waiting room, rate limit and quota state must not be. Eviction is per instance, so they are separate: allkeys-lru for the cache, noeviction for the state. It also makes it safe to demo eviction on the cache.
- **Registration proof:** roll number + college-issued password. It proves the roll number, not the email address. The damage is capped at one email per roll number, so a confirmation email is skipped (it would also use Mailjet quota).
- **No MongoDB:** results are document-shaped, but Postgres JSONB reads by key just as fast, and Redis gives the real speed-up. Mongo would be one more thing to run and keep in sync.

## 14. Logging

SLF4J API with Logback (Spring Boot default). Lombok @Slf4j in each class.

The Node services (account-service, result-ingestion-service) use pino with the same line format. A small middleware reads or creates X-Correlation-Id, keeps it in AsyncLocalStorage, and puts it in RabbitMQ message headers.

**Format:** every line has timestamp, level, service name, correlation ID, message.

- The gateway creates an X-Correlation-Id for each request (or reuses the incoming one)
- Each service puts it in the MDC, so it prints on every line
- It is passed on in HTTP headers and in RabbitMQ and Kafka message headers
- To follow one request across services, search all logs for that ID

### What to log (key=value style)

| Service | Events |
|---|---|
| api-gateway | request received, invalid roll number, rate limited, waiting room queued / admitted |
| account-service | registration accepted or rejected, lockout |
| result-read-service | cache hit or miss, shard chosen, DB read time, lock wait, not-found cached, strong read served, warm-up page done |
| result-ingestion-service | upload received (row count), batches published |
| result-persistence-service | batch received, rows upserted, duplicates skipped, sent to DLQ, saga step started / done / retried / undone, publish status changed, Kafka event sent |
| notification-service | event received, registered students fetched, jobs queued |
| email worker | job started, email sent, 429 backoff, quota cap reached, moved to DLQ |

**Levels:** INFO for normal events, WARN for retries and rate limits, ERROR for failures, DEBUG for detail (off by default).

### Rules

- Never log full email addresses (mask them, for example `a***@gmail.com`)
- Do not log names or marks
- Log at decision points, not on every line of code
- Reading logs: `docker compose logs -f <service>`, then search by correlation ID. No log stack (ELK, Loki) for now, in line with the no-observability-stack decision.

## 15. Dependencies

### Java services (Spring Initializr)

Project settings: Maven, Java 21, Jar, the default stable Spring Boot version (Initializr picks the matching Spring Cloud version). Artifact = folder name. Names in the Initializr search box can differ slightly by version.

Every Java service except service-discovery: Eureka Discovery Client, Spring Boot Actuator, Lombok

| Service | Add in Initializr | Add manually |
|---|---|---|
| service-discovery | Eureka Server, Actuator | none |
| api-gateway | Gateway (the reactive one, not Gateway MVC), Spring Data Reactive Redis, Resilience4J | spring-cloud-starter-circuitbreaker-reactor-resilience4j if the reactive variant is not listed |
| result-read-service | Spring Web, Spring Data JPA, PostgreSQL Driver, Spring Data Redis (Access+Driver), Spring for Apache Kafka, Resilience4J, Validation | none |
| result-persistence-service | Spring Web, Spring Data JPA, PostgreSQL Driver, Spring for RabbitMQ, Spring for Apache Kafka, Validation | none |
| notification-service | Spring Web, Spring Data JPA, PostgreSQL Driver, Spring Data Redis (Access+Driver), Spring for RabbitMQ, Spring for Apache Kafka, Resilience4J, Java Mail Sender, Validation, Flyway (optional) | none |

**Notes**

- Mailjet is called over REST with RestClient (part of Spring Web), so no extra library. Java Mail Sender is for the Mailpit SMTP path.
- Service-to-service calls use RestClient. Calls to the read service are load balanced (included with the Eureka client). Calls to account-service use its fixed URL. No OpenFeign.
- Virtual threads for the read service: spring.threads.virtual.enabled=true (needs Java 21).
- Add a JSON message converter on the RabbitMQ consumers, because ingestion sends plain JSON.
- Left out for now: Testcontainers (tests come last), DevTools, Docker Compose support.

### Node services (TypeScript, current LTS Node)

| Service | Packages | Dev packages |
|---|---|---|
| account-service | express, pg, bcryptjs, ioredis, zod, pino | typescript, tsx, @types/* |
| result-ingestion-service | express, multer, csv-parse, amqplib, zod, pino | typescript, tsx, @types/* |

**Notes**

- pg uses Neon's pooled connection string
- Account DB tables: a plain SQL file, or node-pg-migrate
- bcryptjs is pure JavaScript, so no native build in Docker
- Registration rate limiting happens at the gateway. The failed-attempt counter lives in redis-state via ioredis.