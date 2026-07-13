# bash.apt.sh — Bash APT Module (callable as `bash.apt:`)

## Overview

A pure Bash replacement for `ansible.builtin.apt` — callable as **`bash.apt:`** in Ansible playbooks. Manages Debian/Ubuntu packages via `apt-get` (or `apt`). Designed for environments with fine-grained sudo policies. The module handles privilege escalation internally via `sudo -n`, so no Ansible `become` is required.

Mirrors the full parameter surface of the original Python module.

**Target distributions:** Debian, Ubuntu, Linux Mint, Pop!_OS, and other dpkg/apt-based systems.

## Quick Start

### Install a package

```yaml
- hosts: all
  tasks:
    - name: Install nginx
      bash.apt:
        name: nginx
        state: present
```

### Remove a package

```yaml
    - name: Remove old nginx
      bash.apt:
        name: nginx
        state: absent
```

### Upgrade all packages

```yaml
    - name: Upgrade all packages safely
      bash.apt:
        upgrade: safe
        update_cache: true
```

### Autoremove orphaned packages

```yaml
    - name: Clean up orphaned dependencies
      bash.apt:
        autoremove: true
```

## Parameter Reference

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `pkg` | list | — | Package name(s), version spec (`pkg=1.0`), URL, or local `.deb` path. Comma-separated or list. Required unless `autoremove=true`. |
| `state` | str | `present` | `absent` / `present` / `installed` / `removed` / `latest` / `fixed` / `build-dep` |
| `upgrade` | str | — | Upgrade all packages: `yes` or `safe` (runs `apt-get upgrade`), `full` (runs `apt-get dist-upgrade`) |
| `deb` | str | — | Local `.deb` file path to install directly |
| `autoremove` | bool | `false` | Remove orphaned leaf packages that were installed as dependencies |

### Cache & Updates

| Parameter | Type | Default | Description |
|---|---|---|---|
| `update_cache` | bool | `false` | Run `apt-get update` before the transaction |
| `cache_valid_time` | int | — | Skip `apt-get update` if cache is younger than this many seconds |

### Transaction Control

| Parameter | Type | Default | Description |
|---|---|---|---|
| `purge` | bool | `false` | Remove configuration files too (`apt-get purge` instead of `remove`) |
| `only_upgrade` | bool | `false` | Only upgrade already-installed packages; never install new ones |
| `allow_downgrade` | bool | `false` | Allow downgrading to an older version |
| `allow_change_held_packages` | bool | `false` | Override package holds and allow held packages to change |
| `allow_unauthenticated` | bool | `false` | Allow packages that cannot be authenticated |
| `default_release` | str | — | Pin to a specific release (e.g. `stable`, `noble`) via `-t` |
| `install_recommends` | bool | `true` | Install recommended packages (set `false` to pass `--no-install-recommends`) |
| `dpkg_options` | str | — | Comma-separated dpkg options (e.g. `Force-ConfDef,Force-ConfOld`) passed via `-o Dpkg::Options::` |
| `fail_on_autoremove` | bool | `false` | Fail the task if `autoremove` would remove packages |

### Backend & Escalation

| Parameter | Type | Default | Description |
|---|---|---|---|
| `force_apt_get` | bool | `false` | Force use of `apt-get` over `apt` (useful on older systems where `apt` is absent) |
| `use_sudo` | str | `auto` | `auto` — use `sudo -n` if non-root; `true` — always use `sudo -n`; `false` — never |
| `lock_timeout` | int | `60` | Seconds to wait for the dpkg lock before giving up |
| `policy_rc_d` | int | — | Override `/usr/sbin/policy-rc.d` (`101` = disable service restarts, `0` = enable) |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Package operation(s) completed successfully",
  "rc": 0,
  "results": [
    "Installed nginx"
  ],
  "invocation": {
    "module_args": {
      "name": ["nginx"],
      "state": "present"
    }
  }
}
```

| Return | Type | Description |
|---|---|---|
| `changed` | bool | Whether any package was installed, removed, or upgraded |
| `failed` | bool | Whether the operation encountered an error |
| `msg` | str | Human-readable summary of the operation |
| `rc` | int | Module exit code (always `0` on success; apt exit codes are captured in `results` or `stderr`) |
| `results` | list | Per-package outcome messages (e.g. `"Installed nginx"`, `"Removed curl"`) |
| `stdout` | str | Raw stdout from the apt command (when present) |
| `stderr` | str | Raw stderr from the apt command (when present) |
| `invocation` | dict | Original module arguments — used by Ansible callback plugins for audit logging |

## Sudo & Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every apt command when running as a non-root user. This is the key design difference vs. Ansible's built-in `apt` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific apt commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/apt-get install *, /usr/bin/apt-get remove *`
- ✅ **Non-root users** can run package management with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare apt-get if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run apt-get directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage packages without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get install *, /usr/bin/apt-get remove *, /usr/bin/apt-get update, /usr/bin/apt-get autoremove, /usr/bin/apt-get purge *

# For dist-upgrade support, add:
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get dist-upgrade, /usr/bin/apt-get upgrade
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Install package
      bash.apt:
        name: nginx
        state: present
```

## State Mapping

| Playbook State | apt Command | Behavior |
|---|---|---|
| `present` / `installed` | `apt-get install` | Install if missing, no-op if already present |
| `latest` | `apt-get install` | Install if missing, upgrade if a newer version is available |
| `absent` / `removed` | `apt-get remove` | Remove if present, no-op if absent |
| `absent` + `purge` | `apt-get purge` | Remove including configuration files |
| `fixed` | `apt-get install -f` | Fix broken dependencies (no package names needed) |
| `build-dep` | `apt-get build-dep` | Install build dependencies for the given package(s) |
| `latest` + `only_upgrade` | `apt-get install --only-upgrade` | Upgrade existing only, skip packages not yet installed |

## Idempotency

The module is fully idempotent — repeated runs produce no changes when the system is already in the desired state.

- **`state: present`** — Uses `dpkg -l <pkg>` to check for `ii` (installed) status. Skips packages that are already installed.
- **`state: latest`** — Compares `apt-cache policy` output: `Installed` vs `Candidate` version strings. Only triggers an upgrade when the candidate is newer and differs from the installed version.
- **`state: absent`** — Checks `dpkg -l <pkg>` for installed status. Skips packages that are already absent.
- **`state: fixed`** — Runs `apt-get install -f` regardless (dependency resolution is inherently stateful).
- **`state: build-dep`** — Runs every time (build deps are not individually tracked for idempotency).

### `cache_valid_time` and idempotency

When `cache_valid_time` is set, the module checks the age of files under `/var/cache/apt/` (looking at `*-Packages`, `*-Sources`, `*-Release` timestamps). If the cache is younger than the specified number of seconds, `apt-get update` is skipped. This avoids unnecessary network calls on frequent playbook runs.

## APT vs apt-get Auto-Detection

The module auto-detects which apt backend to use:

| Condition | Backend Selected |
|---|---|
| `force_apt_get: true` | `apt-get` (fails if not installed) |
| `apt` is available on PATH | `apt` |
| `apt-get` is available on PATH | `apt-get` |
| Neither available | `apt-get` (will error at runtime) |

- By default, the module prefers `apt` over `apt-get` when both are available.
- Set `force_apt_get: true` on older systems where `apt` is not installed or where `apt-get` behavior is required.
- The `-y` (assume-yes) flag is always passed for non-interactive operation.
