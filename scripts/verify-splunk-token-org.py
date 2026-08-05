#!/usr/bin/env python3
"""Verify SPLUNK_ACCESS_TOKEN (ingest) and SPLUNK_API_TOKEN (query) target the same org."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env.splunk"


def load_env() -> None:
    if not ENV_FILE.is_file():
        print(f"ERROR: Missing {ENV_FILE}")
        sys.exit(1)
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def api_base() -> str:
    url = os.environ.get("SPLUNK_API_URL") or f"https://api.{os.environ.get('SPLUNK_REALM', 'us1')}.signalfx.com"
    url = url.rstrip("/")
    return url if url.endswith("/v2") else f"{url}/v2"


def ingest_base() -> str:
    url = os.environ.get("SPLUNK_INGEST_URL") or f"https://ingest.{os.environ.get('SPLUNK_REALM', 'us1')}.signalfx.com"
    return url.rstrip("/")


def api_get(path: str) -> dict:
    token = os.environ.get("SPLUNK_API_TOKEN", "")
    if not token or token.startswith("your-"):
        raise RuntimeError("SPLUNK_API_TOKEN is missing or still a placeholder in .env.splunk")
    req = urllib.request.Request(
        f"{api_base()}{path}",
        headers={"X-SF-TOKEN": token},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def post_datapoint(metric: str, value: float = 1.0) -> int:
    token = os.environ.get("SPLUNK_ACCESS_TOKEN", "")
    if not token or token.startswith("your-"):
        raise RuntimeError("SPLUNK_ACCESS_TOKEN is missing or still a placeholder in .env.splunk")
    body = json.dumps(
        {
            "metric": metric,
            "dimensions": {
                "deployment.environment.name": "messaging-demo-lab",
                "demo.pipeline.test": "token-org-check",
            },
            "value": value,
            "timestamp": int(time.time() * 1000),
        }
    ).encode()
    req = urllib.request.Request(
        f"{ingest_base()}/v2/datapoint",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-SF-Token": token,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        print(f"Ingest HTTP {exc.code}: {exc.read().decode()[:300]}")
        raise


def dim_count(query: str) -> int:
    token = os.environ.get("SPLUNK_API_TOKEN", "")
    req = urllib.request.Request(
        f"{api_base()}/dimension?query={urllib.parse.quote(query)}&limit=1",
        headers={"X-SF-TOKEN": token},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read()).get("count", 0)


def main() -> int:
    load_env()
    test_metric = "demo.pipeline.token.org.check"

    print("== Splunk token org verification ==")
    print(f"API:    {api_base()}")
    print(f"Ingest: {ingest_base()}")
    print()

    try:
        org = api_get("/organization")
        print(f"OK  API token org: {org.get('organizationName') or org.get('id', '(unknown)')}")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL API token: {exc}")
        return 1

    try:
        status = post_datapoint(test_metric)
        print(f"OK  Ingest token accepted test datapoint (HTTP {status})")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL Ingest token: {exc}")
        return 1

    print("Waiting up to 90s for test metric to index...")
    for attempt in range(18):
        time.sleep(5)
        count = dim_count(f"metric:{test_metric}")
        if count > 0:
            print(f"OK  Test metric visible via API token (count={count}) after {(attempt + 1) * 5}s")
            print()
            print("Tokens are aligned — if MQ metrics still missing, restart collector and wait ~2 min:")
            print("  docker compose up -d --force-recreate otel-collector")
            return 0
        print(f"  ... not indexed yet ({(attempt + 1) * 5}s)")

    print()
    print("FAIL Ingest accepted data but API token cannot see the test metric.")
    print("      SPLUNK_ACCESS_TOKEN and SPLUNK_API_TOKEN are almost certainly from")
    print("      different Splunk orgs (or wrong realm URLs in .env.splunk).")
    print()
    print("Fix:")
    print("  1. Splunk O11y → Settings → Access Tokens")
    print("  2. Create NEW Ingest + API tokens in the SAME org")
    print("  3. Update .env.splunk (SPLUNK_REALM, SPLUNK_*_URL must match that org)")
    print("  4. docker compose up -d --force-recreate otel-collector")
    return 1


if __name__ == "__main__":
    sys.exit(main())
