# Module ownership and dependency rules

Companion to `dependency-map.md` (runtime dependencies) and ADR-0001
(monorepo decomposition). This page covers the **build-time** shape: module
boundaries, ownership, and the rules that keep the reactor decoupled.

## Build task graph

Maven reactor order (a module may depend only on modules above it):

```
fogcache-bom
    ↑
fogcache-common        fogcache-contracts
    ↑                       ↑
    └───────────┬───────────┘
                ↓
fogcache-routing-service      fogcache-edge-service
fogcache-content-service      fogcache-control-service
fogcache-analytics-service
    └───────────────┬───────────────┘
                    ↓
fogcache-integration-tests
```

Outside the Maven reactor (own build/tooling, own lifecycle):

- `fogcache-admin-web` — Next.js admin console
- `fogcache-model-training` — Python ML pipeline

## Ownership matrix

| Module | Owner (feature area) | Depends on (build) | May import |
|---|---|---|---|
| `fogcache-bom` | platform | — | nothing (pom) |
| `fogcache-common` | platform | parent, bom | spring-boot-starter-webflux, jakarta.validation |
| `fogcache-contracts` | platform | parent, bom | protobuf-java(-util) |
| `fogcache-routing-service` | routing | common, contracts | spring (boot starters) |
| `fogcache-edge-service` | data plane | common, contracts | spring (boot starters) |
| `fogcache-content-service` | origin | common, contracts | spring (boot starters) |
| `fogcache-control-service` | control plane | common, contracts | spring (boot starters) |
| `fogcache-analytics-service` | analytics | common, contracts | spring (boot starters) |
| `fogcache-integration-tests` | platform QA | all services (test scope) | anything |

## Dependency rules

1. **Versions live in exactly two places** — parent POM properties and
   `fogcache-bom` / parent `pluginManagement`. Never inline a version in a
   module pom (enforced by review; enforcer bans duplicate declarations).
2. **Service → service dependencies are forbidden at build time.** Services
   communicate through the contracts (gRPC) or Kafka events, never by
   importing each other's classes. This is what keeps the data path testable
   and independently deployable (ADR-0001, ADR-0008).
3. **`fogcache-common` is for shared runtime infrastructure only** —
   auto-configuration, filters, utilities. Feature logic lives in the owning
   service; if two services need the same feature logic, it belongs in
   `fogcache-common` only after an ADR review.
4. **Generated code is never committed.** proto/OpenAPI sources live in
   `fogcache-contracts`; generated Java lands under `target/generated-sources`.
5. **Testcontainers configs are per-service test fixtures.** The LGTM stack
   container in each service is Docker-conditional so `verify` works without
   Docker; cross-service scenarios belong in `fogcache-integration-tests`.

## Quality gates per module

All gates are inherited from the parent and run in `verify`. The JaCoCo gate
is currently enabled on `fogcache-common` only; the remaining modules set
`jacoco.skip=true` until their milestone adds real unit tests — removing that
property is part of the milestone definition of done.
