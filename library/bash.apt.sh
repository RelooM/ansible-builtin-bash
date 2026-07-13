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
# ansible-module: bash.apt
# description: Manages packages with the apt package manager — pure Bash.
#   Callable as `bash.apt:` in Ansible playbooks.
#   Calls sudo -n internally when running as non-root, respecting fine-grained
#   sudoers policies. No reliance on Ansible's become system.
# options:
#   name:
#     description: A package name or package specifier with version (pkg=1.0), a URL, or local path to a .deb.
#                  Can be a comma-separated string or list.
#     required: true (unless list is used or autoremove=true)
#     type: list
#   pkg:
#     description: Alias for name.
#     required: false
#     type: list
#   state:
#     description: Whether to install (present, latest), or remove (absent) a package.
#     required: false
#     default: "present"
#     choices: ["absent", "present", "installed", "removed", "latest", "fixed", "build-dep"]
#   update_cache:
#     description: Force apt to update the package cache before the transaction.
#     required: false
#     type: bool
#     default: false
#   cache_valid_time:
#     description: Update the package cache if the cache is older than this value in seconds.
#     required: false
#     type: int
#   upgrade:
#     description: Upgrade all packages. 'yes' (same as 'safe'), 'safe' (upgrade), 'full' (dist-upgrade).
#     required: false
#     type: str
#   deb:
#     description: Install a local .deb file.
#     required: false
#     type: str
#   autoremove:
#     description: Remove orphaned packages.
#     required: false
#     type: bool
#     default: false
#   purge:
#     description: Remove configuration files as well (*apt-get purge*).
#     required: false
#     type: bool
#     default: false
#   only_upgrade:
#     description: Only upgrade packages; never install new ones.
#     required: false
#     type: bool
#     default: false
#   force_apt_get:
#     description: Force the use of apt-get rather than apt (useful for older systems).
#     required: false
#     type: bool
#     default: false
#   default_release:
#     description: Default release for pinning (e.g. stable).
#     required: false
#     type: str
#   install_recommends:
#     description: Install recommended packages.
#     required: false
#     type: bool
#     default: true
#   allow_unauthenticated:
#     description: Ignore if packages cannot be authenticated.
#     required: false
#     type: bool
#     default: false
#   allow_downgrade:
#     description: Allow downgrading packages.
#     required: false
#     type: bool
#     default: false
#   allow_change_held_packages:
#     description: Allow changing of held packages.
#     required: false
#     type: bool
#     default: false
#   dpkg_options:
#     description: Options to pass to dpkg (e.g. 'Force-ConfOld,Force-ConfDef').
#     required: false
#     type: str
#   fail_on_autoremove:
#     description: Make the task fail if autoremove wants to remove a package.
#     required: false
#     type: bool
#     default: false
#   lock_timeout:
#     description: Number of seconds to wait for the lock file before giving up.
#     required: false
#     type: int
#     default: 60
#   policy_rc_d:
#     description: Override /usr/sbin/policy-rc.d to prevent services from starting automatically.
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
MODULE_NAME="bash.apt"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- Default state vars (defaults) ----
state="present"
autoremove=false
update_cache=false
cache_valid_time=""
upgrade=""
deb=""
purge=false
only_upgrade=false
force_apt_get=false
default_release=""
install_recommends=true
allow_unauthenticated=false
allow_downgrade=false
allow_change_held_packages=false
dpkg_options=""
fail_on_autoremove=false
lock_timeout=60
policy_rc_d=""
use_sudo="auto"
names=()  # main package list
pkgs=()   # alias for names

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
  # names array (as 'name' in the module args)
  if [ ${#names[@]} -gt 0 ]; then
    $first || out+=", "
    first=false
    out+="\"name\": ["
    local name_first=true
    for n in "${names[@]}"; do
      $name_first || out+=", "
      name_first=false
      out+=$(jq_safe "$n")
    done
    out+="]"
  fi
  # state
  [ -n "$state" ] && { $first || out+=", "; first=false; out+="\"state\": $(jq_safe "$state")"; }
  # update_cache
  [ "$update_cache" = true ] && { $first || out+=", "; first=false; out+="\"update_cache\": true"; }
  # cache_valid_time
  [ -n "$cache_valid_time" ] && { $first || out+=", "; first=false; out+="\"cache_valid_time\": $cache_valid_time"; }
  # upgrade
  [ -n "$upgrade" ] && { $first || out+=", "; first=false; out+="\"upgrade\": $(jq_safe "$upgrade")"; }
  # deb
  [ -n "$deb" ] && { $first || out+=", "; first=false; out+="\"deb\": $(jq_safe "$deb")"; }
  # autoremove
  [ "$autoremove" = true ] && { $first || out+=", "; first=false; out+="\"autoremove\": true"; }
  # purge
  [ "$purge" = true ] && { $first || out+=", "; first=false; out+="\"purge\": true"; }
  # only_upgrade
  [ "$only_upgrade" = true ] && { $first || out+=", "; first=false; out+="\"only_upgrade\": true"; }
  # force_apt_get
  [ "$force_apt_get" = true ] && { $first || out+=", "; first=false; out+="\"force_apt_get\": true"; }
  # default_release
  [ -n "$default_release" ] && { $first || out+=", "; first=false; out+="\"default_release\": $(jq_safe "$default_release")"; }
  # install_recommends
  [ "$install_recommends" = false ] && { $first || out+=", "; first=false; out+="\"install_recommends\": false"; }
  # allow_unauthenticated
  [ "$allow_unauthenticated" = true ] && { $first || out+=", "; first=false; out+="\"allow_unauthenticated\": true"; }
  # allow_downgrade
  [ "$allow_downgrade" = true ] && { $first || out+=", "; first=false; out+="\"allow_downgrade\": true"; }
  # allow_change_held_packages
  [ "$allow_change_held_packages" = true ] && { $first || out+=", "; first=false; out+="\"allow_change_held_packages\": true"; }
  # dpkg_options
  [ -n "$dpkg_options" ] && { $first || out+=", "; first=false; out+="\"dpkg_options\": $(jq_safe "$dpkg_options")"; }
  # fail_on_autoremove
  [ "$fail_on_autoremove" = true ] && { $first || out+=", "; first=false; out+="\"fail_on_autoremove\": true"; }
  # lock_timeout
    [ -n "$lock_timeout" ] && [ "$lock_timeout" -ne 60 ] && { $first || out+=", "; first=false; out+="\"lock_timeout\": $lock_timeout"; }
        # policy_rc_d
        [ -n "$policy_rc_d" ] && [ "$policy_rc_d" -ne 0 ] && { $first || out+=", "; first=false; out+="\"policy_rc_d\": $policy_rc_d"; }
  # use_sudo
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

# ---- Helper: detect available apt backend and sudo prefix ----
# Sets global APT_BIN and SUDO_PREFIX
detect_apt_and_sudo() {
  local backend=""

  if [ "$force_apt_get" = true ]; then
    if command_exists apt-get; then
      backend="apt-get"
    else
      FAILED=true
      MSG="Requested backend 'apt-get' (force_apt_get=true) but apt-get is not installed on the target system."
      emit_result
    fi
  else
    if command_exists apt; then
      backend="apt"
    elif command_exists apt-get; then
      backend="apt-get"
    else
      # Don't fail here; let the command itself error if neither is found
      backend="apt-get"
    fi
  fi

  # Determine sudo prefix
  SUDO_PREFIX=""
  if [ "$use_sudo" = "auto" ]; then
    if [ "$(id -u)" -ne 0 ]; then
      # Running as non-root — need sudo for apt commands
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
  # use_sudo=false → SUDO_PREFIX stays empty

  APT_BIN="$backend"
}

# ---- Helper: run apt command and capture output ----
# Sets global STDOUT and STDERR from the apt command output
# Returns the exit code of the apt command
run_apt() {
  local cmd="$1"
  shift
  local extra_args=("$@")

  # Start building the argument array
  local apt_args=()

  # If we have a sudo prefix, add it as individual words
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    apt_args+=($SUDO_PREFIX)
  fi

  apt_args+=("$APT_BIN")

  # Always pass -y (assume-yes) for non-interactive operation
  apt_args+=("-y")

  # Global options
  if [ -n "$default_release" ]; then
    apt_args+=("-t" "$default_release")
  fi

  if [ "$allow_unauthenticated" = true ]; then
    apt_args+=("--allow-unauthenticated")
  fi

  if [ "$allow_downgrade" = true ]; then
    apt_args+=("--allow-downgrades")
  fi

  if [ "$allow_change_held_packages" = true ]; then
    apt_args+=("--allow-change-held-packages")
  fi

  if [ -n "$dpkg_options" ]; then
    # dpkg-options is passed via -o Dpkg::Options::="..."
    IFS=',' read -ra OPTS <<< "$dpkg_options"
    for opt in "${OPTS[@]}"; do
      apt_args+=("-o" "Dpkg::Options::$opt")
    done
  fi

  if [ "$install_recommends" = false ]; then
    apt_args+=("--no-install-recommends")
  fi

  # Subcommand
  apt_args+=("$cmd")

  # Extra positional args (packages, etc.)
  apt_args+=("${extra_args[@]}")

  # Run — allow failure so we can capture return code
  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$("${apt_args[@]}" 2>"$tmp_stderr")
  local rc=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  return $rc
}

# ---- Helper: run apt for a read-only query (no sudo needed on most systems) ----
# Uses sudo only if SUDO_PREFIX is set, but caller can force no-sudo with check_only=true
# Returns exit code of the apt command
run_apt_query() {
  local cmd="$1"
  shift
  local extra_args=("$@")

  local q_args=()

  # Only use sudo for queries if we need it (usually not for read-only)
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    q_args+=($SUDO_PREFIX)
  fi
  q_args+=("$APT_BIN" "$cmd")
  q_args+=("${extra_args[@]}")

  set +e
  "${q_args[@]}" 2>/dev/null
  local rc=$?
  set -e
  return $rc
}

# ---- Helper: check if a package is installed ----
package_installed() {
  local pkg="$1"
  # dpkg -l returns 0 if package is found in desired state install and status installed
  if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
    return 0
  fi
  return 1
}

# ---- Helper: check if package is available (not installed) ----
package_available() {
  local pkg="$1"
  # apt-cache policy returns 0 if package exists in cache
  if run_apt_query "policy" "$pkg" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ---- Helper: check cache validity and update if needed ----
maybe_update_cache() {
  # If update_cache is explicitly true, always update
  if [ "$update_cache" = true ]; then
    run_apt "update"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
      FAILED=true
      MSG="Failed to update apt cache (exit code $rc)"
      emit_result
    fi
    return
  fi

  # If cache_valid_time is set, check the age of the cache
  if [ -n "$cache_valid_time" ]; then
    local cache_dir="/var/cache/apt"
    if [ -d "$cache_dir" ]; then
      # Find the most recent timestamp in the cache directory
      local cache_age
      cache_age=$(find "$cache_dir" -type f \( -name '*-Packages' -o -name '*-Sources' -o -name '*-Release' \) -o -path '*/Packages' -o -path '*/Sources' -o -path '*/Release' 2>/dev/null | sort -n | tail -1 | xargs stat -c '%Y' 2>/dev/null || true)
      if [ -z "$cache_age" ]; then
        # No cache files found, update
        run_apt "update"
        local rc=$?
        if [ "$rc" -ne 0 ]; then
          FAILED=true
          MSG="Failed to update apt cache (exit code $rc)"
          emit_result
        fi
        return
      fi

      local now
      now=$(date +%s)
      local age=$((now - cache_age))

      if [ "$age" -gt "$cache_valid_time" ]; then
        run_apt "update"
        local rc=$?
        if [ "$rc" -ne 0 ]; then
          FAILED=true
          MSG="Failed to update apt cache (exit code $rc)"
          emit_result
        fi
      fi
    else
      # Cache directory doesn't exist, update
      run_apt "update"
      local rc=$?
      if [ "$rc" -ne 0 ]; then
        FAILED=true
        MSG="Failed to update apt cache (exit code $rc)"
        emit_result
      fi
    fi
  fi
}

# ---- Main: parse arguments ----
# Ansible passes arguments as KEY=VALUE
PARSE_ERROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    name=*)
      # Handle comma-separated list
      IFS=',' read -ra ADDR <<< "${1#*=}"
      for item in "${ADDR[@]}"; do
        names+=("$item")
      done
      ;;
    pkg=*)
      # Handle comma-separated list (alias for name)
      IFS=',' read -ra ADDR <<< "${1#*=}"
      for item in "${ADDR[@]}"; do
        pkgs+=("$item")
      done
      ;;
    state=*)
      state="${1#*=}"
      ;;
    update_cache=*)
      update_cache="${1#*=}"
      ;;
    cache_valid_time=*)
      cache_valid_time="${1#*=}"
      ;;
    upgrade=*)
      upgrade="${1#*=}"
      ;;
    deb=*)
      deb="${1#*=}"
      ;;
    purge=*)
      purge="$(parse_bool "${1#*=}")"
      ;;
    only_upgrade=*)
      only_upgrade="$(parse_bool "${1#*=}")"
      ;;
    force_apt_get=*)
      force_apt_get="$(parse_bool "${1#*=}")"
      ;;
    default_release=*)
      default_release="${1#*=}"
      ;;
    install_recommends=*)
      install_recommends="$(parse_bool "${1#*=}")"
      ;;
    allow_unauthenticated=*)
      allow_unauthenticated="$(parse_bool "${1#*=}")"
      ;;
    allow_downgrade=*)
      allow_downgrade="$(parse_bool "${1#*=}")"
      ;;
    allow_change_held_packages=*)
      allow_change_held_packages="$(parse_bool "${1#*=}")"
      ;;
    dpkg_options=*)
      dpkg_options="${1#*=}"
      ;;
    fail_on_autoremove=*)
      fail_on_autoremove="$(parse_bool "${1#*=}")"
      ;;
    lock_timeout=*)
      lock_timeout="${1#*=}"
      ;;
    policy_rc_d=*)
      policy_rc_d="${1#*=}"
      ;;
    use_sudo=*)
      use_sudo="${1#*=}"
      ;;
    *)
      # Unknown parameter — record but continue (Ansible may pass _ansible_* keys)
      ;;
  esac
  shift
done

# Merge pkgs alias into names
if [ ${#pkgs[@]} -gt 0 ]; then
  for p in "${pkgs[@]}"; do
    names+=("$p")
  done
fi

# ---- Validate state ----
case "$state" in
  present|absent|latest) ;;
  *)
    FAILED=true
    MSG="Invalid state '$state'. Valid states: present, absent, latest"
    emit_result
    ;;
esac

# ---- Validate use_sudo ----
case "$use_sudo" in
  auto|true|false) ;;
  *)
    FAILED=true
    MSG="Invalid use_sudo '$use_sudo'. Valid values: auto, true, false"
    emit_result
    ;;
esac

if [ "$state" = "present" ] && [ ${#names[@]} -eq 0 ] && [ -z "$deb" ] && [ "$update_cache" = false ] && [ -z "$upgrade" ]; then
  FAILED=true
  MSG="Either 'name', 'deb', 'update_cache' or 'upgrade' is required."
  emit_result
fi

# ---- Detect backend + sudo ----
detect_apt_and_sudo

# ---- Update cache if requested ----
maybe_update_cache

# ---- Handle local .deb install ----
if [ -n "$deb" ]; then
  if [ ! -f "$deb" ]; then
    FAILED=true
    MSG="Local .deb file not found: $deb"
    emit_result
  fi
  if run_apt "install" "$deb"; then
    CHANGED=true
    RESULTS+=("Installed local .deb: $deb")
  else
    FAILED=true
    MSG="Failed to install .deb: $STDERR"
    emit_result
  fi
fi

# ---- Upgrade ----
if [ -n "$upgrade" ]; then
  case "$upgrade" in
    dist|full|yes|safe|true)
      up_cmd="upgrade"
      [ "$upgrade" = "dist" ] || [ "$upgrade" = "full" ] && up_cmd="dist-upgrade"
      if run_apt "$up_cmd"; then
        CHANGED=true
        RESULTS+=("System upgraded ($upgrade)")
      else
        FAILED=true
        MSG="Upgrade failed: $STDERR"
        emit_result
      fi
      ;;
    *)
      FAILED=true
      MSG="Invalid upgrade value '$upgrade'. Valid: dist, full, yes, safe"
      emit_result
      ;;
  esac
fi

# ---- Install / remove packages ----
if [ ${#names[@]} -gt 0 ]; then
  case "$state" in
    present|latest)
      to_install=()
      for pkg in "${names[@]}"; do
        if ! package_installed "$pkg"; then
          to_install+=("$pkg")
        else
          RESULTS+=("Package already installed: $pkg")
        fi
      done
      if [ ${#to_install[@]} -gt 0 ]; then
        apt_install_args=("install")
        [ "$state" = "latest" ] && apt_install_args+=("--only-upgrade")
        [ "$only_upgrade" = true ] && apt_install_args+=("--only-upgrade")
        for pkg in "${to_install[@]}"; do
          apt_install_args+=("$pkg")
        done
        if run_apt "${apt_install_args[@]}"; then
          CHANGED=true
          for pkg in "${to_install[@]}"; do
            RESULTS+=("Installed: $pkg")
          done
        else
          FAILED=true
          MSG="Failed to install packages: $STDERR"
          emit_result
        fi
      fi
      ;;
    absent)
      to_remove=()
      for pkg in "${names[@]}"; do
        if package_installed "$pkg"; then
          to_remove+=("$pkg")
        else
          RESULTS+=("Package already absent: $pkg")
        fi
      done
      if [ ${#to_remove[@]} -gt 0 ]; then
        apt_remove_args=("remove")
        [ "$purge" = true ] && apt_remove_args=("purge")
        for pkg in "${to_remove[@]}"; do
          apt_remove_args+=("$pkg")
        done
        if run_apt "${apt_remove_args[@]}"; then
          CHANGED=true
          for pkg in "${to_remove[@]}"; do
            RESULTS+=("Removed: $pkg")
          done
          if [ "$autoremove" = true ]; then
            if run_apt "autoremove"; then
              RESULTS+=("Autoremoved orphaned dependencies")
            elif [ "$fail_on_autoremove" = true ]; then
              FAILED=true
              MSG="autoremove failed: $STDERR"
              emit_result
            fi
          fi
        else
          FAILED=true
          MSG="Failed to remove packages: $STDERR"
          emit_result
        fi
      fi
      ;;
  esac
fi

# ---- Final message ----
if [ -z "$MSG" ]; then
  if [ "$CHANGED" = true ]; then
    MSG="apt operation completed"
  else
    MSG="Nothing to do — system already in desired state"
  fi
fi

emit_result
