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
cp .env.splunk.example .env.splunk
# Edit .env.splunk — set SPLUNK_ACCESS_TOKEN (see below)
bash scripts/run-demo.sh             # build, start, verify, load MQ + Kafka + Rabbit traffic
```

### Splunk access token

Put your **ingest token** in **`.env.splunk`** at the repo root (gitignored — never commit it):

```bash
cp .env.splunk.example .env.splunk
nano .env.splunk   # or open in Cursor
```

Set these lines (match realm/URLs to your org):

```
SPLUNK_REALM=us1
SPLUNK_ACCESS_TOKEN=your-ingest-token-here
SPLUNK_INGEST_URL=https://ingest.us1.signalfx.com
SPLUNK_API_URL=https://api.us1.signalfx.com
```

Get a token: **Splunk O11y → Settings → Organization Settings → Access Tokens → New Token (Ingest)**.

After editing, restart the collector: `docker compose up -d otel-collector`

**Splunk filter (Metric Explorer):** `deployment.environment.name:messaging-demo-lab`

> **Gotcha:** Use `deployment.environment.name`, not `deployment.environment` — the UI often only matches on `.name`.

See [demo guide — Splunk token](https://garrett-splunk.github.io/MQ-Rabbit-Kafka/#splunk-token) for full steps.

Or step by step:

```bash
cp .env.example .env
cp .env.splunk.example .env.splunk
docker compose up --build -d
bash scripts/verify-stack.sh
```

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
