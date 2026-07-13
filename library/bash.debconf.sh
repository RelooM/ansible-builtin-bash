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
# bash.debconf — Pure Bash replacement for ansible.builtin.debconf
# pre-seeds the debconf database with values.

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.debconf"
CHANGED=false
FAILED=false
MSG=""
STDOUT=""
STDERR=""
RC=0

# ---- Defaults ----
name=""
question=""
value=""
vtype="string"
unseen=false
use_sudo="auto"
SUDO_PREFIX=""

# ---- Helper: emit JSON result and exit ----
emit_result() {
  local out
  out="{"
  out+="\"changed\": $CHANGED,"
  out+="\"failed\": $FAILED,"
  out+="\"msg\": $(jq_safe "$MSG")"
  out+=", \"rc\": $RC"
  [ -n "$STDOUT" ] && out+=", \"stdout\": $(jq_safe "$STDOUT")"
  [ -n "$STDERR" ] && out+=", \"stderr\": $(jq_safe "$STDERR")"
  
  out+=", \"invocation\": {\"module_args\": {"
  out+="\"name\": $(jq_safe "$name"), "
  out+="\"question\": $(jq_safe "$question"), "
  out+="\"value\": $(jq_safe "$value"), "
  out+="\"vtype\": $(jq_safe "$vtype"), "
  out+="\"unseen\": $unseen, "
  out+="\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"
  
  echo "$out"
  [ "$FAILED" = true ] && exit 1 || exit 0
}

# ---- Helper: JSON-safe string quoting ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_sudo() {
  if [ "$use_sudo" = "auto" ]; then
    if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
      SUDO_PREFIX="sudo -n"
    fi
  elif [ "$use_sudo" = "true" ]; then
    if command_exists sudo; then
      SUDO_PREFIX="sudo -n"
    else
      FAILED=true; MSG="sudo requested but not found"; emit_result
    fi
  fi
}

run_cmd() {
  local cmd=("$@")
  [ -n "$SUDO_PREFIX" ] && cmd=($SUDO_PREFIX "${cmd[@]}")
  set +e
  local tmp_err=$(mktemp)
  STDOUT=$("${cmd[@]}" 2>"$tmp_err")
  RC=$?
  STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
  set -e
  return $RC
}

# ---- Argument Parsing ----
for arg in "$@"; do
  case "$arg" in
    name=*) name="${arg#*=}" ;; # Package name
    package=*) name="${arg#*=}" ;; # Alias for name
    question=*) question="${arg#*=}" ;;
    value=*) value="${arg#*=}" ;;
    vtype=*) vtype="${arg#*=}" ;;
    unseen=*) [[ "${arg#*=}" =~ ^(true|yes|1|True|TRUE)$ ]] && unseen=true || unseen=false ;;
    use_sudo=*) use_sudo="${arg#*=}" ;;
    *) # handle name= as package if not already set
       if [[ "$arg" == name=* ]]; then
         name="${arg#*=}"
       fi
       ;;
  esac
done

# Validation
[ -z "$name" ] && { FAILED=true; MSG="Missing required parameter: name (package)"; emit_result; }
[ -z "$question" ] && { FAILED=true; MSG="Missing required parameter: question"; emit_result; }

detect_sudo

# 1. Get current value via debconf-show. This is reliable even for selections
#    set without a registered template, unlike `debconf-communicate GET` which
#    returns "10 <question> doesn't exist" in that case (so curr_val would stay
#    empty and the module would always report changed).
# debconf-show <package> outputs:
#   * <package>/<question>: <value>   (seen)
#     <package>/<question>: <value>   (unseen)
set +e
curr_line=$(debconf-show "$name" 2>/dev/null | grep -F "$question:" || true)
set -e

curr_val=""
exists=false
if [ -n "$curr_line" ]; then
  exists=true
  # Strip everything up to and including the first ": " to obtain the value.
  curr_val="${curr_line#*: }"
fi

# 2. Check if change needed
if [ "$exists" = true ] && [ "$curr_val" = "$value" ]; then
    MSG="Value already set to '$value'"
    emit_result
fi

# 3. Set value
# Format for debconf-set-selections: <package> <question> <vtype> <value>
# If unseen=true, use debconf-set-selections -u
cmd=("debconf-set-selections")
[ "$unseen" = true ] && cmd+=("-u")

if ! printf "%s %s %s %s\n" "$name" "$question" "$vtype" "$value" | run_cmd "${cmd[@]}"; then
    FAILED=true
    MSG="Failed to set debconf selection"
    emit_result
fi

CHANGED=true
MSG="Successfully set debconf selection $name/$question to $value"
emit_result
