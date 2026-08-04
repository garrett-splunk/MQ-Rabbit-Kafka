#!/usr/bin/env bash
# Create a Kafka topic and produce sample records for consumer-group metrics
set -euo pipefail
TOPIC="${1:-demo.orders}"
COUNT="${2:-20}"

docker compose exec -T kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic "$TOPIC" --partitions 1 --replication-factor 1 2>/dev/null || true

for i in $(seq 1 "$COUNT"); do
  echo "demo-order-$i" | docker compose exec -T kafka kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$TOPIC" >/dev/null 2>&1
done

echo "Produced $COUNT messages to topic $TOPIC"
echo "Kafka metrics update within ~30s (kafkametrics scrape interval)"
