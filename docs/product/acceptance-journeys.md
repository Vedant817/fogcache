# FogCache — End-to-End Acceptance Journeys (00.2)

Status: Agreed · Version: 0.1.0 · Issue: VED-51
Each journey records **preconditions, trigger, state transitions, expected response, emitted events, and observable evidence**, and converts directly into end-to-end tests (`fogcache-integration-tests`). Negative/partial-failure variants are included. `E<key>` tags are used in test tickets.

## J-01 Request routing to healthy node

- **Pre:** 3 nodes registered and healthy; tenant `t1` with origin `o1`; topology version `v1`.
- **Trigger:** `GET /cache/o1/static/a.js`.
- **Transitions:** key normalized → ring lookup → primary `n2` selected → request served by `n2`.
- **Response:** 200, `X-FogCache-Node: n2`, `X-FogCache-Topology: v1`.
- **Events:** `access` (route resolved).
- **Evidence:** routing decision log; `resolve` API shows n2 for the key hash.
- **Variant E1 (negative):** `n2` marked draining → request routed to `n3`; no traffic to `n2`; drain completes within lease timeout.

## J-02 Cache hit

- **Pre:** key cached on `n2` (unexpired, correct generation).
- **Trigger:** `GET` for the same key.
- **Transitions:** memory hit → response assembled from stored representation.
- **Response:** 200 + body + `X-FogCache-Status: HIT`, `Age` present.
- **Events:** `access(hit=true)`.
- **Evidence:** hit counter +1; origin fetch count unchanged.

## J-03 Cache miss → origin fetch → store

- **Pre:** key not cached anywhere; origin healthy.
- **Trigger:** `GET`.
- **Transitions:** miss → single-flight loader → origin 200 → size/cacheability validation → persist memory+disk → release waiters.
- **Response:** 200 + `X-FogCache-Status: MISS`, `Age: 0`.
- **Events:** `access(miss=true)`, `fetch(ok)`, `replication(created)`.
- **Evidence:** exactly 1 origin fetch for N concurrent requests (see J-04); entry visible in key-inspect admin API.

## J-04 Stampede protection under concurrent misses

- **Pre:** key absent; origin latency 200 ms; 50 concurrent identical requests.
- **Trigger:** all 50 arrive simultaneously.
- **Transitions:** first request acquires loader lock; 49 wait on single-flight future; loader completes; all 50 receive the same stored representation.
- **Response:** all 200; **exactly one** origin fetch.
- **Events:** 50 `access` events, 1 `fetch`, 1 lock-acquire metric, 49 `waiter_released`.
- **Evidence:** origin access log shows 1 request; lock contention metric == 49.
- **Variant E2:** loader times out (2 s) → waiters fail fast or receive stale (policy-dependent), lock cleared, no deadlock.

## J-05 Stale-while-revalidate

- **Pre:** entry expired but within `stale-while-revalidate` window; origin slow (400 ms).
- **Trigger:** `GET`.
- **Transitions:** stale served immediately → background revalidation → fresh entry stored.
- **Response:** 200 stale body, `X-FogCache-Status: STALE`, `Age` > TTL.
- **Events:** `access(stale=true)`, `fetch(revalidate)`.
- **Evidence:** first-byte latency < origin latency; next request returns fresh HIT.

## J-06 Origin failure → stale-if-error

- **Pre:** stale entry present; origin returns 5xx or times out.
- **Trigger:** `GET`.
- **Transitions:** miss for fresh → origin error → stale-if-error policy serves stale.
- **Response:** 200 stale body + `X-FogCache-Status: STALE-ERROR` (or 502 if no stale).
- **Events:** `fetch(error)`, `access(stale_error=true)`.
- **Evidence:** error rate SLI increments; alert fires per `slos.md` burn policy.
- **Variant E3 (no stale):** 502 returned with generic error body; negative cache stores the 502 for a short TTL if policy permits.

## J-07 Invalidation (exact / prefix / tag)

- **Pre:** key `a.js`, key group `/static/`, tag `release-42` cached.
- **Trigger:** admin `DELETE /v1/admin/keys` (exact), `POST …:invalidate` with prefix/tag.
- **Transitions:** control service records invalidation → Kafka `invalidation` event → edges increment generation and drop matching entries → tombstone recorded.
- **Response:** 202 Accepted, idempotent on retry.
- **Events:** `invalidation` (with kind and idempotency key).
- **Evidence:** subsequent GET is MISS; convergence within invalidation SLO (`slos.md`).
- **Variant E4:** invalidation arrives delayed/out-of-order → generation comparison rejects the stale application (see `replication-semantics.md` §5).

## J-08 Node failure and failover

- **Pre:** 3 nodes; key owned by `n2`; replicas on `n3`.
- **Trigger:** `n2` process killed.
- **Transitions:** health lease expires (≥ 2 missed heartbeats) → ring membership update → owner promoted to `n3` → request served from `n3` replica (or origin fetch if absent).
- **Response:** 200 with `X-FogCache-Node: n3`.
- **Events:** `node(failed)`, `topology(updated)`, `promotion`.
- **Evidence:** remap bound (≤ 20% of keys move for 3-node cluster per capacity model); alert `edge-node-down` fires.

## J-09 Replication and repair

- **Pre:** hot key `k` with replication factor 2; replicas missing on `n3`.
- **Trigger:** placement decision (or repair sweep).
- **Transitions:** analytics publishes `placement` → owner transfers metadata+payload → receiver validates checksum → commit → ack.
- **Response:** internal (no client response); admin shows replica list.
- **Events:** `placement`, `replication(transfer, committed)`.
- **Evidence:** replica present on `n3`; anti-entropy sweep reports 0 missing replicas.

## J-10 Hot-key classification

- **Pre:** key `k` crossing HOT threshold (e.g., > 50 rps in 1-min window).
- **Trigger:** sustained access rate.
- **Transitions:** features computed → classifier labels HOT (with hysteresis) → placement/prefetch actions eligible.
- **Response:** internal; admin hot-key API shows `k` as HOT with feature values.
- **Events:** `classification(HOT)`.
- **Evidence:** label churn bounded (≤ 3 state flips/hour for stable traffic); classification not applied to ML actions until shadow mode validates.

## J-11 Prefetch

- **Pre:** prediction engine scores `p` high for key `k`; budgets permit.
- **Trigger:** prediction cycle.
- **Transitions:** prefetch scheduled → origin fetch → store → mark `prefetched=true`.
- **Response:** internal; metrics record bytes wasted/used.
- **Events:** `prefetch(started, outcome)`.
- **Evidence:** demand hit on prefetched key ≤ prefetch horizon; prefetch precision ≥ threshold (`slos.md`); demand requests always outrank prefetch.

## J-12 Admin operations

- **Pre:** authenticated platform-admin; tenant policy `p1`.
- **Trigger:** admin creates tenant/origin/policy/quota; warms, pins, evicts keys; flips kill switches.
- **Transitions:** control service validates → persists to PostgreSQL → publishes events → audit record written.
- **Response:** 2xx with resource URIs; idempotent.
- **Events:** `audit(operation)` for every mutation.
- **Evidence:** audit trail shows actor, action, resource, result, timestamp; unauthorized role receives 403.

## Conversion rule

Every journey above maps to ≥ 1 end-to-end test in `fogcache-integration-tests` with the named variants; every journey carries an SLI (see `slos.md`) so tests and SLOs stay coupled.
