#!/usr/bin/env bash
# Test dnf.sh module — validates argument parsing, JSON output, state dispatch shape.
# Note: actual dnf calls will fail in this environment (no dnf installed).
# We test the module contract:
#   1. Always valid JSON
#   2. Argument parsing works for all parameter combinations
#   3. JSON has required keys (changed, failed, msg, rc, invocation)
#   4. Correct error state for invalid input
set -euo pipefail

cd "$(dirname "$0")/.."
DNF_MODULE="./library/dnf.sh"

PASS="✓"
FAIL="✗"

passed=0
failed=0

test_case() {
  local desc="$1"
  local expected_failed="$2"  # "true" or "false"
  shift 2
  local args=("$@")

  local output rc_val
  set +e
  output=$(bash "$DNF_MODULE" "${args[@]}" 2>/dev/null)
  rc_val=$?
  set -e

  # Check JSON validity (MANDATORY)
  if ! echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
    echo "  $FAIL $desc — INVALID JSON"
    echo "    Output: $output"
    failed=$((failed + 1))
    return
  fi

  # Parse and verify required keys
  local parse_ok
  parse_ok=$(echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
required = ['changed', 'failed', 'msg', 'rc', 'invocation']
for key in required:
    if key not in data:
        print('MISSING:' + key)
        sys.exit(1)
print('OK')
")
  if [ "$parse_ok" != "OK" ]; then
    echo "  $FAIL $desc — missing required key: ${parse_ok#MISSING:}"
    echo "    Output: $output"
    failed=$((failed + 1))
    return
  fi

  # Check failed field matches expectation (case-insensitive)
  local failed_val
  failed_val=$(echo "$output" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('failed', 'MISSING')).lower())")
  if [ "$failed_val" != "$(echo "$expected_failed" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "  $FAIL $desc — expected failed=$expected_failed, got failed=$failed_val"
    echo "    Output: $output"
    failed=$((failed + 1))
    return
  fi

  echo "  $PASS $desc"
  passed=$((passed + 1))
}

# ============================================================
echo "=== dnf.sh Module Tests ==="
echo

echo "--- Validation: argument parsing errors ---"
test_case "No arguments (missing name)"           "true"
test_case "Invalid state"                         "true" name=curl state=WRONG

echo
echo "--- State dispatch: present ---"
test_case "state=present (single pkg)"            "true" name=curl state=present
test_case "state=present (multi pkg, comma)"      "true" name=curl,wget state=present
test_case "state=present with enablerepo"         "true" name=curl state=present enablerepo=epel
test_case "state=present with allowerasing"       "true" name=curl state=present allowerasing=true
test_case "state=present with nobest"             "true" name=curl state=present nobest=true
test_case "state=present with disable_gpg_check"  "true" name=curl state=present disable_gpg_check=true
test_case "state=present with skip_broken"        "true" name=curl state=present skip_broken=true
test_case "state=present with conf_file"          "true" name=curl state=present conf_file=/etc/dnf/dnf.conf
test_case "state=present with installroot"        "true" name=curl state=present installroot=/mnt/sysroot
test_case "state=present with releasever"         "true" name=curl state=present releasever=9
test_case "state=present with exclude"            "true" name=curl state=present exclude=bad-pkg
test_case "state=present with download_only"      "true" name=curl state=present download_only=true
test_case "state=present with cacheonly"          "true" name=curl state=present cacheonly=true
test_case "state=present with sslverify"          "true" name=curl state=present sslverify=false
test_case "state=present with allow_downgrade"    "true" name=curl state=present allow_downgrade=true
test_case "state=present with install_weak_deps"  "true" name=curl state=present install_weak_deps=false
test_case "state=present with lock_timeout"       "true" name=curl state=present lock_timeout=60

echo
echo "--- State dispatch: latest ---"
test_case "state=latest (single pkg)"             "true" name=curl state=latest
test_case "state=latest all packages (*)"          "true" name='*' state=latest
test_case "state=latest with security"            "true" name=curl state=latest security=true
test_case "state=latest with bugfix"              "true" name=curl state=latest bugfix=true
test_case "state=latest with update_only"         "false" name=curl state=latest update_only=true
test_case "state=latest with enablerepo"          "true" name=curl state=latest enablerepo=updates-testing

echo
echo "--- State dispatch: absent ---"
test_case "state=absent (single pkg)"             "false" name=curl state=absent
test_case "state=absent (multi pkg comma)"        "false" name=curl,wget state=absent
test_case "state=absent with autoremove"          "false" name=curl state=absent autoremove=true

echo
echo "--- State aliases ---"
test_case "state=installed (alias for present)"   "true" name=curl state=installed
test_case "state=removed (alias for absent)"      "false" name=curl state=removed

echo
echo "--- Additional features ---"
test_case "Autoremove only (no name)"             "true" autoremove=true
test_case "With update_cache"                     "true" name=curl state=present update_cache=true
test_case "With enablerepo + disablerepo"          "true" name=curl state=present enablerepo=epel disablerepo=appstream
test_case "With disable_plugin + enable_plugin"   "true" name=curl state=present disable_plugin=slow enable_plugin=fast
test_case "With disable_excludes"                 "true" name=curl state=present disable_excludes=all
test_case "With download_dir"                     "true" name=curl state=present download_only=true download_dir=/tmp/rpms
test_case "Package with version specifier"        "true" "name=curl >= 7.0" state=present

echo
echo "--- List mode ---"
test_case "list=installed"                        "true" list=installed
test_case "list=available"                        "true" list=available
test_case "list=updates"                          "true" list=updates
test_case "list=package-name"                     "false" list=curl

echo
echo "--- JSON output structure (deep inspection) ---"
output=$(bash "$DNF_MODULE" name=curl state=present 2>/dev/null || true)

# Validate full JSON structure with Python
python3 -c "
import sys, json
data = json.load(sys.stdin)

# Check all required keys
assert 'changed' in data, 'Missing: changed'
assert 'failed' in data, 'Missing: failed'
assert 'msg' in data, 'Missing: msg'
assert 'rc' in data, 'Missing: rc'
assert 'invocation' in data, 'Missing: invocation'

# Check types
assert isinstance(data['changed'], bool), 'changed must be bool'
assert isinstance(data['failed'], bool), 'failed must be bool'
assert isinstance(data['msg'], str), 'msg must be string'
assert isinstance(data['rc'], int), 'rc must be int'

# Check invocation shape
inv = data['invocation']
assert 'module_args' in inv, 'Missing invocation.module_args'
mod_args = inv['module_args']
assert 'name' in mod_args, 'Missing invocation.module_args.name'
assert 'state' in mod_args, 'Missing invocation.module_args.state'
assert isinstance(mod_args['name'], list), 'name must be a list'

# Check rc is always 0 (module internal, not dnf exit code)
assert data['rc'] == 0, f'rc should be 0, got {data[\"rc\"]}'

print('  $PASS Full JSON structure validation passed')
print(f'  Parsed: changed={data[\"changed\"]}, failed={data[\"failed\"]}, msg={data[\"msg\"][:60]}...')
" <<< "$output" || { failed=$((failed + 1)); echo "  $FAIL JSON deep inspection failed"; }

echo
echo "=== Results: $passed passed, $failed failed ==="
[ "$failed" -eq 0 ] || exit 1
