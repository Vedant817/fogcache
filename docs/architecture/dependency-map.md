# FogCache — Dependency Map & Ownership Matrix (00.10)

Status: Agreed · Version: 1 · Issue: VED-59
Every external dependency has explicit **timeout, retry, fallback, and observability** expectations; criticality feeds the risk register and runbooks.

## 1. Service → dependency ownership matrix

| Service | Depends on | Purpose | Criticality |
|---|---|---|---|
| Edge | Routing (topology snapshot) | ring + candidates | High (cached; degraded mode OK) |
| Edge | Origin (HTTP) | fetch/revalidate | High (fallback: stale/502) |
| Edge | Kafka | event emission | Medium (buffered ≤ 10 min) |
| Edge | Redis | cross-node single-flight fallback | Low (request path independent) |
| Edge | RocksDB (local) | disk tier | Medium (memory-only mode) |
| Routing | Redis | health leases, ring state | High (control; data plane degrades gracefully) |
| Control | PostgreSQL | config + audit source of truth | High |
| Control | Kafka | invalidation/audit events | High (invalidation propagation) |
| Control | OIDC provider | admin auth | High (login only; cached tokens) |
| Analytics | Kafka | event streams | High |
| Analytics | ONNX model artifact (S3) | inference | Medium (rule fallback) |
| Content | S3-compatible object storage | payloads | High |
| All | OTel collector → LGTM | telemetry | Medium (no request-path impact) |

## 2. Dependency expectations (timeout / retry / fallback / observability)

| Dependency | Timeout | Retry | Fallback | Observability |
|---|---|---|---|---|
| Origin fetch | 3 s connect + total 10 s (per class) | 1 retry on connect/idempotent failures only | stale-if-error; negative cache | fetch duration, status, error class, amplification |
| Origin revalidate | 2 s | none (single-flight) | serve stale | 304 rate |
| Routing resolve | 100 ms | none (cache topology) | last cached topology; direct ring computation | resolve latency, cache staleness |
| Redis lease | 50 ms | 1 | local lease (optimistic) | lease errors, fallback count |
| Redis single-flight | 200 ms | 1 | in-process future only | fallback count |
| Kafka produce | 2 s batch | 3 with backoff | in-memory buffer, then drop-with-metric after 10 min | buffer depth, dropped events |
| Kafka consume | n/a | infinite with rebalance | lag monitors; rule-based classification | lag per partition |
| PostgreSQL | 1 s | 2 | read replica not in v1; degrade admin writes to 503 | pool saturation |
| S3 | 5 s | 3 | none (content service) | latency, error rate |
| OIDC | 3 s | 1 | cached JWKS; deny closed | auth failure rate |
| gRPC transfer | 30 s stream idle | 3 on network error | repair sweep re-issues | transfer duration, retry, checksum failures |
| OTel export | 1 s | 3 | drop metrics (never block) | export failure count |

## 3. Failure-mode and dependency-criticality map

| Failure | Impact | Mitigation | Criticality |
|---|---|---|---|
| Routing down | topology refresh stops; ring stale | edges use cached snapshot + direct ring (≥ 5 min); alerts | High |
| Redis down | leases degrade | local lease fallback; control-plane degradation only | Medium |
| Kafka down | events buffered; classification degrades to rules | buffering + drop-with-metric; invalidation via gRPC push fallback | Medium |
| PostgreSQL down | admin/config writes fail; reads from cache | control-plane availability SLO separate; failover in milestone 13 | Medium |
| Origin down | misses fail | stale-if-error / negative cache / 502 | High |
| Single edge node down | keys remap | ≤ 20% movement, replica promotion | High |
| One AZ down | 1/3 nodes | cross-AZ replicas (rf=2 → HOT rf=3) | High |
| RocksDB corrupt | disk tier lost | entry checksums + recovery sweep + memory-only mode | Medium |

## 4. Ownership of dependencies (team/owner)

| Dependency | Owner | Notes |
|---|---|---|
| Edge cache engine, single-flight, key normalization | Edge platform | milestone 05/06 |
| Ring, leases, topology | Routing platform | milestone 04 |
| Config, audit, admin APIs | Control platform | milestone 10 |
| Classification, placement, ML | Analytics/ML | milestones 08/09 |
| Kafka/Redis/PostgreSQL/S3 ops | Platform/SRE | milestones 13/14 |
| Dashboards, alerts, burn rates | SRE | milestone 10/12 |
