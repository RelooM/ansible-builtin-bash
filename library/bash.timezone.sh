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
# ansible-module: bash.timezone
# description: Manage system timezone (timedatectl set-timezone/show) — pure Bash
#   replacement for ansible.builtin.timezone. Cross-distro (systemd hosts with
#   timedatectl). Calls sudo -n internally when running as non-root, respecting
#   fine-grained sudoers policies. No reliance on Ansible's become.
# options:
#   name:
#     description: Timezone (e.g. America/New_York, UTC). Alias 'timezone'.
#     required: true
#     type: str
#   use_sudo:
#     description: Sudo policy — auto (sudo -n when non-root), true (force), false (never).
#     required: false
#     type: str
#     default: "auto"
#
# Output (stdout): single JSON object with changed/failed/msg/rc/invocation.args.
set -uo pipefail

MODULE_NAME="bash.timezone"
CHANGED=false
FAILED=false
MSG=""
RC=0
TZ=""
USE_SUDO="auto"
SUDO_PREFIX=""

# ---- Helpers (shared boilerplate, no jq dependency) ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Detect sudo prefix from use_sudo + EUID. Uses passwordless sudo (-n) to avoid
# blocking on a password prompt; falls back to plain sudo only when forced.
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

# Run a command, capturing stdout/stderr and exit code into globals.
# SUDO_PREFIX is prepended internally (and skipped entirely when empty, so the
# command is never an empty-string arg). Callers pass ONLY the real command.
run_cmd() {
  local args=()
  [ -n "$SUDO_PREFIX" ] && args+=($SUDO_PREFIX)   # shellcheck disable=SC2086
  args+=("$@")
  set +e
  RUN_STDOUT="$("${args[@]}" 2>&1)"; RUN_RC=$?
  set -uo pipefail
}

emit_result() {
  local out
  out="{"
  out+="\"changed\": $CHANGED,"
  out+="\"failed\": $FAILED,"
  out+="\"msg\": $(jq_safe "$MSG")"
  out+=",\"rc\": $RC"
  out+=",\"invocation\": {\"args\": {"
  out+="\"name\": $(jq_safe "$TZ")"
  out+=",\"use_sudo\": $(jq_safe "$USE_SUDO")"
  out+="}}"
  out+="}"
  printf '%s\n' "$out"
  exit 0
}

# ---- Parse arguments (positional key=value) ----
for arg in "$@"; do
  case "$arg" in
    *=*) key="${arg%%=*}"; val="${arg#*=}" ;;
    *) continue ;;
  esac
  case "$key" in
    name|timezone) TZ="$val" ;;
    use_sudo)      USE_SUDO="$val" ;;
  esac
done

if [[ -z "$TZ" ]]; then
  FAILED=true; MSG="name (timezone) is required"; emit_result
fi

if ! command_exists timedatectl; then
  FAILED=true; MSG="timedatectl not found; is this a systemd host?"; emit_result
fi

detect_sudo

# ---- Read current timezone: "Time zone: America/New_York (...)" ----
run_cmd timedatectl show --property=Timezone --value
CURRENT="$(printf '%s' "$RUN_STDOUT" | tr -d '[:space:]')"

# ---- Apply ----
if [[ "$CURRENT" == "$TZ" ]]; then
  CHANGED=false
  MSG="Timezone already set to '$TZ'"
else
  run_cmd timedatectl set-timezone "$TZ"
  if [[ $RUN_RC -ne 0 ]]; then
    FAILED=true; RC=$RUN_RC; MSG="timedatectl set-timezone failed: $RUN_STDOUT"; emit_result
  fi
  CHANGED=true
  MSG="Set timezone to '$TZ'"
fi

emit_result
