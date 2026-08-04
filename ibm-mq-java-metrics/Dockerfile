# syntax=docker/dockerfile:1
# OpenTelemetry Java Contrib ibm-mq-metrics → OTLP (Splunk Observability Cloud lab track).
# Prebuilt JARs from Maven Central — avoids multi-minute Gradle builds in the workshop.
ARG IBM_MQ_METRICS_VERSION=1.59.0-alpha
ARG IBM_MQ_ALLCLIENT_VERSION=10.0.0.0

FROM eclipse-temurin:11-jre-jammy AS runtime

ARG IBM_MQ_METRICS_VERSION
ARG IBM_MQ_ALLCLIENT_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --home /opt/ibm-mq-metrics --shell /usr/sbin/nologin mqmetrics

WORKDIR /opt/ibm-mq-metrics
RUN curl -fsSL \
  "https://repo1.maven.org/maven2/io/opentelemetry/contrib/opentelemetry-ibm-mq-metrics/${IBM_MQ_METRICS_VERSION}/opentelemetry-ibm-mq-metrics-${IBM_MQ_METRICS_VERSION}-all.jar" \
  -o /opt/ibm-mq-metrics/ibm-mq-metrics.jar \
  && curl -fsSL \
  "https://repo1.maven.org/maven2/com/ibm/mq/com.ibm.mq.allclient/${IBM_MQ_ALLCLIENT_VERSION}/com.ibm.mq.allclient-${IBM_MQ_ALLCLIENT_VERSION}.jar" \
  -o /opt/ibm-mq-metrics/com.ibm.mq.allclient.jar

COPY config.lab.yml /opt/ibm-mq-metrics/config.lab.yml
COPY entrypoint.sh /opt/ibm-mq-metrics/entrypoint.sh

RUN chmod 755 /opt/ibm-mq-metrics/entrypoint.sh \
  && chown -R mqmetrics:mqmetrics /opt/ibm-mq-metrics

USER mqmetrics
ENTRYPOINT ["/opt/ibm-mq-metrics/entrypoint.sh"]
