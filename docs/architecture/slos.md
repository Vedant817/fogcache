# FogCache — SLOs, SLIs, Error Budgets, Release Quality (00.4)

Status: Agreed · Version: 0.1.0 · Issue: VED-53
Every SLI has an owner, a PromQL query, an aggregation window, and a data source. Objectives distinguish **user-visible failures** from **background degradation**. Thresholds connect to performance and production-readiness tickets (milestones 12–14).

## 1. Availability definitions

- **Data plane availability** = successful edge responses / total edge responses. Exclusions: tenant-misconfigured origins (401/403), intentional drain maintenance windows (announced, ≤ 30 min/month), and traffic during declared outage windows (error budget).
- **Control plane availability** = successful admin/routing-control requests / total. Measured separately; a control-plane outage must not count against data-plane availability.
- **Routing availability** = successful `resolve` + topology refresh; served from cache during control outage.

## 2. Latency objectives (data plane)

| Class | p50 | p95 | p99 |
|---|---|---|---|
| HIT (small) | 2 ms | 5 ms | 15 ms |
| HIT (medium) | 5 ms | 15 ms | 40 ms |
| HIT (large/huge) | 20 ms | 100 ms | 400 ms |
| MISS (small) | 80 ms | 300 ms | 1 s |
| MISS (large) | 250 ms | 800 ms | 2.5 s |
| STALE (any) | ≤ p50 HIT + 50 ms | ≤ p95 HIT + 150 ms | — |

Router decision latency: p95 ≤ 5 ms end-to-end (including lease cache lookup).

## 3. Error-rate and origin-amplification objectives

| SLI | Target | Window |
|---|---|---|
| Edge 5xx rate (excluding origin-failure cascade) | < 0.05% | 30 d |
| Edge 5xx rate (all causes) | < 0.5% | 30 d |
| Origin amplification (origin requests / client requests) | < 0.20 at 85% hit ratio | 1 h |
| Origin fetch success | ≥ 99.5% | 30 d |
| Origin fetch timeout rate | < 1% | 1 d |

## 4. Convergence objectives

| SLI | Target | Window |
|---|---|---|
| Invalidation propagation (admin commit → last edge applies) | p95 ≤ 10 s, p99 ≤ 30 s | 1 d |
| Replication convergence (owner commit → replicas present) | p95 ≤ 30 s | 1 d |
| Node failure detection (last heartbeat → topology update) | ≤ 15 s (2 missed leases) | 1 d |
| Remap bound on single node loss | ≤ 20% of keys | per incident |

## 5. Cache, prefetch, and model quality

| SLI | Target | Window |
|---|---|---|
| Steady-state hit ratio | ≥ 85% | 7 d |
| Prefetch precision (prefetched → demanded within horizon) | ≥ 40% | 7 d |
| Prefetch waste (bytes prefetched not used) | ≤ 60% of prefetch bytes | 7 d |
| Classification churn (HOT↔WARM flips per key/hour) | ≤ 3 | 1 h |
| Model decision availability (ONNX inference success) | ≥ 99.9% | 30 d |
| ML uplift vs rule baseline (shadow mode) | ≥ +1 pt hit ratio | 14 d before enablement |

## 6. Error budgets and burn-rate policy

- Budget window: **30 days rolling**, 10% of SLO (i.e., data-plane: 9 hours of unavailability budget; error-rate budget 0.05%).
- Burn rate classes: **slow burn** (≤ 2% / hour of budget per hour) — review; **fast burn** (> 5× SLI breach rate for 1 h) — page; **very fast burn** (> 14× for 30 min) — page + incident.
- Alerts: `slo-data-plane-burn-slow`, `-fast`, `-very-fast`; same for control plane and invalidation.
- When budget < 30% remaining: freeze risky releases; when exhausted: mandatory incident review and mitigation plan.

## 7. Release and rollback thresholds

| Gate | Threshold | Evidence |
|---|---|---|
| Functional journeys | 100% pass (J-01…J-12) | integration suite |
| Performance | p95 latency ≤ 1.25× SLO for 1 h at load-test profile | k6/Gatling report |
| Error rate | edge 5xx < 0.1% during load | load test |
| Security | 0 urgent/high open defects; scans clean | milestone 11 gates |
| Failover drills | node-loss + AZ-loss drill pass | chaos report |
| Rollback | schema/model/image rollback ≤ 15 min | documented runbook, drill result |

## 8. Ownership matrix (summary)

| SLI group | Owner | Data source | Query |
|---|---|---|---|
| Latency/hit ratio | Edge platform | Prometheus, edge metrics | `histogram_quantile` over edge requests |
| Origin amplification | Edge platform | origin client metrics | rate of fetch counters |
| Invalidation/replication | Platform | Kafka lag + ack counters | convergence lag metric |
| Model/prefetch quality | ML platform | analytics metrics | precision/waste counters |
| Control plane | Platform | control service metrics | availability query |
| Availability/budget | SRE | Prometheus + alertmanager | burn-rate recording rules |

Implementation tickets: milestone 10 (dashboards/alerts), milestone 12 (load & soak verification), milestone 14 (final SLO validation and launch readiness).
