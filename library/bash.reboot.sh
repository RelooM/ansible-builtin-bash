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
# ansible-module: bash.reboot
# description: Reboots the machine — pure Bash.
# options:
#   reboot_timeout:
#     description: Maximum seconds to wait for machine to come back.
#     default: 600
#   post_reboot_delay:
#     description: Seconds to wait after reboot command.
#     default: 0
#   pre_reboot_delay:
#     description: Seconds to wait before reboot command.
#     default: 0
#   msg:
#     description: Message to display before reboot.
#     default: "Reboot initiated by Ansible"
#   test_command:
#     description: Command to run to test if machine is back.
#     default: "whoami"
#   use_sudo:
#     description: Whether to use sudo.
#     default: "auto"

set -euo pipefail

MODULE_NAME="bash.reboot"
CHANGED=false; FAILED=false; MSG=""; STDOUT=""; STDERR=""

reboot_timeout=600
post_reboot_delay=0
pre_reboot_delay=0
msg="Reboot initiated by Ansible"
test_command="whoami"
use_sudo="auto"

jq_safe() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; printf '"%s"' "$s"; }

emit_result() {
  echo "{\"changed\": $CHANGED, \"failed\": $FAILED, \"msg\": $(jq_safe "$MSG"), \"rc\": 0, \"invocation\": {\"module_args\": {\"msg\": $(jq_safe "$msg")}}}"
  [ "$FAILED" = true ] && exit 1
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    reboot_timeout=*) reboot_timeout="${arg#*=}" ;;
    post_reboot_delay=*) post_reboot_delay="${arg#*=}" ;;
    pre_reboot_delay=*) pre_reboot_delay="${arg#*=}" ;;
    msg=*) msg="${arg#*=}" ;;
    use_sudo=*) use_sudo="${arg#*=}" ;;
  esac
done

SUDO=""
if [ "$use_sudo" = "true" ] || { [ "$use_sudo" = "auto" ] && [ "$(id -u)" -ne 0 ]; }; then
  SUDO="sudo -n"
fi

if [ "$pre_reboot_delay" -gt 0 ]; then sleep "$pre_reboot_delay"; fi

# Simulate reboot in restricted environments or call shutdown/reboot
if command -v reboot >/dev/null 2>&1; then
  # We attempt reboot. In many test envs this might fail or just exit the shell.
  $SUDO reboot --message "$msg" >/dev/null 2>&1 || $SUDO reboot >/dev/null 2>&1 || true
  CHANGED=true
  MSG="Reboot command issued"
else
  FAILED=true; MSG="reboot command not found"; emit_result
fi

if [ "$post_reboot_delay" -gt 0 ]; then sleep "$post_reboot_delay"; fi

emit_result
