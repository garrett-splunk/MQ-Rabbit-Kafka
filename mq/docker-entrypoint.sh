#!/bin/sh
# Re-apply lab MQSC after QM1 is ready (Java Contrib exporter runs as a separate sidecar).
set -eu

apply_lab_mqsc() {
  attempt=0
  while [ "$attempt" -lt 90 ]; do
    if chkmqready 2>/dev/null; then
      for mqsc in /opt/mqm/lab/20-lab-connect.mqsc /opt/mqm/lab/10-dev.mqsc; do
        if [ -f "$mqsc" ]; then
          echo "Applying ${mqsc}..."
          runmqsc "${MQ_QMGR_NAME:-QM1}" < "$mqsc" || true
        fi
      done
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "Lab MQSC: queue manager not ready within timeout" >&2
  return 1
}

(
  apply_lab_mqsc
) &

exec runmqdevserver
