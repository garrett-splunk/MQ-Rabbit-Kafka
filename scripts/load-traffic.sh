#!/usr/bin/env bash
# Send test orders to order-producer (no Node/npm required).
set -euo pipefail

BASE_URL="${PRODUCER_URL:-http://localhost:8080}"
COUNT="${1:-20}"
DELAY_MS="${2:-500}"
WAIT_SECS="${WAIT_SECS:-60}"

wait_for_producer() {
  local deadline=$((SECONDS + WAIT_SECS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -sf "${BASE_URL}/health" | grep -q order-producer; then
      return 0
    fi
    sleep 2
  done
  echo "FAIL producer not ready at ${BASE_URL}/health after ${WAIT_SECS}s"
  echo "Hint: wait for 'docker compose up' to finish, then retry."
  exit 1
}

wait_for_producer
echo "Sending ${COUNT} orders to ${BASE_URL} (${DELAY_MS}ms apart)"
for ((i = 0; i < COUNT; i++)); do
  correlation_id="load-$(date +%s)-${i}"
  sku=$((100 + i % 5))
  qty=$((1 + i % 3))

  tmp="$(mktemp)"
  http_code="$(curl -sS -o "$tmp" -w '%{http_code}' -X POST "${BASE_URL}/orders" \
    -H "Content-Type: application/json" \
    -H "X-Correlation-Id: ${correlation_id}" \
    -d "{\"productId\":\"SKU-${sku}\",\"quantity\":${qty}}" || echo "000")"
  body="$(tr -d '\n' < "$tmp" | head -c 200)"
  rm -f "$tmp"

  if [ "$http_code" = "202" ]; then
    echo "${http_code} ${correlation_id} ${body}"
  else
    echo "FAIL request ${i} (${correlation_id}) HTTP ${http_code} ${body}"
    exit 1
  fi

  if [ "$DELAY_MS" -gt 0 ] && [ "$i" -lt $((COUNT - 1)) ]; then
    python3 -c "import time; time.sleep(${DELAY_MS} / 1000)"
  fi
done
