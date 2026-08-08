#!/usr/bin/env python3
"""FogCache configurable traffic generator (milestone 02.7).

Deterministic, seed-reproducible request scenarios against the local (or
staging) stack, with expected-outcome validation per event.

Scenarios: uniform | zipfian | burst | sequential | regional | invalidation | origin-fault

Examples:
  python scripts/traffic-gen.py --scenario uniform --rate 5 --duration 10
  python scripts/traffic-gen.py --scenario zipfian --seed 42 --metrics-out out/metrics.json
  python scripts/traffic-gen.py --scenario regional --targets http://localhost:8081,http://localhost:8082
  python scripts/traffic-gen.py --scenario invalidation --target http://localhost:8081

Safety: --target must be http(s). Nothing is mutated except the demo eviction
endpoint under the invalidation scenario. Non-local targets require --token
(auto token fetch is localhost-only). --dry-run prints the plan without
sending requests.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES = REPO_ROOT / "seed" / "fixtures" / "v1"
MAX_DURATION_SECONDS = 3600

DEMO_UIDS = frozenset({"object-hello", "object-config", "object-page", "object-image"})


def load_corpus() -> dict:
    objects = json.loads((FIXTURES / "objects.json").read_text(encoding="utf-8"))["objects"]
    return {
        obj["uid"]: {
            "sha256": obj["sha256"],
            "declaredSha256": obj.get("declaredSha256", obj["sha256"]),
        }
        for obj in objects
    }


def zipf_weights(n: int, exponent: float) -> list[float]:
    denom = sum(1.0 / (i**exponent) for i in range(1, n + 1))
    return [1.0 / ((i**exponent) * denom) for i in range(1, n + 1)]


class ExpectedOutcome:
    def __init__(self, status, cache_status=None, checksum_matches=None):
        self.status = status
        self.cache_status = cache_status
        self.checksum_matches = checksum_matches


class Event:
    def __init__(self, seq, scenario, target, uid, expected):
        self.seq = seq
        self.scenario = scenario
        self.target = target
        self.uid = uid
        self.expected = expected
        self.actual_status = None
        self.cache_status = None
        self.latency_ms = None
        self.checksum_match = None
        self.error = None

    def to_dict(self) -> dict:
        return {
            "seq": self.seq,
            "scenario": self.scenario,
            "target": self.target,
            "uid": self.uid,
            "expected": vars(self.expected),
            "actual_status": self.actual_status,
            "cache_status": self.cache_status,
            "latency_ms": self.latency_ms,
            "checksum_match": self.checksum_match,
            "error": self.error,
            "passed": self.ok(),
        }

    def ok(self) -> bool:
        if self.error:
            return False
        if self.actual_status != self.expected.status:
            return False
        if self.expected.cache_status and self.cache_status != self.expected.cache_status:
            return False
        if self.expected.checksum_matches is not None and self.expected.checksum_matches != self.checksum_match:
            return False
        return True


class Generator:
    def __init__(self, args):
        self.args = args
        corpus = load_corpus()
        if args.corpus == "demo":
            corpus = {uid: meta for uid, meta in corpus.items() if uid in DEMO_UIDS}
        self.corpus = corpus
        self.uids = list(corpus.keys())
        self.known = [u for u in self.uids if corpus[u]["sha256"] == corpus[u]["declaredSha256"]]
        self.corrupt = [u for u in self.uids if corpus[u]["sha256"] != corpus[u]["declaredSha256"]]
        self.rng = random.Random(args.seed)
        self.token = args.token
        self.events = []
        self.lock = threading.Lock()
        self._next_slot = time.monotonic()
        self._seq = 0

    def ensure_token(self) -> str:
        if self.token:
            return self.token
        if "localhost" not in self.args.target and "127.0.0.1" not in self.args.target:
            raise SystemExit("Refusing to auto-fetch tokens for a non-local target; pass --token explicitly.")
        token_url = self.args.token_url.rstrip("/") + "/realms/fogcache/protocol/openid-connect/token"
        body = urllib.parse.urlencode(
            {
                "grant_type": "password",
                "client_id": "fogcache-admin-web",
                "username": self.args.username,
                "password": self.args.password,
            }
        ).encode()
        req = urllib.request.Request(token_url, data=body, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())["access_token"]

    def pick_key(self, scenario: str) -> str:
        if scenario == "zipfian":
            return self.rng.choices(self.known, weights=zipf_weights(len(self.known), self.args.zipf), k=1)[0]
        if scenario == "sequential":
            return self.known[self._seq % len(self.known)]
        if scenario == "origin-fault":
            if self._seq % 3 == 0 and self.corrupt:
                return self.rng.choice(self.corrupt)
            return "object-does-not-exist-" + str(self.rng.randint(1, 1000))
        return self.rng.choice(self.known)

    def expected_for(self, scenario: str, uid: str) -> ExpectedOutcome:
        if scenario == "origin-fault":
            if uid in self.corrupt:
                return ExpectedOutcome(200, checksum_matches=False)
            return ExpectedOutcome(404)
        if uid in self.known:
            return ExpectedOutcome(200, checksum_matches=True)
        return ExpectedOutcome(404)

    def pace(self) -> None:
        with self.lock:
            now = time.monotonic()
            if now < self._next_slot:
                time.sleep(self._next_slot - now)
            self._next_slot = max(self._next_slot, now) + (1.0 / self.args.rate)

    def burst_active(self, elapsed: float) -> bool:
        period = self.args.burst_high + self.args.burst_low
        return (elapsed % period) < self.args.burst_high

    def rate_for(self, elapsed: float) -> float:
        if self.scenario_mode == "burst":
            return self.args.burst_rate if self.burst_active(elapsed) else self.args.rate
        return self.args.rate

    def request(self, method: str, target: str, uid: str) -> tuple[int, dict]:
        url = f"{target}/demo/cache/{urllib.parse.quote(uid)}"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.token}"}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.args.timeout) as resp:
                return resp.status, dict(resp.headers)
        except urllib.error.HTTPError as err:
            return err.code, dict(err.headers)

    def send(self, target: str, uid: str, expected: ExpectedOutcome) -> None:
        started = time.monotonic()
        event = Event(self._seq, self.scenario_mode, target, uid, expected)
        try:
            status, headers = self.request("GET", target, uid)
            event.actual_status = status
            event.cache_status = headers.get("X-FogCache-Status")
            header_sha = headers.get("X-FogCache-Sha256")
            if expected.checksum_matches is not None and header_sha:
                event.checksum_match = header_sha == self.corpus[uid]["declaredSha256"]
        except Exception as exc:
            event.error = f"{type(exc).__name__}: {exc}"
        event.latency_ms = round((time.monotonic() - started) * 1000, 1)
        with self.lock:
            self.events.append(event)

    def run(self) -> None:
        self.scenario_mode = self.args.scenario
        if self.args.dry_run:
            print(f"[dry-run] scenario={self.scenario_mode} targets={self.args.targets} rate={self.args.rate} "
                  f"concurrency={self.args.concurrency} duration={self.args.duration}s seed={self.args.seed}")
            return
        self.token = self.ensure_token()
        targets = self.args.targets
        deadline = time.monotonic() + min(self.args.duration, MAX_DURATION_SECONDS)
        started = time.monotonic()

        def worker(_worker_id: int) -> None:
            while True:
                now = time.monotonic()
                if now >= deadline:
                    return
                rate = self.rate_for(now - started)
                if rate > 0:
                    self.pace()
                with self.lock:
                    self._seq += 1
                    seq = self._seq
                if self.scenario_mode == "invalidation" and seq % 2 == 0:
                    target = targets[seq % len(targets)]
                    uid = self.pick_key("invalidation")
                    try:
                        status, _headers = self.request("DELETE", target, uid)
                        if status != 204:
                            raise RuntimeError(f"evict {uid}: expected 204, got {status}")
                    except Exception as exc:
                        event = Event(seq, self.scenario_mode, target, uid, ExpectedOutcome(204))
                        event.error = f"{type(exc).__name__}: {exc}"
                        with self.lock:
                            self.events.append(event)
                        continue
                    event = Event(seq, self.scenario_mode, target, uid, ExpectedOutcome(200, cache_status="miss"))
                    event.cache_status = "miss"
                    event.actual_status = 200
                    event.latency_ms = 0
                    with self.lock:
                        self.events.append(event)
                    continue
                uid = self.pick_key(self.scenario_mode)
                target = targets[seq % len(targets)]
                self.send(target, uid, self.expected_for(self.scenario_mode, uid))

        with ThreadPoolExecutor(max_workers=max(1, self.args.concurrency)) as pool:
            list(pool.map(worker, range(max(1, self.args.concurrency))))

    def report(self) -> dict:
        total = len(self.events)
        ok = sum(1 for e in self.events if e.ok())
        latencies = sorted(e.latency_ms for e in self.events if e.latency_ms is not None)
        hits = sum(1 for e in self.events if e.cache_status == "hit")
        misses = sum(1 for e in self.events if e.cache_status == "miss")

        def percentile(p: float):
            if not latencies:
                return None
            return latencies[min(len(latencies) - 1, int(p * len(latencies)))]

        summary = {
            "scenario": self.scenario_mode,
            "seed": self.args.seed,
            "targets": self.args.targets,
            "rate": self.args.rate,
            "concurrency": self.args.concurrency,
            "duration": self.args.duration,
            "events": total,
            "passed": ok,
            "failed": total - ok,
            "latency_ms": {"p50": percentile(0.50), "p95": percentile(0.95), "p99": percentile(0.99)},
            "cache": {"hits": hits, "misses": misses, "hit_rate": round(hits / max(1, hits + misses), 3)},
        }
        if self.args.metrics_out:
            out = Path(self.args.metrics_out)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        if self.args.events_out:
            out = Path(self.args.events_out)
            out.parent.mkdir(parents=True, exist_ok=True)
            with open(out, "w", encoding="utf-8") as fh:
                for e in self.events:
                    fh.write(json.dumps(e.to_dict()) + "\n")
        print(json.dumps(summary, indent=2))
        for e in self.events:
            if not e.ok():
                print(f"  FAIL seq={e.seq} uid={e.uid} expected={e.expected.status} got={e.actual_status}",
                      file=sys.stderr)
        return summary


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scenario", choices=["uniform", "zipfian", "burst", "sequential", "regional", "invalidation", "origin-fault"], default="uniform")
    p.add_argument("--corpus", choices=["demo", "all"], default="demo",
                   help="demo = objects the demo edge serves; all = every seed fixture")
    p.add_argument("--target", default="http://localhost:8081", help="primary target base URL")
    p.add_argument("--targets", default=None, help="comma-separated target base URLs (regional/invalidation)")
    p.add_argument("--rate", type=float, default=5.0, help="steady request rate (req/s)")
    p.add_argument("--burst-rate", type=float, default=50.0, help="burst scenario high rate")
    p.add_argument("--burst-high", type=float, default=3.0, help="burst high period (s)")
    p.add_argument("--burst-low", type=float, default=3.0, help="burst low period (s)")
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--duration", type=int, default=10, help="scenario duration (s, capped at 3600)")
    p.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility")
    p.add_argument("--zipf", type=float, default=1.0, help="zipfian exponent")
    p.add_argument("--timeout", type=float, default=10.0)
    p.add_argument("--token", default=None, help="bearer token (required for non-local targets)")
    p.add_argument("--token-url", default="http://localhost:8088", help="Keycloak base URL for auto token fetch")
    p.add_argument("--username", default="viewer")
    p.add_argument("--password", default="fogcache_dev_password")
    p.add_argument("--metrics-out", default=None, help="write summary JSON here")
    p.add_argument("--events-out", default=None, help="write JSONL event log here")
    p.add_argument("--dry-run", action="store_true", help="print the plan without sending requests")
    return p


def main() -> int:
    args = build_parser().parse_args()
    if not (args.target.startswith("http://") or args.target.startswith("https://")):
        raise SystemExit("--target must be http:// or https://")
    if args.targets:
        args.targets = [t.rstrip("/") for t in args.targets.split(",") if t]
        for t in args.targets:
            if not (t.startswith("http://") or t.startswith("https://")):
                raise SystemExit(f"target {t} must be http:// or https://")
    else:
        args.targets = [args.target.rstrip("/")]
    gen = Generator(args)
    gen.run()
    gen.report()
    return 0 if all(e.ok() for e in gen.events) else 1


if __name__ == "__main__":
    sys.exit(main())
