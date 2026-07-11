#!/usr/bin/env bash
# Test bash.debconf.sh

MODULE="/root/ansible-bash-modules/library/bash.debconf.sh"
passed=0
failed=0

test_case() {
  local label="$1"
  local expect_fail="$2"
  shift 2
  echo -n "  $label ... "
  output=$("$MODULE" "$@" 2>&1 || true)
  
  if ! echo "$output" | python3 -m json.tool >/dev/null 2>&1; then
    echo "FAIL (invalid JSON)"
    ((failed++))
    return
  fi

  f=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin).get('failed'))")
  if [ "$expect_fail" = "true" ]; then
    if [ "$f" = "True" ]; then echo "PASS"; ((passed++)); else echo "FAIL (expected failure)"; ((failed++)); fi
  else
    if [ "$f" = "False" ]; then echo "PASS"; ((passed++)); else echo "FAIL (unexpected failure: $(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin).get('msg'))"))"; ((failed++)); fi
  fi
}

echo "=== bash.debconf.sh Module Tests ==="
test_case "Missing name" "true" question="test/q" value="v"
test_case "Missing question" "true" name="test-pkg" value="v"

# Note: These might fail if debconf-utils isn't installed, but we'll see the error.
test_case "Set string value" "false" name="debconf" question="debconf/priority" value="high" vtype="select" use_sudo=false

echo "=== Results: $passed passed, $failed failed ==="
[ $failed -eq 0 ] && exit 0 || exit 1
