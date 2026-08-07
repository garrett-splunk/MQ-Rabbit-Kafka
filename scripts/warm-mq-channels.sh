#!/usr/bin/env bash
# Activate DEV.APP.SVRCONN for Splunk channel table (ibm.mq.status + byte totals).
#
# MQOTEL.SVRCONN is always active via ibm-mq-java-metrics. DEV.APP.SVRCONN needs a
# long-lived client connection — order-consumer (GET loop) + order-producer traffic.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ORDERS="${1:-15}"
QM="${MQ_QUEUE_MANAGER:-QM1}"
CHANNEL="${MQ_CHANNEL:-DEV.APP.SVRCONN}"

echo "== Warm DEV.APP.SVRCONN channel row =="
echo "  Channel: ${CHANNEL} on ${QM}"
echo "  Orders:  ${ORDERS} (producer PUTs + consumer GET keeps connection RUNNING)"
echo

if ! docker compose ps --status running mq order-producer 2>/dev/null | grep -q order-producer; then
  echo "ERROR: mq + order-producer must be running — run: docker compose up -d" >&2
  exit 1
fi

echo "Starting order-consumer (persistent DEV.APP.SVRCONN connection)..."
docker compose up -d order-consumer

echo -n "Waiting for order-consumer health"
for _ in $(seq 1 30); do
  if curl -sf http://localhost:8081/health >/dev/null 2>&1; then
    echo " OK"
    break
  fi
  echo -n "."
  sleep 2
done
echo

echo "Sending ${ORDERS} orders through order-producer..."
for i in $(seq 1 "$ORDERS"); do
  curl -sf -X POST http://localhost:8080/orders \
    -H "Content-Type: application/json" \
    -d "{\"productId\":\"SKU-CHAN-${i}\",\"quantity\":1}" >/dev/null || true
  sleep 1
done

echo
echo "Channel status on queue manager:"
docker compose exec -T mq runmqsc "$QM" <<MQSC
DISPLAY CHSTATUS(${CHANNEL}) STATUS MCASTAT BYTSSENT BYTSRCVD MSGS
MQSC

echo
echo "Done. Wait ~30–60s, refresh channel table (Last 15 min)."
echo "  DEV.APP.SVRCONN: Channel Status ≈ 3 (running), Bytes Sent/Received > 0."
echo "  Keep order-consumer running — stopping it clears DEV.APP between PUTs."
