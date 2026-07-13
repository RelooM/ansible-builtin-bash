#!/usr/bin/bash
# Copyright (C) 2026 ansible-bash-modules contributors
# This program is free software under the GNU GPL v3.0+ (see LICENSE).
# SPDX-License-Identifier: GPL-3.0-or-later
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
# ansible-module: bash.systemd
# description: Manages systemd units — pure Bash replacement for ansible.builtin.systemd_service.
# Supports idempotent service lifecycle: start/stop/restart/reload/enable/disable/mask/unmask.
# Handles privilege escalation internally via sudo -n — no Ansible become required.
# auto-detects non-root → prefixes sudo -n for commands needing it.
#
# options:
# name:
#   description: Unit name (e.g., "httpd.service", "sshd", "cron.service").
#   required: true
#   type: str
# state:
#   description: Desired state of the unit.
#   required: false
#   choices:
#     - started
#     - stopped
#     - restarted
#     - reloaded
#     - enabled
#     - disabled
#     - masked
#     - unmasked
#   type: str
# enabled:
#   description: Whether unit should start at boot.
#   required: false
#   type: bool
# daemon_reload:
#   description: Run daemon-reload before any unit operations.
#   required: false
#   default: false
#   type: bool
# masked:
#   description: Whether unit should be masked.
#   required: false
#   type: bool
# scope:
#   description: Scope of the unit (system or user).
#   required: false
#   default: system
#   choices: [system, user]
#   type: str
# no_block:
#   description: Non-blocking operation.
#   required: false
#   default: false
#   type: bool
# force:
#   description: Force stop/disable if unit is running.
#   required: false
#   default: false
#   type: bool
# use_sudo:
#   description: Whether to prefix systemctl commands with sudo.
#   required: false
#   default: auto
#   choices: [auto, true, false]
#   type: str

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.systemd"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- State vars (defaults) ----
state=""
enabled=""
daemon_reload=false
masked=""
scope="system"
no_block=false
force=false
use_sudo="auto"

# Initialize name to empty string to avoid 'unbound variable' with set -u
name=""

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

    if [ -n "$STDOUT" ]; then
        out+=",\"stdout\": $(jq_safe "$STDOUT")"
    fi
    if [ -n "$STDERR" ]; then
        out+=",\"stderr\": $(jq_safe "$STDERR")"
    fi

    # Include invocation info for debugging
    out+=",\"invocation\": {\"module_args\": {\"name\": $(jq_safe "$name")"
    [ -n "$state" ] && out+=", \"state\": $(jq_safe "$state")"
    [ -n "$enabled" ] && out+=", \"enabled\": $(jq_safe "$enabled")"
    out+=", \"daemon_reload\": $daemon_reload"
    [ -n "$masked" ] && out+=", \"masked\": $(jq_safe "$masked")"
    out+=", \"scope\": $(jq_safe "$scope")"
    out+=", \"no_block\": $no_block"
    out+=", \"force\": $force"
    out+=", \"use_sudo\": $(jq_safe "$use_sudo")}}"

    out+="}"

    echo "$out"
    if [ "$FAILED" = true ]; then
        exit 1
    fi
    exit 0
}

# ---- Helper: JSON-safe string quoting (Bash-native, no jq dependency) ----
jq_safe() {
    local s="$1"
    # Escape backslashes, newlines, tabs, and double-quotes
    s="${s//\\/\\\\}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# ---- Helper: check if a command exists ----
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---- Helper: detect sudo prefix based on use_sudo param and EUID ----
detect_sudo() {
    SUDO_PREFIX=""
    if [ "$use_sudo" = "auto" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            if command_exists sudo; then
                SUDO_PREFIX="sudo -n"
            else
                FAILED=true
                MSG="Running as non-root but sudo is not available. Install sudo or set 'use_sudo=false'."
                emit_result
            fi
        fi
    elif [ "$use_sudo" = "true" ]; then
        if command_exists sudo; then
            SUDO_PREFIX="sudo -n"
        else
            FAILED=true
            MSG="use_sudo=true but sudo is not installed on the target system."
            emit_result
        fi
    fi
    # use_sudo=false → SUDO_PREFIX stays empty
}

# ---- Helper: run systemctl and capture output ----
run_systemctl() {
    local cmd="$1"
    shift
    local extra_args=("$@")

    local systemctl_args=()

    # Build systemctl command
    if [ -n "$SUDO_PREFIX" ]; then
        systemctl_args+=($SUDO_PREFIX)
    fi

    systemctl_args+=("systemctl")

    # Add scope if not system
    if [ "$scope" = "user" ]; then
        systemctl_args+=("--user")
    fi

    # Add no_block
    if [ "$no_block" = true ]; then
        systemctl_args+=("--no-block")
    fi

    # Force flag (primarily for stop/disable)
    if [ "$force" = true ]; then
        case "$cmd" in
            stop|disable)
                systemctl_args+=("--force")
                ;;
        esac
    fi

    systemctl_args+=("$cmd")
    # daemon-reload doesn't take a unit name
    if [ "$cmd" != "daemon-reload" ]; then
        systemctl_args+=("$name")
    fi
    systemctl_args+=("${extra_args[@]}")

    # Run command, capture stderr, return exit code
    set +e
    local tmp_stderr
    tmp_stderr=$(mktemp)
    STDOUT=$("${systemctl_args[@]}" 2>"$tmp_stderr")
    local rc=$?
    STDERR=$(cat "$tmp_stderr")
    rm -f "$tmp_stderr"
    set -e

    RESULTS+=("$cmd $name: exit=$rc")
    return $rc
}

# ---- Helper: run read-only systemctl query ----
run_systemctl_query() {
    local cmd="$1"
    shift

    local query_args=()

    # Only use sudo for queries if we need it (read-only, but sometimes needs elevated access)
    if [ -n "$SUDO_PREFIX" ]; then
        query_args+=($SUDO_PREFIX)
    fi

    query_args+=("systemctl")

    # Add scope if not system
    if [ "$scope" = "user" ]; then
        query_args+=("--user")
    fi

    query_args+=("$cmd")
    query_args+=("$name")
    query_args+=("$@")

    set +e
    "${query_args[@]}" 2>/dev/null
    local rc=$?
    set -e
    return $rc
}

# ---- Check unit active state ----
is_active() {
    run_systemctl_query is-active >/dev/null 2>&1
    return $?
}

# ---- Check unit enabled state ----
is_enabled() {
    run_systemctl_query is-enabled >/dev/null 2>&1
    return $?
}

# ---- Check unit masked state ----
is_masked() {
    run_systemctl_query is-enabled 2>&1 | grep -q "masked"
    return $?
}

# ======== MAIN ========

# ---- Parse arguments ----
for arg in "$@"; do
    case "${arg}" in
        *=*)
            key="${arg%%=*}"
            val="${arg#*=}"
            ;;
        *)
            continue
            ;;
    esac

    case "$key" in
        name)
            name="$val"
            ;;
        state)
            state="$val"
            ;;
        enabled)
            case "$val" in
                1|yes|true|True|TRUE) enabled="true" ;;
                *) enabled="false" ;;
            esac
            ;;
        daemon_reload)
            case "$val" in
                1|yes|true|True|TRUE) daemon_reload=true ;;
                *) daemon_reload=false ;;
            esac
            ;;
        masked)
            case "$val" in
                1|yes|true|True|TRUE) masked="true" ;;
                *) masked="false" ;;
            esac
            ;;
        scope)
            scope="$val"
            ;;
        no_block)
            case "$val" in
                1|yes|true|True|TRUE) no_block=true ;;
                *) no_block=false ;;
            esac
            ;;
        force)
            case "$val" in
                1|yes|true|True|TRUE) force=true ;;
                *) force=false ;;
            esac
            ;;
        use_sudo)
            use_sudo="$val"
            ;;
        *)
            MSG="Unknown parameter: $key"
            ;;
    esac
done

# ---- Validate required params (MUST be before detect_sudo due to set -u) ----
# daemon_reload is a global command that does not require a unit name.
if [ -z "$name" ] && [ "$daemon_reload" != true ]; then
    FAILED=true
    MSG="Unit name is required (name parameter)"
    emit_result
fi

# ---- Validate scope ----
if [ "$scope" != "system" ] && [ "$scope" != "user" ]; then
    FAILED=true
    MSG="scope must be 'system' or 'user', got '$scope'"
    emit_result
fi

# ---- Validate state ----
if [ -n "$state" ]; then
    case "$state" in
        started|stopped|restarted|reloaded|enabled|disabled|masked|unmasked)
            ;;
        *)
            FAILED=true
            MSG="Invalid state '$state'. Valid states: started, stopped, restarted, reloaded, enabled, disabled, masked, unmasked"
            emit_result
            ;;
    esac
fi

# ---- Detect sudo prefix ----
detect_sudo

# ---- Check if systemctl exists ----
if ! command_exists systemctl; then
    FAILED=true
    MSG="systemctl command not found on target system"
    emit_result
fi

# ---- Daemon reload ----
if [ "$daemon_reload" = true ]; then
    # daemon-reload is a global command - no unit name
    if run_systemctl "daemon-reload"; then
        CHANGED=true
        RESULTS+=("daemon-reload: executed")
    else
        FAILED=true
        MSG="daemon-reload failed: $STDERR"
        emit_result
    fi
fi

# ---- Mask/unmask ----
if [ -n "$masked" ]; then
    case "$masked" in
        "true")
            if ! is_masked; then
                if run_systemctl "mask"; then
                    CHANGED=true
                    RESULTS+=("masked unit")
                else
                    FAILED=true
                    MSG="mask failed: $STDERR"
                    emit_result
                fi
            else
                RESULTS+=("unit already masked — no change")
            fi
            ;;
        "false")
            if is_masked; then
                if run_systemctl "unmask"; then
                    CHANGED=true
                    RESULTS+=("unit unmasked")
                else
                    FAILED=true
                    MSG="unmask failed: $STDERR"
                    emit_result
                fi
            else
                RESULTS+=("unit already unmasked — no change")
            fi
            ;;
    esac
fi

# ---- Enable/disable ----
if [ -n "$enabled" ]; then
    case "$enabled" in
        "true")
            if ! is_enabled; then
                if run_systemctl "enable"; then
                    CHANGED=true
                    RESULTS+=("enabled unit")
                else
                    FAILED=true
                    MSG="enable failed: $STDERR"
                    emit_result
                fi
            else
                RESULTS+=("unit already enabled — no change")
            fi
            ;;
        "false")
            if is_enabled; then
                if run_systemctl "disable"; then
                    CHANGED=true
                    RESULTS+=("disabled unit")
                else
                    FAILED=true
                    MSG="disable failed: $STDERR"
                    emit_result
                fi
            else
                RESULTS+=("unit already disabled — no change")
            fi
            ;;
    esac
fi

# ---- State management ----
# States that require current state lookup
case "$state" in
    started|restarted|reloaded)
        if ! is_active; then
            state="started"  # Force start if not running, regardless of requested restart/reload
        fi
        ;;
    stopped)
        if is_active; then
            :  # State is correct; proceed
        else
            state=""  # Skip state handling if not running
            RESULTS+=("unit already stopped — no change")
        fi
        ;;
esac

# Execute state operations
case "$state" in
    started)
        if run_systemctl "start"; then
            CHANGED=true
            RESULTS+=("started unit")
        else
            FAILED=true
            MSG="start failed: $STDERR"
            emit_result
        fi
        ;;
    stopped)
        if run_systemctl "stop"; then
            CHANGED=true
            RESULTS+=("stopped unit")
        else
            FAILED=true
            MSG="stop failed: $STDERR"
            emit_result
        fi
        ;;
    restarted)
        if run_systemctl "restart"; then
            CHANGED=true
            RESULTS+=("restarted unit")
        else
            FAILED=true
            MSG="restart failed: $STDERR"
            emit_result
        fi
        ;;
    reloaded)
        if run_systemctl "reload"; then
            CHANGED=true
            RESULTS+=("reloaded unit")
        else
            FAILED=true
            MSG="reload failed: $STDERR"
            emit_result
        fi
        ;;
esac

# ---- Final result ----
if [ -z "$MSG" ]; then
    if [ "$CHANGED" = true ]; then
        MSG="Unit $name state changed successfully"
    else
        MSG="Unit $name is already in the desired state"
    fi
fi

emit_result
