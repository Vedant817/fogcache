<#
.SYNOPSIS
One-command FogCache local platform workflows: bootstrap, status, smoke, reset, teardown.

.DESCRIPTION
Cross-platform helper (PowerShell; `scripts/fogcache.sh` wraps pwsh). Commands:

  fogcache.ps1 bootstrap [--dev] [--disposable]   Start everything, wait for readiness, show endpoints.
  fogcache.ps1 up [--dev] [--disposable]          Alias for bootstrap.
  fogcache.ps1 status              Show container + service health; diagnose partial startup.
  fogcache.ps1 smoke               End-to-end smoke: auth, routing, miss/hit, metrics.
  fogcache.ps1 reset [--cache|--data|--full] [--yes]   Reset state (see below).
  fogcache.ps1 teardown [--purge]  Stop the stack (keep volumes unless --purge).

Reset semantics:
  --cache  Flush caches only (restart edge nodes, flush Redis). Fast, safe.
  --data   Recreate data stores (postgres, redis, kafka, minio, keycloak, observability
           volumes); services are restarted. Loses all stored data.
  --full   Everything --data does plus delete locally built service images. Confirmation
           is required unless --yes is passed.

Prerequisites are checked up front (Docker CLI, daemon, Compose plugin, free ports) and
fail fast with actionable messages.

.EXAMPLE
  pwsh scripts/fogcache.ps1 bootstrap
  pwsh scripts/fogcache.ps1 smoke
  pwsh scripts/fogcache.ps1 reset --cache
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('bootstrap', 'up', 'status', 'smoke', 'reset', 'teardown', 'down')]
    [string]$Command = 'bootstrap',
    [switch]$Dev,
    [switch]$Disposable,
    [switch]$Cache,
    [switch]$Data,
    [switch]$Full,
    [switch]$Yes,
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$composeBase = @('-f', 'compose.yaml', '-f', 'compose.services.yaml')
if ($Dev) { $composeBase += @('-f', 'compose.dev.yaml') }
if ($Disposable) { $composeBase += @('-f', 'compose.disposable.yaml') }

$services = @{
    'routing'   = 8080
    'edge-1'    = 8081
    'edge-2'    = 8082
    'content'   = 8083
    'control'   = 8084
    'analytics' = 8085
}
$webUis = @(
    @{ name = 'Keycloak console'; url = 'http://localhost:8088' }
    @{ name = 'Grafana'; url = 'http://localhost:3000' }
    @{ name = 'Prometheus'; url = 'http://localhost:9090' }
    @{ name = 'MinIO console'; url = 'http://localhost:9001' }
)

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    & docker compose @composeBase @ComposeArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose $($ComposeArgs -join ' ') failed (exit $LASTEXITCODE)" }
}

function Test-Prerequisites {
    Write-Host '== Prerequisite check =='
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found. Install Docker Desktop (https://www.docker.com/products/docker-desktop/) and restart your shell.'
    }
    $daemon = & docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker daemon is not reachable. Start Docker Desktop and wait for the engine to be ready.'
    }
    Write-Host "  docker daemon OK ($daemon)"
    $composeVersion = & docker compose version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose plugin is missing. Install it or enable it in Docker Desktop settings.'
    }
    Write-Host "  compose plugin OK ($(($composeVersion -split "`n")[0]))"
    if (-not (Test-Path '.env')) {
        Copy-Item '.env.example' '.env'
        Write-Host '  .env created from .env.example (adjust values if needed)'
    }
}

function Test-Ports {
    # Docker Desktop publishes container ports through wslrelay/com.docker.backend/vpnkit
    # proxies - those listeners are the stack itself, not conflicts. On Linux/macOS the
    # same check runs against `ss` and ignores docker-proxy listeners.
    $dockerOwned = @('wslrelay', 'com.docker.backend', 'vpnkit', 'docker-proxy', 'com.docker.dev-envs')
    $conflicts = @()
    foreach ($entry in $services.GetEnumerator()) {
        $heldBy = $null
        if ($env:OS -eq 'Windows_NT') {
            $conn = Get-NetTCPConnection -LocalPort $entry.Value -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                $proc = Get-Process -Id $conn[0].OwningProcess -ErrorAction SilentlyContinue
                $heldBy = "$($proc.ProcessName) (PID $($conn[0].OwningProcess))"
            }
        } else {
            $listener = & ss -ltnp "sport = :$($entry.Value)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $listener) {
                $match = $listener | Select-String 'users:\(\("([^"]+)"'
                if ($match) {
                    $procName = $match.Matches[0].Groups[1].Value
                    $pidMatch = [regex]::Match($listener, 'pid=(\d+)')
                    $heldBy = "$procName (PID $($pidMatch.Groups[1].Value))"
                }
            }
        }
        if ($heldBy) {
            $name = ($heldBy -split ' \(')[0]
            if ($dockerOwned -notcontains $name) {
                $conflicts += "port $($entry.Value) ($($entry.Key)) is held by $heldBy"
            }
        }
    }
    foreach ($c in $conflicts) {
        Write-Warning "  $c - stop that process or override the port in .env"
    }
    if ($conflicts.Count -gt 0) {
        throw 'Port conflicts detected; fix them first (see warnings above).'
    }
}

function Wait-ForStack {
    Write-Host '== Waiting for readiness (up to 300s) =='
    $deadline = (Get-Date).AddSeconds(300)
    $lastProbe = @{}
    do {
        $ready = $true
        foreach ($entry in $services.GetEnumerator()) {
            try {
                $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri "http://localhost:$($entry.Value)/actuator/health"
                $json = $resp.Content | ConvertFrom-Json
                if ($json.status -ne 'UP') {
                    $ready = $false
                    $lastProbe[$entry.Key] = "actuator status=$($json.status)"
                } else {
                    $lastProbe.Remove($entry.Key)
                }
            } catch {
                $ready = $false
                $lastProbe[$entry.Key] = $_.Exception.Message
            }
        }
        if ($ready) { break }
        if (((Get-Date).Second % 30) -lt 5) {
            foreach ($k in $lastProbe.Keys) { Write-Host "  waiting: $k -> $($lastProbe[$k])" }
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    if (-not $ready) {
        Write-Host 'Stack did not become ready. Last probe results:'
        foreach ($k in $lastProbe.Keys) { Write-Host "  $k -> $($lastProbe[$k])" }
        Write-Host 'Run "fogcache.ps1 status" to diagnose; resuming is safe - bootstrap is idempotent.'
        exit 1
    }
    Write-Host '  all services healthy'
}

function Show-Endpoints {
    Write-Host ''
    Write-Host '== Endpoints =='
    foreach ($entry in $services.GetEnumerator()) {
        Write-Host ("  {0,-10} http://localhost:{1}/actuator/health" -f $entry.Key, $entry.Value)
    }
    foreach ($ui in $webUis) {
        Write-Host ("  {0,-16} {1}" -f $ui.name, $ui.url)
    }
    Write-Host '  Credentials: see .env (KEYCLOAK_ADMIN_*, MINIO_ROOT_*, Grafana admin/fogcache_dev_password)'
}

function Invoke-Bootstrap {
    Test-Prerequisites
    Test-Ports
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-Compose -ComposeArgs @('up', '-d', '--build', '--remove-orphans')
    Wait-ForStack
    $sw.Stop()
    Write-Host ("  stack ready in {0:N1}s (build + start + readiness wait)" -f $sw.Elapsed.TotalSeconds)
    Show-Endpoints
    Write-Host ''
    Write-Host 'Smoke test:  pwsh scripts/fogcache.ps1 smoke'
    Write-Host 'Status:      pwsh scripts/fogcache.ps1 status'
}

function Invoke-Status {
    Test-Prerequisites
    $ps = & docker compose @composeBase ps --format 'table {{.Name}}\t{{.Status}}' 2>&1
    $ps
    $up = & docker compose @composeBase ps --format '{{.Name}} {{.State}}' | Select-String ' running' | Measure-Object
    $total = & docker compose @composeBase ps -q | Measure-Object
    Write-Host ''
    Write-Host "Containers: $($up.Count) running / $($total.Count) defined"
    Write-Host 'Diagnostics:'
    Write-Host '  docker compose logs -f <service>      (e.g. fogcache-edge-1)'
    Write-Host '  docker compose ps --format ...       (per-container state)'
    if ($up.Count -lt $total.Count) {
        Write-Host '  Some containers are down; re-run bootstrap to resume.'
    }
}

function Get-ViewerToken {
    $body = @{
        grant_type = 'password'
        client_id  = 'fogcache-admin-web'
        username   = 'viewer'
        password   = 'fogcache_dev_password'
    }
    $resp = Invoke-RestMethod -Method Post -Uri 'http://localhost:8088/realms/fogcache/protocol/openid-connect/token' -Body $body
    return $resp.access_token
}

function Invoke-Smoke {
    Test-Prerequisites
    $failures = @()
    $checks = @()

    # --- Authentication ---
    $checks += 'auth: viewer password grant'
    try {
        $token = Get-ViewerToken
        if (-not $token) { throw 'no access_token in response' }
        $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + (4 - ($payload.Length % 4)) % 4, '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        if ($claims -notmatch 'viewer') { throw 'token has no viewer role' }
        Write-Host "  PASS $($checks[-1])"
    } catch {
        $failures += $checks[-1]; Write-Host "  FAIL $($checks[-1]): $_"
    }

    # --- Routing + edge reachability ---
    foreach ($name in @('routing', 'edge-1', 'edge-2')) {
        $checks += "reachability: $name health"
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://localhost:$($services[$name])/actuator/health"
            if ($r.StatusCode -ne 200) { throw "HTTP $($r.StatusCode)" }
            Write-Host "  PASS $($checks[-1])"
        } catch {
            $failures += $checks[-1]; Write-Host "  FAIL $($checks[-1]): $_"
        }
    }

    # --- Auth enforced: anonymous request must be 401 ---
    $checks += 'auth: anonymous request rejected (401)'
    try {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://localhost:8081/demo/cache/object-hello" | Out-Null
        throw 'expected 401, request was served'
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 401) {
            Write-Host "  PASS $($checks[-1])"
        } else {
            $failures += $checks[-1]; Write-Host "  FAIL $($checks[-1]): $($_.Exception.Message)"
        }
    }

    # --- Miss / hit with fixture checksums ---
    $manifest = Get-Content "seed/fixtures/v1/objects.json" -Raw | ConvertFrom-Json
    $hello = $manifest.objects | Where-Object uid -eq 'object-hello'
    $headers = @{ Authorization = "Bearer $token" }
    $checks += 'cache: miss then hit with matching checksums'
    try {
        # Deterministic cold start: evict first, then expect miss -> hit.
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Method Delete -Headers $headers "http://localhost:8081/demo/cache/object-hello" | Out-Null
        $first = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Headers $headers "http://localhost:8081/demo/cache/object-hello"
        $second = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Headers $headers "http://localhost:8081/demo/cache/object-hello"
        if ($first.Headers['X-FogCache-Status'] -ne 'miss') { throw "expected miss, got $($first.Headers['X-FogCache-Status'])" }
        if ($second.Headers['X-FogCache-Status'] -ne 'hit') { throw "expected hit, got $($second.Headers['X-FogCache-Status'])" }
        $hash = (Get-FileHash -Algorithm SHA256 -InputStream $first.RawContentStream).Hash.ToLower()
        if ($hash -ne $hello.sha256) { throw "body sha256 $hash != manifest $($hello.sha256)" }
        Write-Host "  PASS $($checks[-1])"
    } catch {
        $failures += $checks[-1]; Write-Host "  FAIL $($checks[-1]): $_"
    }

    # --- Metrics ---
    $checks += 'metrics: prometheus counters present'
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://localhost:8081/actuator/prometheus"
        if ($r.Content -notmatch 'fogcache_demo_cache_hits_total') { throw 'hits counter missing' }
        if ($r.Content -notmatch 'fogcache_demo_cache_misses_total') { throw 'misses counter missing' }
        Write-Host "  PASS $($checks[-1])"
    } catch {
        $failures += $checks[-1]; Write-Host "  FAIL $($checks[-1]): $_"
    }

    Write-Host ''
    if ($failures.Count -gt 0) {
        Write-Host "SMOKE FAILED: $($failures.Count) check(s) failed"
        exit 1
    }
    Write-Host 'SMOKE PASSED: auth, routing, miss/hit, metrics all green'
}

function Confirm-Destructive {
    param([string]$Message)
    if ($Yes) { return $true }
    Write-Host $Message
    $answer = Read-Host 'Type YES to continue'
    return ($answer -eq 'YES')
}

function Invoke-Reset {
    if ($Cache) {
        if (-not (Confirm-Destructive 'Reset --cache: flush Redis and restart edge nodes (no data loss).')) { Write-Host 'Aborted.'; return }
        Write-Host 'Flushing Redis and restarting edge nodes...'
        $redisId = & docker compose @composeBase ps -q redis
        if (-not $redisId) { throw 'redis container not running' }
        & docker exec $redisId redis-cli FLUSHALL | Out-Null
        Invoke-Compose -ComposeArgs @('restart', 'edge-1', 'edge-2')
        Write-Host 'Cache reset done. Run smoke to confirm.'
    } elseif ($Data) {
        if (-not (Confirm-Destructive 'Reset --data: destroys ALL stored data (postgres, redis, kafka, minio, keycloak, observability volumes) and recreates the stack.')) { Write-Host 'Aborted.'; return }
        Invoke-Compose -ComposeArgs @('down', '-v', '--remove-orphans')
        Invoke-Bootstrap
    } elseif ($Full) {
        if (-not (Confirm-Destructive 'Reset --full: destroys ALL data AND deletes locally built service images. Requires a full rebuild afterwards.')) { Write-Host 'Aborted.'; return }
        Invoke-Compose -ComposeArgs @('down', '-v', '--remove-orphans')
        & docker rmi fogcache-routing-service:local fogcache-edge-service:local fogcache-content-service:local fogcache-control-service:local fogcache-analytics-service:local 2>$null
        Invoke-Bootstrap
    } else {
        Write-Host 'reset requires one of --cache, --data, or --full.'
        exit 2
    }
}

function Invoke-Teardown {
    if ($Purge) {
        Invoke-Compose -ComposeArgs @('down', '-v', '--remove-orphans')
        Write-Host 'Stack stopped; volumes deleted.'
    } else {
        Invoke-Compose -ComposeArgs @('down', '--remove-orphans')
        Write-Host 'Stack stopped; volumes preserved (use --purge to delete them, reset --data to recreate data).'
    }
}

switch ($Command) {
    'bootstrap' { Invoke-Bootstrap }
    'up' { Invoke-Bootstrap }
    'status' { Invoke-Status }
    'smoke' { Invoke-Smoke }
    'reset' { Invoke-Reset }
    'teardown' { Invoke-Teardown }
    'down' { Invoke-Teardown }
}
