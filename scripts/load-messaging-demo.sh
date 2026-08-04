#!/usr/bin/env bash
# Load sample traffic across IBM MQ, Kafka, and RabbitMQ (no pika / npm required).
#
# Usage:
#   load-messaging-demo                    # defaults from any directory
#   load-messaging-demo --mq 20 --kafka 30 --rabbit 15
#   load-messaging-demo --mq-only
#   load-messaging-demo --skip-kafka
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$LINK_DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

MQ_COUNT=10
MQ_DELAY_MS=200
KAFKA_TOPIC=demo.orders
KAFKA_COUNT=15
RABBIT_COUNT=10
DO_MQ=true
DO_KAFKA=true
DO_RABBIT=true
REQUIRE_DOCKER=true

usage() {
  cat <<'EOF'
Usage: load-messaging-demo [OPTIONS]

Generate demo traffic for the MQ-Rabbit-Kafka lab (Splunk metrics + APM).

Options:
  --mq N           MQ orders to send (default: 10)
  --mq-delay MS    Delay between MQ orders in ms (default: 200)
  --kafka N        Kafka messages to produce (default: 15)
  --kafka-topic T  Kafka topic (default: demo.orders)
  --rabbit N       RabbitMQ messages to publish (default: 10)
  --mq-only        Load MQ traffic only
  --kafka-only     Load Kafka traffic only
  --rabbit-only    Load RabbitMQ traffic only
  --skip-mq        Skip MQ
  --skip-kafka     Skip Kafka
  --skip-rabbit    Skip RabbitMQ
  --no-docker-check  Skip Docker daemon check
  -h, --help       Show this help

Examples:
  load-messaging-demo
  load-messaging-demo --mq 25 --kafka 50 --rabbit 20
  load-messaging-demo --rabbit-only --rabbit 5

Requires: Docker stack running (docker compose up -d in this repo).
Splunk filter: deployment.environment.name:messaging-demo-lab
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mq|--mq-count) MQ_COUNT="${2:?}"; shift ;;
    --mq-delay) MQ_DELAY_MS="${2:?}"; shift ;;
    --kafka|--kafka-count) KAFKA_COUNT="${2:?}"; shift ;;
    --kafka-topic) KAFKA_TOPIC="${2:?}"; shift ;;
    --rabbit|--rabbit-count) RABBIT_COUNT="${2:?}"; shift ;;
    --mq-only) DO_MQ=true; DO_KAFKA=false; DO_RABBIT=false ;;
    --kafka-only) DO_MQ=false; DO_KAFKA=true; DO_RABBIT=false ;;
    --rabbit-only) DO_MQ=false; DO_KAFKA=false; DO_RABBIT=true ;;
    --skip-mq) DO_MQ=false ;;
    --skip-kafka) DO_KAFKA=false ;;
    --skip-rabbit) DO_RABBIT=false ;;
    --no-docker-check) REQUIRE_DOCKER=false ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$REQUIRE_DOCKER" = true ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon not running." >&2
    echo "  Start Docker Desktop: open -a Docker" >&2
    echo "  Then bring up the stack: cd $ROOT && docker compose up -d" >&2
    exit 1
  fi
fi

echo "== Messaging demo traffic =="
echo "Repo: $ROOT"
echo

if [ "$DO_MQ" = true ]; then
  echo "== MQ (${MQ_COUNT} orders, ${MQ_DELAY_MS}ms apart) =="
  bash "$SCRIPT_DIR/load-traffic.sh" "$MQ_COUNT" "$MQ_DELAY_MS"
  echo
fi

if [ "$DO_KAFKA" = true ]; then
  echo "== Kafka (${KAFKA_COUNT} messages → ${KAFKA_TOPIC}) =="
  bash "$SCRIPT_DIR/load-kafka-traffic.sh" "$KAFKA_TOPIC" "$KAFKA_COUNT"
  echo
fi

if [ "$DO_RABBIT" = true ]; then
  echo "== RabbitMQ (${RABBIT_COUNT} messages) =="
  bash "$SCRIPT_DIR/load-rabbit-traffic.sh" "$RABBIT_COUNT"
  echo
fi

echo "== Done =="
echo "  Splunk filter: deployment.environment.name:messaging-demo-lab"
echo "  MQ metric:     ibm.mq.queue.depth (queue=ORDER.REQ)"
echo "  Rabbit metric: rabbitmq.message.current (message.state=ready)"
echo "  Kafka metrics: kafka.broker.* / kafka.consumer.* (~30s scrape)"
