# Unified Messaging Observability Demo

**IBM MQ · Kafka · RabbitMQ → OpenTelemetry Collector → Splunk Observability Cloud**

Presenter demo for enterprise customers running multiple messaging platforms (often with Dynatrace extensions, AWS Distro OTel, and Grafana today). One collector, one Splunk backend, metrics + APM for MQ sample apps.

| Resource | URL |
|----------|-----|
| **Demo guide (GitHub Pages)** | https://garrett-splunk.github.io/MQ-Rabbit-Kafka/ |
| **MQ-only deep-dive lab** | https://garrett-splunk.github.io/MQ-Java-Otel-Workshop/ |
| **Local demo site** | http://localhost:8092 (with stack running) |

## Quick start (facilitator)

```bash
git clone https://github.com/garrett-splunk/MQ-Rabbit-Kafka.git
cd MQ-Rabbit-Kafka
cp .env.splunk.example .env.splunk   # add Splunk ingest token (optional for local UI only)
bash scripts/run-demo.sh             # build, start, verify, load MQ + Kafka + Rabbit traffic
```

Or step by step:

```bash
cp .env.example .env
cp .env.splunk.example .env.splunk
docker compose up --build -d
bash scripts/verify-stack.sh
```

**Splunk filter:** `deployment.environment:messaging-demo-lab`

## What's in the stack

| Platform | Ingest path | Splunk signal |
|----------|-------------|---------------|
| IBM MQ | Java Contrib `ibm-mq-metrics` sidecar → OTLP | `ibm.mq.*` metrics |
| IBM MQ apps | order-producer / consumer → OTLP traces | APM service map |
| Kafka | [kafkametrics](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-components/receivers/kafka-metrics-receiver) receiver | Broker / topic / consumer metrics |
| RabbitMQ | [rabbitmq](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-components/receivers/rabbitmq-receiver) receiver | Queue / node metrics |

## Demo scripts

```bash
bash scripts/load-traffic.sh 10 200              # MQ orders
bash scripts/demo-incident-mq-backlog.sh         # stop consumer → depth alert story
bash scripts/load-kafka-traffic.sh demo.orders 15
bash scripts/load-rabbit-traffic.sh 10           # pip install pika
```

## GitHub Pages

The demo guide in `demo-site/` deploys to `gh-pages` on push to `main`. Enable Pages: repo **Settings → Pages → Source: Deploy from branch → gh-pages / root**.

## License

IBM MQ container requires `LICENSE=accept` (developer/education use).
