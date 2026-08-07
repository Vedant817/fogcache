# FogCache — Capacity Model (00.3)

Status: Agreed · Version: 0.1.0 · Issue: VED-52
All assumptions are **parameterized** (names in `snake_case`) and referenced by load-test profiles and initial Kubernetes resource requests. Values are validated in milestone 12.

## 1. Baseline workload (normal)

| Parameter | Value | Notes |
|---|---|---|
| `total_rps_normal` | 20,000 rps | aggregate edge ingress |
| `peak_rps` | 80,000 rps (4× normal, 15-min window) | product launch / flash traffic |
| `degraded_rps` | 10,000 rps (control-plane degraded) | no Redis/Kafka dependency at request path |
| `concurrency_per_node` | 2,000 in-flight | per edge node |
| `tenants` | 10 (v1), 100 (year 2) | quota enforcement per tenant |
| `keys_total` | 200 M unique normalized keys (disk indexable) | 50% LRU-active at any time |
| `nodes_initial` | 3 local / 9 production edge nodes | 3 per AZ, 3 AZs |
| `replication_factor` | 2 (HOT: 3) | per `replication-semantics.md` |
| `virtual_nodes_per_node` | 160 | ring granularity |

## 2. Object-size distribution

| Class | Size range | Share of requests | Share of bytes |
|---|---|---|---|
| small | < 8 KB | 55% | 4% |
| medium | 8 KB – 256 KB | 30% | 22% |
| large | 256 KB – 5 MB | 13% | 48% |
| huge | 5 MB – 100 MB | 2% | 26% |

`max_object_size = 100 MB` (reject above; per-tenant override). Median 6 KB, p95 1.5 MB.

## 3. Read/write/invalidation ratios

- `reads : origin_writes : invalidations = 98 : 1 : 1` (invalidations dominated by tag/prefix purges).
- Origin writes are **not** proxied (non-goal); invalidations are explicit admin/control-plane operations plus content-service events.

## 4. Hot-key and burst characteristics

- 1% of keys carry 40% of requests (`hot_key_head`).
- Burst: 10× steady rate for 30 s on a single key (flash crowd); `burst_ratio` feature feeds the classifier.
- HOT threshold baseline: > 50 rps over 1-min window; WARM: 5–50 rps; COLD: < 5 rps (configurable, hysteresis per `slos.md`/`cache-semantics.md`).

## 5. Origin latency and error distributions

| Metric | Value |
|---|---|
| origin p50 | 40 ms |
| origin p95 | 250 ms |
| origin p99 | 900 ms |
| origin timeout (fetch) | 3 s (`origin_fetch_timeout`) |
| origin error rate | 0.5% baseline, bursts to 10% |
| revalidation cost | 1.5% of origin load (ETag 304s) |

## 6. Resource estimates

| Resource | Per edge node (production size) | Basis |
|---|---|---|
| memory tier | 32 GB (Caffeine) | 100 M entries × ~300 B metadata avg |
| disk tier | 500 GB (RocksDB) | large/huge classes + recovery |
| network | 1 Gbps sustained, 10 Gbps peak burst | replication + origin fetch |
| Kafka ingress | 250 MB/s access events (batched) | ~4 KB/event × 20K rps → reduced by aggregation |
| Cassandra-style write amp | n/a | events batched server-side |

Edge hot ratio assumption: steady-state hit ratio 85% → origin load = 3,000 rps at 20K rps normal, 12,000 rps at peak (before prefetch; prefetch budget ≤ 5% of origin capacity).

## 7. Failure assumptions

| Assumption | Value |
|---|---|
| node loss | 1 node per 3-month window (AZ outage: 1/3 of nodes) |
| node restart | ≤ 2 min, disk tier recovers from RocksDB |
| zone partition | ≤ 30 s visible split; resolved by lease expiry |
| control-plane outage | routing continues from cached topology ≥ 5 min |
| Kafka outage | edges buffer events ≤ 10 min; classification degrades to rules |
| Redis outage | request path unaffected; leases degrade to optimistic mode |
| origin total outage | served from stale-if-error for ≤ 15 min |

## 8. Scenarios

- **Normal:** 20K rps, 3K origin rps, hit 85%, replication traffic 50 MB/s.
- **Peak:** 80K rps, 12K origin rps, memory tier saturates to 90%, disk tier 60%.
- **Degraded:** control plane down; edges serve from cached topology, no new invalidation; hit ratio drifts to ~80%.

## 9. Outputs

These numbers seed: load-test profiles (Gatling/k6), Kubernetes resource requests (milestone 13), Kafka partition counts (24 partitions access topic), Redis memory (1 GB), PostgreSQL sizing (10 K write tps control plane), and alert thresholds (`slos.md`).
