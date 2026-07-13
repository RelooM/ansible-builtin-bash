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
# ansible-module: bash.iptables
# description: Manages iptables rules — pure Bash.
# options:
#   table:
#     description: The iptables table to operate on.
#     required: false
#     type: str
#     default: "filter"
#     choices: ["filter", "nat", "mangle", "raw", "security"]
#   chain:
#     description: The chain to operate on.
#     required: true
#     type: str
#   rule_num:
#     description: The rule number to delete/insert.
#     required: false
#     type: int
#   action:
#     description: Whether to insert (-I) or append (-A) a rule.
#     required: false
#     type: str
#     default: "append"
#     choices: ["insert", "append"]
#   protocol:
#     description: The protocol to match.
#     required: false
#     type: str
#   source:
#     description: Source specification (address[/mask]).
#     required: false
#     type: str
#   destination:
#     description: Destination specification (address[/mask]).
#     required: false
#     type: str
#   jump:
#     description: Target of the rule (e.g., ACCEPT, DROP, REJECT, RETURN).
#     required: false
#     type: str
#   in_interface:
#     description: Name of the interface via which a packet was received.
#     required: false
#     type: str
#   out_interface:
#     description: Name of the interface via which a packet is going to be sent.
#     required: false
#     type: str
#   fragment:
#     description: Match second and further fragments of fragmented packets.
#     required: false
#     type: bool
#     default: false
#   gateway:
#     description: The gateway to use for the rule.
#     required: false
#     type: str
#   set_counters:
#     description: Set packet and byte counters during insert/delete/append.
#     required: false
#     type: str
#   destination_port:
#     description: Destination port or port range to match.
#     required: false
#     type: str
#   source_port:
#     description: Source port or port range to match.
#     required: false
#     type: str
#   to_ports:
#     description: Destination port range for REDIRECT, DNAT, SNAT, and MASQUERADE.
#     required: false
#     type: str
#   to_source:
#     description: Source address for SNAT, MASQUERADE, REDIRECT.
#     required: false
#     type: str
#   to_destination:
#     description: Destination address for DNAT, SNAT, MASQUERADE, REDIRECT.
#     required: false
#     type: str
#   state:
#     description: Whether the rule should be present or absent.
#     required: true
#     type: str
#     choices: ["present", "absent"]
#   wait:
#     description: Maximum seconds to wait for xtables lock.
#     required: false
#     type: int
#   use_sudo:
#     description: Whether to sudo the operations. 'auto' (default) sudo if not root.
#     required: false
#     type: str
#     default: "auto"
#     choices: ["auto", true, false]

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.iptables"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- Defaults ----
table="filter"
chain=""
rule_num=""
action="append"
protocol=""
source=""
destination=""
jump=""
in_interface=""
out_interface=""
fragment=false
gateway=""
set_counters=""
destination_port=""
source_port=""
to_ports=""
to_source=""
to_destination=""
state=""
wait=""
use_sudo="auto"

# ---- Helper: JSON-safe string quoting ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\\n'/\\n}"
  s="${s//$'\\r'/\\r}"
  s="${s//$'\\t'/\\t}"
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

  if [ -n "$STDOUT" ]; then out+=",\"stdout\": $(jq_safe "$STDOUT")"; fi
  if [ -n "$STDERR" ]; then out+=",\"stderr\": $(jq_safe "$STDERR")"; fi

  out+=",\"invocation\": {\"module_args\": {"
  out+="\"table\": $(jq_safe "$table")"
  out+=",\"chain\": $(jq_safe "$chain")"
  out+=",\"rule_num\": $(jq_safe "$rule_num")"
  out+=",\"action\": $(jq_safe "$action")"
  out+=",\"protocol\": $(jq_safe "$protocol")"
  out+=",\"source\": $(jq_safe "$source")"
  out+=",\"destination\": $(jq_safe "$destination")"
  out+=",\"jump\": $(jq_safe "$jump")"
  out+=",\"in_interface\": $(jq_safe "$in_interface")"
  out+=",\"out_interface\": $(jq_safe "$out_interface")"
  out+=",\"fragment\": $(jq_safe "$fragment")"
  out+=",\"gateway\": $(jq_safe "$gateway")"
  out+=",\"set_counters\": $(jq_safe "$set_counters")"
  out+=",\"destination_port\": $(jq_safe "$destination_port")"
  out+=",\"source_port\": $(jq_safe "$source_port")"
  out+=",\"to_ports\": $(jq_safe "$to_ports")"
  out+=",\"to_source\": $(jq_safe "$to_source")"
  out+=",\"to_destination\": $(jq_safe "$to_destination")"
  out+=",\"state\": $(jq_safe "$state")"
  out+=",\"wait\": $(jq_safe "$wait")"
  out+=",\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_sudo() {
  SUDO_PREFIX=""
  case "$use_sudo" in
    auto)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then SUDO_PREFIX="sudo -n"; else FAILED=true; MSG="Running as non-root but sudo is not available."; emit_result; fi
      fi
      ;;
    true|True|TRUE|1|yes)
      if command_exists sudo; then SUDO_PREFIX="sudo -n"; else FAILED=true; MSG="use_sudo=true but sudo is not installed."; emit_result; fi
      ;;
  esac
}

run_cmd() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then args+=($SUDO_PREFIX); fi
  args+=("$@")
  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$("${args[@]}" 2>"$tmp_stderr")
  RC=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  return 0
}

# ---- Argument parsing ----
PARSE_ERROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    table=*) table="${1#*=}" ;;
    chain=*) chain="${1#*=}" ;;
    rule_num=*) rule_num="${1#*=}" ;;
    action=*) action="${1#*=}" ;;
    protocol=*) protocol="${1#*=}" ;;
    source=*) source="${1#*=}" ;;
    destination=*) destination="${1#*=}" ;;
    jump=*) jump="${1#*=}" ;;
    in_interface=*) in_interface="${1#*=}" ;;
    out_interface=*) out_interface="${1#*=}" ;;
    fragment=*) fragment="${1#*=}" ;;
    gateway=*) gateway="${1#*=}" ;;
    set_counters=*) set_counters="${1#*=}" ;;
    destination_port=*) destination_port="${1#*=}" ;;
    source_port=*) source_port="${1#*=}" ;;
    to_ports=*) to_ports="${1#*=}" ;;
    to_source=*) to_source="${1#*=}" ;;
    to_destination=*) to_destination="${1#*=}" ;;
    state=*) state="${1#*=}" ;;
    wait=*) wait="${1#*=}" ;;
    use_sudo=*) use_sudo="${1#*=}" ;;
    *) PARSE_ERROR="${PARSE_ERROR}Unknown parameter: ${1%%=*}; " ;;
  esac
  shift
done

[ -n "$chain" ] || { FAILED=true; MSG="Missing required argument: chain"; emit_result; }
[ -n "$state" ] || { FAILED=true; MSG="Missing required argument: state"; emit_result; }
[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

case "$table" in
  filter|nat|mangle|raw|security) ;;
  *) FAILED=true; MSG="Invalid table: $table. Choices: filter, nat, mangle, raw, security"; emit_result ;;
esac

case "$action" in
  insert|append) ;;
  *) FAILED=true; MSG="Invalid action: $action. Choices: insert, append"; emit_result ;;
esac

case "$state" in
  present|absent) ;;
  *) FAILED=true; MSG="Invalid state: $state. Choices: present, absent"; emit_result ;;
esac

[ -z "$rule_num" ] || { [[ "$rule_num" =~ ^[0-9]+$ ]] || { FAILED=true; MSG="rule_num must be a non-negative integer"; emit_result; }; }
[ -z "$wait" ] || { [[ "$wait" =~ ^[0-9]+$ ]] || { FAILED=true; MSG="wait must be a non-negative integer"; emit_result; }; }

case "$fragment" in
  true|false) ;;
  *) FAILED=true; MSG="fragment must be 'true' or 'false'"; emit_result ;;
esac

detect_sudo

# Check if rule exists
rule_exists() {
  full_cmd=()
  if [ -n "$SUDO_PREFIX" ]; then full_cmd+=($SUDO_PREFIX); fi
  full_cmd+=(iptables)
  [ -n "$wait" ] && full_cmd+=("--wait" "$wait")
  full_cmd+=("-t" "$table" "-C" "$chain")
  [ -n "$protocol" ] && full_cmd+=("-p" "$protocol")
  [ -n "$source" ] && full_cmd+=("-s" "$source")
  [ -n "$destination" ] && full_cmd+=("-d" "$destination")
  [ -n "$jump" ] && full_cmd+=("-j" "$jump")
  [ -n "$in_interface" ] && full_cmd+=("-i" "$in_interface")
  [ -n "$out_interface" ] && full_cmd+=("-o" "$out_interface")
  [ "$fragment" = true ] && full_cmd+=("-f")
  [ -n "$gateway" ] && full_cmd+=("--gateway" "$gateway")
  [ -n "$set_counters" ] && full_cmd+=("--set-counters" "$set_counters")
  [ -n "$destination_port" ] && full_cmd+=("--dport" "$destination_port")
  [ -n "$source_port" ] && full_cmd+=("--sport" "$source_port")
  [ -n "$to_ports" ] && full_cmd+=("--to-ports" "$to_ports")
  [ -n "$to_source" ] && full_cmd+=("--to-source" "$to_source")
  [ -n "$to_destination" ] && full_cmd+=("--to-destination" "$to_destination")
  set +e
  "${full_cmd[@]}" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

# Main logic
CMD=()
case "$state" in
  present)
    if ! rule_exists; then
      CHANGED=true
      
      CMD=()
      if [ -n "$SUDO_PREFIX" ]; then CMD+=($SUDO_PREFIX); fi
      CMD+=(iptables)
      [ -n "$wait" ] && CMD+=("--wait" "$wait")
      CMD+=("-t" "$table")
      
      case "$action" in
        insert)
          [ -z "$rule_num" ] && { FAILED=true; MSG="rule_num is required for action=insert"; emit_result; }
          CMD+=("-I" "$chain" "$rule_num")
          ;;
        append|*)
          CMD+=("-A" "$chain")
          ;;
      esac
      
      [ -n "$protocol" ] && CMD+=("-p" "$protocol")
      [ -n "$source" ] && CMD+=("-s" "$source")
      [ -n "$destination" ] && CMD+=("-d" "$destination")
      [ -n "$jump" ] && CMD+=("-j" "$jump")
      [ -n "$in_interface" ] && CMD+=("-i" "$in_interface")
      [ -n "$out_interface" ] && CMD+=("-o" "$out_interface")
      [ "$fragment" = true ] && CMD+=("-f")
      [ -n "$gateway" ] && CMD+=("--gateway" "$gateway")
      [ -n "$set_counters" ] && CMD+=("--set-counters" "$set_counters")
      [ -n "$destination_port" ] && CMD+=("--dport" "$destination_port")
      [ -n "$source_port" ] && CMD+=("--sport" "$source_port")
      [ -n "$to_ports" ] && CMD+=("--to-ports" "$to_ports")
      [ -n "$to_source" ] && CMD+=("--to-source" "$to_source")
      [ -n "$to_destination" ] && CMD+=("--to-destination" "$to_destination")
      
      run_cmd "${CMD[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to add iptables rule: $STDERR"
        emit_result
      fi
      
      RESULTS+=("Added iptables rule in table '$table' chain '$chain'")
    else
      RESULTS+=("iptables rule already present in table '$table' chain '$chain'")
    fi
    ;;
  
  absent)
    if rule_exists; then
      CHANGED=true
      CMD=()
      if [ -n "$SUDO_PREFIX" ]; then CMD+=($SUDO_PREFIX); fi
      CMD+=(iptables)
      [ -n "$wait" ] && CMD+=("--wait" "$wait")
      CMD+=("-t" "$table")
      CMD+=("-D" "$chain")
      
      [ -n "$protocol" ] && CMD+=("-p" "$protocol")
      [ -n "$source" ] && CMD+=("-s" "$source")
      [ -n "$destination" ] && CMD+=("-d" "$destination")
      [ -n "$jump" ] && CMD+=("-j" "$jump")
      [ -n "$in_interface" ] && CMD+=("-i" "$in_interface")
      [ -n "$out_interface" ] && CMD+=("-o" "$out_interface")
      [ "$fragment" = true ] && CMD+=("-f")
      [ -n "$gateway" ] && CMD+=("--gateway" "$gateway")
      [ -n "$set_counters" ] && CMD+=("--set-counters" "$set_counters")
      [ -n "$destination_port" ] && CMD+=("--dport" "$destination_port")
      [ -n "$source_port" ] && CMD+=("--sport" "$source_port")
      [ -n "$to_ports" ] && CMD+=("--to-ports" "$to_ports")
      [ -n "$to_source" ] && CMD+=("--to-source" "$to_source")
      [ -n "$to_destination" ] && CMD+=("--to-destination" "$to_destination")
      
      run_cmd "${CMD[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to delete iptables rule: $STDERR"
        emit_result
      fi
      
      RESULTS+=("Deleted iptables rule from table '$table' chain '$chain'")
    else
      RESULTS+=("iptables rule already absent from table '$table' chain '$chain'")
    fi
    ;;
esac

if [ "$CHANGED" = false ]; then
  MSG="Nothing to do — iptables rule is already in the desired state"
else
  MSG="iptables rule updated successfully"
fi

emit_result