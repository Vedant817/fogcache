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

## Local platform stack

All local data services are defined in the root `compose.yaml` (pinned
images, health checks, resource limits, named volumes):

```bash
docker compose up -d            # persistent mode (named volumes)
docker compose ps               # all services should report healthy
docker compose down -v          # teardown AND wipe all data
```

| Service | Image | Port(s) | Credentials |
|---|---|---|---|
| PostgreSQL 17 | `postgres:17-alpine` | 5432 | `fogcache` / `fogcache_dev_password` (db `fogcache`) |
| Redis 7 | `redis:7.4-alpine` | 6379 | — |
| Kafka 4 (KRaft) | `apache/kafka:4.1.0` | 9092 | — |
| MinIO | `minio/minio:RELEASE.2025-04-22T22-12-26Z` | 9000 (API), 9001 (console) | `fogcache` / `fogcache_dev_password` |

MinIO starts with two empty buckets (`fogcache-objects`, `fogcache-policies`)
created by the `minio-init` one-shot service, which waits on the MinIO health
check. Kafka is a single KRaft node (no ZooKeeper) and auto-creates topics.

Disposable mode swaps the named volumes for anonymous volumes, so nothing
survives a teardown and every run starts from a clean slate (anonymous volumes
are initialized from the image directory, preserving image ownership for
non-root users like Kafka's `appuser` and Prometheus' `nobody`):

```bash
docker compose -f compose.yaml -f compose.disposable.yaml up -d
```

Ports and credentials are configurable via a local `.env` (see `.env.example` —
copy it to `.env` and edit; `.env` is gitignored).

> The per-service `compose.yaml` files (used by `spring-boot-docker-compose`
> when a service starts from an IDE) are independent of this stack; both can
> be used side by side on different ports.

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

## Traffic generator

`scripts/traffic-gen.py` (zero-dependency Python 3.11+) drives deterministic,
seed-reproducible request scenarios against the demo edge and validates each
response against an expected outcome (status, cache status, checksum):

```bash
python scripts/traffic-gen.py --scenario uniform --rate 10 --duration 15
python scripts/traffic-gen.py --scenario zipfian --seed 42 --zipf 1.5
python scripts/traffic-gen.py --scenario burst --rate 5 --burst-rate 40 --duration 20
python scripts/traffic-gen.py --scenario regional --targets http://localhost:8081,http://localhost:8082
python scripts/traffic-gen.py --scenario invalidation --rate 10 --duration 12
python scripts/traffic-gen.py --scenario origin-fault --rate 10 --duration 10
python scripts/traffic-gen.py --dry-run          # print the plan, send nothing
```

Scenarios: `uniform`, `zipfian` (exponent via `--zipf`), `burst` (high/low
periods via `--burst-high/--burst-low`), `sequential`, `regional` (round-robin
across `--targets`), `invalidation` (evict + re-fetch, asserts miss),
`origin-fault` (unknown uids → 404, corrupted fixture → 200 with failing
checksum). The request stream is a pure function of `--seed`; only latency
metrics vary run to run. `--corpus demo` (default) targets the uids the demo
edge serves; `--corpus all` expects a full origin that serves every seed
fixture. `--metrics-out`/`--events-out` write JSON/JSONL artifacts. Exit code
is 0 only if every event passed. Tokens are auto-fetched from Keycloak for
localhost targets; non-local targets require `--token`.

## Troubleshooting

- **Tests fail with "connection refused" / Testcontainers errors** — Docker
  is not running; start Docker Desktop or use `-DskipTests`.
- **`spotless:check` fails after a rebase** — run `./mvnw spotless:apply`.
- **Build fails with "Required goal ... not found"** — you ran the wrapper
  from a subdirectory without a `.mvn` dir; run from the repo root.
