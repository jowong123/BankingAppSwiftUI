#!/usr/bin/env bash
# PostToolUse hook: format any Swift file Claude just edited with swift-format.
# Never blocks: formatting failures are reported but don't stop the session.
set -euo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)"

[[ -z "$file" || "$file" != *.swift || ! -f "$file" ]] && exit 0

if command -v swift >/dev/null 2>&1; then
  swift format --in-place "$file" >/dev/null 2>&1 || echo "swift-format could not format $file" >&2
fi
exit 0
