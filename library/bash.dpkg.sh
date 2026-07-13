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
# ansible-module: bash.dpkg
# description: Manages dpkg package selections and installs/removes .deb files — pure Bash.
#   Callable as `bash.dpkg:` in Ansible playbooks.
#   Calls sudo -n internally when running as non-root, respecting fine-grained
#   sudoers policies. No reliance on Ansible's become system.
# options:
#   name:
#     description: Package name for selection state operations (install/hold/deinstall/purge).
#     required: false
#     type: str
#   selection:
#     description: Selection state for the package.
#     required: false
#     choices: ["install", "hold", "deinstall", "purge"]
#     type: str
#   state:
#     description: Whether the selection state should be present or absent.
#     required: false
#     default: "present"
#     choices: ["present", "absent"]
#     type: str
#   deb:
#     description: Path to a local .deb file to install or remove.
#     required: false
#     type: str
#   force:
#     description: Force flags for dpkg operations (e.g., "force-confold", "force-confnew", "force-architecture").
#     required: false
#     type: str
#   use_sudo:
#     description: Whether to sudo the operations. 'auto' (default) sudo if not root.
#     required: false
#     default: "auto"
#     choices: ["auto", true, false]
#     type: str

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.dpkg"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""
RC=0

# ---- Default state vars (defaults) ----
name=""
selection=""
state="present"
deb=""
force=""
use_sudo="auto"
SUDO_PREFIX=""

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
  [ -n "$selection" ] && { $first || out+=", "; first=false; out+="\"selection\": $(jq_safe "$selection")"; }
  [ -n "$state" ] && { $first || out+=", "; first=false; out+="\"state\": $(jq_safe "$state")"; }
  [ -n "$deb" ] && { $first || out+=", "; first=false; out+="\"deb\": $(jq_safe "$deb")"; }
  [ -n "$force" ] && { $first || out+=", "; first=false; out+="\"force\": $(jq_safe "$force")"; }
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
  # use_sudo=false -> SUDO_PREFIX stays empty
}

# ---- Helper: run command with sudo prefix ----
# Sets global STDOUT, STDERR, RC
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

# ---- Helper: run dpkg query (no sudo unless forced) ----
run_dpkg_query() {
  local cmd=("$@")
  local full_cmd=()
  
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    full_cmd+=($SUDO_PREFIX)
  fi
  full_cmd+=("${cmd[@]}")
  
  set +e
  "${full_cmd[@]}" 2>/dev/null
  local rc=$?
  set -e
  return $rc
}

# ---- Helper: check if package is installed ----
package_installed() {
  local pkg="$1"
  if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
    return 0
  fi
  return 1
}

# ---- Helper: get current dpkg selection for a package ----
get_selection() {
  local pkg="$1"
  dpkg --get-selections "$pkg" 2>/dev/null | awk '{print $2}'
}

# ---- Helper: check if .deb file is installed ----
deb_installed() {
  local deb_path="$1"
  local pkg_name
  pkg_name=$(dpkg-deb -f "$deb_path" Package 2>/dev/null || true)
  if [ -n "$pkg_name" ]; then
    package_installed "$pkg_name"
    return $?
  fi
  return 1
}

# ---- Helper: get package name from .deb file ----
get_deb_package_name() {
  local deb_path="$1"
  dpkg-deb -f "$deb_path" Package 2>/dev/null || true
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

# ---- Helper: validate selection parameter ----
validate_selection() {
  local val="$1"
  case "$val" in
    install|hold|deinstall|purge) ;;
    *)
      FAILED=true
      MSG="Invalid selection: $val. Valid values: install, hold, deinstall, purge"
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
  # Normalize to lowercase for case-insensitive comparison
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

# ---- Main: parse arguments ----
PARSE_ERROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    name=*)
      name="${1#*=}"
      ;;
    selection=*)
      selection="${1#*=}"
      ;;
    state=*)
      state="${1#*=}"
      ;;
    deb=*)
      deb="${1#*=}"
      ;;
    force=*)
      force="${1#*=}"
      ;;
    use_sudo=*)
      use_sudo="${1#*=}"
      ;;
    *)
      PARSE_ERROR="${PARSE_ERROR}Unknown parameter: ${1%%=*}; "
      ;;
  esac
  shift
done

# ---- Detect sudo ----
detect_sudo

# ---- Validate force parameter if provided (applies to both modes) ----
if [ -n "$force" ]; then
  # Basic validation - dpkg force options (comma-separated)
  IFS=',' read -ra FORCE_OPTS <<< "$force"
  for opt in "${FORCE_OPTS[@]}"; do
    case "$opt" in
      force-confold|force-confnew|force-confdef|force-confmiss|force-architecture|force-depends|force-depends-version|force-overwrite|force-overwrite-dir|force-overwrite-diverted|force-bad-path|force-bad-verify|force-triggers|force-configure-any|force-remove-reinstreq|force-all) ;;
      *)
        FAILED=true
        MSG="Invalid force option: $opt. Valid options: force-confold, force-confnew, force-confdef, force-confmiss, force-architecture, force-depends, force-depends-version, force-overwrite, force-overwrite-dir, force-overwrite-diverted, force-bad-path, force-bad-verify, force-triggers, force-configure-any, force-remove-reinstreq, force-all"
        emit_result
        ;;
    esac
  done
fi

# ---- Validate parameters ----
[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

# Mode detection: deb file mode vs selection mode
if [ -n "$deb" ]; then
  # Deb file mode
  if [ ! -f "$deb" ]; then
    FAILED=true
    MSG="Deb file not found: $deb"
    emit_result
  fi
  
  # For deb file mode, name is optional (for removal)
  if [ "$state" = "absent" ] && [ -z "$name" ]; then
    name=$(get_deb_package_name "$deb")
    if [ -z "$name" ]; then
      FAILED=true
      MSG="Could not determine package name from .deb file and 'name' parameter not provided for state=absent"
      emit_result
    fi
  fi
  
  validate_state "$state"
  validate_use_sudo "$use_sudo"
  
  # ---- Main: handle deb file mode ----
  case "$state" in
    present)
      # Install .deb file
      if deb_installed "$deb"; then
        MSG="Package from $deb is already installed"
        emit_result
      fi
      
      CHANGED=true
      RESULTS+=("Installing $deb")
      
      dpkg_cmd=("dpkg" "-i")
      if [ -n "$force" ]; then
        IFS=',' read -ra FORCE_OPTS <<< "$force"
        for opt in "${FORCE_OPTS[@]}"; do
          dpkg_cmd+=("--force-$opt")
        done
      fi
      dpkg_cmd+=("$deb")
      
      run_cmd "${dpkg_cmd[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to install $deb (exit code $RC): $STDERR"
        emit_result
      fi
      RESULTS+=("Installed $deb")
      MSG="Successfully installed $deb"
      emit_result
      ;;
    absent)
      # Remove package
      if [ -z "$name" ]; then
        FAILED=true
        MSG="Package name required for removal"
        emit_result
      fi
      
      if ! package_installed "$name"; then
        MSG="Package $name is not installed"
        emit_result
      fi
      
      CHANGED=true
      RESULTS+=("Removing $name")
      
      dpkg_cmd=("dpkg" "-r")
      if [ -n "$force" ]; then
        IFS=',' read -ra FORCE_OPTS <<< "$force"
        for opt in "${FORCE_OPTS[@]}"; do
          dpkg_cmd+=("--force-$opt")
        done
      fi
      dpkg_cmd+=("$name")
      
      run_cmd "${dpkg_cmd[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to remove $name (exit code $RC): $STDERR"
        emit_result
      fi
      RESULTS+=("Removed $name")
      MSG="Successfully removed $name"
      emit_result
      ;;
  esac
  
else
  # Selection mode
  if [ -z "$name" ]; then
    FAILED=true
    MSG="Parameter 'name' is required for selection mode"
    emit_result
  fi
  
  if [ -z "$selection" ]; then
    FAILED=true
    MSG="Parameter 'selection' is required for selection mode"
    emit_result
  fi
  
  validate_selection "$selection"
  validate_state "$state"
  validate_use_sudo "$use_sudo"
  
  # Get current selection
  current_selection=$(get_selection "$name")
  
  # ---- Main: handle selection mode ----
  case "$state" in
    present)
      # Set selection
      if [ "$current_selection" = "$selection" ]; then
        MSG="Package $name already has selection '$selection'"
        emit_result
      fi
      
      CHANGED=true
      RESULTS+=("Setting selection for $name to $selection")
      
      echo "$name $selection" | run_cmd dpkg --set-selections
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to set selection for $name to $selection (exit code $RC): $STDERR"
        emit_result
      fi
      RESULTS+=("Set selection for $name to $selection")
      MSG="Successfully set selection for $name to $selection"
      emit_result
      ;;
    absent)
      # Remove selection (set to deinstall)
      if [ "$current_selection" = "deinstall" ] || [ -z "$current_selection" ]; then
        MSG="Package $name already has no selection (or deinstall)"
        emit_result
      fi
      
      CHANGED=true
      RESULTS+=("Removing selection for $name")
      
      echo "$name deinstall" | run_cmd dpkg --set-selections
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to remove selection for $name (exit code $RC): $STDERR"
        emit_result
      fi
      RESULTS+=("Removed selection for $name")
      MSG="Successfully removed selection for $name"
      emit_result
      ;;
  esac
fi