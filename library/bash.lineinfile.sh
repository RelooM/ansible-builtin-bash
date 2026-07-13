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
# ansible-module: bash.lineinfile
# description: Ensure a line is present/absent in a file — pure-Bash replacement
#   for ansible.builtin.lineinfile. Calls sudo -n internally when running as
#   non-root (no Ansible become needed).
# options:
#   path:
#     description: The file to modify.
#     required: true
#     type: str
#   line:
#     description: The line to insert/ensure present.
#     required: false
#     type: str
#   regex:
#     description: Regex to match existing lines (instead of matching the line literally).
#     required: false
#     type: str
#   state:
#     description: Whether the line should be present or absent.
#     required: false
#     type: str
#     default: "present"
#     choices: [present, absent]
#   create:
#     description: Create the file if it does not exist.
#     required: false
#     type: bool
#     default: false
#   use_sudo:
#     description: Sudo policy — auto (sudo -n when non-root), true (force), false (never).
#     required: false
#     type: str
#     default: "auto"
#
# Output (stdout): single JSON object with changed/failed/msg/rc/invocation.args.
set -uo pipefail

MODULE_NAME="bash.lineinfile"
CHANGED=false
FAILED=false
MSG=""
RC=0
PATH_=""
LINE=""
REGEX=""
STATE="present"
CREATE=false
USE_SUDO="auto"
SUDO_PREFIX=""

# ---- Helpers ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_sudo() {
  SUDO_PREFIX=""
  case "$USE_SUDO" in
    false) SUDO_PREFIX="" ;;
    true)  SUDO_PREFIX="sudo" ;;
    auto|*)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then
          if sudo -n true >/dev/null 2>&1; then SUDO_PREFIX="sudo -n"; else SUDO_PREFIX="sudo"; fi
        else
          FAILED=true; MSG="Running as non-root but sudo is unavailable. Install sudo or set use_sudo=false."; emit_result
        fi
      fi ;;
  esac
}

run_cmd() {  # captures stdout/stderr+rc into RUN_STDOUT/RUN_RC
  RUN_STDOUT="$("$@" 2>&1)"; RUN_RC=$?
}

emit_result() {
  local out
  out="{"
  out+="\"changed\": $CHANGED,"
  out+="\"failed\": $FAILED,"
  out+="\"msg\": $(jq_safe "$MSG")"
  out+=",\"rc\": $RC"
  out+=",\"invocation\": {\"args\": {"
  out+="\"path\": $(jq_safe "$PATH_")"
  out+=",\"line\": $(jq_safe "$LINE")"
  out+=",\"regex\": $(jq_safe "$REGEX")"
  out+=",\"state\": $(jq_safe "$STATE")"
  out+=",\"create\": $(jq_safe "$CREATE")"
  out+=",\"use_sudo\": $(jq_safe "$USE_SUDO")"
  out+="}}"
  out+="}"
  printf '%s\n' "$out"
  exit 0
}

# ---- Parse arguments ----
# Dual contract: prefer positional key=value ($@); if ARGS_JSON env is set and
# no positional args were given, parse the JSON object as key=value pairs.
if [ "$#" -eq 0 ] && [ -n "${ARGS_JSON:-}" ]; then
  if command_exists jq; then
    while IFS== read -r k v; do
      [ -n "$k" ] || continue
      set -- "$@" "$k=$v"
    done < <(printf '%s' "$ARGS_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
  else
    for kv in $(printf '%s' "$ARGS_JSON" | grep -o '"[a-zA-Z_]*"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/"([a-zA-Z_]*)"[[:space:]]*:[[:space:]]*"([^"]*)"/\1=\2/'); do
      set -- "$@" "$kv"
    done
  fi
fi

for arg in "$@"; do
  case "$arg" in
    *=*) key="${arg%%=*}"; val="${arg#*=}" ;;
    *) continue ;;
  esac
  case "$key" in
    path) PATH_="$val" ;;
    line) LINE="$val" ;;
    regex) REGEX="$val" ;;
    state) STATE="$val" ;;
    create)
      case "$val" in 1|yes|true|True|TRUE) CREATE=true ;; *) CREATE=false ;; esac ;;
    use_sudo) USE_SUDO="$val" ;;
  esac
done

detect_sudo

# ---- Validate ----
if [ -z "$PATH_" ]; then
  FAILED=true; MSG="Parameter 'path' is required."; emit_result
fi

case "$STATE" in
  present|absent) ;;
  "") STATE="present" ;;
  *) FAILED=true; MSG="Invalid state: $STATE (expected present|absent)."; emit_result ;;
esac

if [ ! -f "$PATH_" ]; then
  if [ "$CREATE" = "true" ]; then
    run_cmd $SUDO_PREFIX bash -c ": > $(printf '%q' "$PATH_")"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="Failed to create $PATH_: $RUN_STDOUT"; emit_result; }
  else
    FAILED=true; MSG="Destination $PATH_ does not exist and create=false"; emit_result
  fi
fi

# Match pattern: explicit regex wins for deletion, else literal line.
# When a regex is given, "already present" is judged on the literal LINE
# (regex matches any equivalent line); deletion still targets the regex.
if [ -n "$REGEX" ]; then
  MATCH_RE="$REGEX"
  PRESENT_RE="^$(printf '%s' "$LINE" | sed 's/[][\.^*$/]/\\&/g')\$"
else
  MATCH_RE="^$(printf '%s' "$LINE" | sed 's/[][\.^*$/]/\\&/g')\$"
  PRESENT_RE="$MATCH_RE"
fi

EXISTING="$($SUDO_PREFIX grep -cE "$PRESENT_RE" "$PATH_" 2>/dev/null || true)"
EXISTING="${EXISTING:-0}"

if [ "$STATE" = "present" ]; then
  if [ "${EXISTING:-0}" -eq 0 ]; then
    if [ -n "$REGEX" ]; then
      run_cmd $SUDO_PREFIX sed -i -E "/$MATCH_RE/d" "$PATH_"
      [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="Failed to replace line in $PATH_: $RUN_STDOUT"; emit_result; }
    fi
    run_cmd $SUDO_PREFIX bash -c "printf '%s\n' $(printf '%q' "$LINE") >> $(printf '%q' "$PATH_")"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="Failed to append line to $PATH_: $RUN_STDOUT"; emit_result; }
    CHANGED=true
  fi
elif [ "$STATE" = "absent" ]; then
  if [ "${EXISTING:-0}" -gt 0 ]; then
    run_cmd $SUDO_PREFIX sed -i -E "/$MATCH_RE/d" "$PATH_"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="Failed to remove line from $PATH_: $RUN_STDOUT"; emit_result; }
    CHANGED=true
  fi
fi

if [ "$CHANGED" = false ]; then
  MSG="Line already in desired state in $PATH_"
else
  MSG="Line state updated in $PATH_"
fi

emit_result
