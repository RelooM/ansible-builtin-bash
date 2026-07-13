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
# Ansible-compatible pure-bash replacement for ansible.builtin.known_hosts
# Manages SSH known_hosts entries — pure Bash.
set -uo pipefail

ARGS_JSON="${ARGS_JSON:-{}}"

_get() {
  local key="$1" def="$2" v=""
  v="$(printf '%s' "$ARGS_JSON" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E "s/.*:[[:space:]]*\"//; s/\"$//")"
  [ -z "$v" ] && printf '%s' "$def" || printf '%s' "$v"
}

name="$(_get name "")"
key="$(_get key "")"
state="$(_get state "present")"
path_file="$(_get path "${HOME:-/root}/.ssh/known_hosts")"
hash_host="$(_get hash_host "false")"

if [ -z "$name" ]; then
  echo "{\"failed\":true,\"msg\":\"name is required\",\"rc\":0,\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  exit 1
fi

mkdir -p "$(dirname "$path_file")" 2>/dev/null

# Build the entry line (optionally hashed host)
entry="$name $key"
if [ "$hash_host" = "true" ]; then
  hashed="$(printf '%s' "$name" | sha1sum | awk '{print $1}')"
  entry="|1|$(printf '%s' "$hashed" | base64 2>/dev/null || printf '%s' "$hashed")| $key"
fi

if [ "$state" = "absent" ]; then
  if grep -qF -- "$name" "$path_file" 2>/dev/null; then
    # grep -v exits 1 when ALL lines are filtered out (empty output); do NOT gate
    # mv on its exit status or the single-line file would never be truncated.
    grep -vF -- "$name" "$path_file" > "${path_file}.tmp" 2>/dev/null || true
    mv "${path_file}.tmp" "$path_file"
    echo "{\"changed\":true,\"name\":\"$name\",\"state\":\"absent\",\"path\":\"$path_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  else
    echo "{\"changed\":false,\"name\":\"$name\",\"state\":\"absent\",\"path\":\"$path_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  fi
else
  if [ -z "$key" ]; then
    echo "{\"failed\":true,\"msg\":\"key is required when state=present\",\"rc\":0,\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
    exit 1
  fi
  if grep -qF "$entry" "$path_file" 2>/dev/null; then
    echo "{\"changed\":false,\"name\":\"$name\",\"state\":\"present\",\"path\":\"$path_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  else
    printf '%s\n' "$entry" >> "$path_file"
    echo "{\"changed\":true,\"name\":\"$name\",\"state\":\"present\",\"path\":\"$path_file\",\"invocation\":{\"module_args\":{\"name\":\"$name\",\"state\":\"$state\"}}}"
  fi
fi