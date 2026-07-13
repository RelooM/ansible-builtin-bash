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
# ansible-module: bash.rpm_key
# description: Manage RPM GPG keys (import / remove) — pure Bash replacement for
#   ansible.builtin.rpm_key. Works on any RPM-based distro (RHEL, Fedora, CentOS,
#   Rocky, Alma, Amazon Linux). Calls sudo -n internally when running as non-root,
#   respecting fine-grained sudoers policies. No reliance on Ansible's become.
# options:
#   key:
#     description: URL or local path of the GPG key to import (http/https/file).
#     required: true (when state=present)
#     type: str
#   state:
#     description: Whether the key should be present or absent.
#     required: false
#     type: str
#     default: "present"
#     choices: ["present", "absent"]
#   key_id:
#     description: Key ID / fingerprint used to locate the key for removal when
#       'key' is not supplied, or to verify the imported key matches expectations.
#     required: false
#     type: str
#   validate_certs:
#     description: Validate TLS certificates when fetching an https key URL.
#     required: false
#     type: bool
#     default: true
#   use_sudo:
#     description: Sudo policy — auto (sudo -n when non-root), true (force), false (never).
#     required: false
#     type: str
#     default: "auto"
#
# Output (stdout): single JSON object with changed/failed/msg/rc/invocation.args.
set -uo pipefail

MODULE_NAME="bash.rpm_key"
CHANGED=false
FAILED=false
MSG=""
RC=0
KEY_URL=""
STATE="present"
KEY_ID=""
TARGET_ID=""
VALIDATE_CERTS=true
USE_SUDO="auto"

# ---- Helpers (shared boilerplate, no jq dependency) ----
jq_safe() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Detect sudo prefix from use_sudo + EUID. Uses passwordless sudo (-n) to avoid
# blocking on a password prompt; falls back to plain sudo only when forced.
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

# Run a command, capturing stdout/stderr and exit code into globals.
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
  out+="\"key\": $(jq_safe "$KEY_URL")"
  out+=",\"state\": $(jq_safe "$STATE")"
  out+=",\"key_id\": $(jq_safe "$KEY_ID")"
  out+=",\"validate_certs\": $VALIDATE_CERTS"
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
    key)  KEY_URL="$val" ;;
    state) STATE="$val" ;;
    key_id) KEY_ID="$val" ;;
    validate_certs)
      case "$val" in 1|yes|true|True|TRUE) VALIDATE_CERTS=true ;; *) VALIDATE_CERTS=false ;; esac ;;
    use_sudo) USE_SUDO="$val" ;;
  esac
done

detect_sudo

# ---- Validate ----
case "$STATE" in
  present|absent) ;;
  *) FAILED=true; MSG="Invalid state '$STATE' (expected present|absent)."; emit_result ;;
esac

if ! command_exists rpm; then
  FAILED=true; MSG="The 'rpm' command is required but not found on this system."; emit_result
fi

# Normalize key id to lowercase, strip 0x prefix and spaces for comparison.
norm_keyid() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^0x//; s/[[:space:]]//g'; }

# List currently-imported gpg-pubkey ids (short 8-char + long form), lowercased.
imported_keyids() {
  $SUDO_PREFIX rpm -q gpg-pubkey --qf '%{VERSION}\n' 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]//g' | sort -u
}

# Map a key id to the gpg-pubkey package name rpm uses (gpg-pubkey-<id>).
key_pkgname() {
  local id; id="$(norm_keyid "$1")"
  printf 'gpg-pubkey-%s' "${id:0:8}"
}

# =====================================================================
# State: present
# =====================================================================
if [ "$STATE" = "present" ]; then
  if [ -z "$KEY_URL" ]; then
    FAILED=true; MSG="Parameter 'key' is required when state=present."; emit_result
  fi

  # Determine the key id we are about to import (when key_id given, trust it;
  # otherwise we discover it after import via rpm -qi of the new package).
  if [ -n "$KEY_ID" ]; then
    TARGET_ID="$(norm_keyid "$KEY_ID")"
    # Already imported (match short or long id)?
    if imported_keyids | grep -qx "$TARGET_ID"; then
      CHANGED=false; MSG="RPM key $TARGET_ID already present."; emit_result
    fi
  fi

  # Fetch the key to a temp file (support http/https/file).
  tmpkey="$(mktemp /tmp/rpmkey.XXXXXX)"
  case "$KEY_URL" in
    file://*|/*)
      src="${KEY_URL#file://}"
      if [ ! -r "$src" ]; then
        rm -f "$tmpkey"
        FAILED=true; MSG="Key file not readable: $src"; emit_result
      fi
      cp -f "$src" "$tmpkey" 2>/dev/null || { rm -f "$tmpkey"; FAILED=true; MSG="Failed to copy key file: $src"; emit_result; }
      ;;
    https://*)
      curl_opts=(-fsSL)
      [ "$VALIDATE_CERTS" = "false" ] && curl_opts+=(-k)
      if ! command_exists curl; then
        rm -f "$tmpkey"
        FAILED=true; MSG="curl is required to fetch https key URLs."; emit_result
      fi
      if ! $SUDO_PREFIX curl "${curl_opts[@]}" "$KEY_URL" -o "$tmpkey" 2>/tmp/rpmkey.err.$$; then
        err="$(cat /tmp/rpmkey.err.$$ 2>/dev/null)"; rm -f "$tmpkey" /tmp/rpmkey.err.$$
        FAILED=true; MSG="Failed to fetch key from $KEY_URL: $err"; emit_result
      fi
      rm -f /tmp/rpmkey.err.$$
      ;;
    http://*)
      curl_opts=(-fsSL)
      [ "$VALIDATE_CERTS" = "false" ] && curl_opts+=(-k)
      if ! command_exists curl; then
        rm -f "$tmpkey"
        FAILED=true; MSG="curl is required to fetch http key URLs."; emit_result
      fi
      if ! $SUDO_PREFIX curl "${curl_opts[@]}" "$KEY_URL" -o "$tmpkey" 2>/tmp/rpmkey.err.$$; then
        err="$(cat /tmp/rpmkey.err.$$ 2>/dev/null)"; rm -f "$tmpkey" /tmp/rpmkey.err.$$
        FAILED=true; MSG="Failed to fetch key from $KEY_URL: $err"; emit_result
      fi
      rm -f /tmp/rpmkey.err.$$
      ;;
    *)
      rm -f "$tmpkey"
      FAILED=true; MSG="Unsupported key URL scheme: $KEY_URL (use file://, http://, or https://)."; emit_result
      ;;
  esac

  # Import.
  run_cmd $SUDO_PREFIX rpm --import "$tmpkey"
  rm -f "$tmpkey"

  if [ "$RUN_RC" -ne 0 ]; then
    FAILED=true; RC="$RUN_RC"; MSG="rpm --import failed: $RUN_STDOUT"; emit_result
  fi

  # Discover the imported key id for reporting.
  imported="$(imported_keyids | tail -1)"
  if [ -z "$imported" ]; then
    CHANGED=true; MSG="RPM key imported from $KEY_URL."; emit_result
  fi

  # If a key_id was requested, verify the imported key matches.
  if [ -n "$TARGET_ID" ]; then
    if ! imported_keyids | grep -qx "$TARGET_ID"; then
      FAILED=true; MSG="Imported key does not match requested key_id $TARGET_ID."; emit_result
    fi
  fi

  CHANGED=true
  [ -n "$imported" ] && MSG="RPM key $imported imported from $KEY_URL." || MSG="RPM key imported from $KEY_URL."
  emit_result
fi

# =====================================================================
# State: absent
# =====================================================================
if [ -z "$KEY_ID" ] && [ -z "$KEY_URL" ]; then
  FAILED=true; MSG="Either 'key_id' or 'key' is required when state=absent."; emit_result
fi

remove_id=""
if [ -n "$KEY_ID" ]; then
  remove_id="$(norm_keyid "$KEY_ID")"
  # Accept either the long id or its 8-char short form.
  if ! imported_keyids | grep -qx "$remove_id"; then
    short="${remove_id:0:8}"
    if imported_keyids | grep -qx "$short"; then remove_id="$short"; fi
  fi
else
  # Derive key id from the key URL basename (e.g. RPM-GPG-KEY-foo -> foo).
  base="$(basename "$KEY_URL")"
  remove_id="$(printf '%s' "$base" | sed -E 's/^RPM-GPG-KEY-//I; s/^GPG-KEY-//I' | tr '[:upper:]' '[:lower:]')"
fi

pkgname="$(key_pkgname "$remove_id")"

if ! $SUDO_PREFIX rpm -q "$pkgname" >/dev/null 2>&1; then
  CHANGED=false; MSG="RPM key $pkgname not present; nothing to remove."; emit_result
fi

run_cmd $SUDO_PREFIX rpm -e "$pkgname"
if [ "$RUN_RC" -ne 0 ]; then
  FAILED=true; RC="$RUN_RC"; MSG="rpm -e $pkgname failed: $RUN_STDOUT"; emit_result
fi

CHANGED=true; MSG="RPM key $pkgname removed."; emit_result
