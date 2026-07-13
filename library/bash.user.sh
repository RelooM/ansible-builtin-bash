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
# ansible-module: bash.user
# description: Manage users on Linux systems
# options:
#   name:
#     description: Username
#     required: true
#     type: str
#   state:
#     description: Whether the user should be present or absent
#     required: false
#     type: str
#     default: present
#     choices: [present, absent]
#   uid:
#     description: User ID
#     required: false
#     type: int
#   group:
#     description: Primary group name or GID
#     required: false
#     type: str
#   groups:
#     description: Supplementary group names (comma-separated)
#     required: false
#     type: list
#   home:
#     description: Home directory path
#     required: false
#     type: str
#   shell:
#     description: Login shell path
#     required: false
#     type: str
#   system:
#     description: Create as a system user
#     required: false
#     type: bool
#     default: false
#   comment:
#     description: GECOS field (full name, etc.)
#     required: false
#     type: str
#   password:
#     description: Encrypted password string
#     required: false
#     type: str
#   remove:
#     description: Remove home directory and mail spool on state=absent
#     required: false
#     type: bool
#     default: false
#   create_home:
#     description: Create home directory for new users
#     required: false
#     type: bool
#     default: true
#   move_home:
#     description: Move home directory when changing home path
#     required: false
#     type: bool
#     default: false
#   non_unique:
#     description: Allow non-unique UID (only applies when uid is specified)
#     required: false
#     type: bool
#     default: false
#   skeleton:
#     description: Skeleton directory for new home
#     required: false
#     type: str
#   uid_range:
#     description: UID range for system users (e.g., 100-999)
#     required: false
#     type: str
#   force:
#     description: Force removal even if user is logged in
#     required: false
#     type: bool
#     default: false
#   append:
#     description: Append to supplementary groups (don't replace)
#     required: false
#     type: bool
#     default: false
#   use_sudo:
#     description: Whether to use sudo (auto: use if not root)
#     required: false
#     type: str
#     default: auto
#     choices: [auto, true, false]

set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.user"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- Default state vars ----
name=""
state="present"
uid=""
group=""
groups=""
home=""
shell=""
system=false
comment=""
password=""
remove=false
create_home=true
move_home=false
non_unique=false
skeleton=""
uid_range=""
force=false
append=false
use_sudo="auto"

# ID ranges from /etc/login.defs (defaults if not found)
SYS_UID_MIN=100
SYS_UID_MAX=999
UID_MIN=1000
UID_MAX=60000

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

  if [ -n "$STDOUT" ]; then
    out+=",\"stdout\": $(jq_safe "$STDOUT")"
  fi
  if [ -n "$STDERR" ]; then
    out+=",\"stderr\": $(jq_safe "$STDERR")"
  fi

  out+=",\"invocation\": {\"module_args\": {"
  local first=true
  # name
  [ -n "$name" ] && { $first || out+=", "; first=false; out+="\"name\": $(jq_safe "$name")"; }
  # state
  [ -n "$state" ] && { $first || out+=", "; first=false; out+="\"state\": $(jq_safe "$state")"; }
  # uid
  if [ -n "$uid" ]; then
    $first || out+=", "; first=false
    out+="\"uid\": $(jq_safe "$uid")"
  fi
  # group
  if [ -n "$group" ]; then
    $first || out+=", "; first=false
    out+="\"group\": $(jq_safe "$group")"
  fi
  # groups
  if [ -n "$groups" ]; then
    $first || out+=", "; first=false
    out+="\"groups\": $(jq_safe "$groups")"
  fi
  # home
  if [ -n "$home" ]; then
    $first || out+=", "; first=false
    out+="\"home\": $(jq_safe "$home")"
  fi
  # shell
  if [ -n "$shell" ]; then
    $first || out+=", "; first=false
    out+="\"shell\": $(jq_safe "$shell")"
  fi
  # system
  $first || out+=", "; first=false
  if [ "$system" = true ]; then out+="\"system\": true"; else out+="\"system\": false"; fi
  # comment
  if [ -n "$comment" ]; then
    $first || out+=", "; first=false
    out+="\"comment\": $(jq_safe "$comment")"
  fi
  # password (log presence, not value)
  $first || out+=", "; first=false
  if [ -n "$password" ]; then out+="\"password_set\": true"; else out+="\"password_set\": false"; fi
  # remove
  $first || out+=", "; first=false
  if [ "$remove" = true ]; then out+="\"remove\": true"; else out+="\"remove\": false"; fi
  # create_home
  $first || out+=", "; first=false
  if [ "$create_home" = true ]; then out+="\"create_home\": true"; else out+="\"create_home\": false"; fi
  # move_home
  $first || out+=", "; first=false
  if [ "$move_home" = true ]; then out+="\"move_home\": true"; else out+="\"move_home\": false"; fi
  # non_unique
  $first || out+=", "; first=false
  if [ "$non_unique" = true ]; then out+="\"non_unique\": true"; else out+="\"non_unique\": false"; fi
  # skeleton
  if [ -n "$skeleton" ]; then
    $first || out+=", "; first=false
    out+="\"skeleton\": $(jq_safe "$skeleton")"
  fi
  # uid_range
  if [ -n "$uid_range" ]; then
    $first || out+=", "; first=false
    out+="\"uid_range\": $(jq_safe "$uid_range")"
  fi
  # force
  $first || out+=", "; first=false
  if [ "$force" = true ]; then out+="\"force\": true"; else out+="\"force\": false"; fi
  # append
  $first || out+=", "; first=false
  if [ "$append" = true ]; then out+="\"append\": true"; else out+="\"append\": false"; fi
  # use_sudo
  $first || out+=", "; first=false
  out+="\"use_sudo\": $(jq_safe "$use_sudo")"
  out+="}}}"

  echo "$out"
  if [ "$FAILED" = true ]; then exit 1; fi
  exit 0
}

# ---- Helper: check command existence ----
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ---- Helper: detect sudo prefix ----
detect_sudo() {
  SUDO_PREFIX=""
  case "$use_sudo" in
    auto)
      if [ "$(id -u)" -ne 0 ]; then
        if command_exists sudo; then
          SUDO_PREFIX="sudo -n"
        else
          FAILED=true
          MSG="Running as non-root but sudo is not available."
          emit_result
        fi
      fi
      ;;
    true)
      if command_exists sudo; then
        SUDO_PREFIX="sudo -n"
      else
        FAILED=true
        MSG="use_sudo=true but sudo is not installed."
        emit_result
      fi
      ;;
  esac
  # use_sudo=false → SUDO_PREFIX stays empty
}

# ---- Helper: run command with capture ----
# Uses global RC variable to avoid set -e trap
run_cmd() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    args+=($SUDO_PREFIX)
  fi
  args+=("$@")

  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$( "${args[@]}" 2>"$tmp_stderr" )
  local rc=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  RC=$rc
  return 0
}

# ---- Helper: read-only query (no sudo unless forced) ----
run_query() {
  local args=()
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    args+=($SUDO_PREFIX)
  fi
  args+=("$@")

  set +e
  "${args[@]}" 2>/dev/null
  local rc=$?
  set -e
  return $rc
}

# ---- Helper: boolean parsing ----
bool_true() {
  case "$1" in
    1|yes|true|True|TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- Helper: read ID ranges from /etc/login.defs ----
get_id_ranges() {
  local line
  while IFS= read -r line; do
    case "$line" in
      SYS_UID_MIN*)  SYS_UID_MIN=$(echo "$line" | awk '{print $2}') ;;
      SYS_UID_MAX*)  SYS_UID_MAX=$(echo "$line" | awk '{print $2}') ;;
      UID_MIN*)      UID_MIN=$(echo "$line" | awk '{print $2}') ;;
      UID_MAX*)      UID_MAX=$(echo "$line" | awk '{print $2}') ;;
    esac
  done < /etc/login.defs
}

# Get ID ranges (if file exists)
if [ -f /etc/login.defs ]; then
  get_id_ranges
fi

# ---- Helper: check if a uid is in system range ----
is_system_uid() {
  local uid_to_check="$1"
  [ "$uid_to_check" -ge "$SYS_UID_MIN" ] && [ "$uid_to_check" -le "$SYS_UID_MAX" ]
}

# ---- Helper: resolve uid_range string into min/max ----
parse_uid_range() {
  local range="$1"
  UID_RANGE_MIN="${range%%-*}"
  UID_RANGE_MAX="${range##*-}"
  # Validate
  if [ -z "$UID_RANGE_MIN" ] || [ -z "$UID_RANGE_MAX" ]; then
    FAILED=true
    MSG="Invalid uid_range format: $range (expected min-max, e.g., 100-999)"
    emit_result
  fi
  case "$UID_RANGE_MIN" in ''|*[!0-9]*) FAILED=true; MSG="uid_range min must be non-negative integer"; emit_result ;; esac
  case "$UID_RANGE_MAX" in ''|*[!0-9]*) FAILED=true; MSG="uid_range max must be non-negative integer"; emit_result ;; esac
}

# ---- Helper: check if current UID is in system range ----
is_system_uid_current() {
  local current="$1"
  local min="${UID_RANGE_MIN:-$SYS_UID_MIN}"
  local max="${UID_RANGE_MAX:-$SYS_UID_MAX}"
  [ "$current" -ge "$min" ] && [ "$current" -le "$max" ]
}

# ---- Helper: get current user info (returns via CURRENT_* globals) ----
get_current_user() {
  if run_query getent passwd "$name" >/dev/null 2>&1; then
    # Parse: username:password:uid:gid:gecos:home:shell
    local entry
    entry=$(getent passwd "$name")
    CURRENT_UID=$(echo "$entry" | cut -d: -f3)
    CURRENT_GID=$(echo "$entry" | cut -d: -f4)
    CURRENT_COMMENT=$(echo "$entry" | cut -d: -f5)
    CURRENT_HOME=$(echo "$entry" | cut -d: -f6)
    CURRENT_SHELL=$(echo "$entry" | cut -d: -f7)
    CURRENT_PRIMARY_GROUP_NAME=$(getent group "$CURRENT_GID" 2>/dev/null | cut -d: -f1)
    # Get supplementary groups
    CURRENT_GROUPS=$(id -Gn "$name" 2>/dev/null || echo "")
  else
    CURRENT_UID=""
    CURRENT_GID=""
    CURRENT_COMMENT=""
    CURRENT_HOME=""
    CURRENT_SHELL=""
    CURRENT_PRIMARY_GROUP_NAME=""
    CURRENT_GROUPS=""
  fi
}

# ---- Argument parsing ----
PARSE_ERROR=""
for arg in "$@"; do
  case "${arg}" in
    *=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      ;;
    *) continue ;;
  esac
  case "$key" in
    name)        name="$val" ;;
    state)       state="$val" ;;
    uid)         uid="$val" ;;
    group)       group="$val" ;;
    groups)      groups="$val" ;;
    home)        home="$val" ;;
    shell)       shell="$val" ;;
    system)
      if bool_true "$val"; then system=true; else system=false; fi ;;
    comment)     comment="$val" ;;
    password)    password="$val" ;;
    remove)
      if bool_true "$val"; then remove=true; else remove=false; fi ;;
    create_home)
      if bool_true "$val"; then create_home=true; else create_home=false; fi ;;
    move_home)
      if bool_true "$val"; then move_home=true; else move_home=false; fi ;;
    non_unique)
      if bool_true "$val"; then non_unique=true; else non_unique=false; fi ;;
    skeleton)    skeleton="$val" ;;
    uid_range)   uid_range="$val" ;;
    force)
      if bool_true "$val"; then force=true; else force=false; fi ;;
    append)
      if bool_true "$val"; then append=true; else append=false; fi ;;
    use_sudo)    use_sudo="$val" ;;
    *)
      PARSE_ERROR="${PARSE_ERROR}Unknown parameter: $key; " ;;
  esac
done

# ---- Detect sudo ----
detect_sudo

# ---- Validate parameters ----
[ -n "$name" ] || { FAILED=true; MSG="Missing required argument: name"; emit_result; }
[ -z "$PARSE_ERROR" ] || { FAILED=true; MSG="$PARSE_ERROR"; emit_result; }

# Validate state
case "$state" in
  present|absent) ;;
  *)
    FAILED=true; MSG="Invalid state: $state. Valid values: present, absent"
    emit_result
    ;;
esac

# Validate uid if provided
if [ -n "$uid" ]; then
  case "$uid" in
    ''|*[!0-9]*)
      FAILED=true; MSG="UID must be a non-negative integer"
      emit_result
      ;;
  esac
fi

# Parse uid_range if provided
if [ -n "$uid_range" ]; then
  parse_uid_range "$uid_range"
fi

# ---- Get current user state ----
get_current_user

# ---- MAIN logic ----
case "$state" in
  present)
    if [ -z "$CURRENT_UID" ]; then
      # User does not exist — CREATE
      CMD=("useradd")

      # System user flag
      [ "$system" = true ] && { CMD+=(-r); }

      # Prevent creating a group with the same name as user (use -N)
      CMD+=(-N)

      # UID
      if [ -n "$uid" ]; then
        # Validate system range if system=true
        if [ "$system" = true ]; then
          if ! is_system_uid_current "$uid"; then
            FAILED=true
            MSG="UID $uid is not in the system UID range [${UID_RANGE_MIN:-$SYS_UID_MIN}-${UID_RANGE_MAX:-$SYS_UID_MAX}]"
            emit_result
          fi
        fi
        CMD+=(-u "$uid")
        [ "$non_unique" = true ] && CMD+=(-o)
      fi

      # Primary group
      if [ -n "$group" ]; then
        CMD+=(-g "$group")
      fi

      # Supplementary groups
      if [ -n "$groups" ]; then
        CMD+=(-G "$groups")
      fi

      # Home directory
      if [ -n "$home" ]; then
        CMD+=(-d "$home")
      fi

      # Login shell
      if [ -n "$shell" ]; then
        CMD+=(-s "$shell")
      fi

      # GECOS comment
      if [ -n "$comment" ]; then
        CMD+=(-c "$comment")
      fi

      # Create home flag
      if [ "$create_home" = true ]; then
        CMD+=(-m)
      else
        CMD+=(-M)
      fi

      # Skeleton directory
      if [ -n "$skeleton" ]; then
        CMD+=(-k "$skeleton")
      fi

      # Create the user
      CMD+=("$name")
      run_cmd "${CMD[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to create user $name: $STDERR"
        emit_result
      fi
      RESULTS+=("Created user $name")
      CHANGED=true

      # Set password if provided
      if [ -n "$password" ]; then
        run_cmd usermod -p "$password" "$name"
        if [ "$RC" -ne 0 ]; then
          FAILED=true
          MSG="Failed to set password for $name: $STDERR"
          emit_result
        fi
        RESULTS+=("Set password for $name")
      fi

    else
      # User exists — MODIFY
      CMD=("usermod")
      did_modify=false

      # UID change
      if [ -n "$uid" ] && [ "$uid" != "$CURRENT_UID" ]; then
        CMD+=(-u "$uid")
        [ "$non_unique" = true ] && CMD+=(-o)
        did_modify=true
      fi

      # Primary group change
      if [ -n "$group" ] && [ "$group" != "$CURRENT_PRIMARY_GROUP_NAME" ]; then
        CMD+=(-g "$group")
        did_modify=true
      fi

      # Home change
      if [ -n "$home" ] && [ "$home" != "$CURRENT_HOME" ]; then
        CMD+=(-d "$home")
        [ "$move_home" = true ] && CMD+=(-m)
        did_modify=true
      fi

      # Shell change
      if [ -n "$shell" ] && [ "$shell" != "$CURRENT_SHELL" ]; then
        CMD+=(-s "$shell")
        did_modify=true
      fi

      # Comment change
      if [ -n "$comment" ] && [ "$comment" != "$CURRENT_COMMENT" ]; then
        CMD+=(-c "$comment")
        did_modify=true
      fi

      # Supplementary groups
      if [ -n "$groups" ]; then
        if [ "$append" = true ]; then
          run_cmd usermod -aG "$groups" "$name"
          if [ "$RC" -ne 0 ]; then
            FAILED=true
            MSG="Failed to append groups for $name: $STDERR"
            emit_result
          fi
          RESULTS+=("Appended groups $groups to $name")
          CHANGED=true
        else
          CMD+=(-G "$groups")
          did_modify=true
        fi
      fi

      # Apply modifications if any
      if [ "$did_modify" = true ]; then
        CMD+=("$name")
        run_cmd "${CMD[@]}"
        if [ "$RC" -ne 0 ]; then
          FAILED=true
          MSG="Failed to modify user $name: $STDERR"
          emit_result
        fi
        RESULTS+=("Modified user $name")
        CHANGED=true
      fi

      # Password
      if [ -n "$password" ]; then
        run_cmd usermod -p "$password" "$name"
        if [ "$RC" -ne 0 ]; then
          FAILED=true
          MSG="Failed to set password for $name: $STDERR"
          emit_result
        fi
        RESULTS+=("Set password for $name")
        CHANGED=true
      fi

      if [ "$CHANGED" = false ]; then
        RESULTS+=("User $name already configured")
      fi
    fi
    ;;

  absent)
    if [ -z "$CURRENT_UID" ]; then
      # User does not exist
      RESULTS+=("User $name already absent")
    else
      CMD=("userdel")
      [ "$remove" = true ] && CMD+=(-r)
      [ "$force" = true ] && CMD+=(-f)
      CMD+=("$name")
      run_cmd "${CMD[@]}"
      if [ "$RC" -ne 0 ]; then
        FAILED=true
        MSG="Failed to remove user $name: $STDERR"
        emit_result
      fi
      RESULTS+=("Removed user $name")
      CHANGED=true
    fi
    ;;
esac

# ---- Final emit ----
if [ "$FAILED" != true ] && [ -z "$MSG" ]; then
  MSG="User operation(s) completed successfully"
fi
emit_result
