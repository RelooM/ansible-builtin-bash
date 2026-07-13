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
# ansible-module: bash.subscription_manager
# description: Manage Red Hat Subscription Manager registration — pure Bash
#   replacement for community.general.redhat_subscription. Registers/unregisters
#   with RHSM, optionally attaches pools, sets release, and enables repos. Calls
#   sudo -n internally when running as non-root. No reliance on Ansible become.
# options:
#   state:
#     description: present = register (and optionally attach/repos/release), absent = unregister.
#     required: false
#     type: str
#     default: "present"
#     choices: ["present", "absent"]
#   username:
#     description: RHSM account username (for password-based registration).
#     required: false
#     type: str
#   password:
#     description: RHSM account password.
#     required: false
#     type: str
#   activationkey:
#     description: Activation key (used with org_id instead of user/pass).
#     required: false
#     type: str
#   org_id:
#     description: Organization ID (required with activationkey, optional otherwise).
#     required: false
#     type: str
#   pool:
#     description: Pool ID to attach (comma-separated list supported).
#     required: false
#     type: str
#   auto_attach:
#     description: Auto-attach compatible subscriptions.
#     required: false
#     type: bool
#     default: false
#   release:
#     description: Set the OS release version (e.g. 9.2).
#     required: false
#     type: str
#   repos:
#     description: Comma-separated list of repo ids to enable.
#     required: false
#     type: str
#   server_hostname:
#     description: Subscription server hostname.
#     required: false
#     type: str
#   force_register:
#     description: Re-register even if already registered.
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

MODULE_NAME="bash.subscription_manager"
CHANGED=false
FAILED=false
MSG=""
RC=0
STATE="present"
USERNAME=""
PASSWORD=""
ACTIVATIONKEY=""
ORG_ID=""
POOL=""
AUTO_ATTACH=false
RELEASE=""
REPOS=""
SERVER_HOSTNAME=""
FORCE_REGISTER=false
USE_SUDO="auto"

# ---- Helpers (shared boilerplate, no jq dependency) ----
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

run_cmd() {
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
  out+="\"state\": $(jq_safe "$STATE")"
  out+=",\"username\": $(jq_safe "$USERNAME")"
  out+=",\"activationkey\": $(jq_safe "$ACTIVATIONKEY")"
  out+=",\"org_id\": $(jq_safe "$ORG_ID")"
  out+=",\"pool\": $(jq_safe "$POOL")"
  out+=",\"auto_attach\": $AUTO_ATTACH"
  out+=",\"release\": $(jq_safe "$RELEASE")"
  out+=",\"repos\": $(jq_safe "$REPOS")"
  out+=",\"server_hostname\": $(jq_safe "$SERVER_HOSTNAME")"
  out+=",\"force_register\": $FORCE_REGISTER"
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
    state) STATE="$val" ;;
    username) USERNAME="$val" ;;
    password) PASSWORD="$val" ;;
    activationkey) ACTIVATIONKEY="$val" ;;
    org_id) ORG_ID="$val" ;;
    pool) POOL="$val" ;;
    auto_attach)
      case "$val" in 1|yes|true|True|TRUE) AUTO_ATTACH=true ;; *) AUTO_ATTACH=false ;; esac ;;
    release) RELEASE="$val" ;;
    repos) REPOS="$val" ;;
    server_hostname) SERVER_HOSTNAME="$val" ;;
    force_register)
      case "$val" in 1|yes|true|True|TRUE) FORCE_REGISTER=true ;; *) FORCE_REGISTER=false ;; esac ;;
    use_sudo) USE_SUDO="$val" ;;
  esac
done

detect_sudo

case "$STATE" in
  present|absent) ;;
  *) FAILED=true; MSG="Invalid state '$STATE' (expected present|absent)."; emit_result ;;
esac

if ! command_exists subscription-manager; then
  FAILED=true; MSG="The 'subscription-manager' command is required but not found on this system."; emit_result
fi

# Is the system currently registered?
registered=false
if $SUDO_PREFIX subscription-manager status >/dev/null 2>&1; then
  registered=true
fi

# =====================================================================
# State: absent — unregister
# =====================================================================
if [ "$STATE" = "absent" ]; then
  if [ "$registered" = "false" ]; then
    CHANGED=false; MSG="System already unregistered."; emit_result
  fi
  run_cmd $SUDO_PREFIX subscription-manager unregister
  if [ "$RUN_RC" -ne 0 ]; then
    FAILED=true; RC="$RUN_RC"; MSG="subscription-manager unregister failed: $RUN_STDOUT"; emit_result
  fi
  CHANGED=true; MSG="System unregistered from RHSM."; emit_result
fi

# =====================================================================
# State: present — register (+ optional attach/repos/release)
# =====================================================================
if [ "$registered" = "true" ] && [ "$FORCE_REGISTER" = "false" ]; then
  CHANGED=false; MSG="System already registered."
  # Still reconcile release/repos if requested.
  changed_any=false
  if [ -n "$RELEASE" ]; then
    cur_rel="$($SUDO_PREFIX subscription-manager release --show 2>/dev/null | sed -n 's/.*:[[:space:]]*//p')"
    if [ "$cur_rel" != "$RELEASE" ]; then
      $SUDO_PREFIX subscription-manager release --set="$RELEASE" >/dev/null 2>&1 && changed_any=true
    fi
  fi
  if [ -n "$REPOS" ]; then
    IFS=',' read -ra repo_list <<< "$REPOS"
    for r in "${repo_list[@]}"; do
      r="$(printf '%s' "$r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$r" ] && continue
      cur="$($SUDO_PREFIX subscription-manager repos --list-enabled 2>/dev/null | awk -F': ' "/Repo ID:/{print \$2}")"
      if ! printf '%s\n' "$cur" | grep -qx "$r"; then
        $SUDO_PREFIX subscription-manager repos --enable="$r" >/dev/null 2>&1 && changed_any=true
      fi
    done
  fi
  [ "$changed_any" = "true" ] && CHANGED=true
  emit_result
fi

# Decide credentials form: activationkey+org OR username+password.
if [ -n "$ACTIVATIONKEY" ]; then
  if [ -z "$ORG_ID" ]; then
    FAILED=true; MSG="org_id is required when using activationkey."; emit_result
  fi
  reg_args=(--activationkey="$ACTIVATIONKEY" --org="$ORG_ID")
  [ -n "$SERVER_HOSTNAME" ] && reg_args+=(--serverurl="https://$SERVER_HOSTNAME/subscription")
  [ "$AUTO_ATTACH" = "true" ] && reg_args+=(--auto-attach)
else
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    FAILED=true; MSG="username and password are required unless activationkey is supplied."; emit_result
  fi
  reg_args=(--username="$USERNAME" --password="$PASSWORD")
  [ -n "$ORG_ID" ] && reg_args+=(--org="$ORG_ID")
  [ -n "$SERVER_HOSTNAME" ] && reg_args+=(--serverurl="https://$SERVER_HOSTNAME/subscription")
  [ "$AUTO_ATTACH" = "true" ] && reg_args+=(--auto-attach)
fi

if [ "$FORCE_REGISTER" = "true" ] && [ "$registered" = "true" ]; then
  $SUDO_PREFIX subscription-manager unregister >/dev/null 2>&1 || true
fi

run_cmd $SUDO_PREFIX subscription-manager register "${reg_args[@]}"
if [ "$RUN_RC" -ne 0 ]; then
  FAILED=true; RC="$RUN_RC"; MSG="subscription-manager register failed: $RUN_STDOUT"; emit_result
fi
CHANGED=true; MSG="System registered with RHSM."

# Attach a specific pool if requested.
if [ -n "$POOL" ]; then
  IFS=',' read -ra pool_list <<< "$POOL"
  for p in "${pool_list[@]}"; do
    p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$p" ] && continue
    $SUDO_PREFIX subscription-manager attach --pool="$p" >/dev/null 2>&1 || true
  done
fi

# Set release if requested.
if [ -n "$RELEASE" ]; then
  $SUDO_PREFIX subscription-manager release --set="$RELEASE" >/dev/null 2>&1 || true
fi

# Enable repos if requested.
if [ -n "$REPOS" ]; then
  IFS=',' read -ra repo_list <<< "$REPOS"
  for r in "${repo_list[@]}"; do
    r="$(printf '%s' "$r" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$r" ] && continue
    $SUDO_PREFIX subscription-manager repos --enable="$r" >/dev/null 2>&1 || true
  done
fi

emit_result
