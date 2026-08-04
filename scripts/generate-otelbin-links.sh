#!/usr/bin/env bash
# Generate OTelBin deep links for collector example YAMLs.
# Usage: bash scripts/generate-otelbin-links.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLES="${ROOT}/collector/otelbin-examples"
OUT="${ROOT}/demo-site/otelbin-links.json"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
python3 - <<'PY' "$EXAMPLES" "$OUT"
import json, subprocess, sys
from pathlib import Path

examples_dir = Path(sys.argv[1])
out_path = Path(sys.argv[2])
files = [
    "splunk-agent-baseline.yaml",
    "rabbitmq-receiver.yaml",
    "kafka-metrics-receiver.yaml",
    "ibm-mq-otlp-sidecar.yaml",
]
links = {}
for name in files:
    path = examples_dir / name
    result = subprocess.run(
        [
            "curl", "-sf", "-X", "POST", "https://www.otelbin.io/deep-link",
            "-H", "Content-Type: text/plain",
            "--data-binary", f"@{path}",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    links[name.removesuffix(".yaml")] = result.stdout.strip()
    print(f"Generated link for {name}", file=sys.stderr)

out_path.write_text(json.dumps(links, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {out_path}", file=sys.stderr)

html_path = out_path.parent / "index.html"
html = html_path.read_text()
import re
for key, url in links.items():
    pattern = rf'(<a class="otelbin-link" data-otelbin-link="{re.escape(key)}" href=")[^"]*(")'
    html, n = re.subn(pattern, rf'\1{url}\2', html)
    if n == 0:
        print(f"WARNING: no HTML anchor for {key}", file=sys.stderr)
    else:
        print(f"Patched index.html for {key} ({n})", file=sys.stderr)
html_path.write_text(html, encoding="utf-8")
PY
