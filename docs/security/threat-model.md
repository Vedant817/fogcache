# FogCache — Threat Model & Security-Control Matrix (00.8)

Status: Agreed · Version: 1 · Issue: VED-57
Scope: public data plane, internal services, control plane, storage, messaging, model, and delivery boundaries. Every **high**-risk threat maps to implementation and verification tickets; residual risk is tracked in the risk register (`docs/architecture/risk-register.md`).

## 1. Assets

| # | Asset | Confidentiality | Integrity | Availability |
|---|---|---|---|---|
| A1 | cached content (tenant payloads) | high | high | high |
| A2 | tenant config (origins, policies, quotas, keys) | high | high | high |
| A3 | admin credentials / OIDC sessions | high | high | high |
| A4 | node/ring topology & health state | medium | high | high |
| A5 | Kafka event streams (access, audit) | medium | high | high |
| A6 | model artifacts & features | low | high | medium |
| A7 | audit trail | high | high | medium |
| A8 | deployment pipeline (images, secrets, Helm) | high | high | high |

## 2. Actors

`Anonymous client` (data plane), `Authenticated client` (private cache), `Tenant admin`, `Platform operator`, `Security auditor`, `Origin/content service`, `Internal service principals` (mTLS), `Kafka producer/consumer principals`, `Deploy pipeline`, `Compromised node or credential` (adversary), `Malicious tenant`.

## 3. Trust boundaries

B1 Internet ↔ edge ingress · B2 edge ↔ origin · B3 edge ↔ routing/control · B4 control ↔ PostgreSQL/Redis · B5 services ↔ Kafka · B6 edge ↔ edge (gRPC) · B7 control ↔ OIDC provider · B8 CI/CD ↔ container registry/cluster · B9 analytics ↔ model artifacts · B10 admin web ↔ control service. All cross-boundary traffic is authenticated; B1..B3/B10 are TLS; B3/B5/B6/B8 use mTLS/service identity.

## 4. Threat table

ID = identifier used in tickets. Likelihood/Impact: H/M/L. Residual = risk after controls.

| ID | Threat | Boundary | Likelihood | Impact | Controls | Residual | Owner |
|---|---|---|---|---|---|---|---|
| T-01 | Cross-tenant cache-key collision & data disclosure | B1 | M | H | tenant+origin UUID structurally in key (cache-semantics §5); per-tenant quotas; no bare-path admin actions; tenant-scoped metrics/analytics | L | Edge platform |
| T-02 | Cache poisoning via deceptive `Vary` / inconsistent headers | B1↔B2 | M | H | Vary allowlist only; unknown Vary ⇒ uncacheable; header allowlist on store; generation check on serve; integrity check of stored metadata | L | Edge platform |
| T-03 | SSRF / DNS rebinding through origin config | B3↔B2 | M | H | origin allowlist (host/IP/CIDR), IP revalidation on resolve, no private ranges by default, rebinding cache; admin-only origin config | L | Control/Edge |
| T-04 | Request smuggling, header injection, path traversal, oversized payloads | B1 | M | H | strict path validation (`\`, `//`, dot-segment rejection — cache-semantics §2), header size limits, body/size limits (`max_object_size`), HTTP parsing hardening, request smuggling tests (TE/CL) | L | Edge platform |
| T-05 | Stampede & resource exhaustion (flash crowd, slowloris, decompression bomb) | B1 | M | H | single-flight caps (loader/waiter timeouts, max waiters), concurrency limits, compressed-ratio limits, request rate limits per tenant, global backpressure | M | Edge platform |
| T-06 | Compromised node / service credential | B3/B6 | L | H | mTLS identity, least-privilege service accounts, short-lived credentials, secrets rotation, node quarantine procedure | L | Platform |
| T-07 | Compromised Kafka producer (forged invalidations/events) | B5 | L | H | mTLS client identity, ACLs per topic, event schema validation, originSeq monotonicity enforcement, audit of invalidation producers | L | Platform |
| T-08 | Malicious model artifact / feature injection | B9 | L | M | artifact checksum + version registry, feature schema validation, shadow-mode first, kill switches, inference input bounds | L | ML platform |
| T-09 | Admin privilege abuse & audit tampering | B10/B4 | M | H | RBAC (viewer/operator/tenant-admin/platform-admin/auditor), OIDC MFA, idempotent+audited mutations, append-only audit (immutable store), tamper-evident hashing | L | Control platform |
| T-10 | Supply chain & container/image risks | B8 | M | H | dependency scanning (SBOM), image signing + scanning, pinned base images, minimal containers, secretless CI (OIDC), PR review gates | L | Delivery |
| T-11 | Private-cache leakage via `Cache-Control: private` mismatch | B1 | M | H | private responses never shared across tenants (policy + key structure), cookie/Authorization never in key, tests for private variants | L | Edge platform |
| T-12 | DNS rebinding of edge hostname | B1 | M | L | Host header validation against configured hosts; origin alias mapping only | L | Edge platform |

## 5. Security-control matrix (grouped)

| Control group | Controls | Threats covered | Verification ticket |
|---|---|---|---|
| Authentication | OIDC (admin), mTLS internal, Kafka ACLs, ingress TLS | T-06/07/09 | milestone 11 |
| Authorization | RBAC roles, tenant-scoped enforcement at every admin call, service identity | T-09/01 | milestone 11 |
| Input validation | path/header/size limits, Vary allowlist, decompression limits | T-02/04/05 | milestone 05/11 |
| Cache correctness | key structure, generation semantics, negative caching controls | T-01/02/11 | milestone 06 |
| Secrets | encrypted storage, rotation, External Secrets/SealedSecrets, no secrets in logs | T-06/10 | milestone 11 |
| Audit | append-only audit, tamper-evident, export | T-09 | milestone 10/11 |
| Delivery | scan+sign images, dependency scan, secretless CI, OIDC deploy | T-10 | milestone 13 |
| Runtime | network policies, pod security, image pull policy, runtime scan | T-06/10 | milestone 13 |
| Abuse | per-tenant rate limits, quotas, kill switches | T-05 | milestone 05/10 |
| ML | artifact checksum/registry, shadow mode, kill switches | T-08 | milestone 09 |

## 6. Security assumptions (contract for architecture & deployment)

- mTLS/service mesh identity is available for internal traffic in production (B3/B5/B6).
- TLS terminated at ingress; edge accepts h2c only in local dev.
- OIDC provider is standards-compliant (Keycloak-compatible locally).
- Kafka, PostgreSQL, Redis, object storage are network-isolated (private subnets, network policies) — exposed only to their consumers.
- Secrets never enter application logs, traces, or events; audit of secret rotation is required.
- Deployment pipeline runs on ephemeral agents with OIDC federation (no static cloud keys).

## 7. High-risk threat → ticket mapping

T-01, T-02, T-03, T-04, T-05, T-09, T-10, T-11 each have implementation tickets in milestones 05/06/10/11/13 and verification tickets (security tests, pen-test scenarios) in milestone 12. See `docs/architecture/risk-register.md` for tracking and `slos.md` for security-related release gates (0 urgent/high defects).
