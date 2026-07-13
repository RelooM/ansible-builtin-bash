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
# ansible-module: bash.service
# description: Manages a systemd unit's runtime state and/or enablement —
#   pure-Bash replacement for ansible.builtin.service.
#   Callable as `bash.service:` in Ansible playbooks. Calls sudo -n internally
#   when running as non-root (no Ansible become needed).
# options:
#   name:
#     description: Unit name, e.g. "nginx.service".
#     required: true
#     type: str
#   state:
#     description: Desired runtime state.
#     required: false
#     type: str
#     choices: [started, stopped, restarted, reloaded]
#     aliases: [start, stop, restart, reload]
#   enabled:
#     description: Whether the unit should be enabled/disabled at boot.
#     required: false
#     type: bool
#   daemon_reload:
#     description: Run `systemctl daemon-reload` before other operations.
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

MODULE_NAME="bash.service"
CHANGED=false
FAILED=false
MSG=""
RC=0
NAME=""
STATE=""
ENABLED=""
DAEMON_RELOAD=false
STATE_CHANGED=false
ENABLE_CHANGED=false
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
  out+=",\"state_changed\": $STATE_CHANGED"
  out+=",\"enabled_changed\": $ENABLE_CHANGED"
  out+=",\"invocation\": {\"args\": {"
  out+="\"name\": $(jq_safe "$NAME")"
  out+=",\"state\": $(jq_safe "$STATE")"
  out+=",\"enabled\": $(jq_safe "$ENABLED")"
  out+=",\"daemon_reload\": $(jq_safe "$DAEMON_RELOAD")"
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
  # Best-effort JSON->kv using jq if available, else a tolerant grep fallback.
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
    name) NAME="$val" ;;
    state) STATE="$val" ;;
    enabled) ENABLED="$val" ;;
    daemon_reload)
      case "$val" in 1|yes|true|True|TRUE) DAEMON_RELOAD=true ;; *) DAEMON_RELOAD=false ;; esac ;;
    use_sudo) USE_SUDO="$val" ;;
  esac
done

detect_sudo

# ---- Validate (daemon_reload is a global command and does not require a name) ----
if [ -z "$NAME" ] && [ "$DAEMON_RELOAD" != "true" ]; then
  FAILED=true; MSG="Parameter 'name' is required."; emit_result
fi

case "$STATE" in
  started|start) STATE="started" ;;
  stopped|stop) STATE="stopped" ;;
  restarted|restart) STATE="restarted" ;;
  reloaded|reload) STATE="reloaded" ;;
  "") STATE="" ;;
  *) FAILED=true; MSG="Invalid state: $STATE (expected started|stopped|restarted|reloaded)."; emit_result ;;
esac

if [ -n "$ENABLED" ]; then
  case "$ENABLED" in
    true|True|TRUE|1|yes|false|False|FALSE|0|no) ;;
    *) FAILED=true; MSG="Invalid enabled: $ENABLED (expected true|false)."; emit_result ;;
  esac
fi

if ! command_exists systemctl; then
  FAILED=true; MSG="The 'systemctl' command is required but not found on this system."; emit_result
fi

# ---- Apply ----
if [ "$DAEMON_RELOAD" = "true" ]; then
  run_cmd $SUDO_PREFIX systemctl daemon-reload
  [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="daemon-reload failed: $RUN_STDOUT"; emit_result; }
  CHANGED=true
fi

case "$STATE" in
  started)
    if ! $SUDO_PREFIX systemctl is-active --quiet "$NAME"; then
      run_cmd $SUDO_PREFIX systemctl start "$NAME"
      [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="start failed: $RUN_STDOUT"; emit_result; }
      STATE_CHANGED=true; CHANGED=true
    fi
    ;;
  stopped)
    if $SUDO_PREFIX systemctl is-active --quiet "$NAME"; then
      run_cmd $SUDO_PREFIX systemctl stop "$NAME"
      [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="stop failed: $RUN_STDOUT"; emit_result; }
      STATE_CHANGED=true; CHANGED=true
    fi
    ;;
  restarted)
    run_cmd $SUDO_PREFIX systemctl restart "$NAME"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="restart failed: $RUN_STDOUT"; emit_result; }
    STATE_CHANGED=true; CHANGED=true
    ;;
  reloaded)
    run_cmd $SUDO_PREFIX systemctl reload-or-restart "$NAME"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="reload failed: $RUN_STDOUT"; emit_result; }
    STATE_CHANGED=true; CHANGED=true
    ;;
  "") : ;;  # no runtime change requested
esac

if [ -n "$ENABLED" ] && [ "$ENABLED" != "null" ]; then
  norm_enabled=false
  case "$ENABLED" in true|True|TRUE|1|yes) norm_enabled=true ;; esac
  is_enabled="$($SUDO_PREFIX systemctl is-enabled "$NAME" 2>/dev/null || echo disabled)"
  if [ "$norm_enabled" = true ] && [ "$is_enabled" != "enabled" ]; then
    run_cmd $SUDO_PREFIX systemctl enable "$NAME"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="enable failed: $RUN_STDOUT"; emit_result; }
    ENABLE_CHANGED=true; CHANGED=true
  elif [ "$norm_enabled" = false ] && [ "$is_enabled" = "enabled" ]; then
    run_cmd $SUDO_PREFIX systemctl disable "$NAME"
    [ "$RUN_RC" -eq 0 ] || { FAILED=true; MSG="disable failed: $RUN_STDOUT"; emit_result; }
    ENABLE_CHANGED=true; CHANGED=true
  fi
fi

if [ "$CHANGED" = false ]; then
  MSG="Service $NAME is already in the desired state"
else
  MSG="Service $NAME state updated"
fi

emit_result
