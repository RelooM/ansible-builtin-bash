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
# Ansible-compatible pure-bash replacement for ansible.builtin.yum_repository
# Manages YUM/DNF repository definition files — pure Bash.
set -uo pipefail

REPO_DIR="${REPO_DIR:-/etc/yum.repos.d}"

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
description="$(_get description "$name")"
baseurl="$(_get baseurl "")"
gpgcheck="$(_get gpgcheck "1")"
enabled="$(_get enabled "1")"
state="$(_get state "present")"

if [ -z "$name" ]; then
  echo "{\"failed\":true,\"msg\":\"name is required\",\"rc\":0,\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  exit 1
fi

repo_file="$REPO_DIR/$name.repo"
tmp_file="$(mktemp)"

if [ "$state" = "absent" ]; then
  if [ -f "$repo_file" ]; then
    if ! run rm -f "$repo_file"; then
      echo "{\"failed\":true,\"msg\":\"cannot remove $repo_file (permission denied)\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
      exit 1
    fi
    echo "{\"changed\":true,\"repo\":\"$name\",\"state\":\"absent\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  else
    echo "{\"changed\":false,\"repo\":\"$name\",\"state\":\"absent\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  fi
  exit 0
fi

# Build desired file content (written as the connecting user into a temp file)
{
  echo "[$name]"
  echo "name=$description"
  [ -n "$baseurl" ] && echo "baseurl=$baseurl"
  echo "enabled=$enabled"
  echo "gpgcheck=$gpgcheck"
} > "$tmp_file"

if [ -f "$repo_file" ] && diff -q "$tmp_file" "$repo_file" >/dev/null 2>&1; then
  rm -f "$tmp_file"
  echo "{\"changed\":false,\"repo\":\"$name\",\"state\":\"present\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
else
  if ! ( run mkdir -p "$REPO_DIR" 2>/dev/null && run mv "$tmp_file" "$repo_file" ); then
    rm -f "$tmp_file"
    echo "{\"failed\":true,\"msg\":\"cannot write $repo_file (permission denied)\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
    exit 1
  fi
  echo "{\"changed\":true,\"repo\":\"$name\",\"state\":\"present\",\"path\":\"$repo_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
fi