# Local development

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| JDK | 21 (Temurin) | Enforced by the build: `[21,22)` |
| Maven | 3.9+ (wrapper) | `./mvnw` / `mvnw.cmd`, nothing to install |
| Docker Desktop | latest | Only needed for Testcontainers smoke tests |
| Node.js | 20+ | Only needed for `@redocly/cli` contract linting |
| Python | 3.11+ | Only needed for `fogcache-model-training` |

## First build

```bash
./mvnw verify
```

Runs the full quality gate suite (enforcer, spotless, checkstyle, spotbugs,
tests, jacoco, packaging). The LGTM Testcontainers smoke tests start
`grafana/otel-lgtm:latest` **only when a Docker daemon is available**; on a
machine without Docker they degrade to plain context loads, so the build is
green either way. Start Docker Desktop if you want the full smoke coverage.

## What each module is

See `docs/architecture/module-ownership.md` for the ownership matrix and
dependency rules. Quick orientation:

- `fogcache-bom` — dependency version management
- `fogcache-common` — shared auto-configuration (correlation IDs, ...
  grows with each milestone)
- `fogcache-contracts` — proto (gRPC) + OpenAPI (REST) schemas; generated
  Java is produced by the build
- `fogcache-*-service` — the five Spring Boot services
- `fogcache-integration-tests` — cross-service tests (needs Docker)
- `fogcache-admin-web` — Next.js admin console (own build, outside Maven)
- `fogcache-model-training` — Python ML pipeline (own tooling, outside Maven)

## Running a service

```bash
./mvnw -pl fogcache-routing-service spring-boot:run
```

Each service exposes:

- `http://localhost:<port>/actuator/health` — liveness/readiness probes
- `http://localhost:<port>/actuator/info` — git commit metadata
- `/actuator/prometheus` — metrics (port 8080 by default until milestone 02
  assigns per-service ports)

## Common workflows

```bash
./mvnw -pl fogcache-common test                 # fast loop on one module
./mvnw spotless:apply                            # format everything
./mvnw -Psecurity verify -DskipTests             # dependency-check only
npx @redocly/cli lint fogcache-contracts/src/main/resources/openapi/*.yaml
```

## Troubleshooting

- **Tests fail with "connection refused" / Testcontainers errors** — Docker
  is not running; start Docker Desktop or use `-DskipTests`.
- **`spotless:check` fails after a rebase** — run `./mvnw spotless:apply`.
- **Build fails with "Required goal ... not found"** — you ran the wrapper
  from a subdirectory without a `.mvn` dir; run from the repo root.
