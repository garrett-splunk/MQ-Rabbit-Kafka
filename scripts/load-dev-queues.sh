#!/usr/bin/env bash
# Put sample messages on DEV.QUEUE.* (and optionally ORDER.RESP) so Splunk queue
# table rows show depth, oldest age, and enqueue/min — not all zeros.
#
# ORDER.REQ is fed by order-producer; DEV queues are not. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QM="${MQ_QUEUE_MANAGER:-QM1}"
MSGS_PER_QUEUE="${1:-5}"
SLEEP_SEC="${LOAD_DEV_QUEUE_SLEEP:-2}"
QUEUES=(DEV.QUEUE.1 DEV.QUEUE.2 DEV.QUEUE.3)

if ! docker compose ps --status running mq 2>/dev/null | grep -q mq; then
  echo "ERROR: mq container not running — run: docker compose up -d mq" >&2
  exit 1
fi

echo "== Load DEV sample queues =="
echo "  Queue manager: ${QM}"
echo "  Messages per queue: ${MSGS_PER_QUEUE} (${SLEEP_SEC}s between puts)"
echo

bash scripts/enable-mq-queue-monitoring.sh

put_messages() {
  local queue="$1"
  local count="$2"
  local i body
  for ((i = 1; i <= count; i++)); do
    body="splunk-demo ${queue} msg ${i} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n\n' "$body" | docker compose exec -T mq /opt/mqm/samp/bin/amqsput "$queue" "$QM" >/dev/null
    echo "  PUT ${queue} (${i}/${count})"
    if [ "$i" -lt "$count" ] && [ "$SLEEP_SEC" -gt 0 ]; then
      sleep "$SLEEP_SEC"
    fi
  done
}

for queue in "${QUEUES[@]}"; do
  put_messages "$queue" "$MSGS_PER_QUEUE"
done

echo
echo "Queue status:"
docker compose exec -T mq runmqsc "$QM" <<MQSC
DISPLAY QSTATUS(DEV.QUEUE.1) CURDEPTH MSGAGE MONQ
DISPLAY QSTATUS(DEV.QUEUE.2) CURDEPTH MSGAGE MONQ
DISPLAY QSTATUS(DEV.QUEUE.3) CURDEPTH MSGAGE MONQ
MQSC

echo
echo "Done. Wait ~30–60s, refresh IBM MQ Ops dashboard (Last 15 min)."
echo "  DEV rows: depth > 0, oldest msg (s) > 0, enqueue/min > 0 (no consumer on these queues)."
