#!/usr/bin/env bash
# Verify that modules produce valid JSON output
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Testing JSON output from library modules..."

for module in library/*.sh; do
  [ -f "$module" ] || continue
  name="$(basename "$module")"

  # Run with a test argument and capture output
  output=$(bash "$module" test_mode=true 2>/dev/null || true)

  # Validate JSON
  if echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
    echo "  ✓ $name — valid JSON"
  else
    echo "  ✗ $name — INVALID JSON"
    echo "    Output: $output"
    exit 1
  fi
done

echo "All modules produce valid JSON."
