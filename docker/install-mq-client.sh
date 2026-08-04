#!/bin/sh
# Install IBM MQ redistributable client for ibmmq Node bindings (linux/amd64 lab images).
set -eu

VRMF="${MQ_CLIENT_VRMF:-10.0.0.0}"
RDURL="${MQ_CLIENT_RDURL:-https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist}"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) MQARCH=X64 ;;
  *)
    echo "Unsupported architecture for MQ client: $arch (lab images use linux/amd64)" >&2
    exit 1
    ;;
esac

mkdir -p /opt/mqm
curl -fsSL "${RDURL}/${VRMF}-IBM-MQC-Redist-Linux${MQARCH}.tar.gz" -o /tmp/mqclient.tar.gz
tar -zxf /tmp/mqclient.tar.gz -C /opt/mqm
rm -f /tmp/mqclient.tar.gz
if [ -x /opt/mqm/bin/genmqpkg.sh ]; then
  /opt/mqm/bin/genmqpkg.sh -b /opt/mqm
fi
