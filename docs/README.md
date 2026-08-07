# FogCache — Documentation Index (Milestone 00)

Status: Agreed baseline · Version: 0.1.0

Milestone **00 — Product definition & architecture** deliverables. Master spec: `docs/technical-design.md`.

## Engineering (milestone 01)

| Doc | Covers |
|---|---|
| `../CONTRIBUTING.md` | Build, quality gates, dependency hygiene, commit conventions, CI |
| `development.md` | Local setup, first build, running services, troubleshooting |
| `architecture/module-ownership.md` | Build-time module graph, ownership matrix, dependency rules (VED-36) |

## Product

| Doc | Covers |
|---|---|
| `product/scope.md` | Personas, use cases, protocol boundaries, multi-tenancy, non-goals (VED-50) |
| `product/acceptance-journeys.md` | J-01…J-12 journeys with negative variants, events, evidence (VED-51) |

## Architecture

| Doc | Covers |
|---|---|
| `architecture/capacity-model.md` | Workload, object sizes, ratios, failure assumptions, scenarios (VED-52) |
| `architecture/slos.md` | SLI/SLO tables, error budgets, burn rates, release thresholds (VED-53) |
| `architecture/cache-semantics.md` | Key normalization, Vary/private/compression, conditional requests, invalidation (VED-55) |
| `architecture/replication-semantics.md` | Ownership, generations, tombstones, transfer protocol, anti-entropy (VED-56) |
| `architecture/contract-conventions.md` | Versioning, compatibility, idempotency, pagination, errors, topics (VED-58) |
| `architecture/diagrams.md` | Mermaid context/container/sequence/state diagrams (VED-59) |
| `architecture/dependency-map.md` | Ownership matrix, timeout/retry/fallback expectations, criticality (VED-59) |
| `architecture/risk-register.md` | Risk register with mitigation, trigger, owner, contingency (VED-59) |

## Decisions

| Doc | Covers |
|---|---|
| `adr/ADR-0001.md` | Monorepo and service decomposition |
| `adr/ADR-0002.md` | Spring WebFlux/Netty request path |
| `adr/ADR-0003.md` | Caffeine memory tier + RocksDB disk tier |
| `adr/ADR-0004.md` | PostgreSQL/Redis/Kafka/S3 responsibilities (source of truth) |
| `adr/ADR-0005.md` | REST vs gRPC boundaries |
| `adr/ADR-0006.md` | Consistent-hash ownership model |
| `adr/ADR-0007.md` | Python training + ONNX inference in Spring Boot |
| `adr/ADR-0008.md` | Kubernetes deployment topology |

(VED-54)

## Security

| Doc | Covers |
|---|---|
| `security/threat-model.md` | Assets, actors, trust boundaries, threat table T-01…T-12, control matrix (VED-57) |

## Contracts (VED-58)

| Artifact | Covers |
|---|---|
| `fogcache-contracts/src/main/proto/fogcache_internal.proto` | Metadata, Transfer, Invalidation, Probe, Repair, Prefetch gRPC |
| `fogcache-contracts/src/main/proto/fogcache_events.proto` | Access, Invalidation, Replication, Classification, Placement, Prefetch, Audit Kafka events |
| `fogcache-contracts/src/main/resources/openapi/fogcache-edge.yaml` | Public GET/HEAD data plane |
| `fogcache-contracts/src/main/resources/openapi/fogcache-routing.yaml` | Register, heartbeat, drain, resolve, topology |
| `fogcache-contracts/src/main/resources/openapi/fogcache-admin.yaml` | Tenant, origin, policy, quota, key-action, node, analytics, model, audit |

## Versioning convention

Docs change via PRs that also update the corresponding ADR/contract; diagrams are re-validated against `technical-design.md` on every milestone review.
