# FogCache — Product Scope (00.1)

Status: Agreed · Version: 0.1.0 · Issue: VED-50

## 1. Personas

| Persona | Primary goals | Key permissions |
|---|---|---|
| **Platform operator** | Keep the edge healthy, sized, and cost-efficient; run failover and capacity drills | Viewer/operator on nodes, topology, quotas |
| **Application developer** | Publish cacheable content and APIs; control TTL, Vary, and invalidation behavior | Create/manage origins and policies for own tenant |
| **Tenant administrator** | Manage keys, quotas, and cache actions for the tenant; observe hit ratios and hot keys | tenant-admin on own tenant data |
| **Security auditor** | Verify isolation, audit trails, key handling, and threat controls | Read-only security-auditor role on audit/security views |

## 2. Supported use cases (v1)

1. **Static objects** — cache immutable assets (images, JS/CSS, fonts) served from a content origin with long TTLs and ETag validation.
2. **Cacheable API responses** — cache GET/HEAD JSON responses with explicit `Cache-Control` policy, including negative caching of selected statuses.
3. **Explicit reverse-proxy origin mapping** — map an origin alias to an HTTP origin; the edge proxies and caches `GET /cache/{originAlias}/**`, with an optional transparent host-based mapping.

Supported methods v1: `GET`, `HEAD` (identical key space; HEAD shares the GET representation). All other methods return `405` at the edge unless the origin proxy mode is enabled for a tenant policy.

## 3. Protocol boundaries (v1)

- **Client → edge:** HTTP/1.1 and HTTP/2 (h2c locally), TLS terminated at ingress in production.
- **Edge → origin:** HTTP/1.1 with `If-None-Match` / `If-Modified-Since` revalidation; S3-compatible API for the reference content service.
- **Internal:** gRPC for node-to-node metadata/transfer/probe; REST for routing and admin APIs; Kafka for events.
- **Admin:** REST + OIDC (Keycloak-compatible locally, any standards OIDC in production).

## 4. Multi-tenant assumptions and deployment modes

- Tenants are first-class entities; every key, origin, policy, quota, and metric is tenant-scoped.
- Deployment modes v1: single-tenant local/CI, single-tenant production, and multi-tenant production with hard key/namespace isolation and per-tenant quotas.
- No cross-tenant shared cache namespaces; key isolation is enforced at normalization time (see `cache-semantics.md` §5).

## 5. Explicit non-goals (v1) — with rationale and revisit conditions

| Non-goal | Rationale | Revisit when |
|---|---|---|
| Full CDN DNS anycast | Requires global DNS infrastructure not needed for v1 market | Multi-region POP launch |
| Arbitrary write-through caching | Origin writes are out of scope; complicates invalidation ordering | Origin-side write traffic becomes significant |
| Video segment optimization / advanced range coalescing | Range semantics deferred to a dedicated correctness phase | Video workloads appear |
| P2P transport across untrusted nodes | Security and trust-model cost too high for v1 | Scale requires bandwidth offload |
| Autonomous ML actions without shadow/canary | Unvalidated ML actions risk cache correctness | Model value proven in shadow mode |
| Multi-cloud active-active control plane | Single-cloud reliability must be proven first | Second cloud provider demand |
| Arbitrary methods (POST caching, custom verbs), request bodies, WebSockets | Request-path correctness scope | Cacheable POST patterns demand it |

## 6. Service-to-use-case mapping

- Edge service: use cases 1–3.
- Routing service: all use cases (node selection).
- Content service: use case 1 reference origin (external origins supported).
- Control service: tenant/policy/quota management for all use cases.
- Analytics: hot-key classification/prefetch for use cases 1–2.

## 7. Success and failure examples

| Use case | Success | Failure |
|---|---|---|
| Static object | First miss fetches from origin; second request served from memory tier with `X-FogCache-Status: HIT`; ETag revalidation yields 304 | Origin returns 5xx; edge serves stale-if-error content and logs the origin failure as an SLI miss |
| Cacheable API | 200 stored with TTL; concurrent duplicate requests coalesce into one origin fetch | Misconfigured `Vary` causes key collision; policy validation rejects the origin response as uncacheable |
| Reverse-proxy mapping | `/cache/{originAlias}/path` returns proxied, cached representation | Origin alias resolves to a non-allowlisted host; edge returns 502 with a safe, generic body |

Scope is considered unambiguous when an incoming request can be classified **in-scope / in-scope-but-uncacheable / out-of-scope (405)** purely from tenant policy + request shape.
