#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Unified messaging demo stack verification =="

failures=0
check() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local pattern="${3:-}"
  local deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -n "$pattern" ]; then
      if curl -sf "$url" | grep -q "$pattern"; then
        echo "OK  $name"
        return 0
      fi
    elif curl -sf "$url" >/dev/null; then
      echo "OK  $name"
      return 0
    fi
    sleep 2
  done
  echo "FAIL $name (not ready after 90s)"
  failures=$((failures + 1))
  return 1
}

wait_for_url "order-producer health" "http://localhost:8080/health" order-producer || true
wait_for_url "order-consumer health" "http://localhost:8081/health" order-consumer || true
wait_for_url "inventory-service health" "http://localhost:8082/health" inventory-service || true
check "otel-collector health" bash -c 'curl -sf "http://localhost:13133/" >/dev/null'
check "demo site" bash -c 'curl -sf "http://localhost:8092/" | grep -qi "Unified messaging"'
check "kafka healthy" bash -c 'docker compose ps --status running kafka 2>/dev/null | grep -q kafka'
check "rabbitmq healthy" bash -c 'docker compose ps --status running rabbitmq 2>/dev/null | grep -q rabbitmq'
check "ibm-mq-java-metrics running" bash -c 'docker compose ps --status running ibm-mq-java-metrics 2>/dev/null | grep -q ibm-mq-java-metrics'

echo "== Sample MQ order =="
RESP="$(curl -sf -X POST "http://localhost:8080/orders" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: verify-$(date +%s)" \
  -d '{"productId":"SKU-100","quantity":2}' 2>&1)" || RESP="curl failed: $?"
echo "$RESP" | grep -q accepted && echo "OK  POST /orders" || { echo "FAIL POST /orders: $RESP"; failures=$((failures + 1)); }

if [ "$failures" -gt 0 ]; then
  echo "Verification finished with $failures failure(s)."
  exit 1
fi

echo "All checks passed."
