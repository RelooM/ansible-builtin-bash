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
# ansible-module: bash.firewalld
# description: Manages firewalld zones, services, ports, and rich rules — pure Bash.
#   Callable as `bash.firewalld:` in Ansible playbooks. Replaces ansible.posix.firewalld.
#   Calls sudo -n internally when running as non-root.
# options:
#   zone:
#     description: The firewalld zone to manage. Defaults to the default zone.
#     required: false
#     type: str
#   service:
#     description: Name of a service to add/remove (e.g. ssh, http).
#     required: false
#     type: str
#   port:
#     description: Port/protocol to add/remove (e.g. 80/tcp, 5000-5100/udp).
#     required: false
#     type: str
#   protocol:
#     description: Protocol to add/remove (e.g. igmp).
#     required: false
#     type: str
#   source:
#     description: Source address (address[/mask]) to add/remove from zone.
#     required: false
#     type: str
#   interface:
#     description: Interface to add/remove from zone.
#     required: false
#     type: str
#   rich_rule:
#     description: A firewalld rich rule string.
#     required: false
#     type: str
#   masquerade:
#     description: Enable/disable masquerading for the zone.
#     required: false
#     type: bool
#   icmp_block:
#     description: ICMP block type to add/remove.
#     required: false
#     type: str
#   icmp_block_inversion:
#     description: Enable/disable ICMP block inversion for the zone.
#     required: false
#     type: bool
#   state:
#     description: Whether to enable/add (enabled/present) or disable/remove (disabled/absent).
#     required: false
#     type: str
#     default: "enabled"
#     choices: ["enabled", "disabled", "present", "absent"]
#   permanent:
#     description: Whether the change should be permanent.
#     required: false
#     type: bool
#     default: true
#   immediate:
#     description: Whether a permanent change should also be applied to the runtime immediately.
#     required: false
#     type: bool
#     default: false
#   offline:
#     description: Use firewall-offline-cmd (when firewalld daemon is stopped).
#     required: false
#     type: bool
#     default: false
#   use_sudo:
#     description: Whether to sudo the operations. 'auto' (default) sudo if not root.
#     required: false
#     type: str
#     default: "auto"
#     choices: ["auto", true, false]

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.firewalld"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""
RC=0

# ---- Defaults ----
zone=""
service=""
port=""
protocol=""
source_addr=""
interface=""
rich_rule=""
masquerade=""
icmp_block=""
icmp_block_inversion=""
state="enabled"
permanent="true"
immediate="false"
offline="false"
use_sudo="auto"

# ---- Helper: JSON-safe string quoting ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
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
  out+="\"state\": $(jq_safe "$state")"
  out+=",\"permanent\": $permanent"
  out+=",\"immediate\": $immediate"
  out+=",\"offline\": $offline"
  [ -n "$zone" ] && out+=",\"zone\": $(jq_safe "$zone")"
  [ -n "$service" ] && out+=",\"service\": $(jq_safe "$service")"
  [ -n "$port" ] && out+=",\"port\": $(jq_safe "$port")"
  [ -n "$protocol" ] && out+=",\"protocol\": $(jq_safe "$protocol")"
  [ -n "$source_addr" ] && out+=",\"source\": $(jq_safe "$source_addr")"
  [ -n "$interface" ] && out+=",\"interface\": $(jq_safe "$interface")"
  [ -n "$rich_rule" ] && out+=",\"rich_rule\": $(jq_safe "$rich_rule")"
  [ -n "$masquerade" ] && out+=",\"masquerade\": $masquerade"
  [ -n "$icmp_block" ] && out+=",\"icmp_block\": $(jq_safe "$icmp_block")"
  [ -n "$icmp_block_inversion" ] && out+=",\"icmp_block_inversion\": $icmp_block_inversion"
  out+=",\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_sudo() {
  SUDO_PREFIX=""
  case "$use_sudo" in
    auto)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then SUDO_PREFIX="sudo -n"; else FAILED=true; MSG="Running as non-root but sudo is not available."; emit_result; fi
      fi
      ;;
    true)
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

# Read-only query — returns command exit code
run_query() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then args+=($SUDO_PREFIX); fi
  args+=("$@")
  set +e
  "${args[@]}" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

normalize_bool() {
  # echoes "true"/"false" or "INVALID"
  case "$1" in
    1|yes|true|True|TRUE|on) echo "true" ;;
    0|no|false|False|FALSE|off) echo "false" ;;
    *) echo "INVALID" ;;
  esac
}

# ---- Argument parsing ----
PARSE_ERROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    zone=*) zone="${1#*=}" ;;
    service=*) service="${1#*=}" ;;
    port=*) port="${1#*=}" ;;
    protocol=*) protocol="${1#*=}" ;;
    source=*) source_addr="${1#*=}" ;;
    interface=*) interface="${1#*=}" ;;
    rich_rule=*) rich_rule="${1#*=}" ;;
    masquerade=*) masquerade="${1#*=}" ;;
    icmp_block=*) icmp_block="${1#*=}" ;;
    icmp_block_inversion=*) icmp_block_inversion="${1#*=}" ;;
    state=*) state="${1#*=}" ;;
    permanent=*) permanent="${1#*=}" ;;
    immediate=*) immediate="${1#*=}" ;;
    offline=*) offline="${1#*=}" ;;
    use_sudo=*) use_sudo="${1#*=}" ;;
    *) PARSE_ERROR="${PARSE_ERROR}Unknown parameter: ${1%%=*}; " ;;
  esac
  shift
done

[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

# ---- Validate state ----
case "$state" in
  enabled|disabled|present|absent) ;;
  *) FAILED=true; MSG="Invalid state: $state. Choices: enabled, disabled, present, absent"; emit_result ;;
esac

# ---- Normalize & validate booleans ----
permanent=$(normalize_bool "$permanent")
[ "$permanent" != "INVALID" ] || { FAILED=true; MSG="permanent must be a boolean"; emit_result; }
immediate=$(normalize_bool "$immediate")
[ "$immediate" != "INVALID" ] || { FAILED=true; MSG="immediate must be a boolean"; emit_result; }
offline=$(normalize_bool "$offline")
[ "$offline" != "INVALID" ] || { FAILED=true; MSG="offline must be a boolean"; emit_result; }
if [ -n "$masquerade" ]; then
  masquerade=$(normalize_bool "$masquerade")
  [ "$masquerade" != "INVALID" ] || { FAILED=true; MSG="masquerade must be a boolean"; emit_result; }
fi
if [ -n "$icmp_block_inversion" ]; then
  icmp_block_inversion=$(normalize_bool "$icmp_block_inversion")
  [ "$icmp_block_inversion" != "INVALID" ] || { FAILED=true; MSG="icmp_block_inversion must be a boolean"; emit_result; }
fi

# ---- At least one thing to manage ----
if [ -z "$service" ] && [ -z "$port" ] && [ -z "$protocol" ] && [ -z "$source_addr" ] \
   && [ -z "$interface" ] && [ -z "$rich_rule" ] && [ -z "$masquerade" ] \
   && [ -z "$icmp_block" ] && [ -z "$icmp_block_inversion" ]; then
  FAILED=true
  MSG="At least one of service, port, protocol, source, interface, rich_rule, masquerade, icmp_block, or icmp_block_inversion must be specified"
  emit_result
fi

detect_sudo

# ---- Determine backend ----
CMD="firewall-cmd"
if [ "$offline" = "true" ]; then CMD="firewall-offline-cmd"; fi

if ! command_exists "$CMD"; then
  FAILED=true; MSG="Required command $CMD not found. Please install firewalld.";
  emit_result
fi

# ---- Build base args (zone + permanent) ----
base_args=()
[ -n "$zone" ] && base_args+=("--zone=$zone")
perm_args=()
[ "$permanent" = "true" ] && perm_args+=("--permanent")

# desired: is this an "add/enable" or "remove/disable" operation?
adding=true
case "$state" in
  enabled|present) adding=true ;;
  disabled|absent) adding=false ;;
esac

# Apply an add/remove for a given query/add/remove flag set.
# $1 = query flag (e.g. --query-service=ssh)
# $2 = add flag    (e.g. --add-service=ssh)
# $3 = remove flag (e.g. --remove-service=ssh)
# $4 = human label
manage_item() {
  local q="$1" add="$2" rem="$3" label="$4"
  if [ "$adding" = true ]; then
    if run_query "$CMD" "${base_args[@]}" "${perm_args[@]}" "$q"; then
      RESULTS+=("$label already present")
    else
      run_cmd "$CMD" "${base_args[@]}" "${perm_args[@]}" "$add"
      if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to add $label: $STDERR"; emit_result; fi
      CHANGED=true
      RESULTS+=("Added $label")
      # apply to runtime too if permanent + immediate
      if [ "$permanent" = "true" ] && [ "$immediate" = "true" ]; then
        run_cmd "firewall-cmd" "${base_args[@]}" "$add"
      fi
    fi
  else
    if run_query "$CMD" "${base_args[@]}" "${perm_args[@]}" "$q"; then
      run_cmd "$CMD" "${base_args[@]}" "${perm_args[@]}" "$rem"
      if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to remove $label: $STDERR"; emit_result; fi
      CHANGED=true
      RESULTS+=("Removed $label")
      if [ "$permanent" = "true" ] && [ "$immediate" = "true" ]; then
        run_cmd "firewall-cmd" "${base_args[@]}" "$rem"
      fi
    else
      RESULTS+=("$label already absent")
    fi
  fi
}

# Boolean toggles (masquerade, icmp_block_inversion) — desired driven by the bool value itself
manage_toggle() {
  local q="$1" add="$2" rem="$3" label="$4" want="$5"
  if [ "$want" = "true" ]; then
    if run_query "$CMD" "${base_args[@]}" "${perm_args[@]}" "$q"; then
      RESULTS+=("$label already enabled")
    else
      run_cmd "$CMD" "${base_args[@]}" "${perm_args[@]}" "$add"
      if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to enable $label: $STDERR"; emit_result; fi
      CHANGED=true
      RESULTS+=("Enabled $label")
      if [ "$permanent" = "true" ] && [ "$immediate" = "true" ]; then
        run_cmd "firewall-cmd" "${base_args[@]}" "$add"
      fi
    fi
  else
    if run_query "$CMD" "${base_args[@]}" "${perm_args[@]}" "$q"; then
      run_cmd "$CMD" "${base_args[@]}" "${perm_args[@]}" "$rem"
      if [ "$RC" -ne 0 ]; then FAILED=true; MSG="Failed to disable $label: $STDERR"; emit_result; fi
      CHANGED=true
      RESULTS+=("Disabled $label")
      if [ "$permanent" = "true" ] && [ "$immediate" = "true" ]; then
        run_cmd "firewall-cmd" "${base_args[@]}" "$rem"
      fi
    else
      RESULTS+=("$label already disabled")
    fi
  fi
}

# ---- Manage each requested item ----
[ -n "$service" ]   && manage_item "--query-service=$service"    "--add-service=$service"    "--remove-service=$service"    "service $service"
[ -n "$port" ]      && manage_item "--query-port=$port"          "--add-port=$port"          "--remove-port=$port"          "port $port"
[ -n "$protocol" ]  && manage_item "--query-protocol=$protocol"  "--add-protocol=$protocol"  "--remove-protocol=$protocol"  "protocol $protocol"
[ -n "$source_addr" ] && manage_item "--query-source=$source_addr" "--add-source=$source_addr" "--remove-source=$source_addr" "source $source_addr"
[ -n "$interface" ] && manage_item "--query-interface=$interface" "--add-interface=$interface" "--remove-interface=$interface" "interface $interface"
[ -n "$rich_rule" ] && manage_item "--query-rich-rule=$rich_rule" "--add-rich-rule=$rich_rule" "--remove-rich-rule=$rich_rule" "rich rule"
[ -n "$icmp_block" ] && manage_item "--query-icmp-block=$icmp_block" "--add-icmp-block=$icmp_block" "--remove-icmp-block=$icmp_block" "icmp-block $icmp_block"
[ -n "$masquerade" ] && manage_toggle "--query-masquerade" "--add-masquerade" "--remove-masquerade" "masquerade" "$masquerade"
[ -n "$icmp_block_inversion" ] && manage_toggle "--query-icmp-block-inversion" "--add-icmp-block-inversion" "--remove-icmp-block-inversion" "icmp-block-inversion" "$icmp_block_inversion"

if [ "$CHANGED" = false ]; then
  MSG="Nothing to do — firewalld is already in the desired state"
else
  MSG="Firewalld configuration updated successfully"
fi

emit_result