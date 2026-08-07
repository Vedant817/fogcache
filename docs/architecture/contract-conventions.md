# FogCache — Contract Conventions (00.9)

Status: Agreed · Version: 1 · Issue: VED-58
Applies to every contract in `fogcache-contracts/` (OpenAPI in `src/main/resources/openapi/`, Protobuf in `src/main/proto/`, Kafka topics per `fogcache_events.proto`).

## 1. Versioning and compatibility

- **APIs:** path versioning `/v1/…`. A major version breaks backward compatibility; minors are additive only.
- **Protobuf:** package `fogcache.internal.v1` / `fogcache.events.v1`. Within a version: fields are additive; field numbers are never reused; removed fields are reserved; `oneof` members may be added, not removed or reordered.
- **Kafka events:** schema evolution uses the same Protobuf rules; topic names never change within a major; a new major uses a new topic name (`fogcache.events.access.v2`).
- **Compatibility contract (testable):** new producer + old consumer and old producer + new consumer must both decode; serialization compatibility is property-tested (milestone 01/12).
- **Cache key schema:** `keyVersion` in every entry; bumping the version invalidates old-version entries (migration, not code change).

## 2. Idempotency

- All mutating admin operations accept an optional `Idempotency-Key` header; responses for a repeated key within the retention window (24 h) replay the original result.
- Event processors dedupe on `(originId, originSeq)` or `(keyHash, originGeneration, entryGeneration)`.
- Transfers are idempotent: equal/lower generation ⇒ `ALREADY_CURRENT` no-op.

## 3. Pagination

- `page` (0-based) + `pageSize` (default 100, max 1000); stable ordering by `id` (or `keyHash`) so pages do not shift between calls.
- Response: `{items, page, pageSize, total, nextPage}`; `nextPage` cursor for streams.

## 4. Errors

- RFC 7807 `application/problem+json`: `{type, title, status, detail, instance, correlationId}`.
- Error taxonomy: `400 validation`, `401 unauthenticated`, `403 forbidden` (incl. role), `404 unknown resource`, `405 method`, `409 conflict/idempotency`, `413 too large`, `429 quota/rate limit` (with `Retry-After`), `502 origin unreachable`, `503 no healthy node`, `504 upstream timeout`.
- Internal error details are never leaked in responses or cache content; generic safe messages plus `correlationId`.

## 5. Correlation and tracing

- Every request accepts/propagates `X-Request-Id` (edge, routing, admin); generated if absent (UUID), echoed in responses and in every emitted event envelope (`correlation_id`).
- Trace context (W3C `traceparent`) propagated across REST/gRPC/Kafka for OpenTelemetry correlation.

## 6. Kafka topics and retention

| Topic | Partition key | Retention | Sensitive fields |
|---|---|---|---|
| `fogcache.events.access` | keyHash | 7 d | none (normalized key may be hashed for high-cardinality) |
| `fogcache.events.invalidation` | originId | 7 d | none |
| `fogcache.events.replication` | keyHash | 7 d | none |
| `fogcache.events.classification` | keyHash | 30 d | none |
| `fogcache.events.placement` | keyHash | 30 d | none |
| `fogcache.events.prefetch` | keyHash | 7 d | none |
| `fogcache.events.audit` | originId | 90 d | `detail` must not contain secrets/PII |

- Ordering guarantees: per-partition ordering by `originSeq` for invalidation; access events may be batched/aggregated.
- Producers: edges (access/replication/prefetch), control (invalidation/audit), analytics (classification/placement), content (invalidation).

## 7. Ownership of contract changes

`fogcache-contracts` is the single review surface: any schema change requires a PR touching only `fogcache-contracts` + consumers' adapters; compatibility tests must pass before merge.
