#!/usr/bin/env bash
# After updating mqtracingexit.conf, restart the queue manager so the tracing exit reloads.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose restart mq
echo "Restarted mq. Allow ~60s for QM1 to become ready, then generate message traffic."
