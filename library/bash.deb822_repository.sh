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
# ansible-module: bash.deb822_repository
# description: Manages Debian deb822-style .sources files in /etc/apt/sources.list.d/ — pure Bash.
#   Callable as `bash.deb822_repository:` in Ansible playbooks.
#   Calls sudo -n internally when running as non-root, respecting fine-grained
#   sudoers policies. No reliance on Ansible's become system.
# options:
#   name:
#     description: Repository name (used as filename stem for .sources file).
#     required: true
#     type: str
#   state:
#     description: Whether the repository should be present or absent.
#     required: false
#     default: "present"
#     choices: ["present", "absent"]
#     type: str
#   types:
#     description: List of repository types (deb, deb-src).
#     required: false
#     default: ["deb"]
#     type: list
#     elements: str
#   uris:
#     description: List of base URIs for the repository.
#     required: true
#     type: list
#     elements: str
#   suites:
#     description: List of suite names (e.g., noble, bookworm, stable).
#     required: true
#     type: list
#     elements: str
#   components:
#     description: List of components (e.g., main, contrib, non-free, non-free-firmware).
#     required: true
#     type: list
#     elements: str
#   signed_by:
#     description: Key source for verification — URL, file path, or inline keyblock.
#     required: false
#     type: str
#   architectures:
#     description: List of architectures (e.g., amd64, arm64).
#     required: false
#     type: list
#     elements: str
#   enabled:
#     description: Whether the repository is enabled.
#     required: false
#     default: true
#     type: bool
#   mode:
#     description: File mode for the .sources file (octal).
#     required: false
#     default: "0644"
#     type: str
#   acquire_by_hash:
#     description: Use by-hash for package downloads.
#     required: false
#     type: bool
#   acquire_check_date:
#     description: Check Release file date.
#     required: false
#     type: bool
#   acquire_check_valid_until:
#     description: Check Release file Valid-Until field.
#     required: false
#     type: bool
#   acquire_date_max_future:
#     description: Maximum future date tolerance for Release file (seconds).
#     required: false
#     type: int
#   acquire_pdiffs:
#     description: Use pdiffs for package index updates.
#     required: false
#     type: bool
#   acquire_languages:
#     description: Comma-separated list of languages to download (e.g., "en,de").
#     required: false
#     type: str
#   acquire_allow_insecure:
#     description: Allow insecure repositories.
#     required: false
#     type: bool
#   acquire_allow_weak:
#     description: Allow weak crypto in repositories.
#     required: false
#     type: bool
#   acquire_allow_downgrade_to_insecure:
#     description: Allow downgrade to insecure.
#     required: false
#     type: bool
#   use_sudo:
#     description: Whether to sudo the operations. 'auto' (default) sudo if not root.
#     required: false
#     default: "auto"
#     choices: ["auto", true, false]
#     type: str

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.deb822_repository"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""
RC=0

# ---- Default state vars (defaults) ----
name=""
state="present"
types=("deb")
uris=()
suites=()
components=()
signed_by=""
architectures=()
enabled=true
mode="0644"
acquire_by_hash=""
acquire_check_date=""
acquire_check_valid_until=""
acquire_date_max_future=""
acquire_pdiffs=""
acquire_languages=""
acquire_allow_insecure=""
acquire_allow_weak=""
acquire_allow_downgrade_to_insecure=""
use_sudo="auto"
SUDO_PREFIX=""
SOURCES_DIR="/etc/apt/sources.list.d"
KEYRINGS_DIR="/etc/apt/keyrings"

# ---- Helper: emit JSON result and exit ----
emit_result() {
  local out
  out="{"
  out+="\"changed\": $CHANGED,"
  out+="\"failed\": $FAILED,"
  out+="\"msg\": $(jq_safe "$MSG")"
  out+=",\"rc\": $RC"

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
  [ -n "$name" ] && { $first || out+=", "; first=false; out+="\"name\": $(jq_safe "$name")"; }
  [ -n "$state" ] && { $first || out+=", "; first=false; out+="\"state\": $(jq_safe "$state")"; }
  [ ${#types[@]} -gt 0 ] && { $first || out+=", "; first=false; out+="\"types\": $(jq_array "${types[@]}")"; }
  [ ${#uris[@]} -gt 0 ] && { $first || out+=", "; first=false; out+="\"uris\": $(jq_array "${uris[@]}")"; }
  [ ${#suites[@]} -gt 0 ] && { $first || out+=", "; first=false; out+="\"suites\": $(jq_array "${suites[@]}")"; }
  [ ${#components[@]} -gt 0 ] && { $first || out+=", "; first=false; out+="\"components\": $(jq_array "${components[@]}")"; }
  [ -n "$signed_by" ] && { $first || out+=", "; first=false; out+="\"signed_by\": $(jq_safe "$signed_by")"; }
  [ ${#architectures[@]} -gt 0 ] && { $first || out+=", "; first=false; out+="\"architectures\": $(jq_array "${architectures[@]}")"; }
  [ "$enabled" != "true" ] && { $first || out+=", "; first=false; out+="\"enabled\": $(jq_safe "$enabled")"; }
  [ "$mode" != "0644" ] && { $first || out+=", "; first=false; out+="\"mode\": $(jq_safe "$mode")"; }
  [ -n "$acquire_by_hash" ] && { $first || out+=", "; first=false; out+="\"acquire_by_hash\": $(jq_safe "$acquire_by_hash")"; }
  [ -n "$acquire_check_date" ] && { $first || out+=", "; first=false; out+="\"acquire_check_date\": $(jq_safe "$acquire_check_date")"; }
  [ -n "$acquire_check_valid_until" ] && { $first || out+=", "; first=false; out+="\"acquire_check_valid_until\": $(jq_safe "$acquire_check_valid_until")"; }
  [ -n "$acquire_date_max_future" ] && { $first || out+=", "; first=false; out+="\"acquire_date_max_future\": $(jq_safe "$acquire_date_max_future")"; }
  [ -n "$acquire_pdiffs" ] && { $first || out+=", "; first=false; out+="\"acquire_pdiffs\": $(jq_safe "$acquire_pdiffs")"; }
  [ -n "$acquire_languages" ] && { $first || out+=", "; first=false; out+="\"acquire_languages\": $(jq_safe "$acquire_languages")"; }
  [ -n "$acquire_allow_insecure" ] && { $first || out+=", "; first=false; out+="\"acquire_allow_insecure\": $(jq_safe "$acquire_allow_insecure")"; }
  [ -n "$acquire_allow_weak" ] && { $first || out+=", "; first=false; out+="\"acquire_allow_weak\": $(jq_safe "$acquire_allow_weak")"; }
  [ -n "$acquire_allow_downgrade_to_insecure" ] && { $first || out+=", "; first=false; out+="\"acquire_allow_downgrade_to_insecure\": $(jq_safe "$acquire_allow_downgrade_to_insecure")"; }
  [ "$use_sudo" != "auto" ] && { $first || out+=", "; first=false; out+="\"use_sudo\": $(jq_safe "$use_sudo")"; }
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

# ---- Helper: JSON-safe string quoting (Bash-native, no jq dependency) ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# ---- Helper: JSON array from bash array ----
jq_array() {
  local arr=("$@")
  local out="["
  local first=true
  for item in "${arr[@]}"; do
    $first || out+=", "
    first=false
    out+=$(jq_safe "$item")
  done
  out+="]"
  printf "%s" "$out"
}

# ---- Helper: check if a command exists ----
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ---- Helper: detect sudo prefix ----
detect_sudo() {
  SUDO_PREFIX=""
  if [ "$use_sudo" = "auto" ]; then
    if [ "$(id -u)" -ne 0 ]; then
      if command_exists sudo; then
        SUDO_PREFIX="sudo -n"
      else
        FAILED=true
        MSG="Running as non-root but sudo is not available. Install sudo or set 'use_sudo=false' if running as root."
        emit_result
      fi
    fi
  elif [ "$use_sudo" = "true" ]; then
    if command_exists sudo; then
      SUDO_PREFIX="sudo -n"
    else
      FAILED=true
      MSG="use_sudo=true but sudo is not installed."
      emit_result
    fi
  fi
}

# ---- Helper: run command with sudo prefix ----
run_cmd() {
  local cmd=("$@")
  local full_cmd=()
  
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    full_cmd+=($SUDO_PREFIX)
  fi
  full_cmd+=("${cmd[@]}")
  
  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$("${full_cmd[@]}" 2>"$tmp_stderr")
  RC=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  set -e
  return $RC
}

# ---- Helper: validate boolean parameter ----
validate_bool() {
  local val="$1"
  local param_name="$2"
  case "$val" in
    true|false) ;;
    *)
      FAILED=true
      MSG="$param_name must be 'true' or 'false'"
      emit_result
      ;;
  esac
}

# ---- Helper: validate state parameter ----
validate_state() {
  local val="$1"
  case "$val" in
    present|absent) ;;
    *)
      FAILED=true
      MSG="Invalid state: $val. Valid values: present, absent"
      emit_result
      ;;
  esac
}

# ---- Helper: validate use_sudo parameter ----
validate_use_sudo() {
  local val="$1"
  val=$(echo "$val" | tr '[:upper:]' '[:lower:]')
  case "$val" in
    auto|true|false) ;;
    *)
      FAILED=true
      MSG="Invalid use_sudo: $val. Valid values: auto, true, false"
      emit_result
      ;;
  esac
}

# ---- Helper: validate types parameter ----
validate_types() {
  local arr=("$@")
  for t in "${arr[@]}"; do
    case "$t" in
      deb|deb-src) ;;
      *)
        FAILED=true
        MSG="Invalid type: $t. Valid values: deb, deb-src"
        emit_result
        ;;
    esac
  done
}

# ---- Helper: validate mode parameter (octal) ----
validate_mode() {
  local val="$1"
  if [[ ! "$val" =~ ^0?[0-7]{3}$ ]]; then
    FAILED=true
    MSG="Invalid mode: $val. Must be octal (e.g., 0644, 644)"
    emit_result
  fi
}

# ---- Helper: parse boolean string to true/false ----
parse_bool() {
  local val="$1"
  case "${val,,}" in
    true|yes|on|1) echo "true" ;;
    false|no|off|0) echo "false" ;;
    *) echo "$val" ;;
  esac
}

# ---- Helper: parse a list-typed arg, tolerating ansible-core's Python-repr
#      form for YAML lists (e.g. "['deb', 'deb-src']", "['deb']", '"['deb']"',
#      or a plain "deb"). Strips ALL bracketing/quote chars, splits on comma,
#      trims whitespace, drops empties. Stores the result in the nameref array.
split_list() {
  local -n _sl_arr=$1
  local raw="$2"
  raw="$(printf '%s' "$raw" | tr -d "[]'\"")"
  if [ -z "$raw" ]; then _sl_arr=(); return; fi
  local _sl_tmp=() _sl_e
  IFS=',' read -ra _sl_tmp <<< "$raw"
  _sl_arr=()
  for _sl_e in "${_sl_tmp[@]}"; do
    _sl_e="$(printf '%s' "$_sl_e" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$_sl_e" ] && _sl_arr+=("$_sl_e")
  done
}

# ---- Helper: read and parse existing .sources file ----
parse_sources_file() {
  local file="$1"
  local -n out_types=$2
  local -n out_uris=$3
  local -n out_suites=$4
  local -n out_components=$5
  local -n out_signed_by=$6
  local -n out_architectures=$7
  local -n out_enabled=$8
  local -n out_acquire_by_hash=$9
  local -n out_acquire_check_date=${10}
  local -n out_acquire_check_valid_until=${11}
  local -n out_acquire_date_max_future=${12}
  local -n out_acquire_pdiffs=${13}
  local -n out_acquire_languages=${14}
  local -n out_acquire_allow_insecure=${15}
  local -n out_acquire_allow_weak=${16}
  local -n out_acquire_allow_downgrade_to_insecure=${17}

  # Clear output arrays/vars
  out_types=()
  out_uris=()
  out_suites=()
  out_components=()
  out_signed_by=""
  out_architectures=()
  out_enabled="true"
  out_acquire_by_hash=""
  out_acquire_check_date=""
  out_acquire_check_valid_until=""
  out_acquire_date_max_future=""
  out_acquire_pdiffs=""
  out_acquire_languages=""
  out_acquire_allow_insecure=""
  out_acquire_allow_weak=""
  out_acquire_allow_downgrade_to_insecure=""

  if [ ! -f "$file" ]; then
    return 1
  fi

  local current_types=()
  local current_uris=()
  local current_suites=()
  local current_components=()
  local current_signed_by=""
  local current_architectures=()
  local current_enabled="true"
  local current_acquire_by_hash=""
  local current_acquire_check_date=""
  local current_acquire_check_valid_until=""
  local current_acquire_date_max_future=""
  local current_acquire_pdiffs=""
  local current_acquire_languages=""
  local current_acquire_allow_insecure=""
  local current_acquire_allow_weak=""
  local current_acquire_allow_downgrade_to_insecure=""

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Parse key: value
    if [[ "$line" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      key=$(echo "$key" | xargs)  # trim whitespace
      value=$(echo "$value" | xargs)

      case "$key" in
        Types)
          IFS=' ' read -ra current_types <<< "$value"
          ;;
        URIs)
          IFS=' ' read -ra current_uris <<< "$value"
          ;;
        Suites)
          IFS=' ' read -ra current_suites <<< "$value"
          ;;
        Components)
          IFS=' ' read -ra current_components <<< "$value"
          ;;
        Signed-By)
          current_signed_by="$value"
          ;;
        Architectures)
          IFS=' ' read -ra current_architectures <<< "$value"
          ;;
        Enabled)
          current_enabled=$(parse_bool "$value")
          ;;
        "Acquire::By-Hash")
          current_acquire_by_hash=$(parse_bool "$value")
          ;;
        "Acquire::Check-Date")
          current_acquire_check_date=$(parse_bool "$value")
          ;;
        "Acquire::Check-Valid-Until")
          current_acquire_check_valid_until=$(parse_bool "$value")
          ;;
        "Acquire::Date-Max-Future")
          current_acquire_date_max_future="$value"
          ;;
        "Acquire::Pdiffs")
          current_acquire_pdiffs=$(parse_bool "$value")
          ;;
        "Acquire::Languages")
          current_acquire_languages="$value"
          ;;
        "Acquire::Allow-Insecure")
          current_acquire_allow_insecure=$(parse_bool "$value")
          ;;
        "Acquire::Allow-Weak")
          current_acquire_allow_weak=$(parse_bool "$value")
          ;;
        "Acquire::Allow-Downgrade-To-Insecure")
          current_acquire_allow_downgrade_to_insecure=$(parse_bool "$value")
          ;;
      esac
    fi
  done < "$file"

  # Assign to output variables
  out_types=("${current_types[@]}")
  out_uris=("${current_uris[@]}")
  out_suites=("${current_suites[@]}")
  out_components=("${current_components[@]}")
  out_signed_by="$current_signed_by"
  out_architectures=("${current_architectures[@]}")
  out_enabled="$current_enabled"
  out_acquire_by_hash="$current_acquire_by_hash"
  out_acquire_check_date="$current_acquire_check_date"
  out_acquire_check_valid_until="$current_acquire_check_valid_until"
  out_acquire_date_max_future="$current_acquire_date_max_future"
  out_acquire_pdiffs="$current_acquire_pdiffs"
  out_acquire_languages="$current_acquire_languages"
  out_acquire_allow_insecure="$current_acquire_allow_insecure"
  out_acquire_allow_weak="$current_acquire_allow_weak"
  out_acquire_allow_downgrade_to_insecure="$current_acquire_allow_downgrade_to_insecure"
}

# ---- Helper: compare arrays (order-independent) ----
arrays_equal() {
  local -n arr1=$1
  local -n arr2=$2

  if [ ${#arr1[@]} -ne ${#arr2[@]} ]; then
    return 1
  fi

  # Create temp files for sorting and comparing
  local tmp1 tmp1=$(mktemp)
  tmp2=$(mktemp)

  printf '%s\n' "${arr1[@]}" | sort > "$tmp1"
  printf '%s\n' "${arr2[@]}" | sort > "$tmp2"

  if diff -q "$tmp1" "$tmp2" >/dev/null; then
    rm -f "$tmp1" "$tmp2"
    return 0
  else
    rm -f "$tmp1" "$tmp2"
    return 1
  fi
}

# ---- Helper: build the .sources file content from current params ----
build_sources_content() {
  local content=""
  content+="Types: $(IFS=' '; echo "${types[*]}")"
  content+=$'\n'"URIs: $(IFS=' '; echo "${uris[*]}")"
  content+=$'\n'"Suites: $(IFS=' '; echo "${suites[*]}")"
  if [ ${#components[@]} -gt 0 ]; then
    content+=$'\n'"Components: $(IFS=' '; echo "${components[*]}")"
  fi
  if [ -n "$signed_by" ]; then
    content+=$'\n'"Signed-By: $signed_by"
  fi
  if [ ${#architectures[@]} -gt 0 ]; then
    content+=$'\n'"Architectures: $(IFS=' '; echo "${architectures[*]}")"
  fi
  if [ "$enabled" != "true" ]; then
    content+=$'\n'"Enabled: $enabled"
  fi
  [ -n "$acquire_by_hash" ] && content+=$'\n'"Acquire::By-Hash: $acquire_by_hash"
  [ -n "$acquire_check_date" ] && content+=$'\n'"Acquire::Check-Date: $acquire_check_date"
  [ -n "$acquire_check_valid_until" ] && content+=$'\n'"Acquire::Check-Valid-Until: $acquire_check_valid_until"
  [ -n "$acquire_date_max_future" ] && content+=$'\n'"Acquire::Date-Max-Future: $acquire_date_max_future"
  [ -n "$acquire_pdiffs" ] && content+=$'\n'"Acquire::Pdiffs: $acquire_pdiffs"
  [ -n "$acquire_languages" ] && content+=$'\n'"Acquire::Languages: $acquire_languages"
  [ -n "$acquire_allow_insecure" ] && content+=$'\n'"Acquire::Allow-Insecure: $acquire_allow_insecure"
  [ -n "$acquire_allow_weak" ] && content+=$'\n'"Acquire::Allow-Weak: $acquire_allow_weak"
  [ -n "$acquire_allow_downgrade_to_insecure" ] && content+=$'\n'"Acquire::Allow-Downgrade-To-Insecure: $acquire_allow_downgrade_to_insecure"
  printf '%s' "$content"
}

# ======== MAIN ========

# ---- Parse arguments ----
while [ $# -gt 0 ]; do
  case "$1" in
    name=*)
      name="${1#*=}"
      ;;
    state=*)
      state="${1#*=}"
      ;;
    types=*)
      split_list types "${1#*=}"
      ;;
    uris=*)
      split_list uris "${1#*=}"
      ;;
    suites=*)
      split_list suites "${1#*=}"
      ;;
    components=*)
      split_list components "${1#*=}"
      ;;
    signed_by=*)
      signed_by="${1#*=}"
      ;;
    architectures=*)
      split_list architectures "${1#*=}"
      ;;
    enabled=*)
      enabled="$(parse_bool "${1#*=}")"
      ;;
    mode=*)
      mode="${1#*=}"
      ;;
    acquire_by_hash=*)
      acquire_by_hash="$(parse_bool "${1#*=}")"
      ;;
    acquire_check_date=*)
      acquire_check_date="$(parse_bool "${1#*=}")"
      ;;
    acquire_check_valid_until=*)
      acquire_check_valid_until="$(parse_bool "${1#*=}")"
      ;;
    acquire_date_max_future=*)
      acquire_date_max_future="${1#*=}"
      ;;
    acquire_pdiffs=*)
      acquire_pdiffs="$(parse_bool "${1#*=}")"
      ;;
    acquire_languages=*)
      acquire_languages="${1#*=}"
      ;;
    acquire_allow_insecure=*)
      acquire_allow_insecure="$(parse_bool "${1#*=}")"
      ;;
    acquire_allow_weak=*)
      acquire_allow_weak="$(parse_bool "${1#*=}")"
      ;;
    acquire_allow_downgrade_to_insecure=*)
      acquire_allow_downgrade_to_insecure="$(parse_bool "${1#*=}")"
      ;;
    use_sudo=*)
      use_sudo="${1#*=}"
      ;;
    *)
      # Ignore unknown/ansible control keys
      ;;
  esac
  shift
done

# ---- Validate ----
if [ -z "$name" ]; then
  FAILED=true
  MSG="name is required"
  emit_result
fi

validate_state "$state"
validate_use_sudo "$use_sudo"
[ "$state" = "present" ] && validate_types "${types[@]}"
[ "$mode" != "0644" ] && validate_mode "$mode"

if [ "$state" = "present" ] && [ ${#uris[@]} -eq 0 ]; then
  FAILED=true
  MSG="uris is required when state=present"
  emit_result
fi
if [ "$state" = "present" ] && [ ${#suites[@]} -eq 0 ]; then
  FAILED=true
  MSG="suites is required when state=present"
  emit_result
fi

# ---- Detect sudo ----
detect_sudo

# ---- Determine file path ----
SOURCES_FILE="$SOURCES_DIR/${name}.sources"

if [ "$state" = "absent" ]; then
  if [ -f "$SOURCES_FILE" ]; then
    if run_cmd rm -f "$SOURCES_FILE"; then
      CHANGED=true
      RESULTS+=("Removed $SOURCES_FILE")
      MSG="Repository $name removed"
    else
      FAILED=true
      MSG="Failed to remove $SOURCES_FILE: $STDERR"
      emit_result
    fi
  else
    RESULTS+=("Repository $name already absent")
    MSG="Repository $name already absent"
  fi
  emit_result
fi

# ---- state=present ----
# Ensure directory exists
if [ ! -d "$SOURCES_DIR" ]; then
  if run_cmd mkdir -p "$SOURCES_DIR"; then
    CHANGED=true
    RESULTS+=("Created $SOURCES_DIR")
  else
    FAILED=true
    MSG="Failed to create $SOURCES_DIR: $STDERR"
    emit_result
  fi
fi

# Parse existing file if present
existing_types=()
existing_uris=()
existing_suites=()
existing_components=()
existing_signed_by=""
existing_architectures=()
existing_enabled="true"
existing_acquire_by_hash=""
existing_acquire_check_date=""
existing_acquire_check_valid_until=""
existing_acquire_date_max_future=""
existing_acquire_pdiffs=""
existing_acquire_languages=""
existing_acquire_allow_insecure=""
existing_acquire_allow_weak=""
existing_acquire_allow_downgrade_to_insecure=""

file_exists=false
if [ -f "$SOURCES_FILE" ]; then
  file_exists=true
  parse_sources_file "$SOURCES_FILE" \
    existing_types existing_uris existing_suites existing_components \
    existing_signed_by existing_architectures existing_enabled \
    existing_acquire_by_hash existing_acquire_check_date existing_acquire_check_valid_until \
    existing_acquire_date_max_future existing_acquire_pdiffs existing_acquire_languages \
    existing_acquire_allow_insecure existing_acquire_allow_weak existing_acquire_allow_downgrade_to_insecure
fi

# Compare desired vs existing
needs_change=false
if [ "$file_exists" = false ]; then
  needs_change=true
else
  if ! arrays_equal types existing_types; then needs_change=true; fi
  if ! arrays_equal uris existing_uris; then needs_change=true; fi
  if ! arrays_equal suites existing_suites; then needs_change=true; fi
  if ! arrays_equal components existing_components; then needs_change=true; fi
  if ! arrays_equal architectures existing_architectures; then needs_change=true; fi
  [ "$signed_by" != "$existing_signed_by" ] && needs_change=true
  [ "$enabled" != "$existing_enabled" ] && needs_change=true
  [ -n "$acquire_by_hash" ] && [ "$acquire_by_hash" != "$existing_acquire_by_hash" ] && needs_change=true
  [ -n "$acquire_check_date" ] && [ "$acquire_check_date" != "$existing_acquire_check_date" ] && needs_change=true
  [ -n "$acquire_check_valid_until" ] && [ "$acquire_check_valid_until" != "$existing_acquire_check_valid_until" ] && needs_change=true
  [ -n "$acquire_date_max_future" ] && [ "$acquire_date_max_future" != "$existing_acquire_date_max_future" ] && needs_change=true
  [ -n "$acquire_pdiffs" ] && [ "$acquire_pdiffs" != "$existing_acquire_pdiffs" ] && needs_change=true
  [ -n "$acquire_languages" ] && [ "$acquire_languages" != "$existing_acquire_languages" ] && needs_change=true
  [ -n "$acquire_allow_insecure" ] && [ "$acquire_allow_insecure" != "$existing_acquire_allow_insecure" ] && needs_change=true
  [ -n "$acquire_allow_weak" ] && [ "$acquire_allow_weak" != "$existing_acquire_allow_weak" ] && needs_change=true
  [ -n "$acquire_allow_downgrade_to_insecure" ] && [ "$acquire_allow_downgrade_to_insecure" != "$existing_acquire_allow_downgrade_to_insecure" ] && needs_change=true
fi

if [ "$needs_change" = true ]; then
  content=$(build_sources_content)
  # Write via temp file then move with sudo prefix if needed
  tmpf=$(mktemp)
  printf '%s\n' "$content" > "$tmpf"
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    if $SUDO_PREFIX cp "$tmpf" "$SOURCES_FILE" && $SUDO_PREFIX chmod "$mode" "$SOURCES_FILE"; then
      CHANGED=true
      RESULTS+=("Wrote $SOURCES_FILE")
    else
      FAILED=true
      MSG="Failed to write $SOURCES_FILE: $STDERR"
      rm -f "$tmpf"
      emit_result
    fi
  else
    if cp "$tmpf" "$SOURCES_FILE" && chmod "$mode" "$SOURCES_FILE"; then
      CHANGED=true
      RESULTS+=("Wrote $SOURCES_FILE")
    else
      FAILED=true
      MSG="Failed to write $SOURCES_FILE: $STDERR"
      rm -f "$tmpf"
      emit_result
    fi
  fi
  rm -f "$tmpf"
  MSG="Repository $name configured"
else
  RESULTS+=("Repository $name already in desired state")
  MSG="Repository $name already in desired state"
fi

emit_result
