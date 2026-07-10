#!/usr/bin/env bash
# Run all module tests
set -euo pipefail

cd "$(dirname "$0")/.."
failed=0

for test_script in tests/test_*.sh; do
  if [ -f "$test_script" ]; then
    echo "=== Running: $test_script ==="
    if bash "$test_script"; then
      echo "=== PASS: $test_script ==="
    else
      echo "=== FAIL: $test_script ==="
      failed=1
    fi
    echo
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests failed."
  exit 1
fi
