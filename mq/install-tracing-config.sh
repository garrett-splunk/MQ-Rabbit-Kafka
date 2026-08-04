#!/bin/sh
# Copy tracing exit config into the active queue manager data directory after QM1 starts.
set -eu

QMGR="${MQ_QMGR_NAME:-QM1}"
CONF_SRC="${MQ_TRACING_CONF_SRC:-/etc/mqm/mqtracingexit.conf}"
DATA_DIR="/mnt/mqm/qmgrs/${QMGR}"

if [ ! -f "$CONF_SRC" ]; then
  echo "MQ tracing: no config at $CONF_SRC, skipping"
  exit 0
fi

attempt=0
while [ "$attempt" -lt 120 ]; do
  if [ -d "$DATA_DIR" ]; then
    cp "$CONF_SRC" "${DATA_DIR}/mqtracingexit.conf"
    echo "MQ tracing: installed ${DATA_DIR}/mqtracingexit.conf"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 2
done

echo "MQ tracing: queue manager data dir not found under ${DATA_DIR}" >&2
exit 0
