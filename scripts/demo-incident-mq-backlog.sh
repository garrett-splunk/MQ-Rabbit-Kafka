#!/usr/bin/env bash
# Demo: stop MQ consumer and load orders — queue depth rises in Splunk (ibm.mq.queue.depth)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Stopping order-consumer..."
docker compose stop order-consumer

echo "Sending 20 orders..."
bash scripts/load-traffic.sh 20 150

echo ""
echo "== Demo state =="
echo "  Consumer: STOPPED (backlog building on ORDER.REQ)"
echo "  Splunk:   Metric Explorer → ibm.mq.queue.depth, filter queue=ORDER.REQ"
echo "  APM:      order-producer traces show mq.put.order; no consumer GET spans"
echo ""
echo "Restore: docker compose start order-consumer"
echo "         bash scripts/load-traffic.sh 5 200"
