# Tradeoffs: What this project is and is not

This is not a replacement for OU's current result portal. It is a prototype of a general architecture for a specific class of traffic shape: high read spikes, controlled write windows, and outbound work that must respect external limits (like email quota).

The OU result page is the concrete example. The same shape appears in ticket booking, exam results, visa appointment openings, and flash sales. Those systems all share the same problem: millions of reads in a short window, writes that must not fail halfway, and downstream systems with hard limits.

This project is built for that shape. It is not the cheapest way to serve OU, and it does not try to be. It is the version that handles the shape at scale, with mutation, and with external constraints.

## Table of Contents

- [1. Cost](#1-cost)
- [2. Complexity](#2-complexity)
- [What this project demonstrates](#what-this-project-demonstrates)
- [What this project actually solves](#what-this-project-actually-solves)
- [Why Kafka when there is already a message queue?](#why-kafka-when-there-is-already-a-message-queue)

---

## 1. Cost

Idle cost is the first thing to understand. Most services (read, ingestion, persistence, notification, gateway) sit idle ~99% of the year. Results are published roughly twice a year. The system is not a 24/7 workload.

| Deployment | Monthly cost | Notes |
|---|---|---|
| Naive managed (always-on Kafka, RabbitMQ, 9 ECS services, 4 always-on Postgres) | $500–1000 | What you get if you deploy the spec without thinking about cost |
| Cost-aware (scale-to-zero compute, Upstash, Neon auto-suspend, self-hosted messaging) | $20–80 | The correct deployment for this workload |
| CDN + small backend (R2 + Cloudflare + small function + Neon Free) | $5–30 | Cheapest for OU's actual read path |

The gap is 2–3x, not 50x. The $500–1000 figure exists because most people deploy naively on managed services. That's a real deployment, and it's what a junior engineer would do. It's worth documenting so the tradeoff is visible.

What makes it cheap:

- Compute scales to zero between publish windows (Cloud Run, Fly.io, or ECS with min tasks = 0)
- Neon auto-suspends Postgres after idle (already the default on Free)
- Messaging (Kafka, RabbitMQ) only runs during publish windows - not always on
- Redis is only needed for the cache and state, not for cold idle time

The honest conclusion: the system is not cost-optimized - it is shape-optimized. A CDN + small backend is cheaper and would serve OU fine. This project builds the distributed version because the shape is the interesting problem.

---

## 2. Complexity

Yes, this is overengineered for OU's actual load. Own it.

**Why 9 services?**
Because the goal is to demonstrate ownership boundaries and independent scaling, not to serve OU cheaply. Each service exists to show a distinct concern: saga in persistence, backpressure in notification, cache-aside and stampede protection in read, admission control in gateway.

The 3-service version that would actually run OU:

- gateway (routing, rate limit, validation)
- results-service (read + write merged)
- notification-worker (email jobs)

With Redis + Neon + Mailjet, that handles result day fine. It would cost less and be easier to operate.

**Why not build that instead?**
Because it doesn't demonstrate sharding, saga, DLQ, cache warm-up, or paced consumption - and those are the mechanisms that matter when the shape is real (ticket booking, flash sales, payment systems). The full version exists to show what the shape demands at scale, not to be the cheapest possible OU backend.

The README says so, and that's the point. The complexity is deliberate, documented, and justified by the goal (demonstrating the shape at scale), not hidden.

---

## What this project demonstrates

Not a checklist of patterns - a set of architectural qualities that follow from the shape:

- Horizontally scalable: add read-service instances, add replicas, add shards, without rewriting
- Independently scalable layers: read and write scale on different axes
- Loosely coupled: services communicate through events and queues, no shared code, no cross-service DB reads
- Extensible: new consumers join the event log without touching producers
- Resilient: failures in one layer don't cascade (circuit breakers, DLQ, fallbacks)
- Consistent where it matters: students read replicas (eventual), email reads primaries (strong)
- Cost-aware by design: scale-to-zero compute, serverless Postgres, messaging only during publish windows

Patterns like saga, cache-aside, and DLQ are the mechanisms behind these qualities - not the goal.

---

## What this project actually solves

It solves:

- A read endpoint that survives a 100x spike without overloading the database
- A publish flow that writes across two independent shards atomically, with rollback and a point of no return
- An email pipeline that respects provider quota and rate limits without dropping messages
- Cache invalidation and re-publish for mutable results (revaluation)

It does not solve:

- OU's actual production needs (which are simpler: CDN + small backend)
- Real student data, real auth, PDF downloads, deployment
- Cross-shard queries or global consistency across shards

Say this plainly in the README. It shows judgment, not just coding ability.

---

## Why Kafka when there is already a message queue?

RabbitMQ is a job queue. Kafka is an event log. They solve different problems.

| | RabbitMQ | Kafka |
|---|---|---|
| Model | Job queue | Event log |
| Message lifetime | Deleted after ack | Retained for days/weeks |
| Consumers | One consumer (or competing consumers) | Many independent consumer groups |
| Replay | No | Yes |
| Best for | "Do this job, retry on failure, DLQ" | "This happened, react to it, replay if needed" |

In this project:

- results.write → job queue. Batches must be processed once, retried, DLQ'd. RabbitMQ.
- results.publish → command. Acked only after the saga completes. RabbitMQ.
- email.send → job queue with pacing and quota. RabbitMQ.
- results.published → event. Two independent consumers (read service for cache warm-up, notification service for email jobs). Replayable. Kafka.

Honest counter: for two consumers, Redis Streams or Postgres LISTEN/NOTIFY would do. Kafka is here to demonstrate fan-out to independent consumer groups with replay and retention - the pattern that matters when the number of consumers grows (analytics, audit, new services) without touching producers.

The README states this explicitly. Kafka is used for exactly one event, and the honest alternative is named.