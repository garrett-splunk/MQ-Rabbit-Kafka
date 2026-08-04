#!/usr/bin/env bash
# Publish sample messages to RabbitMQ demo queue (requires pika: pip install pika)
set -euo pipefail
COUNT="${1:-10}"
QUEUE="${RABBITMQ_QUEUE:-demo.orders}"
HOST="${RABBITMQ_HOST:-localhost}"
PORT="${RABBITMQ_PORT:-5672}"
USER="${RABBITMQ_USER:-demo}"
PASS="${RABBITMQ_PASSWORD:-passw0rd}"

python3 - <<PY
import os, pika
count = int("${COUNT}")
queue = "${QUEUE}"
creds = pika.PlainCredentials("${USER}", "${PASS}")
conn = pika.BlockingConnection(pika.ConnectionParameters(host="${HOST}", port=int("${PORT}"), credentials=creds))
ch = conn.channel()
ch.queue_declare(queue=queue, durable=True)
for i in range(count):
    ch.basic_publish(exchange="", routing_key=queue, body=f"demo-order-{i}".encode())
    print(f"published demo-order-{i}")
conn.close()
PY

echo "RabbitMQ metrics update within ~15s (rabbitmq receiver scrape interval)"
