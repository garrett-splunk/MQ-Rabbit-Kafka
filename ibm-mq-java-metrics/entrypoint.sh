#!/bin/sh
set -eu

MQ_HOST="${MQ_HOST:-mq}"
MQ_PORT="${MQ_PORT:-1414}"
MQ_CHANNEL="${MQ_CHANNEL:-MQOTEL.SVRCONN}"
MQ_USER="${MQ_USER:-app}"
MQ_PASSWORD="${MQ_PASSWORD:-passw0rd}"
OTLP_ENDPOINT="${OTLP_ENDPOINT:-http://otel-collector:4318}"
SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS:-15}"

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
exec java \
  -cp "/opt/ibm-mq-metrics/ibm-mq-metrics.jar:/opt/ibm-mq-metrics/com.ibm.mq.allclient.jar" \
  io.opentelemetry.ibm.mq.opentelemetry.Main \
  "$CONFIG"
