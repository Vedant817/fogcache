# FogCache — Architecture Diagrams (00.10)

Status: Agreed · Version: 1 · Issue: VED-59
All diagrams are Mermaid source; they match `docs/technical-design.md`, the contracts, and the acceptance journeys (J-01…J-12). Versioning convention: diagrams change only with the corresponding design/contract change (see `contract-conventions.md` §1 and `risk-register.md`).

## 1. Context diagram

```mermaid
flowchart LR
    C[Client / Browser / API] -->|GET/HEAD over HTTP| E[Edge Service]
    O[Operator / Tenant Admin / Auditor] -->|HTTPS + OIDC| W[Admin Web]
    W -->|REST| CT[Control Service]
    C -.->|optional gateway mode| E
    E -->|gRPC internal| E2[Edge Service n]
    E -->|HTTP revalidation| OR[Origin / Content Service]
    OR -->|S3 API| OS[(Object Storage)]
    E -->|events| K[Kafka]
    RT[Routing Service] -->|leases/ring| E
    AN[Analytics Service] -->|classification/placement| K
    E -->|telemetry| OB[LGTM: Prometheus/Grafana/Loki/Tempo]
    E -->|leases/idempotency| RD[(Redis)]
    CT -->|config+audit| PG[(PostgreSQL)]
```

## 2. Container diagram (simplified)

```mermaid
flowchart TB
    subgraph DataPlane
        RT[Routing Service<br/>WebFlux + Redis leases]
        E1[Edge Service<br/>Caffeine + RocksDB + single-flight]
        E2[Edge Service ...]
    end
    subgraph OriginPlane
        CS[Content Service<br/>MinIO/S3]
    end
    subgraph ControlPlane
        CT[Control Service<br/>PostgreSQL + Flyway]
        AN[Analytics Service<br/>Kafka Streams + ONNX]
    end
    subgraph Eventing
        K[Kafka]
    end
    E1 --> K
    E2 --> K
    AN --> K
    CT --> K
    RT --> E1
    RT --> E2
    E1 --> CS
```

## 3. Sequence: normal hit and miss

```mermaid
sequenceDiagram
    participant Cl as Client
    participant Ed as Edge
    participant En as Cache Engine
    participant Or as Origin
    participant Ka as Kafka
    Cl->>Ed: GET /cache/{originAlias}/path
    Ed->>En: normalize key, lookup
    alt hit
        En-->>Ed: entry (fresh)
        Ed-->>Cl: 200 + X-FogCache-Status: HIT
        Ed->>Ka: access(hit)
    else miss
        En->>En: single-flight acquire
        En->>Or: fetch (If-None-Match optional)
        Or-->>En: 200 + body
        En->>En: validate, persist, release waiters
        Ed-->>Cl: 200 + X-FogCache-Status: MISS
        Ed->>Ka: access(miss) + replication(created)
    end
```

## 4. Sequence: stale-while-revalidate and stale-if-error

```mermaid
sequenceDiagram
    participant Cl as Client
    participant Ed as Edge
    participant Or as Origin
    Cl->>Ed: GET (entry stale)
    alt within stale-while-revalidate
        Ed-->>Cl: 200 stale + STALE
        Ed->>Or: revalidate
        Or-->>Ed: 304/200 → refresh metadata
    else stale-if-error (origin down)
        Ed->>Or: fetch
        Or--x Ed: error/timeout
        Ed-->>Cl: 200 stale + STALE-ERROR (or 502)
        Ed->>Ed: negative-cache 502 if policy
    end
```

## 5. Sequence: replication (transfer commit)

```mermaid
sequenceDiagram
    participant O as Owner (primary)
    participant R as Replica
    O->>R: TransferHeader{key, metadata, generation}
    O->>R: stream payload chunks
    R->>R: stage, verify sha-256
    alt checksum ok
        R->>R: atomic commit
        R-->>O: COMMITTED
    else mismatch
        R-->>O: CHECKSUM_MISMATCH
        O->>O: retry (bounded) → repair ticket
    end
```

## 6. Sequence: invalidation propagation

```mermaid
sequenceDiagram
    participant A as Admin
    participant CT as Control
    participant K as Kafka
    participant E1 as Edge 1
    participant E2 as Edge n
    A->>CT: POST keys:invalidate (idempotency key)
    CT->>CT: bump origin_generation, audit
    CT->>K: invalidation{originSeq}
    par per-partition ordered delivery
        K-->>E1: apply in order, dedupe
        K-->>E2: apply in order, dedupe
    end
    E1-->>CT: ack (applied originSeq)
    E2-->>CT: ack
```

## 7. Sequence: node failure and failover

```mermaid
sequenceDiagram
    participant E2 as Edge n2 (owner)
    participant RT as Routing
    participant E3 as Edge n3 (replica)
    E2--x RT: lease expires (2 missed heartbeats)
    RT->>RT: topology bump (version v2)
    RT->>E3: promote owner
    E3->>E3: serve replica or fetch from origin
    Note over E3: remap ≤ 20% of keys; alert edge-node-down
```

## 8. Sequence: prefetch

```mermaid
sequenceDiagram
    participant AN as Analytics
    participant K as Kafka
    participant Ed as Edge
    AN->>K: placement{PREFETCH, model_version, budget}
    K-->>Ed: prefetch request
    Ed->>Ed: budget check (demand > prefetch priority)
    Ed->>Or: fetch, store, mark prefetched
    Ed->>K: prefetch(outcome)
    AN->>AN: precision/waste metrics
```

## 9. State diagram: cache entry lifecycle

```mermaid
stateDiagram-v2
    [*] --> Absent
    Absent --> Loading: miss + single-flight acquire
    Loading --> Fresh: origin 200 + validated store
    Loading --> Absent: origin error, no stale
    Loading --> Negative: negative-cacheable status
    Fresh --> Fresh: refresh (304 metadata)
    Fresh --> Stale: TTL elapsed (within SWR)
    Fresh --> StaleError: TTL elapsed (within SIE)
    Stale --> Fresh: background revalidate 304/200
    StaleError --> Fresh: origin recovered
    Stale --> Absent: invalidation / eviction
    Fresh --> Absent: invalidation / eviction / generation bump
    Negative --> Absent: negative TTL / origin success
    Absent --> [*]
```

## 10. State diagram: node membership

```mermaid
stateDiagram-v2
    [*] --> Registering: node start
    Registering --> Healthy: lease granted
    Healthy --> Suspect: heartbeat miss
    Suspect --> Healthy: heartbeat resumes
    Suspect --> Down: lease expiry (2 misses)
    Down --> Registering: restart/rejoin
    Healthy --> Draining: admin drain
    Draining --> Down: replicas pushed, withdraw
    Draining --> Healthy: drain cancelled
```
