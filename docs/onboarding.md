# Onboarding: run FogCache locally

You will finish this guide having started the whole platform, seen a real
cache **miss turn into a hit**, and knowing how to fix the most common
breakages. It should take roughly 10 minutes of commands plus one first-time
image build (~4-8 min; faster afterwards).

The quickest valid end state is `pwsh scripts/fogcache.ps1 smoke` printing
`SMOKE PASSED` — the guide below walks through what that command does so
nothing is magic.

## Prerequisites

| Tool | Version | Required for | Check |
|---|---|---|---|
| PowerShell 7 (`pwsh`) | 7.x | All `fogcache` scripts (single source of truth; `fogcache.sh` is a thin wrapper) | `pwsh -v` |
| Docker Desktop (or daemon + Compose plugin) | latest | The whole platform stack | `docker info`, `docker compose version` |
| JDK | 21 (Temurin) | Build — enforced by the enforcer as `[21,22)` | `java -version` |
| Maven | — | Nothing to install; use the wrapper `./mvnw` / `mvnw.cmd` | — |
| Node.js | 20+ | `@redocly/cli` OpenAPI contract linting | `node -v` |
| Python | 3.11+ | `scripts/traffic-gen.py`, `fogcache-model-training` | `python --version` |
| OpenSSL | any | Only for generating local TLS test certificates | `openssl version` |

Only PowerShell 7 and Docker are needed to start and smoke the platform.

## First startup

From the repository root:

```bash
# Windows (PowerShell)
pwsh scripts/fogcache.ps1 bootstrap

# macOS / Linux (bash) — same script, shim handles the flags
scripts/fogcache.sh bootstrap
```

`bootstrap` does, in order:

1. **Prerequisite check** — Docker CLI, reachable daemon, Compose plugin. Fails fast with actionable messages.
2. **Port conflict check** — warns on ports already held by non-Docker processes; on Windows it ignores Docker's own proxy listeners (`wslrelay`, `vpnkit`, ...).
3. **`.env` creation** — copies `.env.example` to `.env` on first run (all defaults are sane; `.env` is gitignored).
4. **Build + start** — `docker compose up -d --build` for the full stack: 6 service containers, 9 infrastructure containers, plus a one-shot `minio-init` container that creates the MinIO buckets.
5. **Readiness wait (max 300s)** — polls every service's `/actuator/health`; prints `waiting: <service> -> <reason>` every ~30s if something is slow, so a timeout shows *which* service and *why*.
6. **Endpoint summary** — printed when every service reports UP.

The stack is **idempotent** — re-running `bootstrap` (e.g. after a failure) is safe and resumes without losing data.

## Endpoints

| Component | URL | Notes |
|---|---|---|
| Routing service | `http://localhost:8080` | `/actuator/health`, OpenAPI at `/v3/api-docs` |
| Edge node 1 (demo) | `http://localhost:8081` | serves demo tenant; `/demo/cache/<uid>` |
| Edge node 2 | `http://localhost:8082` | |
| Content service | `http://localhost:8083` | |
| Control service | `http://localhost:8084` | |
| Analytics service | `http://localhost:8085` | |
| Keycloak console | `http://localhost:8088` | realm `fogcache` |
| Grafana | `http://localhost:3000` | logs (Loki), traces (Tempo), metrics (Prometheus) |
| Prometheus | `http://localhost:9090` | |
| MinIO console | `http://localhost:9001` | API on 9000; buckets `fogcache-objects`, `fogcache-policies` |
| OTLP collector | `localhost:4317/4318` | gRPC/HTTP telemetry ingress |

Every Spring service exposes `/actuator/health`, `/actuator/info`, and
`/actuator/prometheus`.

## Credentials (local dev only, all in `.env` / realm import)

| Account | Username | Password | Where |
|---|---|---|---|
| OIDC test users | `viewer`, `operator`, `tenant-admin`, `platform-admin`, `auditor` | `fogcache_dev_password` | Keycloak realm `fogcache`, client `fogcache-admin-web` |
| Keycloak admin | `admin` | `fogcache_dev_password` | console at :8088 |
| MinIO root | `fogcache` | `fogcache_dev_password` | console at :9001 |
| Grafana | `admin` | `admin` | anonymous Viewer access also enabled |
| PostgreSQL | `fogcache` | `fogcache_dev_password` | db `fogcache` on :5432 |

## Your first miss, then hit

The edge serves deterministic seed fixtures (`seed/fixtures/v1/objects.json`,
checksummed payloads under `seed/fixtures/v1/payloads/`). The demo route is
`GET /demo/cache/<uid>` on edge-1 (`object-hello` is the canonical first try).

Get a token:

```bash
curl -s http://localhost:8088/realms/fogcache/protocol/openid-connect/token \
  -d grant_type=password -d client_id=fogcache-admin-web \
  -d username=viewer -d password=fogcache_dev_password
# -> copy the access_token value
```

Force a cold start (evicts any cached copy), then fetch twice:

```bash
TOKEN="<access_token>"

curl -s -X DELETE -H "Authorization: Bearer $TOKEN" http://localhost:8081/demo/cache/object-hello   # evict

curl -s -D - -o /dev/null -H "Authorization: Bearer $TOKEN" http://localhost:8081/demo/cache/object-hello
# X-FogCache-Status: miss

curl -s -D - -o /dev/null -H "Authorization: Bearer $TOKEN" http://localhost:8081/demo/cache/object-hello
# X-FogCache-Status: hit
```

That second `hit` with no origin round-trip is the core of the platform. The
body checksum must match the fixture manifest:

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8081/demo/cache/object-hello | sha256sum
# 29d46da10f066712751a480ae70187382b39a4034d4d3986ab2921803b2c6f9f  -   (matches objects.json)
```

The same sequence — evict, miss, hit, checksum — plus auth enforcement and
metrics counters is automated:

```bash
pwsh scripts/fogcache.ps1 smoke        # end-to-end smoke, exit 0 = all green
```

## Everyday workflows

| Task | Command |
|---|---|
| Start / resume the whole stack | `pwsh scripts/fogcache.ps1 bootstrap` |
| Inspect container + service health | `pwsh scripts/fogcache.ps1 status` |
| End-to-end smoke (auth, miss/hit, metrics) | `pwsh scripts/fogcache.ps1 smoke` |
| Flush caches only (fast, no data loss) | `pwsh scripts/fogcache.ps1 reset --cache` |
| Wipe all stored data and restart | `pwsh scripts/fogcache.ps1 reset --data` |
| Wipe data + delete locally built images | `pwsh scripts/fogcache.ps1 reset --full` |
| Stop, keep volumes | `pwsh scripts/fogcache.ps1 teardown` |
| Stop, delete volumes | `pwsh scripts/fogcache.ps1 teardown --purge` |
| Logs for one service | `docker compose logs -f fogcache-edge-1` |
| Run the 7 deterministic traffic scenarios | `python scripts/traffic-gen.py --scenario <name> --rate 10 --duration 15` |
| Fast edit-build-run loop (no image rebuild) | `./mvnw package -DskipTests`, then `bootstrap --dev` |

`reset` variants ask for confirmation (`--yes` skips it). `--data` and
`--full` recreate the Postgres/Redis/Kafka/MinIO/Keycloak/observability
volumes and re-import the Keycloak realm and MinIO buckets; the service
images are rebuilt from source on the next `bootstrap`.

**Dev mode** (`bootstrap --dev`) bind-mounts the jars you just built
(`target/*.jar`) over the image jars, so after editing code you only need
`./mvnw package -DskipTests` + `docker compose restart <service>` — no image
build. Services built in dev mode require the dev-mode jars to be present;
run `reset --full` to switch back to image builds.

**Disposable mode** (`bootstrap --disposable`) swaps named volumes for
anonymous volumes: every teardown leaves nothing behind. This is what CI
uses. It is also the mode to use when you want a guaranteed-clean demo.

## Data & fixtures

- Seed fixtures are deterministic and versioned: `pwsh seed/tools/verify.ps1`
  checksums the tree and fails on drift; `regenerate.ps1` regenerates it
  (byte-identical on every machine).
- The edge serves the demo tenant's objects from these fixtures; the traffic
  generator and smoke tests reference the stable `uid`s, never payload bytes.
- Intentional boundary fixtures exist for negative tests: `object-empty`,
  `object-invalid-utf8`, `object-corrupt`, `object-over-quota`, `origin-down`,
  `policy-stale`, `tenant-zero-quota`, `invalidation-unknown`, `model-disabled`.

## Telemetry inspection

All services export OTLP to the shared collector → Loki (logs), Tempo
(traces), Prometheus (metrics), all queryable from Grafana at
`http://localhost:3000` (anonymous Viewer access is on; `admin`/`admin` to
sign in).

Quick pointers:

- **Metrics**: `http://localhost:9090` (Prometheus) or Grafana Explore →
  Prometheus. Demo cache counters: `fogcache_demo_cache_hits_total` /
  `fogcache_demo_cache_misses_total` on the edge services.
- **Traces**: Grafana Explore → Tempo. Trace sampling is controlled by
  `TRACE_SAMPLING_PROBABILITY` in `.env` (default `1.0` = sample everything).
- **Logs**: `docker compose logs -f fogcache-edge-1` (10 MB x 3 files
  rotation, json-file driver) or Grafana Explore → Loki.

## Local TLS certificates (optional)

`scripts/gen-certs.ps1` (bash: `gen-certs.sh`) generates a local CA plus a
localhost server certificate into `config/certs/` (gitignored). Requires
`openssl` on PATH. Trust the CA per platform:

- Windows: `certutil -addstore Root config\certs\ca.crt` (admin)
- macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain config/certs/ca.crt`
- Linux: `sudo cp config/certs/ca.crt /usr/local/share/ca-certificates/fogcache-ca.crt && sudo update-ca-certificates`
- JVM: `keytool -importcert -noprompt -cacerts -alias fogcache-local-ca -file config/certs/ca.crt`

## Troubleshooting

Ordered by likelihood of hitting them. `fogcache.ps1 status` is the general
first step: it shows per-container state and how to read logs.

| Symptom | Cause / fix |
|---|---|
| `Docker daemon is not reachable` | Docker Desktop (or the engine) isn't running. Start it and wait for the engine. |
| `Docker Compose plugin is missing` | Compose is disabled in Docker Desktop settings (Settings → General → "Use Docker Compose V2"); or install the plugin. |
| `port <p> ... is held by <proc>` | A non-Docker process owns a stack port (8080-8085, 5432, 6379, 9092, 9000/9001, 8088, 3000, 9090, 3100, 3200, 4317/4318). Stop it, or override the port in `.env` (e.g. `EDGE_1_PORT=18081`) and re-run bootstrap. Port changes take effect on the next `bootstrap`; services and infra both read `.env`. |
| Bootstrap times out after 300s with `waiting: <service> -> ...` | The stack is up but a service never reported ready. The probe line tells you which service and the reason (e.g. `connection refused` = still starting, or a non-`UP` actuator status = unhealthy dependency). Check `docker compose logs -f fogcache-<service>` and the infra it depends on. Re-run bootstrap to resume — it is idempotent. |
| Container crash-loops with permission errors (Kafka `AccessDeniedException ... bootstrap.checkpoint.tmp`, Prometheus `Unable to create mmap-ed active query log`) | The volume root is not writable by the container's non-root user. Named volumes and anonymous volumes copy image ownership (fine); a `docker run --mount type=tmpfs` may be root-owned (Compose silently strips tmpfs `mode` options). Use named volumes, or the `--disposable` overlay which uses anonymous volumes. |
| Keycloak reachable but the stack waits on it | First start imports the `fogcache` realm and creates the admin user; on cold disks this can take minutes. Watch `docker compose logs -f fogcache-keycloak`. |
| `Required goal ... not found` from Maven | You ran the wrapper from a subdirectory without its own `.mvn`; run from the repo root. |
| Tests fail with `connection refused` / Testcontainers errors | Docker isn't running; or the `grafana/otel-lgtm:latest` test image needs pulling. The build degrades to plain context loads when no daemon is available, so it's green either way — but smoke tests only run with Docker. |
| `./mvnw spotless:check` fails after a rebase | `./mvnw spotless:apply` and re-check. |
| `Invoke-WebRequest` (pwsh 7) returns a `byte[]` for JSON responses | PowerShell 7 returns `.Content` as bytes when the Content-Type isn't `text/*` (e.g. actuator v3+json), which silently breaks `ConvertFrom-Json`. The `fogcache.ps1` scripts handle this; if you probe manually, use `curl` or `Invoke-RestMethod`. |
| Services started from an IDE (spring-boot-docker-compose) clash with the stack | Each service module has its own small `compose.yaml` for IDE-driven runs on different ports; don't run both against the same stack simultaneously. |
| Docker Desktop shows high memory pressure / build OOMs | Stack limits: infra containers 1 CPU / 1 GB each, services 0.5 CPU / 768 MB each (nominal ceiling ~15 GB; typical idle usage is a few GB). Give Docker Desktop 8+ GB (Settings → Resources) if the build OOMs; on WSL 2 the limit lives in `.wslconfig`. |

### Windows / WSL / macOS / Linux differences

| Aspect | Windows | WSL 2 | macOS / Linux |
|---|---|---|---|
| Entry point | `pwsh scripts/fogcache.ps1 ...` | either (see next row) | `scripts/fogcache.sh ...` |
| Container engine | Docker Desktop (WSL2 backend) | Docker Desktop or a daemon inside WSL; keep the repo on the Linux filesystem (`/home/...`) for file-watching/performance | Docker Desktop (macOS) / native daemon (Linux) |
| Port-conflict detection | `Get-NetTCPConnection`, ignores `wslrelay`/`vpnkit` proxies | same as Windows (uses PowerShell path) | `ss -ltnp`, ignores `docker-proxy` |
| Hostname for containers | `host.docker.internal` auto-added | add `extra_hosts` (the stack already declares `host.docker.internal:host-gateway`) | same as Windows |
| CA trust command | `certutil -addstore Root` | trust inside WSL + optionally Windows | `security add-trusted-cert` / `update-ca-certificates` |
| `openssl` install | `choco install openssl` | `sudo apt install openssl` | `brew install openssl` / `apt` |

## Expected resource usage

- 15 long-running containers (6 Spring services + 9 infra) plus the one-shot
  `minio-init`.
- Per-container ceilings: infra 1 CPU / 1 GB; services 0.5 CPU / 768 MB.
- Idle the stack sits at a few GB of RSS; the nominal ceiling (~15 GB) is only
  approached under full load (e.g. `traffic-gen burst` at high rates).
- Logs are rotated (10 MB x 3) per container; Prometheus TSDB retention is 24h;
  Kafka is a single KRaft node with auto-created topics.

## CI validation

On every push to `master` (and on PRs), GitHub Actions validates exactly the
commands in this guide against an ephemeral stack:

1. `pwsh scripts/fogcache.ps1 bootstrap --disposable` (readiness-gated; startup time reported to the job summary)
2. `pwsh seed/tools/verify.ps1` (fixture integrity)
3. `pwsh scripts/fogcache.ps1 smoke` (auth, routing, miss/hit, metrics)
4. `python3 scripts/traffic-gen.py --scenario <uniform|zipfian|burst|sequential|regional|invalidation|origin-fault>`
5. `pwsh scripts/fogcache.ps1 teardown --purge` (always, even on failure/cancel)

`docs/tools/check-docs.ps1` additionally verifies that every `fogcache.ps1`,
`traffic-gen.py --scenario`, and relative markdown link used in these docs
resolves — so a documented command can't silently go stale.
