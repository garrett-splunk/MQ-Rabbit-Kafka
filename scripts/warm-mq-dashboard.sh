#!/usr/bin/env bash
# Populate IBM MQ Ops dashboard *tables* before a workshop or customer demo.
#
# Tables show 5-minute averages — run this ~3 min before you open the dashboard.
# Fixes the "all zeros and dashes" look when the stack is idle (see demo-site).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MQ_ORDERS="${1:-40}"
DURATION_SEC="${WARM_DURATION_SEC:-120}"

echo "== Warm MQ dashboard tables =="
echo "  Orders: ${MQ_ORDERS} burst + ${DURATION_SEC}s sustained load"
echo "  Consumer: running (enqueue + dequeue both non-zero in tables)"
echo

if ! docker compose ps --status running order-producer 2>/dev/null | grep -q order-producer; then
  echo "ERROR: stack not up — run: docker compose up -d" >&2
  exit 1
fi

docker compose start order-consumer 2>/dev/null || true
bash scripts/enable-mq-queue-monitoring.sh 2>/dev/null || true

echo "Activating DEV.APP.SVRCONN channel row (status + bytes)..."
bash scripts/warm-mq-channels.sh 12 2>/dev/null || true

echo "Seeding DEV.QUEUE.* rows (depth + oldest age for dashboard table)..."
bash scripts/load-dev-queues.sh 3 2>/dev/null || true

echo "Initial burst (MQ + Kafka + Rabbit)..."
bash scripts/load-messaging-demo.sh --mq "$MQ_ORDERS" --kafka 25 --rabbit 15

echo "Sustained order flow (${DURATION_SEC}s) for table rate columns..."
end=$(( $(date +%s) + DURATION_SEC ))
sent=0
while [ "$(date +%s)" -lt "$end" ]; do
  curl -sf -X POST http://localhost:8080/orders \
    -H "Content-Type: application/json" \
    -d "{\"productId\":\"SKU-WARM-${sent}\",\"quantity\":1}" >/dev/null || true
  sent=$((sent + 1))
  sleep 5
done

echo
echo "== Ready =="
echo "  Wait ~60s, then open IBM MQ Ops dashboard (last 15 min)."
echo "  ORDER.REQ: enqueue/min and dequeue/min need traffic in the last 5 min."
echo "  DEV.QUEUE.*: depth and oldest msg stay > 0 (no consumer); enqueue/min from seed puts."
echo "  Channel table: DEV.APP.SVRCONN needs order-consumer running; MQOTEL from sidecar."
echo "  QM + Channel tables: Bytes Sent/Received show session totals (~15k+ when sidecar is active)."
echo
echo "  Optional backlog story: bash scripts/demo-incident-mq-backlog.sh"
echo "  Re-warm after incident: bash scripts/warm-mq-dashboard.sh"
