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
# library/bash.sysctl.sh
#
# Pure-Bash replacement for ansible.builtin.sysctl.
# Conventions (Phase 2+): pure-bash JSON arg parse (no jq), sudo-aware `run`,
# invocation.args echo, namespaced JSON output.
#
# Params:
#   name         (str, required)  sysctl key, e.g. net.ipv4.ip_forward
#   value        (str)            desired value (required when state=present)
#   state        (present|absent) default present
#   sysctl_set   (true|false)     apply live via `sysctl -w` (default true)
#   sysctl_file  (path)           persistence file (default /etc/sysctl.d/99-ansible.conf)
#   reload       (true|false)     run `sysctl -p <file>` after change (default false)
set -uo pipefail

run() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# Canonical positional arg parser (matches all other bash.* modules): name=val ...
name=""
value=""
state="present"
sysctl_set="true"
sysctl_file="/etc/sysctl.d/99-ansible.conf"
reload="false"
for arg in "$@"; do
  case "$arg" in
    name=*)        name="${arg#name=}" ;;
    value=*)       value="${arg#value=}" ;;
    state=*)       state="${arg#state=}" ;;
    sysctl_set=*)  sysctl_set="${arg#sysctl_set=}" ;;
    sysctl_file=*) sysctl_file="${arg#sysctl_file=}" ;;
    reload=*)      reload="${arg#reload=}" ;;
  esac
done

if [[ -z "$name" ]]; then
  printf '{"failed":true,"msg":"name is required"}'; exit 1
fi
if [[ "$state" == "present" && -z "$value" ]]; then
  printf '{"failed":true,"msg":"value is required when state=present"}'; exit 1
fi

changed=false

# current live value (best-effort)
current=""
if command -v sysctl >/dev/null 2>&1; then
  current="$(sysctl -n "$name" 2>/dev/null || true)"
fi

if [[ "$state" == "absent" ]]; then
  if [[ -f "$sysctl_file" ]] && grep -qE "^[[:space:]]*#?[[:space:]]*$name[[:space:]]*=" "$sysctl_file"; then
    run mkdir -p "$(dirname "$sysctl_file")"
    run sed -i -E "/^[[:space:]]*#?[[:space:]]*$name[[:space:]]*=/d" "$sysctl_file"
    changed=true
  fi
else
  run mkdir -p "$(dirname "$sysctl_file")"
  if [[ ! -f "$sysctl_file" ]]; then
    printf '# Managed by bash.sysctl\n' | run tee "$sysctl_file" >/dev/null
    changed=true
  fi
  if ! grep -qxE "[[:space:]]*$name[[:space:]]*=[[:space:]]*$value[[:space:]]*\$" "$sysctl_file"; then
    run sed -i -E "/^[[:space:]]*#?[[:space:]]*$name[[:space:]]*=/d" "$sysctl_file"
    printf '%s = %s\n' "$name" "$value" | run tee -a "$sysctl_file" >/dev/null
    changed=true
  fi
  if [[ "$sysctl_set" == "true" && "$current" != "$value" ]]; then
    if command -v sysctl >/dev/null 2>&1; then
      set +e
      run sysctl -w "$name=$value" >/dev/null 2>&1
      sysctl_rc=$?
      set -e
      # Verify the live value actually took effect; only count as changed if it did.
      live_now="$(sysctl -n "$name" 2>/dev/null || true)"
      if [[ "$sysctl_rc" -eq 0 && "$live_now" == "$value" ]]; then
        changed=true
      else
        printf '{"failed":true,"msg":"Failed to apply sysctl %s=%s live (rc=%s, current=%s)"}' \
          "$name" "$value" "$sysctl_rc" "$live_now"
        exit 1
      fi
    else
      # No sysctl binary on the host — can't apply live; surface instead of
      # silently claiming a change that never happened.
      printf '{"failed":true,"msg":"sysctl binary not found; cannot apply %s=%s live (set sysctl_set=false to persist to file only)"}' \
        "$name" "$value"
      exit 1
    fi
  fi
fi

if [[ "$reload" == "true" ]]; then
  run sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
fi

printf '{"changed":%s,"name":"%s","value":"%s","state":"%s","sysctl_set":"%s","invocation":{"args":{"name":"%s","value":"%s","state":"%s","sysctl_set":"%s","sysctl_file":"%s","reload":"%s"}}}' \
  "$changed" "$name" "$value" "$state" "$sysctl_set" \
  "$name" "$value" "$state" "$sysctl_set" "$sysctl_file" "$reload"
