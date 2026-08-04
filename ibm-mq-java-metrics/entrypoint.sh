#!/bin/sh
set -eu

MQ_HOST="${MQ_HOST:-mq}"
MQ_PORT="${MQ_PORT:-1414}"
MQ_CHANNEL="${MQ_CHANNEL:-MQOTEL.SVRCONN}"
MQ_USER="${MQ_USER:-app}"
MQ_PASSWORD="${MQ_PASSWORD:-passw0rd}"
OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://otel-collector:4318}"
SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS:-15}"
COLLECTOR_HEALTH_URL="${COLLECTOR_HEALTH_URL:-http://otel-collector:13133/}"

echo "Waiting for OTel Collector at ${COLLECTOR_HEALTH_URL}..."
deadline=$(( $(date +%s) + 120 ))
until curl -sf "${COLLECTOR_HEALTH_URL}" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: OTel Collector not ready after 120s — start otel-collector first."
    exit 1
  fi
  sleep 3
done
echo "OTel Collector is ready."

CONFIG=/tmp/config.yml
sed \
  -e "s|__MQ_HOST__|${MQ_HOST}|g" \
  -e "s|__MQ_PORT__|${MQ_PORT}|g" \
  -e "s|__MQ_CHANNEL__|${MQ_CHANNEL}|g" \
  -e "s|__MQ_USER__|${MQ_USER}|g" \
  -e "s|__MQ_PASSWORD__|${MQ_PASSWORD}|g" \
  -e "s|__OTLP_ENDPOINT__|${OTLP_ENDPOINT}|g" \
  -e "s|__SCRAPE_INTERVAL_SECONDS__|${SCRAPE_INTERVAL_SECONDS}|g" \
  /opt/ibm-mq-metrics/config.lab.yml > "$CONFIG"

echo "Starting OpenTelemetry Java Contrib ibm-mq-metrics (client mode) → ${OTLP_ENDPOINT}"
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTLP_ENDPOINT}"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="${OTLP_ENDPOINT}/v1/metrics"
export OTEL_EXPORTER_OTLP_METRICS_PROTOCOL=http/protobuf
export OTEL_LOGS_EXPORTER=none
export OTEL_TRACES_EXPORTER=none
exec java \
  -cp "/opt/ibm-mq-metrics/ibm-mq-metrics.jar:/opt/ibm-mq-metrics/com.ibm.mq.allclient.jar" \
  io.opentelemetry.ibm.mq.opentelemetry.Main \
  "$CONFIG"
