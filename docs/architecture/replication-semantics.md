# FogCache — Ownership, Replication, Invalidation & Conflict Semantics (00.7)

Status: Agreed · Version: 1 · Issue: VED-56
Specifies how object state evolves across origin and edge nodes. Invariants: **a stale replica can never overwrite a newer generation or resurrect a deletion**; availability/consistency trade-offs are explicit and testable.

## 1. Primary ownership and ordered replica candidates

- Each normalized key has a **primary owner** = first live node on the consistent-hash ring (ADR-0006), and an ordered candidate list (ring successors that are live, not draining, tenant-eligible).
- Replication factor `rf` (default 2; 3 for HOT class): primary writes itself + `rf-1` ordered candidates.
- Ownership changes only via topology version bumps; entries are copied during drain (primary pushes replicas), never silently dropped while a client could still be routed to the old node.

## 2. Desired vs observed replica state

- **Desired state** = `(key, generation, replicas=[primary, c1, c2], pin, class, ttl)` produced by placement decisions (rule-based initially; ML only in shadow mode).
- **Observed state** = each node's local entry metadata (`entry-generation`, stored generation, checksum, last-verified time).
- A **reconciler** on each node compares observed vs desired for owned keys (anti-entropy sweep, §8) and issues repair/transfer commands; reconciliation is the single mechanism for placement, repair, and rebalance.

## 3. Version/generation comparison rules

- `originGeneration` — monotonically increasing per origin object, assigned by the content service on write (and bumped on invalidation events).
- `entryGeneration` — local entry version at the edge, bumped on every successful store/revalidate.
- Rule: **apply an update iff** `new.originGeneration > existing.originGeneration` **or** (`==` **and** `new.entryGeneration > existing.entryGeneration`). Equal-and-lower updates are dropped as duplicates/out-of-order (idempotent).
- Revalidation (304) refreshes metadata only; it never raises the origin generation of the stored body (body unchanged).
- Deletions are represented as **tombstones** carrying `originGeneration`; a live entry with a lower generation than a tombstone is removed and never resurrected.

## 4. Mutation invalidation ordering and tombstone lifetime

1. Invalidation (exact/prefix/tag/origin/tenant) is an event with a **monotonic sequence id per origin** (`originSeq`) and an optional idempotency key.
2. Edges apply invalidations in sequence order per origin (Kafka partition = origin ⇒ per-partition ordering); out-of-order arrivals are buffered until the gap fills or the gap-bound (default 60 s) expires, then marked missed and repaired via anti-entropy.
3. Tombstone lifetime = `tombstone_ttl` (default 7 d) — longer than the worst-case node outage (15 min) + sweep interval (1 h); tombstones are dropped only when every replica confirms adoption (observed generation ≥ tombstone generation).
4. A delayed old invalidation (generation lower than the current entry generation) is a no-op — it cannot undo a newer state.

## 5. Transfer commit protocol and checksum validation

1. **Prepare:** owner sends `TransferRequest{key, generation, checksum(sha-256), size, metadata}`.
2. **Stream:** payload streams (gRPC); receiver writes to staging (memory/disk) without making it visible.
3. **Verify:** receiver computes sha-256 of staged payload; mismatch → abort with `CHECKSUM_MISMATCH` (owner re-transfers, bounded retries then repair ticket).
4. **Commit:** atomic metadata + payload pointer update under the key's local lock; visible to readers only after commit.
5. **Ack:** receiver acks; owner records replica state. Duplicate transfers are idempotent (same generation → no-op). Commit ordering guarantees no reader observes a partially transferred object.

## 6. Duplicate, delayed, out-of-order, lost event behavior

| Case | Behavior |
|---|---|
| duplicate event | idempotent via `(origin, originSeq)`/`(key, originGeneration)` dedupe |
| delayed event | applied if generation wins (§3); else dropped |
| out-of-order | buffered per origin until gap-filled or gap-bound; then anti-entropy repair |
| lost event | detected by generation gap/heartbeat of originSeq; repaired by anti-entropy sweep (§8) |
| crashed mid-transfer | staging discarded; receiver stays on old entry; sweep re-issues transfer |

## 7. Node failure, partition, restart, rejoin

- **Failure:** lease expiry (≥ 2 missed heartbeats, ≤ 15 s) → topology bump → owner promotion to next live candidate; promoted node serves existing replicas or fetches from origin (J-08).
- **Partition (split brain):** each side elects its own owner during the partition; on heal, generation comparison resolves conflict — the side with the higher observed origin generation wins and re-replicates; no split is ever resolved by "last writer wins" timestamps alone.
- **Restart:** disk tier recovers entries (RocksDB); all recovered entries are treated as **suspect** until validated against origin generation / invalidation stream (recovery sweep); tombstones present in the local log are replayed first.
- **Rejoin:** node re-registers, receives topology, validates its recovered entries against generation, and rejoins as owner only for keys it can prove current (or refetches).
- **Drain (planned):** primary pushes replicas to successors, then withdraws; no new ownership during drain (J-01 E1).

## 8. Anti-entropy and repair guarantees

- Each node runs a periodic sweep (default 1 h) per owned key: compare observed replicas vs desired; issue repair for missing/stale/checksum-failed replicas; reconcile desired-state changes (class/pin changes → placement decisions).
- Guarantee: **within 2× sweep interval** (≤ 2 h) of a missed event, a replica converges to desired state — subject to origin availability; this is the replication convergence SLO floor (`slos.md`).
- Repair never raises the origin generation; it copies the winning generation.

## 9. Availability/consistency trade-offs (explicit)

| Scenario | Reads | Writes/invalidation | Guarantee |
|---|---|---|---|
| Edge hit, control plane down | served from local cache + cached topology | invalidation buffered | availability over freshness (bounded 15 min) |
| Origin down | stale-if-error within SIE window | n/a | availability over freshness for ≤ SIE |
| Partition with conflicting owners | each side serves own replicas | both sides accept; resolved by generation on heal | AP during partition, convergence after |
| Invalidation vs concurrent miss | miss loader may fetch older origin state | invalidation wins on arrival | write ordering via originSeq |
| Replication under bandwidth pressure | primary serves; replicas lag | transfers backpressure'd | converges within SLO, never torn |

## 10. State-transition diagrams

See `docs/architecture/diagrams.md` (§ sequence diagrams J-07, J-08, J-09; § state diagrams for entry lifecycle and ownership) — these are the testable state machines; every arrow is covered by an integration test in milestone 07.
