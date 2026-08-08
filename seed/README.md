# Seed data fixtures (v1)

Deterministic, versioned, idempotent fixtures for local development, tests, and
demos. Services, tests, and the traffic generator reference the **stable
identifiers** declared in `manifest.json` — never hard-code payload bytes.

## Layout

    seed/
      fixtures/v1/          <- immutable, versioned fixture set (commit these)
        manifest.json       <- version, summary, stable identifiers
        tenants.json        <- sample tenants (tiers, quotas)
        origins.json        <- origin endpoints (healthy, https, down)
        objects.json        <- object catalog with deterministic sha256 checksums
        policies.json       <- cache policies (incl. boundary + negative cases)
        quotas.json         <- quota profiles (incl. zero-quota boundary)
        topology.json       <- edge node topology (mirrors compose.services.yaml)
        invalidations.json  <- invalidation bursts (incl. unknown-object case)
        models.json         <- model configurations (incl. disabled)
        payloads/           <- generated deterministic object bytes
      tools/
        regenerate.ps1      <- regenerate payloads from manifest definitions
        verify.ps1          <- checksum + idempotency verification

## Guarantees

* **Deterministic** — payload bytes are derived from the object id via repeated
  SHA-256 (`sha256(id || "_" || block)`), so regeneration is byte-identical on
  every machine, independent of PRNG or OS.
* **Versioned** — the fixture set lives under `fixtures/vN/`; `manifest.json`
  carries `schemaVersion` and `fixtureVersion`. Consumers pin the version.
* **Idempotent** — running `regenerate.ps1` over an existing tree yields an
  identical tree; `verify.ps1` fails on any drift.
* **Stable identifiers** — every fixture has a `uid` (e.g. `tenant-acme`,
  `object-001`). Tests and demos must reference these, never the payload
  contents.

## Intentionally invalid / boundary fixtures

For negative and boundary testing: `object-empty` (0 bytes), `object-invalid-utf8`
(non-UTF-8 bytes), `object-corrupt` (declared checksum intentionally wrong),
`object-over-quota` (payload larger than the referencing quota), `origin-down`
(unreachable endpoint), `policy-stale` (zero TTL), `tenant-zero-quota` (quota of 0),
`node-zero-capacity`, `invalidation-unknown` (unknown object id), `model-disabled`.

## Usage

    # verify current tree (checksums, idempotency)
    pwsh seed/tools/verify.ps1

    # regenerate payloads (must produce an identical tree)
    pwsh seed/tools/regenerate.ps1

Consumers: `fogcache-integration-tests`, the traffic generator (02.6), and demo
scripts read `fixtures/v1/manifest.json` for stable ids, and
`fixtures/v1/objects.json` for checksums and payload paths.
