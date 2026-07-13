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
# bash.get_url — pure-Bash replacement for ansible.builtin.get_url
#
# Downloads a URL to a local dest, optionally verifying a checksum and setting mode.
# Params (strings via ARGS_JSON or $1):
#   url       (required) source URL
#   dest      (required) local destination path
#   checksum  optional "<algo>:<hex>" where algo ∈ sha256|sha1|md5
#   mode      optional octal mode applied on write (default 0644)
#   tmp_dest  optional temp dir for the download staging file
#
# Behaviour:
#   - Skips download when dest exists AND (no checksum, or checksum matches).
#   - Verifies checksum on the staged temp file BEFORE moving into place.
#   - Atomic move via `install` (sudo-aware).
#
# Output: JSON with changed + invocation.args echoing (Phase 2+ convention).
# NOTE: sudo-aware — no Ansible become needed (2b3a2eb).

set -euo pipefail

ARGS_JSON="${ARGS_JSON:-${1:-}}"
_get() {
  local k="$1" v=""
  v="$(printf '%s' "$ARGS_JSON" \
    | grep -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/")" || true
  printf '%s' "$v"
}

# honour use_sudo: when explicitly false/no, never escalate (run as the
# connecting user). This is required so a non-root user can download into a
# world-writable dest (e.g. /tmp) where root-curl cannot write their temp file.
USE_SUDO="$(_get use_sudo)"
USE_SUDO="${USE_SUDO:-auto}"
case "${USE_SUDO,,}" in
  no|false|0) USE_SUDO=no ;;
  yes|true|1) USE_SUDO=yes ;;
  *) USE_SUDO=auto ;;
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

URL="$(_get url)"
DEST="$(_get dest)"
CHECKSUM="$(_get checksum)"
MODE="$(_get mode)"; MODE="${MODE:-0644}"
TMP_DEST="$(_get tmp_dest)"; TMP_DEST="${TMP_DEST:-${TMPDIR:-/tmp}}"

if [[ -z "$URL" || -z "$DEST" ]]; then
  echo "{\"failed\":true,\"msg\":\"url and dest are required\"}"; exit 1
fi

need_download=true
if [[ -f "$DEST" ]]; then
  need_download=false
  if [[ -n "$CHECKSUM" ]]; then
    algo="${CHECKSUM%%:*}"; hex="${CHECKSUM#*:}"
    actual="$(run "${algo}sum" "$DEST" | awk '{print $1}')"
    [[ "$actual" == "$hex" ]] || need_download=true
  fi
fi

if [[ "$need_download" == true ]]; then
  tmp_dir="${TMP_DEST:-${TMPDIR:-/tmp}}"
  tmp="$(mktemp "$tmp_dir/get_url.XXXXXX")"
  if ! run curl -fsSL "$URL" -o "$tmp"; then
    rm -f "$tmp"
    echo "{\"failed\":true,\"msg\":\"download failed: $URL\"}"; exit 1
  fi
  if [[ -n "$CHECKSUM" ]]; then
    algo="${CHECKSUM%%:*}"; hex="${CHECKSUM#*:}"
    actual="$(run "${algo}sum" "$tmp" | awk '{print $1}')"
    if [[ "$actual" != "$hex" ]]; then
      rm -f "$tmp"
      echo "{\"failed\":true,\"msg\":\"checksum mismatch: expected $hex got $actual\"}"; exit 1
    fi
  fi
  run install -m "$MODE" "$tmp" "$DEST"
  rm -f "$tmp"
fi

cat <<JSON
{"changed": $need_download, "invocation": {"args": {"url": "$URL", "dest": "$DEST", "checksum": "$CHECKSUM", "mode": "$MODE"}}, "dest": "$DEST", "checksum": "$CHECKSUM", "checksum_verified": $([[ -n "$CHECKSUM" ]] && echo true || echo false)}
JSON
