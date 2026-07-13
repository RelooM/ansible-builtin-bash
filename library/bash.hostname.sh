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
# Ansible-compatible pure-bash replacement for ansible.builtin.hostname
# Sets the system hostname persistently and live.
set -uo pipefail

ARGS_JSON="${ARGS_JSON:-{}}"

_get() {
  local key="$1" def="$2" v=""
  v="$(printf '%s' "$ARGS_JSON" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E "s/.*:[[:space:]]*\"//; s/\"$//")"
  [ -z "$v" ] && printf '%s' "$def" || printf '%s' "$v"
}

# sudo-aware: honour use_sudo. Default 'auto' escalates via sudo -n when the
# connecting user is non-root (no Ansible become needed — matches rest of repo).
case "${USE_SUDO:-$(_get use_sudo auto)}" in
  no|false|0) USE_SUDO=no ;;
  yes|true|1) USE_SUDO=yes ;;
  *)          USE_SUDO=auto ;;
esac

run() {
  if [[ "$USE_SUDO" == "no" ]]; then
    "$@"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    if sudo -n true 2>/dev/null; then sudo -n "$@"; else sudo "$@"; fi
  fi
}

name="$(_get name "")"

if [ -z "$name" ]; then
  echo "{\"failed\":true,\"msg\":\"'name' is required\"}"
  exit 1
fi

# Determine current effective hostname across工具.
current="$(hostnamectl --static 2>/dev/null)"
[ -z "$current" ] && current="$(hostname 2>/dev/null)"
[ -z "$current" ] && current="$(cat /etc/hostname 2>/dev/null)"

changed=true
if [ "$current" = "$name" ]; then
  changed=false
else
  if ! run hostnamectl set-hostname "$name" 2>/dev/null; then
    if ! run hostname "$name" 2>/dev/null; then
      echo "{\"failed\":true,\"msg\":\"cannot set live hostname (hostnamectl and hostname both failed)\",\"invocation\":{\"args\":{\"name\":\"$name\"}}}"
      exit 1
    fi
  fi
  if ! printf '%s\n' "$name" | run tee /etc/hostname >/dev/null; then
    echo "{\"failed\":true,\"msg\":\"cannot write /etc/hostname (permission denied)\",\"invocation\":{\"args\":{\"name\":\"$name\"}}}"
    exit 1
  fi
fi

echo "{\"changed\":$changed,\"name\":\"$name\",\"previous\":\"$current\",\"invocation\":{\"args\":{\"name\":\"$name\"}}}"