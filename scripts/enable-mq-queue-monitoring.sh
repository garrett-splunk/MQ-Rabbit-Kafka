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

echo "Enabling MONQ(LOW) on lab queues (queue manager ${QM})..."
docker compose exec -T mq runmqsc "$QM" <<'MQSC'
ALTER QLOCAL(ORDER.REQ) MONQ(LOW)
ALTER QLOCAL(ORDER.RESP) MONQ(LOW)
ALTER QLOCAL(DEV.QUEUE.1) MONQ(LOW)
ALTER QLOCAL(DEV.QUEUE.2) MONQ(LOW)
ALTER QLOCAL(DEV.QUEUE.3) MONQ(LOW)
DISPLAY QSTATUS(ORDER.REQ)
DISPLAY QSTATUS(DEV.QUEUE.1)
MQSC

echo
echo "Verify MONQ(LOW) and MSGAGE when messages are on the queue."
echo "Then: bash scripts/load-dev-queues.sh && bash scripts/warm-mq-dashboard.sh"
