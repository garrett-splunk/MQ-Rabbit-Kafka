#!/usr/bin/env bash
# Enable MONQ on lab order queues so ibm.mq.oldest.msg.age exports to Splunk.
# Safe to re-run — idempotent ALTER QLOCAL statements.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QM="${MQ_QUEUE_MANAGER:-QM1}"

if ! docker compose ps --status running mq 2>/dev/null | grep -q mq; then
  echo "ERROR: mq container not running — start with: docker compose up -d mq" >&2
  exit 1
fi

echo "Enabling MONQ(LOW) on ORDER.* queues (queue manager ${QM})..."
docker compose exec -T mq runmqsc "$QM" <<'MQSC'
ALTER QLOCAL(ORDER.REQ) MONQ(LOW)
ALTER QLOCAL(ORDER.RESP) MONQ(LOW)
DISPLAY QSTATUS(ORDER.REQ)
MQSC

echo
echo "Verify MONQ(ON) and MSGAGE when messages are on the queue."
echo "Then: load-messaging-demo --mq 20 && docker compose restart ibm-mq-java-metrics"
