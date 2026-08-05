#!/usr/bin/env bash
# Wrapper for provision-splunk-mq-ops.py — creates IBM MQ ops dashboard + detectors in Splunk O11y.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/provision-splunk-mq-ops.py" "$@"
