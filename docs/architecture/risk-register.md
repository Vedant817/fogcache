# FogCache — Risk Register (00.10)

Status: Living document · Version: 1 · Issue: VED-59
Each risk records **probability, impact, mitigation, trigger, owner, contingency**. High risks map to mitigation tickets and production-readiness evidence (milestone 14). IDs are referenced from threat model (T-xx) and tests.

| ID | Risk | P | I | Mitigation | Trigger | Owner | Contingency |
|---|---|---|---|---|---|---|---|
| R-01 | Cache correctness bug returns stale/cross-tenant data | M | H | key structure with tenant/origin UUID; generation rules; property tests; Vary allowlist (T-01/02/11) | unit/property test failure; leak report | Edge platform | kill switch serve-from-origin; rollback image; incident runbook |
| R-02 | Replication of large objects overwhelms network | M | H | per-class bandwidth budgets; backpressure; transfer stream pacing; big-object demotion (T-05) | replication queue depth alert | Edge platform | pause transfers; reduce rf; emergency drain |
| R-03 | Hot-key movement oscillates without hysteresis | M | M | hysteresis band entry/exit; churn metric (≤ 3 flips/h); movement dampening in ring weights | churn alert | Analytics | tighten hysteresis; pin suspected keys |
| R-04 | Prefetch increases origin load instead of reducing it | M | H | precision ≥ 40% SLO; waste ≤ 60%; budgets per tenant/node; shadow-first; demand > prefetch priority (T-08) | prefetch precision/waste alert | ML platform | kill switch disable-prefetch |
| R-05 | Topology churn remaps excessive ownership | M | M | dry-run movement estimation before membership changes; ≤ 20% remap bound; capacity-weight safety limits (ADR-0006) | movement > bound | Routing | pin topology; staged membership changes |
| R-06 | High-cardinality telemetry overloads observability | M | M | metric budgets; access event batching/aggregation; key-hash cardinality controls | OTel drop alerts | SRE | raise aggregation; drop low-value metrics |
| R-07 | Disk recovery/schema upgrades corrupt or strand entries | M | H | entry checksums; recovery sweep; tombstones replayed first; keyVersion migration; RocksDB disposable by design (ADR-0003) | recovery validation failure | Edge platform | memory-only mode; rebuild disk tier |
| R-08 | Single point of failure in control plane | L | H | routing independent of control; Redis leases; runbook drills (ADR-0006/0008) | incident | Platform | emergency static topology |
| R-09 | Credential/service principal compromise | L | H | mTLS, least-privilege, rotation, audit (T-06) | audit anomaly | Platform | revoke + rotate + node quarantine |
| R-10 | Supply chain attack on images/dependencies | M | H | SBOM, scanning, signing, pinning, secretless CI (T-10) | scan finding | Delivery | rebuild from clean base; block deploy |
| R-11 | ML model drift degrades hit ratio | M | M | shadow mode; uplift gate ≥ +1 pt; rule fallback; model rollback (ADR-0007) | uplift < gate | ML platform | revert to rules; retire model |
| R-12 | Kafka lag leads to stale classification/invalidation | M | M | lag alert; gRPC invalidation fallback; rule-based classification | lag SLO breach | Platform | increase partitions; reduce event volume |
| R-13 | Tenant abuse (rate, quotas, decompression bombs) | M | H | per-tenant quotas/rate limits; size and compression limits (T-05) | 429/413 alerts | Edge platform | tighten quota; block tenant |
| R-14 | Origin misconfiguration → SSRF/rebinding | M | H | allowlists, IP revalidation, admin-only config (T-03) | scanning of origins | Control | revoke origin; audit config change |
| R-15 | Backup/restore unverified at launch | M | H | restore drills in milestone 13/14; release gate | drill failure | SRE | extend launch; run drills |

## Decision and diagram versioning

- Risks are re-scored after every milestone and on any architecture change (owner updates the register in the same PR as the change).
- Diagrams and contracts reference the ADR that drove them; a decision change bumps the affected ADR status (Superseded → new ADR).
