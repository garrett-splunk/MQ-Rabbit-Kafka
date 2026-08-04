# syntax=docker/dockerfile:1
# IBM MQ dev server for the Java Contrib metrics workshop (no mq_otel embedded).
FROM icr.io/ibm-messaging/mq:latest

USER root
COPY mq/mqtracingexit.conf /etc/mqm/mqtracingexit.conf
COPY mq/10-dev.mqsc /opt/mqm/lab/10-dev.mqsc
COPY mq/20-lab-connect.mqsc /opt/mqm/lab/20-lab-connect.mqsc
COPY mq/install-tracing-config.sh /usr/local/bin/install-tracing-config.sh
COPY mq/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/install-tracing-config.sh /usr/local/bin/docker-entrypoint.sh \
  && mkdir -p /opt/mqm/lab \
  && grep -q '^app:' /etc/passwd || echo 'app:x:1002:0:app user:/home/app:/sbin/nologin' >> /etc/passwd \
  && mkdir -p /home/app && chown 1002:0 /home/app

USER 1001
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
