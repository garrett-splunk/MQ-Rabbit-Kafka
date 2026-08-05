#!/usr/bin/env bash
# Verify demo telemetry is reaching Splunk O11y (traces + MQ metrics).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ROOT}/.env.splunk"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Missing .env.splunk — copy .env.splunk.example and set SPLUNK_ACCESS_TOKEN + SPLUNK_API_TOKEN."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

API_URL="${SPLUNK_API_URL:-https://api.${SPLUNK_REALM:-us1}.signalfx.com}"
API_URL="${API_URL%/}"
if [[ "$API_URL" != */v2 ]]; then
  API_URL="${API_URL}/v2"
fi

export API_URL

echo "== Splunk pipeline validation =="
echo "API: $API_URL"
echo

failures=0

set +e
python3 <<'PY'
import json, os, sys, time, urllib.parse, urllib.request

api = os.environ["SPLUNK_API_TOKEN"]
base = os.environ["API_URL"]
now_ms = int(time.time() * 1000)
failures = 0

def dim_count(query: str) -> int:
    req = urllib.request.Request(
        f"{base}/dimension?query={urllib.parse.quote(query)}&limit=1",
        headers={"X-SF-TOKEN": api},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read()).get("count", 0)

def dim_last_seen_minutes(query: str):
    req = urllib.request.Request(
        f"{base}/dimension?query={urllib.parse.quote(query)}&limit=1&orderBy=lastSeenMs",
        headers={"X-SF-TOKEN": api},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    results = data.get("results") or []
    if not results:
        return None, 0
    row = results[0]
    last = row.get("lastSeenMs")
    if not isinstance(last, (int, float)):
        return None, data.get("count", 0)
    return (now_ms - last) / 60000.0, data.get("count", 0)

def check_dim(label: str, query: str):
    global failures
    age, count = dim_last_seen_minutes(query)
    if count <= 0:
        print(f"FAIL {label} — no indexed dimensions for: {query}")
        failures += 1
        return
    if age is None:
        print(f"WARN {label} — indexed (count={count}) but no recent lastSeen (likely stale)")
        failures += 1
        return
    if age > 30:
        print(f"FAIL {label} — last seen {age:.0f} min ago (count={count}); expected within 30 min")
        failures += 1
        return
    print(f"OK  {label} (count={count}, last seen {age:.0f} min ago)")

check_dim("APM service order-producer", "sf_service:order-producer")
check_dim("Environment tag", "deployment.environment.name:messaging-demo-lab")
check_dim("IBM MQ queue depth metric", "metric:ibm.mq.queue.depth")
check_dim("IBM MQ heartbeat metric", "metric:ibm.mq.heartbeat")
check_dim("IBM MQ oldest message age", "metric:ibm.mq.oldest.msg.age")
check_dim("IBM MQ enqueue count", "metric:ibm.mq.message.enq.count")

if failures:
    print()
    print("NOTE: Stale/missing dimensions usually mean SPLUNK_ACCESS_TOKEN (ingest) and")
    print("      SPLUNK_API_TOKEN (query) are from different Splunk orgs, or ingest stopped.")
    print("      Create BOTH tokens in the same org: Settings → Access Tokens.")
    print("      Collector should log otlphttp/metrics requests with HTTP 200.")

sys.exit(1 if failures else 0)
PY
py_rc=$?
set -e
if [[ "$py_rc" -ne 0 ]]; then
  failures=1
fi

echo
echo "== Local collector health =="
if docker compose ps --status running otel-collector 2>/dev/null | grep -q otel-collector; then
  echo "OK  otel-collector container running"
else
  echo "FAIL otel-collector not running (check: docker compose logs otel-collector --tail 20)"
  failures=$((failures + 1))
fi

if curl -sf "http://localhost:13133/" >/dev/null; then
  echo "OK  otel-collector health endpoint"
else
  echo "FAIL otel-collector not reachable on :13133"
  failures=$((failures + 1))
fi

if docker compose ps --status running ibm-mq-java-metrics 2>/dev/null | grep -q ibm-mq-java-metrics; then
  echo "OK  ibm-mq-java-metrics container running"
else
  echo "FAIL ibm-mq-java-metrics not running"
  failures=$((failures + 1))
fi

recent_export_errors="$(docker compose logs otel-collector --since 10m 2>/dev/null | grep -iE 'Exporting failed|Dropping data' | wc -l | tr -d ' ')"
if [[ "${recent_export_errors:-0}" -gt 0 ]]; then
  echo "FAIL otel-collector export errors in last 10m: $recent_export_errors"
  echo "     Run: docker compose logs otel-collector --since 10m | grep -iE 'error|fail|drop'"
  failures=$((failures + 1))
else
  echo "OK  no collector export errors in last 10m"
fi

otlp_exports="$(docker compose logs otel-collector --since 10m 2>/dev/null | grep -c 'otlphttp/metrics' || true)"
if [[ "${otlp_exports:-0}" -gt 0 ]]; then
  echo "OK  otlphttp/metrics exporter active in last 10m"
else
  echo "WARN no otlphttp/metrics log lines in last 10m (collector may need restart)"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "Pipeline not fully healthy."
  echo
  echo "Try:"
  echo "  python3 scripts/verify-splunk-token-org.py   # ingest vs API token same org?"
  echo "  docker compose up -d --force-recreate otel-collector ibm-mq-java-metrics"
  echo "  bash scripts/load-messaging-demo.sh"
  echo "  sleep 90 && bash scripts/validate-splunk-pipeline.sh"
  echo
  echo "Mac-safe log check (no rg needed):"
  echo "  docker compose logs otel-collector --since 10m | grep -iE 'error|fail|drop'"
  echo
  echo "In Splunk Metric Explorer, search ibm.mq.queue.depth with NO filter first,"
  echo "then add deployment.environment.name:messaging-demo-lab"
  exit 1
fi

echo "Pipeline looks healthy — open the IBM MQ Ops dashboard and confirm panels populate."
exit 0
