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
# ansible-module: bash.yum
# description: Manages packages with the yum/dnf package manager — pure Bash.
#   Callable as `bash.yum:` in Ansible playbooks.
#   Targets RHEL/CentOS 7 (yum) and any dnf-based RHEL family host; auto-detects
#   whether `yum` is backed by the legacy YUM (Python) or by `dnf` and only emits
#   dnf-specific flags (--allowerasing, --nobest, install_weak_deps,
#   allow_downgrade) when a real dnf backend is present.
#   Calls sudo -n internally when running as non-root, respecting fine-grained
#   sudoers policies. No reliance on Ansible's become system.
# options:
#   name:
#     description: A package name or package specifier with version (pkg-1.0), a URL, or local path to an .rpm.
#                  Can be a comma-separated string or list. @group for groups.
#     required: true (unless autoremove=true)
#     type: list
#   pkg:
#     description: Alias for name.
#     required: false
#     type: list
#   state:
#     description: Whether to install (present, latest), or remove (absent) a package.
#     required: false
#     default: "present"
#     choices: ["absent", "present", "installed", "removed", "latest"]
#   enablerepo:
#     description: Repositories to enable for this transaction.
#     required: false
#     type: list
#   disablerepo:
#     description: Repositories to disable for this transaction.
#     required: false
#     type: list
#   autoremove:
#     description: Remove leaf packages no longer required by any user-installed package.
#     required: false
#     type: bool
#     default: false
#   update_cache:
#     description: Force yum/dnf to refresh cache before the transaction.
#     required: false
#     type: bool
#     default: false
#   update_only:
#     description: When state=latest, only update installed packages, do not install new ones.
#     required: false
#     type: bool
#     default: false
#   allow_downgrade:
#     description: Allow downgrading an installed package to match the requested version. (dnf backend only)
#     required: false
#     type: bool
#     default: false
#   allowerasing:
#     description: Allow erasing installed packages to resolve dependencies. (dnf backend only)
#     required: false
#     type: bool
#     default: false
#   nobest:
#     description: Do not force the highest available version. Opposite of best. (dnf backend only)
#     required: false
#     type: bool
#     default: false
#   exclude:
#     description: Package names to exclude from install/update.
#     required: false
#     type: list
#   disable_gpg_check:
#     description: Disable GPG signature checking.
#     required: false
#     type: bool
#     default: false
#   skip_broken:
#     description: Skip packages with broken dependencies.
#     required: false
#     type: bool
#     default: false
#   installroot:
#     description: Alternative install root directory.
#     required: false
#     type: str
#     default: "/"
#   download_only:
#     description: Only download packages, do not install them.
#     required: false
#     type: bool
#     default: false
#   cacheonly:
#     description: Run entirely from system cache, do not download metadata.
#     required: false
#     type: bool
#     default: false
#   bugfix:
#     description: Only install bugfix-related updates when state=latest. (dnf backend only)
#     required: false
#     type: bool
#     default: false
#   security:
#     description: Only install security-related updates when state=latest. (dnf backend only)
#     required: false
#     type: bool
#     default: false
#   conf_file:
#     description: Path to a custom yum/dnf configuration file.
#     required: false
#     type: str
#   validate_certs:
#     description: Validate SSL certificates when installing from HTTPS URLs.
#     required: false
#     type: bool
#     default: true
#   sslverify:
#     description: Enable/disable SSL verification for repository transactions.
#     required: false
#     type: bool
#     default: true
#   releasever:
#     description: Alternative release version for package installation.
#     required: false
#     type: str
#   download_dir:
#     description: Alternate directory to store downloaded packages.
#     required: false
#     type: str
#   disable_excludes:
#     description: Disable excludes defined in yum/dnf config files (all, main, repoid).
#     required: false
#     type: str
#   disable_plugin:
#     description: Plugin names to disable for the transaction.
#     required: false
#     type: list
#   enable_plugin:
#     description: Plugin names to enable for the transaction.
#     required: false
#     type: list
#   lock_timeout:
#     description: Time to wait for the lockfile to be freed.
#     required: false
#     type: int
#     default: 30
#   list:
#     description: Non-idempotent list commands for /usr/bin/ansible (not playbooks).
#     required: false
#     type: str
#   use_backend:
#     description: Which backend to use — auto, yum, dnf.
#     required: false
#     type: str
#     default: "auto"
#   use_sudo:
#     description: Whether to prefix yum/dnf commands with sudo. auto=true if not root.
#     required: false
#     type: str
#     default: "auto"
#     choices: ["auto", true, false]

# STRICT MODE
set -euo pipefail

# ---- Constants ----
MODULE_NAME="bash.yum"
CHANGED=false
FAILED=false
MSG=""
RESULTS=()
STDOUT=""
STDERR=""

# ---- State vars (defaults) ----
state="present"
autoremove=false
update_cache=false
update_only=false
allow_downgrade=false
allowerasing=false
nobest=false
disable_gpg_check=false
skip_broken=false
installroot="/"
download_only=false
cacheonly=false
bugfix=false
security=false
validate_certs=true
sslverify=true
install_weak_deps=true
lock_timeout=30
use_backend="auto"
use_sudo="auto"
names=()
enablerepos=()
disablerepos=()
excludes=()
disable_plugins=()
enable_plugins=()
conf_file=""
releasever=""
download_dir=""
disable_excludes=""
list_mode=""

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

  # Include invocation info for debugging
  out+=",\"invocation\": {\"module_args\": {\"name\": ["
  local first=true
  for n in "${names[@]}"; do
    $first || out+=", "
    first=false
    out+=$(jq_safe "$n")
  done
  out+="], \"state\": $(jq_safe "$state")}}"

  out+="}"

  echo "$out"
  if [ "$FAILED" = true ]; then
    exit 1
  fi
  exit 0
}

# ---- Helper: JSON-safe string quoting (Bash-native, no jq dependency) ----
jq_safe() {
  local s="$1"
  # Escape backslashes, newlines, tabs, CR, and double-quotes (JSON-safe)
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

# ---- Helper: detect available backend and sudo prefix ----
# Sets global PKG_BIN (yum or dnf) + IS_DNF (true/false) + SUDO_PREFIX
detect_backend_and_sudo() {
  local backend=""

  case "$use_backend" in
    dnf)
      if command_exists dnf; then
        backend="dnf"
      else
        FAILED=true
        MSG="Requested backend 'dnf' but dnf is not installed on the target system."
        emit_result
      fi
      ;;
    yum)
      if command_exists yum; then
        backend="yum"
      else
        FAILED=true
        MSG="Requested backend 'yum' but yum is not installed on the target system."
        emit_result
      fi
      ;;
    auto|*)
      if command_exists dnf; then
        backend="dnf"
      elif command_exists yum; then
        backend="yum"
      else
        # Don't fail here — let the command itself error if neither is found
        backend="dnf"
      fi
      ;;
  esac

  IS_DNF=false
  # yum on modern RHEL/Fedora is a compatibility shim that execs dnf; only treat
  # as a real dnf backend when `dnf` exists as its own binary.
  if [ "$backend" = "dnf" ]; then
    IS_DNF=true
  fi

  # Determine sudo prefix
  SUDO_PREFIX=""
  if [ "$use_sudo" = "auto" ]; then
    if [ "$(id -u)" -ne 0 ]; then
      # Running as non-root — need sudo for package commands
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
      MSG="use_sudo=true but sudo is not installed on the target system."
      emit_result
    fi
  fi
  # use_sudo=false → SUDO_PREFIX stays empty

  PKG_BIN="$backend"
}

# ---- Helper: run yum/dnf and capture output ----
# Builds the full command using SUDO_PREFIX and PKG_BIN
run_pkg() {
  local cmd="$1"
  shift
  local extra_args=("$@")

  # Start building the argument array
  local pkg_args=()

  # If we have a sudo prefix, add it as individual words
  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    pkg_args+=($SUDO_PREFIX)
  fi

  pkg_args+=("${PKG_BIN}" "-y")

  # Global flags
  if [ "$disable_gpg_check" = true ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--nogpgcheck")
    else
      # Legacy yum disables checks via conf; -y already implies non-interactive
      pkg_args+=("--setopt=tsflags=nogpgcheck")
    fi
  fi
  if [ "$skip_broken" = true ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--skip-broken")
    else
      pkg_args+=("--setopt=skip_missing_names_on_install=True")
    fi
  fi
  if [ "$IS_DNF" = true ]; then
    # dnf-only flags — must NOT be emitted for legacy yum (would error on EL7)
    if [ "$allowerasing" = true ]; then
      pkg_args+=("--allowerasing")
    fi
    if [ "$nobest" = true ]; then
      pkg_args+=("--nobest")
    fi
    if [ "$install_weak_deps" = false ]; then
      pkg_args+=("--setopt=install_weak_deps=False")
    fi
    if [ "$allow_downgrade" = true ]; then
      pkg_args+=("--setopt=allow_downgrade=True")
    fi
  fi
  if [ "$cacheonly" = true ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("-C")
    else
      pkg_args+=("--cacheonly")
    fi
  fi
  if [ -n "$conf_file" ]; then
    pkg_args+=("-c" "$conf_file")
  fi
  if [ -n "$releasever" ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--releasever" "$releasever")
    else
      pkg_args+=("--releasever=$releasever")
    fi
  fi
  if [ -n "$installroot" ] && [ "$installroot" != "/" ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--installroot" "$installroot")
    else
      pkg_args+=("--installroot=$installroot")
    fi
  fi
  if [ "$download_only" = true ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--downloadonly")
    else
      pkg_args+=("--downloadonly")
    fi
  fi
  if [ -n "$download_dir" ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--downloaddir" "$download_dir")
    else
      pkg_args+=("--downloaddir=$download_dir")
    fi
  fi
  if [ -n "$disable_excludes" ]; then
    if [ "$IS_DNF" = true ]; then
      pkg_args+=("--disableexcludes" "$disable_excludes")
    else
      pkg_args+=("--disableexcludes=$disable_excludes")
    fi
  fi

  # Lock timeout
  if [ "$lock_timeout" -ne 30 ]; then
    pkg_args+=("--setopt=timeout=$lock_timeout")
  fi

  # Weak dependencies (legacy yum: best-effort, no-op when unsupported)

  # Repo management
  for repo in "${enablerepos[@]}"; do
    pkg_args+=("--enablerepo=$repo")
  done
  for repo in "${disablerepos[@]}"; do
    pkg_args+=("--disablerepo=$repo")
  done

  # Plugins
  for p in "${disable_plugins[@]}"; do
    pkg_args+=("--disableplugin=$p")
  done
  for p in "${enable_plugins[@]}"; do
    pkg_args+=("--enableplugin=$p")
  done

  # Excludes
  for ex in "${excludes[@]}"; do
    pkg_args+=("--exclude=$ex")
  done

  # Security/bugfix filters (only meaningful for update/upgrade) — dnf-only
  if [ "$IS_DNF" = true ]; then
    if [ "$cmd" = "update" ] || [ "$cmd" = "install" ]; then
      if [ "$bugfix" = true ]; then
        pkg_args+=("--bugfix")
      fi
      if [ "$security" = true ]; then
        pkg_args+=("--security")
      fi
    fi
  fi

  # Subcommand
  pkg_args+=("$cmd")

  # Extra positional args (packages, groups)
  pkg_args+=("${extra_args[@]}")

  # Run — allow failure so we can capture return code
  set +e
  local tmp_stderr
  tmp_stderr=$(mktemp)
  STDOUT=$( "${pkg_args[@]}" 2>"$tmp_stderr" )
  local rc=$?
  STDERR=$(cat "$tmp_stderr")
  rm -f "$tmp_stderr"
  set -e

  # Extract meaningful messages for results
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^(Installing|Upgrading|Removing|Installed|Upgraded|Removed|Reinstalling|Reinstalled|Obsoleting|Obsoleted)'; then
      RESULTS+=("$line")
    fi
  done <<< "$STDOUT"

  echo "$rc"
}

# ---- Helper: run yum/dnf for a read-only query ----
run_pkg_query() {
  local cmd="$1"
  shift
  local extra_args=("$@")

  local q_args=()

  if [ -n "$SUDO_PREFIX" ]; then
    # shellcheck disable=SC2086
    q_args+=($SUDO_PREFIX)
  fi

  q_args+=("${PKG_BIN}" "$cmd")
  q_args+=("${extra_args[@]}")

  set +e
  "${q_args[@]}" 2>/dev/null
  local rc=$?
  set -e
  return $rc
}

# ---- Check if a package is installed ----
package_installed() {
  local pkg="$1"
  if run_pkg_query "list" "installed" "$pkg"; then
    return 0
  fi
  return 1
}

# ---- Check if package is available (not installed) ----
package_available() {
  local pkg="$1"
  if run_pkg_query "list" "available" "$pkg"; then
    return 0
  fi
  return 1
}

# ---- Is package a group? ----
is_group() {
  local name="$1"
  case "$name" in
    @*|group:*)
      return 0
      ;;
  esac
  return 1
}

# ---- List mode (ansible.builtin.yum list parameter) ----
handle_list() {
  local arg="$1"
  local rc

  # run_pkg sets global STDOUT/STDERR as side effect and echoes rc
  case "$arg" in
    available|updates|upgrades|installed|extras|obsoletes|recent)
      set +e
      rc=$( run_pkg "list" "$arg" 2>/dev/null )
      set -e
      if [ "$rc" -ne 0 ]; then
        FAILED=true
        MSG="Failed to list $arg: $STDERR"
        emit_result
      fi
      MSG="List of $arg packages"
      RESULTS+=("Listed $arg packages")
      emit_result
      ;;
    *)
      # When arg looks like a package name, run list <pkg>
      set +e
      rc=$( run_pkg "list" "$arg" 2>/dev/null )
      set -e
      if [ "$rc" -ne 0 ]; then
        MSG="Package '$arg' not found"
        RESULTS+=("Package '$arg' not found via list")
        emit_result
      fi
      MSG="List results for '$arg'"
      RESULTS+=("Listed package '$arg'")
      emit_result
      ;;
  esac
}

# ======== MAIN ========

# ---- Parse arguments ----
# Ansible passes module arguments as key=value pairs on the command line.
# List-type params are comma-separated.
for arg in "$@"; do
  case "${arg}" in
    *=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      ;;
    *)
      continue
      ;;
  esac

  case "$key" in
    name|pkg)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && names+=("$part")
      done
      ;;
    state)
      state="$val"
      ;;
    enablerepo)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && enablerepos+=("$part")
      done
      ;;
    disablerepo)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && disablerepos+=("$part")
      done
      ;;
    autoremove)
      case "$val" in
        1|yes|true|True|TRUE) autoremove=true ;;
        *) autoremove=false ;;
      esac
      ;;
    update_cache|expire-cache)
      case "$val" in
        1|yes|true|True|TRUE) update_cache=true ;;
        *) update_cache=false ;;
      esac
      ;;
    update_only)
      case "$val" in
        1|yes|true|True|TRUE) update_only=true ;;
        *) update_only=false ;;
      esac
      ;;
    allow_downgrade)
      case "$val" in
        1|yes|true|True|TRUE) allow_downgrade=true ;;
        *) allow_downgrade=false ;;
      esac
      ;;
    allowerasing)
      case "$val" in
        1|yes|true|True|TRUE) allowerasing=true ;;
        *) allowerasing=false ;;
      esac
      ;;
    nobest)
      case "$val" in
        1|yes|true|True|TRUE) nobest=true ;;
        *) nobest=false ;;
      esac
      ;;
    exclude)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && excludes+=("$part")
      done
      ;;
    disable_gpg_check)
      case "$val" in
        1|yes|true|True|TRUE) disable_gpg_check=true ;;
        *) disable_gpg_check=false ;;
      esac
      ;;
    skip_broken)
      case "$val" in
        1|yes|true|True|TRUE) skip_broken=true ;;
        *) skip_broken=false ;;
      esac
      ;;
    installroot)
      installroot="$val"
      ;;
    download_only)
      case "$val" in
        1|yes|true|True|TRUE) download_only=true ;;
        *) download_only=false ;;
      esac
      ;;
    cacheonly)
      case "$val" in
        1|yes|true|True|TRUE) cacheonly=true ;;
        *) cacheonly=false ;;
      esac
      ;;
    bugfix)
      case "$val" in
        1|yes|true|True|TRUE) bugfix=true ;;
        *) bugfix=false ;;
      esac
      ;;
    security)
      case "$val" in
        1|yes|true|True|TRUE) security=true ;;
        *) security=false ;;
      esac
      ;;
    conf_file)
      conf_file="$val"
      ;;
    validate_certs)
      case "$val" in
        0|no|false|False|FALSE) validate_certs=false ;;
        *) validate_certs=true ;;
      esac
      if [ "$validate_certs" = false ]; then
        disable_gpg_check=true
      fi
      ;;
    sslverify)
      case "$val" in
        0|no|false|False|FALSE) sslverify=false ;;
        *) sslverify=true ;;
      esac
      ;;
    releasever)
      releasever="$val"
      ;;
    install_weak_deps)
      case "$val" in
        0|no|false|False|FALSE) install_weak_deps=false ;;
        *) install_weak_deps=true ;;
      esac
      ;;
    download_dir)
      download_dir="$val"
      ;;
    disable_excludes)
      disable_excludes="$val"
      ;;
    disable_plugin)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && disable_plugins+=("$part")
      done
      ;;
    enable_plugin)
      IFS=',' read -ra parts <<< "$val"
      for part in "${parts[@]}"; do
        part="${part## }"
        part="${part%% }"
        [ -n "$part" ] && enable_plugins+=("$part")
      done
      ;;
    lock_timeout)
      lock_timeout="$val"
      ;;
    list)
      list_mode="$val"
      ;;
    use_backend)
      use_backend="$val"
      ;;
    use_sudo)
      use_sudo="$val"
      ;;
    *)
      MSG="${MSG}Unknown parameter: $key; "
      ;;
  esac
done

# ---- Detect yum/dnf binary and sudo prefix ----
detect_backend_and_sudo

# ---- List mode (short-circuits) ----
if [ -n "$list_mode" ]; then
  handle_list "$list_mode"
  # handle_list calls emit_result — never returns
fi

# ---- Validate state ----
case "$state" in
  present|installed|latest|absent|removed) ;;
  *)
    FAILED=true
    MSG="Invalid state '$state'. Valid values: absent, present, installed, removed, latest"
    emit_result
    ;;
esac

# ---- Normalize state aliases ----
case "$state" in
  installed) state="present" ;;
  removed)   state="absent" ;;
esac

# ---- Autoremove mode (if name is empty and autoremove=true) ----
if [ ${#names[@]} -eq 0 ] && [ "$autoremove" = true ]; then
  MSG="Running autoremove of unneeded dependencies"
  rc=$(run_pkg "autoremove")
  if [ "$rc" -eq 0 ]; then
    CHANGED=true
    RESULTS+=("Autoremoved unneeded packages")
    emit_result
  else
    FAILED=true
    MSG="Autoremove failed (exit code $rc)"
    emit_result
  fi
fi

# ---- Require name for non-autoremove operations ----
if [ ${#names[@]} -eq 0 ]; then
  FAILED=true
  MSG="No package name specified. Use 'name' parameter with a package name, or 'autoremove=true'."
  emit_result
fi

# ---- Resolve "state=latest" with update_only ----
if [ "$state" = "latest" ] && [ "$update_only" = true ]; then
  state="latest_update_only"
fi

# ---- Update cache if requested ----
if [ "$update_cache" = true ]; then
  set +e
  if [ "$IS_DNF" = true ]; then
    run_pkg "makecache" >/dev/null 2>&1
  else
    run_pkg "makecache" "fast" >/dev/null 2>&1
  fi
  cache_rc=$?
  set -e
  if [ "$cache_rc" -ne 0 ]; then
    STDERR="${STDERR}Cache update failed."
  fi
fi

# ======== PACKAGE OPERATIONS ========
CHANGED=false
RESULTS=()

for pkg_spec in "${names[@]}"; do
  pkg="${pkg_spec%% *}"   # Strip comparison operators like '>', '>='
  pkg_name="$pkg_spec"
  is_group_name=false

  # Detect group
  if is_group "$pkg_spec"; then
    is_group_name=true
    pkg="${pkg_spec#@}"
    pkg="${pkg#group:}"
    pkg_name="$pkg_spec"
  fi

  case "$state" in
    present)
      if [ "$is_group_name" = true ]; then
        set +e
        run_pkg "group" "list" "installed" "$pkg" >/dev/null 2>&1
        installed_rc=$?
        set -e
        if [ "$installed_rc" -eq 0 ]; then
          RESULTS+=("Group '$pkg_spec' is already installed — no change")
          continue
        fi
        rc=$(run_pkg "groupinstall" "$pkg")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Installed group '$pkg_spec'")
        else
          FAILED=true
          MSG="Failed to install group '$pkg_spec' (exit code $rc)"
          emit_result
        fi
      else
        if echo "$pkg_spec" | grep -qE '(>=?|<=?|==)'; then
          rc=$(run_pkg "install" "$pkg_spec")
        elif package_installed "$pkg"; then
          RESULTS+=("Package '$pkg' is already installed — no change")
          continue
        else
          rc=$(run_pkg "install" "$pkg")
        fi

        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Installed '$pkg_spec'")
        else
          FAILED=true
          MSG="Failed to install '$pkg_spec' (exit code $rc)"
          emit_result
        fi
      fi
      ;;

    latest)
      if [ "$is_group_name" = true ]; then
        rc=$(run_pkg "groupupdate" "$pkg")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Updated group '$pkg_spec' to latest")
        else
          FAILED=true
          MSG="Failed to update group '$pkg_spec' (exit code $rc)"
          emit_result
        fi
      else
        if [ "$pkg_spec" = "*" ]; then
          rc=$(run_pkg "update")
          if [ "$rc" -eq 0 ]; then
            CHANGED=true
            RESULTS+=("Updated all packages to latest")
          else
            FAILED=true
            MSG="Failed to update all packages (exit code $rc)"
            emit_result
          fi
        else
          rc=$(run_pkg "update" "$pkg_spec")
          if [ "$rc" -eq 0 ]; then
            CHANGED=true
            RESULTS+=("Updated '$pkg_spec' to latest")
          else
            FAILED=true
            MSG="Failed to update '$pkg_spec' (exit code $rc)"
            emit_result
          fi
        fi
      fi
      ;;

    latest_update_only)
      if [ "$is_group_name" = true ]; then
        set +e
        run_pkg "group" "list" "installed" "$pkg" >/dev/null 2>&1
        grp_rc=$?
        set -e
        if [ "$grp_rc" -ne 0 ]; then
          RESULTS+=("Group '$pkg_spec' is not installed — skipping (update_only=true)")
          continue
        fi
        rc=$(run_pkg "groupupdate" "$pkg")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Updated group '$pkg_spec'")
        fi
      else
        if ! package_installed "$pkg"; then
          RESULTS+=("Package '$pkg_spec' not installed — skipping (update_only=true)")
          continue
        fi
        rc=$(run_pkg "update" "$pkg_spec")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Updated '$pkg_spec'")
        fi
      fi
      ;;

    absent)
      if [ "$is_group_name" = true ]; then
        set +e
        run_pkg "group" "list" "installed" "$pkg" >/dev/null 2>&1
        g_rc=$?
        set -e
        if [ "$g_rc" -ne 0 ]; then
          RESULTS+=("Group '$pkg_spec' is not installed — no change")
          continue
        fi
        rc=$(run_pkg "groupremove" "$pkg")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Removed group '$pkg_spec'")
        else
          FAILED=true
          MSG="Failed to remove group '$pkg_spec' (exit code $rc)"
          emit_result
        fi
      else
        if ! package_installed "$pkg"; then
          RESULTS+=("Package '$pkg_spec' is not installed — no change")
          continue
        fi
        rc=$(run_pkg "remove" "$pkg_spec")
        if [ "$rc" -eq 0 ]; then
          CHANGED=true
          RESULTS+=("Removed '$pkg_spec'")
        else
          FAILED=true
          MSG="Failed to remove '$pkg_spec' (exit code $rc)"
          emit_result
        fi
      fi
      ;;

    default)
      FAILED=true
      MSG="Internal error: unhandled state '$state'"
      emit_result
      ;;
  esac
done

# ---- If autoremove is set alongside package operations ----
if [ "$autoremove" = true ] && [ ${#names[@]} -gt 0 ]; then
  rc=$(run_pkg "autoremove")
  if [ "$rc" -eq 0 ]; then
    CHANGED=true
    RESULTS+=("Autoremoved orphaned dependencies")
  fi
fi

# ---- Final result ----
if [ "$FAILED" = false ]; then
  if [ "$CHANGED" = true ]; then
    MSG="Package operation(s) completed successfully"
  else
    MSG="Nothing to do — all requested packages are in the desired state"
  fi
fi

emit_result
