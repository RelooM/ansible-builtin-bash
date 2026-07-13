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
# ansible-module: bash.group
# description: Manage groups on Linux systems
# options:
#   name:
#     description: Group name
#     required: true
#     type: str
#   state:
#     description: Whether the group should be present or absent
#     required: false
#     type: str
#     default: present
#     choices: [present, absent]
#   gid:
#     description: Group ID
#     required: false
#     type: int
#   system:
#     description: Create as a system group (only applies when creating the group or changing GID)
#     required: false
#     type: bool
#     default: false
#   local:
#     description: Force local group (not LDAP/NIS) - ignored (we only manage local)
#     required: false
#     type: bool
#     default: false
#   non_unique:
#     description: Allow duplicate GID (only applies when gid is specified)
#     required: false
#     type: bool
#     default: false
#   force:
#     description: Force removal of group
#     required: false
#     type: bool
#     default: false
#   use_sudo:
#     description: Whether to use sudo (auto: use if not root)
#     required: false
#     type: str
#     default: auto
#     choices: [auto, true, false]

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.group"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- Default state vars ----
name=""
state="present"
gid=""
system=false
local=false
non_unique=false
force=false
use_sudo="auto"

# ID ranges from /etc/login.defs (defaults if not found)
SYS_GID_MIN=100
SYS_GID_MAX=999
GID_MIN=1000
GID_MAX=60000

# ---- Helper: JSON-safe string quoting ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
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

  if [ -n "$STDOUT" ]; then
    out+=",\"stdout\": $(jq_safe "$STDOUT")"
  fi
  if [ -n "$STDERR" ]; then
    out+=",\"stderr\": $(jq_safe "$STDERR")"
  fi

  out+=",\"invocation\": {\"module_args\": {"
  local first=true
  # name
  [ -n "$name" ] && { $first || out+=", "; first=false; out+="\"name\": $(jq_safe "$name")"; }
  # state
  [ -n "$state" ] && { $first || out+=", "; first=false; out+="\"state\": $(jq_safe "$state")"; }
  # gid
  if [ -n "$gid" ]; then
    $first || out+=", "; first=false
    out+="\"gid\": $gid"
  fi
  # system
  $first || out+=", "; first=false
  if [ "$system" = true ]; then
    out+="\"system\": true"
  else
    out+="\"system\": false"
  fi
  # local
  $first || out+=", "; first=false
  if [ "$local" = true ]; then
    out+="\"local\": true"
  else
    out+="\"local\": false"
  fi
  # non_unique
  $first || out+=", "; first=false
  if [ "$non_unique" = true ]; then
    out+="\"non_unique\": true"
  else
    out+="\"non_unique\": false"
  fi
  # force
  $first || out+=", "; first=false
  if [ "$force" = true ]; then
    out+="\"force\": true"
  else
    out+="\"force\": false"
  fi
  # use_sudo
  $first || out+=", "; first=false
  out+="\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

# ---- Helper: check command existence ----
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ---- Helper: detect sudo prefix ----
detect_sudo() {
  SUDO_PREFIX=""
  case "$use_sudo" in
    auto)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then
          SUDO_PREFIX="sudo -n"
        else
          FAILED=true
          MSG="Running as non-root but sudo is not available."
          emit_result
        fi
      fi
      ;;
    true)
      if command_exists sudo; then
        SUDO_PREFIX="sudo -n"
      else
        FAILED=true
        MSG="use_sudo=true but sudo is not installed."
        emit_result
      fi
      ;;
  esac
  # use_sudo=false → SUDO_PREFIX stays empty
}

# ---- Helper: run command with capture ----
run_cmd() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    args+=($SUDO_PREFIX)
  fi
  args+=("$@")

  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$( "${args[@]}" 2>"$tmp_stderr" )
  local rc=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  set -e
  echo "$rc"
}

# ---- Helper: read-only query (no sudo unless forced) ----
run_query() {
  local args=()
  # Read-only queries typically don't need sudo, but use it if we already have it
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    args+=($SUDO_PREFIX)
  fi
  args+=("$@")

  set +e
  "${args[@]}" 2>/dev/null
  local rc=$?
  set -e
  return $rc
}

# ---- Helper: boolean parsing ----
bool_true() {
  case "$1" in
    1|yes|true|True|TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- Helper: read ID ranges from /etc/login.defs ----
get_id_ranges() {
  local line
  while IFS= read -r line; do
    case "$line" in
      SYS_GID_MIN*)
        SYS_GID_MIN=$(echo "$line" | awk '{print $2}')
        ;;
      SYS_GID_MAX*)
        SYS_GID_MAX=$(echo "$line" | awk '{print $2}')
        ;;
      GID_MIN*)
        GID_MIN=$(echo "$line" | awk '{print $2}')
        ;;
      GID_MAX*)
        GID_MAX=$(echo "$line" | awk '{print $2}')
        ;;
    esac
  done < /etc/login.defs
}

# Get ID ranges (if file exists)
if [ -f /etc/login.defs ]; then
  get_id_ranges
fi

# ---- Helper: check if a gid is in system range ----
is_system_gid() {
  local gid="$1"
  [ "$gid" -ge "$SYS_GID_MIN" ] && [ "$gid" -le "$SYS_GID_MAX" ]
}

# ---- Argument parsing ----
PARSE_ERROR=""
for arg in "$@"; do
  case "${arg}" in
    *=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      ;;
    *) continue ;;
  esac
  case "$key" in
    name)
      name="$val"
      ;;
    state)
      state="$val"
      ;;
    gid)
      gid="$val"
      ;;
    system)
      if bool_true "$val"; then
        system=true
      else
        system=false
      fi
      ;;
    local)
      if bool_true "$val"; then
        local=true
      else
        local=false
      fi
      ;;
    non_unique)
      if bool_true "$val"; then
        non_unique=true
      else
        non_unique=false
      fi
      ;;
    force)
      if bool_true "$val"; then
        force=true
      else
        force=false
      fi
      ;;
    use_sudo)
      use_sudo="$val"
      ;;
    *)
      PARSE_ERROR="${PARSE_ERROR}Unknown parameter: $key; "
      ;;
  esac
done

# ---- Detect sudo ----
detect_sudo

# ---- Validate parameters ----
[ -n "$name" ] || { FAILED=true; MSG="Missing required argument: name"; emit_result; }
[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

# Validate state
case "$state" in
  present|absent) ;;
  *)
    FAILED=true; MSG="Invalid state: $state. Valid values: present, absent"
    emit_result
    ;;
esac

# Validate gid if provided
if [ -n "$gid" ]; then
  case "$gid" in
    ''|*[!0-9]*)
      FAILED=true; MSG="GID must be a non-negative integer"
      emit_result
      ;;
  esac
fi

# ---- MAIN logic ----
# Get current GID if group exists (suppress output, we only need exit code)
if run_query getent group "$name" >/dev/null 2>&1; then
  # Group exists, get its GID
  CURRENT_GID=$(getent group "$name" | cut -d: -f3)
else
  # Group does not exist
  CURRENT_GID=""
fi

case "$state" in
  present)
    if [ -z "$CURRENT_GID" ]; then
      # Group does not exist, create it
      CMD=("groupadd")
      [ "$system" = true ] && CMD+=(-r)
      [ -n "$gid" ] && {
        # If system=true and gid is specified, check that gid is in system range
        if [ "$system" = true ]; then
          if ! is_system_gid "$gid"; then
            FAILED=true
            MSG="GID $gid is not in the system GID range [$SYS_GID_MIN-$SYS_GID_MAX]"
            emit_result
          fi
        fi
        CMD+=(-g "$gid")
      }
      [ "$local" = true ] && : # groupadd doesn't have a direct --local flag (ignored)
      [ "$non_unique" = true ] && CMD+=(-o)
      CMD+=("$name")

      rc=$(run_cmd "${CMD[@]}")
      if [ "$rc" -eq 0 ]; then
        CHANGED=true
        RESULTS+=("Created group $name")
      else
        FAILED=true
        MSG="Failed to create group $name (exit code $rc)"
        emit_result
      fi
    else
      # Group exists, check if we need to modify it
      NEEDS_MOD=false
      MOD_CMD=("groupmod")

      # Check GID
      if [ -n "$gid" ] && [ "$gid" -ne "$CURRENT_GID" ]; then
        MOD_CMD+=(-g "$gid")
        NEEDS_MOD=true
        # If we are changing GID, check system flag compatibility
        if [ "$system" = true ]; then
          if ! is_system_gid "$gid"; then
            FAILED=true
            MSG="GID $gid is not in the system GID range [$SYS_GID_MIN-$SYS_GID_MAX]"
            emit_result
          fi
        fi
        # If we are changing GID, handle non_unique flag
        if [ "$non_unique" = true ]; then
          MOD_CMD+=(-o)
        fi
      fi

      # If GID is not changing, we cannot change system or non_unique attributes
      if [ -z "$gid" ] || [ "$gid" -eq "$CURRENT_GID" ]; then
        # If system=true is requested but the group is not already a system group, we cannot change it without changing GID
        if [ "$system" = true ]; then
          if ! is_system_gid "$CURRENT_GID"; then
            FAILED=true
            MSG="Cannot make existing group a system group without changing its GID (current GID=$CURRENT_GID is not in system range [$SYS_GID_MIN-$SYS_GID_MAX])"
            emit_result
          fi
          # If it is already a system group, nothing to do
        fi
        # non_unique flag is irrelevant if we are not changing GID (cannot toggle without GID change)
        # local flag is ignored
      fi

      if [ "$NEEDS_MOD" = true ]; then
        MOD_CMD+=("$name")
        rc=$(run_cmd "${MOD_CMD[@]}")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Modified group $name")
        elif [ "$rc" -eq 6 ]; then
          # groupmod returns 6 if the group already has the requested attribute
          # This means no change was needed
          RESULTS+=("Group $name already in desired state")
        else
          FAILED=true
          MSG="Failed to modify group $name (exit code $rc)"
          emit_result
        fi
      else
        RESULTS+=("Group $name already in desired state")
      fi
    fi
    ;;
  absent)
    if [ -n "$CURRENT_GID" ]; then
      # Group exists, remove it
      CMD=("groupdel")
      [ "$force" = true ] && CMD+=(-f)
      CMD+=("$name")

      rc=$(run_cmd "${CMD[@]}")
      if [ "$rc" -eq 0 ]; then
        CHANGED=true
        RESULTS+=("Removed group $name")
      else
        FAILED=true
        MSG="Failed to remove group $name (exit code $rc)"
        emit_result
      fi
    else
      RESULTS+=("Group $name does not exist")
    fi
    ;;
  *)
    FAILED=true
    MSG="Invalid state: $state"
    emit_result
    ;;
esac

# ---- Final result ----
if [ "$FAILED" = false ]; then
  if [ "$CHANGED" = true ]; then
    MSG="Group operation(s) completed successfully"
  else
    MSG="Nothing to do — group is already in desired state"
  fi
fi

emit_result