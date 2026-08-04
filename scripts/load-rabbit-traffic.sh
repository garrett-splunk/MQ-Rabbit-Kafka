#!/usr/bin/env bash
# Publish sample messages to RabbitMQ demo queue via management API (no pika required)
set -euo pipefail

COUNT="${1:-10}"
QUEUE="${RABBITMQ_QUEUE:-demo.orders}"
HOST="${RABBITMQ_HOST:-localhost}"
PORT="${RABBITMQ_MGMT_PORT:-15672}"
USER="${RABBITMQ_USER:-demo}"
PASS="${RABBITMQ_PASSWORD:-passw0rd}"
VHOST="%2F"

BASE="http://${HOST}:${PORT}/api"
AUTH="${USER}:${PASS}"

echo "Declaring queue ${QUEUE}..."
curl -sf -u "${AUTH}" -X PUT "${BASE}/queues/${VHOST}/${QUEUE}" \
  -H "Content-Type: application/json" \
  -d '{"durable":true,"auto_delete":false}' >/dev/null

for i in $(seq 0 $((COUNT - 1))); do
  curl -sf -u "${AUTH}" -X POST "${BASE}/exchanges/${VHOST}/amq.default/publish" \
    -H "Content-Type: application/json" \
    -d "{\"properties\":{},\"routing_key\":\"${QUEUE}\",\"payload\":\"demo-order-${i}\",\"payload_encoding\":\"string\"}" >/dev/null
  echo "published demo-order-${i}"
done

echo "Produced ${COUNT} messages to queue ${QUEUE}"
echo "RabbitMQ metrics update within ~15s (rabbitmq receiver scrape interval)"
