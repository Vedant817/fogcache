# FogCache — Technical Design (Milestone 00)

Status: **Agreed baseline** · Version: 0.1.0 · Owner: Platform Engineering (Vedant Mahajan)
Source of truth: this document, the Linear document *FogCache — Product Requirements & Technical Design*, and the contract-first artifacts in `fogcache-contracts/`.

This is the master specification for milestone **00 — Product definition & architecture**. Every component of the source architecture diagram is represented here and decomposed into the project backlog. Companion documents:

| Area | Document |
|---|---|
| Scope, personas, non-goals | `docs/product/scope.md` |
| Acceptance journeys | `docs/product/acceptance-journeys.md` |
| Capacity model | `docs/architecture/capacity-model.md` |
| SLOs / SLIs / error budgets | `docs/architecture/slos.md` |
| ADRs | `docs/adr/ADR-0001.md` … `ADR-0008.md` |
| Cache-key & HTTP semantics | `docs/architecture/cache-semantics.md` |
| Ownership/replication/invalidation semantics | `docs/architecture/replication-semantics.md` |
| Threat model & controls | `docs/security/threat-model.md` |
| API & event contracts | `fogcache-contracts/` (`openapi/*.yaml`, `proto/*.proto`) |
| Diagrams, dependency map, risk register | `docs/architecture/diagrams.md`, `dependency-map.md`, `risk-register.md` |

## 1. Product goal

FogCache is a distributed, health-aware edge caching platform that serves content close to consumers, protects the origin from repeated requests, adapts object placement to observed demand, and gives operators complete visibility and control.

## 2. System decomposition

| Service | Responsibility | Key technologies |
|---|---|---|
| `fogcache-routing-service` | Node registration, health leases, consistent-hash topology, capacity weighting, routing decisions, topology inspection | Spring WebFlux, Redis/Redisson leases |
| `fogcache-edge-service` | Request handling, key normalization, cache semantics, memory/disk tiers, single-flight, origin client, events, replication endpoints, prefetch workers | WebFlux/Netty, Caffeine, RocksDB, gRPC |
| `fogcache-content-service` | Reference origin: versioned objects, conditional GET/HEAD, metadata, signed uploads, invalidation events | Spring Boot, S3-compatible storage (MinIO) |
| `fogcache-control-service` | Tenants, origins, policies, quotas, topology, models, admin APIs, audit; config source of truth | Spring Boot, PostgreSQL + Flyway |
| `fogcache-analytics-service` | Kafka stream processing: rolling features, HOT/WARM/COLD classification, placement decisions, ONNX inference | Spring Boot, Kafka Streams, ONNX Runtime |
| `fogcache-model-training` | Offline dataset validation, feature generation, baseline comparison, training, calibration, ONNX export | Python (scikit-learn/LightGBM) |
| `fogcache-admin-web` | Operations dashboard | Next.js + TypeScript |
| `fogcache-integration-tests` | E2E / contract / chaos verification | JUnit 5, Testcontainers, WireMock, Awaitility, Toxiproxy |

Shared modules: `fogcache-common` (utilities, clocks, hashing, observability), `fogcache-contracts` (OpenAPI, Protobuf, Kafka schemas), `fogcache-bom` (dependency management).

## 3. Request and routing path

1. Client/API consumer sends `GET/HEAD` to the edge (directly or through the optional gateway mode).
2. Routing service continuously evaluates node health leases, readiness, drain state, and capacity.
3. Consistent hashing maps the normalized cache key (see `cache-semantics.md`) to a primary node plus ordered fallback candidates.
4. The edge request handler validates the request and derives the cache policy (cacheability, TTL, vary, bypass).
5. The cache engine checks memory then disk tiers.
6. Hit: return stored representation with cache-status headers, emit access event.
7. Miss: per-key single-flight elects one loader; waiters share the outcome or receive controlled stale responses.
8. Loader fetches from the origin, validates size/cacheability/checksum, persists, publishes metadata/replication events, and responds.

## 4. Cluster intelligence path

Access/miss/eviction/fetch/prefetch/replication events flow to Kafka. The analytics service computes rolling features (rate, recency, concurrency, byte rate, miss cost, distribution), classifies keys **HOT/WARM/COLD** with hysteresis, estimates near-future demand, and proposes placement/replication/pin/prefetch/eviction actions. The edge executes approved actions within budgets. Kill switches disable ML decisions or prefetching at runtime.

## 5. Data model

Cache entry (`cache-semantics.md` §3): normalized key + hash, tenant/origin, status, selected headers, payload location + checksum, sizes, creation/last-access/expiry/SWR/SIE timestamps, ETag/Last-Modified/type/encoding, origin generation, admission score, traffic class, pin state, replica metadata, schema/serialization versions.

## 6. Consistency, ownership, and failure model

- Eventually consistent with origin unless explicit invalidation is delivered (`replication-semantics.md`).
- Each origin object carries a monotonically increasing invalidation generation.
- Replication transfers metadata + payload; receiver validates checksum and commits atomically; tombstones prevent resurrection.
- Routing serves from a locally cached topology during control-plane interruption; node failure causes bounded remapping and replica promotion.
- Admin operations are idempotent and auditable.

## 7. Quality goals (summary)

Correct cache semantics (TTL, ETag, Last-Modified, stale policies, negative caching, invalidation, size limits); no request stampede per key; graceful node loss with bounded remapping; measurable hit uplift from replication/prefetch without excess bandwidth; secure-by-default APIs; reproducible local environment; automated production delivery; complete runbooks/dashboards/alerts/DR.

## 8. Milestone 00 completion criteria

- [x] Every diagram component and data flow represented in this design and the backlog.
- [x] Open architectural questions resolved via ADR-0001…0008.
- [x] APIs and event contracts versioned and reviewable in `fogcache-contracts/`.
- [x] Acceptance scenarios and production-readiness criteria explicit (`acceptance-journeys.md`, `slos.md`).
- [x] The supplied FogCache architecture diagram remains the baseline reference.

## 9. Release gates (production-ready definition)

A production release requires: functional acceptance journeys pass; no open urgent/high security defects; measured performance with documented headroom; failover/backup/restore/rollback drills pass; dashboards and paging alerts active; runbooks and ownership complete; schema and model rollback paths tested; reproducible deployment from a tagged commit; published release notes and known limitations.
