#!/usr/bin/env python3
"""
Provision Splunk Observability Cloud MQ ops dashboard + detectors for the messaging demo.

Mirrors Dynatrace MQ extension views: queue depth %, oldest message age, enqueue/dequeue
rates, queue inventory table, QM health (connections, channels, uptime, bytes).

Requires an organization API token (not the ingest token). See .env.splunk.example.

Usage:
  python3 scripts/provision-splunk-mq-ops.py
  python3 scripts/provision-splunk-mq-ops.py --dry-run
  python3 scripts/provision-splunk-mq-ops.py --detectors-only
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

TAG = "mq-rabbit-kafka-demo"
PREFIX = "[MQ Demo]"
ENV_DEFAULT = "messaging-demo-lab"


def load_env_file(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.is_file():
        return env
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def api_base_url(raw: str) -> str:
    raw = raw.rstrip("/")
    if raw.endswith("/v2"):
        return raw
    return f"{raw}/v2"


def sf_filter(env: str) -> str:
    return f"filter('deployment.environment.name', '{env}')"


def env_line(env: str) -> str:
    return f"env_filter = {sf_filter(env)}"


def queue_group_dims() -> str:
    # OTel sidecar may emit queue or messaging.destination.name; group by both.
    return "['queue', 'messaging.destination.name', 'queue_manager', 'ibm.mq.queue.manager']"


class SplunkO11yClient:
    def __init__(self, token: str, base_v2: str, dry_run: bool = False) -> None:
        self.token = token
        self.base = base_v2.rstrip("/")
        self.dry_run = dry_run

    def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        params: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        url = f"{self.base}{path}"
        if params:
            qs = "&".join(f"{k}={urllib.parse.quote(v)}" for k, v in params.items())
            url = f"{url}?{qs}"
        data = None
        headers = {
            "Content-Type": "application/json",
            "X-SF-TOKEN": self.token,
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
        if self.dry_run and method != "GET":
            print(f"DRY-RUN {method} {url}")
            if body:
                print(json.dumps(body, indent=2)[:2000])
            return {"id": f"dry-run-{path.strip('/').replace('/', '-')}"}

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {url} failed ({exc.code}): {detail}") from exc

    def find_by_name(self, resource: str, name: str) -> dict[str, Any] | None:
        if self.dry_run:
            return None
        result = self._request("GET", f"/{resource}", params={"name": name, "limit": "50"})
        for item in result.get("results", []):
            if item.get("name") == name:
                return item
        return None

    def upsert_chart(self, name: str, program_text: str, chart_type: str, description: str) -> str:
        existing = self.find_by_name("chart", name)
        body = {
            "name": name,
            "description": description,
            "tags": [TAG, "ibm-mq", "messaging-demo"],
            "programText": program_text,
            "options": {
                "type": chart_type,
                "time": {"type": "relative", "range": 900000},
                "defaultPlotType": "LineChart" if chart_type == "TimeSeriesChart" else None,
            },
        }
        # Remove null keys for cleaner payload
        opts = body["options"]
        if opts.get("defaultPlotType") is None:
            del opts["defaultPlotType"]
        if chart_type == "TableChart":
            opts["groupBy"] = ["queue", "messaging.destination.name", "queue_manager", "ibm.mq.queue.manager"]
            opts["sortBy"] = "Depth"
            opts["sortDirection"] = "Descending"
        if existing:
            chart_id = existing["id"]
            print(f"Updating chart: {name} ({chart_id})")
            if not self.dry_run:
                self._request("PUT", f"/chart/{chart_id}", body=body)
            return chart_id
        print(f"Creating chart: {name}")
        created = self._request("POST", "/chart", body=body)
        return created["id"]

    def ensure_dashboard_group(self, name: str) -> str:
        existing = self.find_by_name("dashboardgroup", name)
        if existing:
            print(f"Using dashboard group: {name} ({existing['id']})")
            return existing["id"]
        print(f"Creating dashboard group: {name}")
        created = self._request("POST", "/dashboardgroup", body={"name": name, "tags": [TAG]})
        return created["id"]

    def upsert_dashboard(
        self,
        name: str,
        group_id: str,
        env: str,
        charts: list[dict[str, Any]],
    ) -> str:
        existing = self.find_by_name("dashboard", name)
        body: dict[str, Any] = {
            "name": name,
            "description": "IBM MQ operations view — mirrors Dynatrace MQ extension queue/QM panels for the messaging demo lab.",
            "tags": [TAG, "ibm-mq"],
            "dashboardGroupId": group_id,
            "charts": charts,
            "filters": [
                {
                    "property": "deployment.environment.name",
                    "values": [env],
                    "preferredSuggestions": [env],
                    "required": True,
                    "restricted": False,
                }
            ],
            "timeRange": "-15m",
        }
        if existing:
            dash_id = existing["id"]
            print(f"Updating dashboard: {name} ({dash_id})")
            if not self.dry_run:
                self._request("PUT", f"/dashboard/{dash_id}", body=body)
            return dash_id
        print(f"Creating dashboard: {name}")
        created = self._request("POST", "/dashboard", body=body)
        return created["id"]

    def upsert_detector(
        self,
        name: str,
        program_text: str,
        detect_label: str,
        severity: str,
        description: str,
    ) -> str:
        existing = self.find_by_name("detector", name)
        body = {
            "name": name,
            "description": description,
            "tags": [TAG, "ibm-mq"],
            "programText": program_text,
            "rules": [
                {
                    "detectLabel": detect_label,
                    "severity": severity,
                    "description": description,
                }
            ],
            "maxDelay": 60,
        }
        if existing:
            det_id = existing["id"]
            print(f"Updating detector: {name} ({det_id})")
            if not self.dry_run:
                self._request("PUT", f"/detector/{det_id}", body=body)
            return det_id
        print(f"Creating detector: {name}")
        created = self._request("POST", "/detector", body=body)
        return created["id"]


def build_charts(env: str) -> list[tuple[str, str, str, str]]:
    el = env_line(env)
    gq = queue_group_dims()

    depth_pct = f"""
{el}
depth = data('ibm.mq.queue.depth', filter=env_filter).sum(by={gq}).publish(label='Depth')
max_depth = data('ibm.mq.max.queue.depth', filter=env_filter).sum(by={gq}).publish(label='Max Depth')
((depth / max_depth) * 100).publish(label='Depth %')
""".strip()

    oldest_age = f"""
{el}
data('ibm.mq.oldest.msg.age', filter=env_filter).sum(by={gq}).publish(label='Oldest message (s)')
""".strip()

    enq_deq = f"""
{el}
data('ibm.mq.message.enq.count', filter=env_filter).rate().scale(60).sum(by={gq}).publish(label='Enqueue/min')
data('ibm.mq.message.deq.count', filter=env_filter).rate().scale(60).sum(by={gq}).publish(label='Dequeue/min')
""".strip()

    queue_table = f"""
{el}
data('ibm.mq.queue.depth', filter=env_filter).sum(by={gq}).publish(label='Depth')
data('ibm.mq.max.queue.depth', filter=env_filter).sum(by={gq}).publish(label='Max Depth')
data('ibm.mq.oldest.msg.age', filter=env_filter).sum(by={gq}).publish(label='Oldest Msg (s)')
data('ibm.mq.message.enq.count', filter=env_filter).rate().scale(60).sum(by={gq}).publish(label='Enqueue/min')
data('ibm.mq.message.deq.count', filter=env_filter).rate().scale(60).sum(by={gq}).publish(label='Dequeue/min')
data('ibm.mq.open.input.count', filter=env_filter).sum(by={gq}).publish(label='Open GET')
data('ibm.mq.open.output.count', filter=env_filter).sum(by={gq}).publish(label='Open PUT')
((data('ibm.mq.queue.depth', filter=env_filter).sum(by={gq}) / data('ibm.mq.max.queue.depth', filter=env_filter).sum(by={gq})) * 100).publish(label='Depth %')
""".strip()

    qm_table = f"""
{el}
gm = ['queue_manager', 'ibm.mq.queue.manager']
data('ibm.mq.manager.status', filter=env_filter).sum(by=gm).publish(label='QM Available')
data('ibm.mq.connection.count', filter=env_filter).sum(by=gm).publish(label='Connections')
data('ibm.mq.manager.active.channels', filter=env_filter).sum(by=gm).publish(label='Active Channels')
data('ibm.mq.queue_manager.uptime', filter=env_filter).sum(by=gm).publish(label='Uptime (s)')
data('ibm.mq.byte.sent', filter=env_filter).rate().sum(by=gm).publish(label='Bytes Sent/s')
data('ibm.mq.byte.received', filter=env_filter).rate().sum(by=gm).publish(label='Bytes Received/s')
""".strip()

    channel_table = f"""
{el}
gc = ['ibm.mq.channel.name', 'ibm.mq.channel.type', 'queue_manager', 'ibm.mq.queue.manager']
data('ibm.mq.status', filter=env_filter).sum(by=gc).publish(label='Channel Status')
data('ibm.mq.byte.sent', filter=env_filter).rate().sum(by=gc).publish(label='Bytes Sent/s')
data('ibm.mq.byte.received', filter=env_filter).rate().sum(by=gc).publish(label='Bytes Received/s')
data('ibm.mq.message.sent.count', filter=env_filter).rate().scale(60).sum(by=gc).publish(label='Msgs Sent/min')
data('ibm.mq.message.received.count', filter=env_filter).rate().scale(60).sum(by=gc).publish(label='Msgs Recv/min')
""".strip()

    unified = f"""
{el}
data('ibm.mq.queue.depth', filter=env_filter).sum(by=['queue', 'messaging.destination.name']).publish(label='MQ depth')
data('rabbitmq.message.current', filter=env_filter and filter('message.state', 'ready')).sum(by=['rabbitmq.queue.name']).publish(label='Rabbit ready')
""".strip()

    return [
        (f"{PREFIX} Queue depth %", depth_pct, "TimeSeriesChart", "Queue depth as % of max depth (Dynatrace CURDEPTH / MAXDEPTH)."),
        (f"{PREFIX} Oldest message age", oldest_age, "TimeSeriesChart", "Age in seconds of the oldest message on each queue (Dynatrace ibmmq.queue.oldest_message)."),
        (f"{PREFIX} Enqueue / Dequeue per min", enq_deq, "TimeSeriesChart", "Message enqueue and dequeue rates per queue."),
        (f"{PREFIX} Queue inventory", queue_table, "TableChart", "Per-queue depth, depth %, oldest message, rates, and open GET/PUT handles."),
        (f"{PREFIX} Queue manager overview", qm_table, "TableChart", "QM availability, connections, active channels, uptime, byte rates."),
        (f"{PREFIX} Channel status", channel_table, "TableChart", "Per-channel status, byte rates, and message rates."),
        (f"{PREFIX} Unified messaging backlog", unified, "TimeSeriesChart", "MQ depth + Rabbit ready messages in one chart (Kafka lag: add after confirming metric names)."),
    ]


def build_detectors(env: str, depth_threshold: int, age_threshold: int) -> list[tuple[str, str, str, str, str]]:
    el = env_line(env)
    gq = "['queue', 'messaging.destination.name', 'queue_manager', 'ibm.mq.queue.manager']"

    depth_det = f"""
{el}
depth = data('ibm.mq.queue.depth', filter=env_filter).max(by={gq})
detect(when(depth > threshold({depth_threshold}), lasting='5m')).publish('MQ queue depth high')
""".strip()

    age_det = f"""
{el}
age = data('ibm.mq.oldest.msg.age', filter=env_filter).max(by={gq})
detect(when(age > threshold({age_threshold}), lasting='5m')).publish('MQ oldest message age SLA')
""".strip()

    nodata_det = f"""
{el}
depth = data('ibm.mq.queue.depth', filter=env_filter).max(by={gq})
detect(when(depth is None, lasting='15m')).publish('MQ metrics absent')
""".strip()

    return [
        (
            f"{PREFIX} Queue depth sustained high",
            depth_det,
            "MQ queue depth high",
            "Major",
            f"Queue depth above {depth_threshold} for 5 minutes — backlog building.",
        ),
        (
            f"{PREFIX} Oldest message age SLA",
            age_det,
            "MQ oldest message age SLA",
            "Major",
            f"Oldest message age above {age_threshold}s for 5 minutes.",
        ),
        (
            f"{PREFIX} MQ metrics absent",
            nodata_det,
            "MQ metrics absent",
            "Critical",
            "No ibm.mq.queue.depth data for 15 minutes — sidecar or scrape failure.",
        ),
    ]


def layout_charts(chart_ids: list[str]) -> list[dict[str, Any]]:
    """12-column grid layout matching a typical Dynatrace MQ overview."""
    specs = [
        (0, 0, 4, 2),
        (4, 0, 4, 2),
        (8, 0, 4, 2),
        (0, 2, 12, 3),
        (0, 5, 6, 3),
        (6, 5, 6, 3),
        (0, 8, 12, 2),
    ]
    charts: list[dict[str, Any]] = []
    for chart_id, (x, y, w, h) in zip(chart_ids, specs, strict=False):
        charts.append({"chartId": chart_id, "x": x, "y": y, "width": w, "height": h})
    return charts


def main() -> int:
    parser = argparse.ArgumentParser(description="Provision Splunk O11y MQ ops dashboard and detectors")
    parser.add_argument("--dry-run", action="store_true", help="Print API actions without calling Splunk")
    parser.add_argument("--detectors-only", action="store_true", help="Create/update detectors only")
    parser.add_argument("--dashboard-only", action="store_true", help="Create/update dashboard only")
    parser.add_argument("--env", default=os.environ.get("DEPLOYMENT_ENVIRONMENT", ENV_DEFAULT))
    parser.add_argument("--depth-threshold", type=int, default=10)
    parser.add_argument("--age-threshold", type=int, default=600)
    parser.add_argument("--dashboard-name", default="IBM MQ Ops — Messaging Demo")
    parser.add_argument("--group-name", default="Messaging Demo Lab")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    env_file = load_env_file(root / ".env.splunk")

    token = os.environ.get("SPLUNK_API_TOKEN") or env_file.get("SPLUNK_API_TOKEN", "")
    api_url = os.environ.get("SPLUNK_API_URL") or env_file.get("SPLUNK_API_URL", "")
    realm = os.environ.get("SPLUNK_REALM") or env_file.get("SPLUNK_REALM", "us1")

    if (not token or token.startswith("your-")) and not args.dry_run:
        print(
            "ERROR: Set SPLUNK_API_TOKEN in .env.splunk (organization API token with admin/power role).\n"
            "       Ingest tokens (SPLUNK_ACCESS_TOKEN) cannot create dashboards.\n"
            "       Splunk O11y → Settings → Access Tokens → New Token → type: API",
            file=sys.stderr,
        )
        return 1

    if not api_url:
        api_url = f"https://api.{realm}.signalfx.com"

    if not token:
        token = "dry-run-token"

    client = SplunkO11yClient(token=token, base_v2=api_base_url(api_url), dry_run=args.dry_run)

    if not args.detectors_only:
        chart_defs = build_charts(args.env)
        chart_ids: list[str] = []
        for name, program, ctype, desc in chart_defs:
            chart_ids.append(client.upsert_chart(name, program, ctype, desc))

        group_id = client.ensure_dashboard_group(args.group_name)
        dashboard_id = client.upsert_dashboard(
            args.dashboard_name,
            group_id,
            args.env,
            layout_charts(chart_ids),
        )
        ui_base = os.environ.get("SPLUNK_APP_URL") or env_file.get("SPLUNK_APP_URL", "")
        if not ui_base:
            ui_base = f"https://app.{realm}.signalfx.com"
        print(f"\nDashboard ready: {ui_base}/#/dashboard/{dashboard_id}")
        print(f"Filter: deployment.environment.name:{args.env}")

    if not args.dashboard_only:
        for name, program, label, severity, desc in build_detectors(
            args.env, args.depth_threshold, args.age_threshold
        ):
            client.upsert_detector(name, program, label, severity, desc)
        print("\nDetectors created/updated. Attach notification integrations in Splunk UI if needed.")

    print("\nNext steps:")
    print("  1. docker compose restart ibm-mq-java-metrics   # pick up new sidecar metrics")
    print("  2. load-messaging-demo                          # generate traffic")
    print("  3. Alerts → Detectors → link Slack/PagerDuty on [MQ Demo] detectors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
