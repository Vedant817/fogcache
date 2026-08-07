# FogCache — Cache-Key Normalization & HTTP Caching Semantics (00.6)

Status: Agreed · Version: 1 · Issue: VED-55
This is the correctness contract used by routing, edge storage, invalidation, and security. **Equivalent requests produce the same key; non-equivalent requests cannot collide by design.** Key algorithm versioning: `keyVersion` is part of every stored entry and of every admin key action so migrations are controlled.

## 1. Versioned key structure

```
keyVersion | tenantId | originId | scheme | host | normalizedPath | canonicalQuery | selectedHeaders | representation
```

- `keyVersion`: int, current 1; bump invalidates all entries under the old version (controlled migration).
- `tenantId`/`originId`: UUIDs — always present; the origin is resolved from tenant policy before normalization (a request that matches no origin is 404, never cached).
- `scheme`: `http`/`https` (never normalized across schemes by default; `normalize_scheme` policy may merge them).
- `host`: lowercase; default-port stripped (`example.com:443` → `example.com`).
- `normalizedPath`: decoded-path normalization with **no** dot-segment resolution beyond RFC 3986 `remove_dot_segments`; path is percent-decoded, then percent-encoded canonically; case preserved (host case is the only case-folded component).
- `canonicalQuery`: parameters sorted by name (then value); duplicate names merged per policy (`merge_duplicate_query`); configured tracking parameters removed (`strip_query_params` allowlist-style); empty query omitted.
- `selectedHeaders`: only headers on the tenant **Vary allowlist** — see §3.
- `representation`: `{contentEncoding, contentMediaType}` from the stored response (see §4).

## 2. URL canonicalization rules

1. Percent-encoding canonicalized (`%41` → `A`; unreserved characters unescaped).
2. Default ports stripped; host lowercase.
3. Query: sort by key, stable by value; omit `?` entirely when empty.
4. Fragments (`#…`) are never part of the key.
5. Dot segments resolved per RFC 3986 (`/a/../b` → `/b`); `//` and backslash `\` are **rejected** (402/400) — see threat model T-04.
6. HEAD shares the GET key space (same representation).

## 3. Vary, authorization, cookies, compression, private-cache

- `Vary` is honored **only from the tenant allowlist** (`vary_allowlist: [Accept-Encoding, Accept-Language]`). Unknown `Vary` values → the response is treated as uncacheable, never stored under a guessed variant. Deceptive or inconsistent `Vary` from origin → response rejected (no cache write) and `uncacheable_reason=vary` logged (T-02).
- Authorization-bearing requests: not cached unless the tenant policy sets `allow_private_cache: true`; then `Authorization` is **never** hashed into the key — the cache stores only the response body/headers with `Cache-Control: private` semantics and the policy limits it to per-tenant, non-shared variants.
- Cookies: `Cookie`/`Set-Cookie` are never part of the key. Responses with `Set-Cookie` are stored only if policy permits (default: not cacheable).
- Compression: `Accept-Encoding` variants keyed on stored `content-encoding`; a compressed variant is stored only for allowlisted encodings (gzip, br, zstd); identity fallback kept for clients that cannot decode.
- Private/non-shared responses are stored in tenant-private key space (tenant UUID already separates), but never served cross-tenant (see §5).

## 4. GET/HEAD behavior

- `HEAD` served from the GET representation: same status/headers, empty body, same `Age`/cache-status headers.
- A `HEAD` miss triggers the same single-flight loader as GET, but never stores the response body separately (the GET store path is shared).

## 5. Cross-tenant and cross-origin isolation

- Tenant UUID and origin UUID are structurally part of the key → collision is impossible by construction, even if paths match exactly.
- Quotas, metrics, admin key actions, and analytics are tenant-scoped; a key action (invalidate/warm/pin/evict) without a tenant scope is rejected.
- Admin inspect/invalidate APIs require `{tenantId, originId}` and an optional exact-key/prefix/tag — never bare paths.

## 6. Cache-Control, Expires, Age, ETag, Last-Modified, conditional requests

**Storing (response):**
- Cacheable when: `GET/HEAD`, origin 200/203/204/301/308/404/410 (and policy-configured negative set), explicit or policy-default TTL > 0, no `no-store` in `Cache-Control`, no `Set-Cookie` (unless policy), body ≤ `max_object_size`, `Content-Length`/chunked well-formed.
- TTL priority: `s-maxage` > `max-age` > `Expires` > tenant policy default (`default_ttl`); `no-cache` → store but always revalidate; `must-revalidate` → no stale serving.
- Entry stores: status, selected headers (minus hop-by-hop), ETag, Last-Modified, Date, Age at store, TTL, SWR window (`stale-while-revalidate`), SIE window (`stale-if-error`), `content-type`, `content-encoding`.

**Serving (request):**
- Fresh entry (now < `expiresAt`): serve directly; set `Age = now - dateStored + ageAtStore`.
- Revalidation on `no-cache` or policy: send `If-None-Match: <etag>` (or `If-Modified-Since: <last-modified>`); 304 → refresh metadata, serve stored body; 200 → replace entry.
- Client conditional requests: `If-None-Match` / `If-Modified-Since` against the stored entry → `304 Not Modified` without body; `If-Match` mismatch → `412`.
- `Cache-Control` request directives honored: `no-cache` → revalidate; `no-store` → bypass + no write; `max-age=0` → revalidate.

## 7. Negative caching, SWR, SIE, bypass

- **Negative caching:** configured statuses (404/410/502/504 with short `negative_ttl`, default 10 s) stored as tombstone-like entries; a later origin success replaces them.
- **stale-while-revalidate:** within SWR window, serve stale + background revalidate (J-05); only one revalidation per key (single-flight).
- **stale-if-error:** within SIE window, serve stale when origin errors (J-06); otherwise 502.
- **Bypass rules:** unsafe methods, authenticated requests (unless private-cache policy), explicit `Cache-Control: no-store`, uncacheable `Vary`, oversize bodies, unknown encodings, range requests (v1: served from origin, not cached — range caching is a non-goal), WebSocket upgrades.

## 8. Invalidation semantics

| Kind | Match | Effect | Example |
|---|---|---|---|
| exact | full normalized key (or key hash) | drop entry, bump generation, tombstone | `DELETE key` |
| prefix | key path prefix within origin | drop all matching | `/static/` |
| tag | surrogate key tag(s) | drop all entries with tag | `release-42` |
| origin | all keys of an origin | drop all + mark generation | origin repoint |
| tenant | all keys of a tenant | drop all (admin only) | tenant deletion |

- Invalidation is **generation-based**: each origin has `generation`; entries carry the generation they were stored against; an entry with `generation < current` is treated as absent (serves miss, not stale). Ordering/tombstone rules in `replication-semantics.md`.
- Admin invalidations are idempotent (idempotency key) and audited; purges propagate via Kafka `invalidation` events.

## 9. Edge-case examples (unit/property-test seeds)

| # | Request A | Request B | Same key? | Why |
|---|---|---|---|---|
| 1 | `/a%2Fb` | `/a/b` | No | encoded slash ≠ path separator |
| 2 | `?b=2&a=1` | `?a=1&b=2` | Yes | canonical query sort |
| 3 | `?track=abc&x=1` | `?x=1` | Yes | tracking param stripped |
| 4 | `example.com/a` | `Example.COM:80/a` | Yes | host fold + default port |
| 5 | tenant A `/x` | tenant B `/x` | No | tenant UUID in key |
| 6 | `/a/../b` | `/b` | Yes | RFC 3986 dot segments |
| 7 | `\x` or `//x` | — | Rejected | smuggling/path attack (T-04) |
| 8 | gzip vs identity variant | — | Different `representation` | Vary allowlist |
| 9 | `/x#frag` vs `/x` | — | Yes | fragment never in key |
| 10 | `?a=1&a=2` vs `?a=2&a=1` | — | Policy | merge_duplicate_query default: ordered merge |

Acceptance: examples above become unit tests (milestone 06) and property tests (key canonicalization is a pure function; serialization versioning tested for compatibility).
