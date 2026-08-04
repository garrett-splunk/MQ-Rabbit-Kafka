#!/usr/bin/env bash
# Start the full unified messaging demo stack and load sample traffic.
#
# Usage:
#   bash scripts/run-demo.sh              # build, start, verify, load traffic
#   bash scripts/run-demo.sh --no-build   # skip image rebuild
#   bash scripts/run-demo.sh --skip-traffic
#   bash scripts/run-demo.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NO_BUILD=false
SKIP_TRAFFIC=false
MQ_COUNT=15
MQ_DELAY_MS=300
KAFKA_COUNT=15
RABBIT_COUNT=10

usage() {
  cat <<'EOF'
Unified messaging demo — one command to start everything.

  bash scripts/run-demo.sh [options]

Options:
  --no-build       docker compose up -d without --build
  --skip-traffic   Start and verify only; do not load MQ/Kafka/Rabbit traffic
  --mq-count N     MQ orders to send (default: 15)
  --kafka-count N  Kafka messages to produce (default: 15)
  --rabbit-count N RabbitMQ messages to publish (default: 10)
  -h, --help       Show this help

Prerequisites: Docker Desktop (or Docker Engine + Compose v2), curl, python3.
Splunk export: copy .env.splunk.example → .env.splunk and set SPLUNK_ACCESS_TOKEN.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) NO_BUILD=true ;;
    --skip-traffic) SKIP_TRAFFIC=true ;;
    --mq-count) MQ_COUNT="${2:?}"; shift ;;
    --kafka-count) KAFKA_COUNT="${2:?}"; shift ;;
    --rabbit-count) RABBIT_COUNT="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' is required but not installed."
    exit 1
  fi
}

require_cmd docker
require_cmd curl
require_cmd python3
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose v2 required."; exit 1; }

echo "== Unified messaging demo =="
echo "Repo: $ROOT"
echo

if [ ! -f .env ]; then
  echo "Creating .env from .env.example"
  cp .env.example .env
fi

if [ ! -f .env.splunk ]; then
  echo "WARN: .env.splunk not found — copying template (metrics/traces will not reach Splunk until you add a token)."
  cp .env.splunk.example .env.splunk
elif grep -q 'your-ingest-token-here' .env.splunk 2>/dev/null; then
  echo "WARN: .env.splunk still has placeholder token — update SPLUNK_ACCESS_TOKEN for Splunk ingest."
fi

echo "== Starting Docker Compose stack =="
if [ "$NO_BUILD" = true ]; then
  docker compose up -d
else
  docker compose up --build -d
fi

echo
echo "== Waiting for services (MQ can take ~2 min on first start) =="
deadline=$((SECONDS + 180))
ready=false
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -sf "http://localhost:8080/health" 2>/dev/null | grep -q order-producer \
    && curl -sf "http://localhost:13133/" >/dev/null 2>&1 \
    && curl -sf "http://localhost:8092/" 2>/dev/null | grep -qi "Unified messaging"; then
    ready=true
    break
  fi
  printf "."
  sleep 5
done
echo

if [ "$ready" != true ]; then
  echo "WARN: Core endpoints not all ready yet; running verify-stack.sh anyway."
fi

# Sidecar caches OTLP connection; restart after collector is up
docker compose restart ibm-mq-java-metrics >/dev/null 2>&1 || true
sleep 5

echo
bash scripts/verify-stack.sh

if [ "$SKIP_TRAFFIC" = true ]; then
  echo
  echo "Skipping traffic (--skip-traffic)."
else
  echo
  echo "== Loading MQ traffic (${MQ_COUNT} orders) =="
  bash scripts/load-traffic.sh "$MQ_COUNT" "$MQ_DELAY_MS"

  echo
  echo "== Loading Kafka traffic (${KAFKA_COUNT} messages) =="
  bash scripts/load-kafka-traffic.sh demo.orders "$KAFKA_COUNT"

  echo
  echo "== Loading RabbitMQ traffic (${RABBIT_COUNT} messages) =="
  bash scripts/load-rabbit-traffic.sh "$RABBIT_COUNT"
fi

echo
echo "== Demo ready =="
echo "  Demo guide:     http://localhost:8092"
echo "  MQ producer:    http://localhost:8080/health"
echo "  Splunk filter:  deployment.environment.name:messaging-demo-lab"
echo "  GitHub Pages:   https://garrett-splunk.github.io/MQ-Rabbit-Kafka/"
echo
echo "Useful follow-ups:"
echo "  bash scripts/demo-incident-mq-backlog.sh   # backlog / alert story"
echo "  docker compose logs -f otel-collector       # collector export"
echo "  docker compose down                         # stop stack"
