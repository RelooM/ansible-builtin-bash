#!/usr/bin/bash
# ---- Ansible-native args bridge ----
# Modern ansible-core invokes modules as `<module> <tmp_args_file>`, writing a
# single line of space-separated `key=value` args (plus _ansible_* control keys)
# into that file. When $1 is a readable file, load its tokens into $@ so the
# module's own key=value parser works unchanged. No external deps / no source.
if [ -n "${1:-}" ] && [ -f "$1" ] && [ -r "$1" ]; then
  _ans_line=$(cat "$1")
  set -f
  set --
  for _ans_tok in $_ans_line; do
    case "$_ans_tok" in
      _ansible_*) ;;
      *=*) set -- "$@" "$_ans_tok" ;;
    esac
  done
  set +f
  unset _ans_line _ans_tok
fi
# ---- end args bridge ----
# ansible-module: bash.selinux
# description: Configures SELinux state and policy — pure Bash.
# options:
#   policy:
#     description: The name of the SELinux policy to use.
#     required: false
#     type: str
#     default: "targeted"
#     choices: ["targeted", "minimum", "mls"]
#   state:
#     description: The SELinux mode.
#     required: true
#     type: str
#     choices: ["enforcing", "permissive", "disabled"]
#   configfile:
#     description: Path to the SELinux configuration file.
#     required: false
#     type: str
#     default: "/etc/selinux/config"
#   use_sudo:
#     description: Whether to sudo the operations. 'auto' (default) sudo if not root.
#     required: false
#     type: str
#     default: "auto"
#     choices: ["auto", true, false]

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.selinux"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- Defaults ----
policy="targeted"
state=""
configfile="/etc/selinux/config"
use_sudo="auto"

# ---- Helper: JSON-safe string quoting ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\\n'/\\n}"
  s="${s//$'\\r'/\\r}"
  s="${s//$'\\t'/\\t}"
  printf '"%s"' "$s"
}

# ---- Helper: emit JSON result and exit ----
emit_result() {
  local out
  out="{"
  out+="\"changed\": $CHANGED,"
  out+="\"failed\": $FAILED,"
  out+="\"msg\": $(jq_safe "$MSG")"
  out+=",\"rc\": 0"

  if [ ${#RESULTS[@]} -gt 0 ]; then
    out+=",\"results\": ["
    local first=true
    for r in "${RESULTS[@]}"; do
      $first || out+=", "
      first=false
      out+=$(jq_safe "$r")
    done
    out+="]"
  fi

  if [ -n "$STDOUT" ]; then out+=",\"stdout\": $(jq_safe "$STDOUT")"; fi
  if [ -n "$STDERR" ]; then out+=",\"stderr\": $(jq_safe "$STDERR")"; fi

  out+=",\"invocation\": {\"module_args\": {"
  out+="\"state\": $(jq_safe "$state")"
  out+=",\"policy\": $(jq_safe "$policy")"
  out+=",\"configfile\": $(jq_safe "$configfile")"
  out+=",\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_sudo() {
  SUDO_PREFIX=""
  case "$use_sudo" in
    auto)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then SUDO_PREFIX="sudo -n"; else FAILED=true; MSG="Running as non-root but sudo is not available."; emit_result; fi
      fi
      ;;
    true|True|TRUE|1|yes)
      if command_exists sudo; then SUDO_PREFIX="sudo -n"; else FAILED=true; MSG="use_sudo=true but sudo is not installed."; emit_result; fi
      ;;
  esac
}

run_cmd() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then args+=($SUDO_PREFIX); fi
  args+=("$@")
  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$("${args[@]}" 2>"$tmp_stderr")
  RC=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  return 0
}

# ---- Argument parsing ----
PARSE_ERROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    state=*) state="${1#*=}" ;;
    policy=*) policy="${1#*=}" ;;
    configfile=*) configfile="${1#*=}" ;;
    use_sudo=*) use_sudo="${1#*=}" ;;
    *) PARSE_ERROR="${PARSE_ERROR}Unknown parameter: ${1%%=*}; " ;;
  esac
  shift
done

[ -n "$state" ] || { FAILED=true; MSG="Missing required argument: state"; emit_result; }
[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

case "$state" in
  enforcing|permissive|disabled) ;;
  *) FAILED=true; MSG="Invalid state: $state. Choices: enforcing, permissive, disabled"; emit_result ;;
esac

detect_sudo

# 1. Handle persistent state in config file
if [ ! -f "$configfile" ]; then
    FAILED=true; MSG="Config file $configfile not found"; emit_result
fi

current_file_state=$(grep '^SELINUX=' "$configfile" | cut -d= -f2 | tr -d ' ' || echo "unknown")
current_file_policy=$(grep '^SELINUXTYPE=' "$configfile" | cut -d= -f2 | tr -d ' ' || echo "unknown")

if [ "$current_file_state" != "$state" ] || [ "$current_file_policy" != "$policy" ]; then
    CHANGED=true
    # Use sed to update the file via sudo
    run_cmd sed -i "s/^SELINUX=.*/SELINUX=$state/" "$configfile"
    if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to update SELINUX in $configfile: $STDERR"; emit_result; fi
    
    run_cmd sed -i "s/^SELINUXTYPE=.*/SELINUXTYPE=$policy/" "$configfile"
    if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to update SELINUXTYPE in $configfile: $STDERR"; emit_result; fi
    
    RESULTS+=("Updated $configfile: SELINUX=$state, SELINUXTYPE=$policy")
fi

# 2. Handle runtime state (cannot set to 'disabled' at runtime if not already)
if command_exists getenforce; then
    current_runtime_state=$(getenforce | tr '[:upper:]' '[:lower:]')
    
    # We can only toggle between enforcing and permissive at runtime
    if [ "$state" != "disabled" ] && [ "$current_runtime_state" != "disabled" ]; then
        if [ "$current_runtime_state" != "$state" ]; then
            CHANGED=true
            case "$state" in
                enforcing)  run_cmd setenforce 1 ;;
                permissive) run_cmd setenforce 0 ;;
            esac
            if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to set runtime SELinux state: $STDERR"; emit_result; fi
            RESULTS+=("Set runtime SELinux state to $state")
        fi
    elif [ "$state" = "disabled" ] && [ "$current_runtime_state" != "disabled" ]; then
        RESULTS+=("Runtime SELinux state cannot be set to 'disabled' without reboot; updated config for next boot")
    elif [ "$state" != "disabled" ] && [ "$current_runtime_state" = "disabled" ]; then
        RESULTS+=("SELinux is disabled at runtime; reboot required to enable to $state")
    fi
fi

if [ "$CHANGED" = false ]; then
    MSG="SELinux is already in the desired state"
else
    MSG="SELinux state updated successfully"
fi

emit_result
