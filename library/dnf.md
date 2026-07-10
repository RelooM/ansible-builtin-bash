# dnf.sh — Bash DNF Module

## Overview

A pure Bash replacement for `ansible.builtin.dnf` designed for environments with fine-grained sudo policies. Mirrors the full parameter surface of the original Python module.

## Supported Parameters

### Core
| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `pkg` | list/str | — | Package name(s), version spec (`name-1.0`), URL, or local RPM path. `@group` for groups. |
| `state` | str | `present` | `present` / `absent` / `latest` / `installed` / `removed` |

### Repositories
| Parameter | Type | Description |
|---|---|---|
| `enablerepo` | list/str | Repos to enable for this transaction |
| `disablerepo` | list/str | Repos to disable for this transaction |
| `disable_excludes` | str | `all`, `main`, or repoid to disable excludes |

### Transaction Control
| Parameter | Type | Default | Description |
|---|---|---|---|
| `allow_downgrade` | bool | `false` | Allow version downgrade |
| `allowerasing` | bool | `false` | Allow erasing packages to resolve deps |
| `nobest` | bool | `false` | Don't force highest version |
| `install_weak_deps` | bool | `true` | Install weak dependencies |
| `skip_broken` | bool | `false` | Skip unavailable/broken packages |
| `download_only` | bool | `false` | Download only, don't install |
| `download_dir` | str | — | Alternate download directory |
| `cacheonly` | bool | `false` | Use system cache only |

### Updates
| Parameter | Type | Default | Description |
|---|---|---|---|
| `update_cache` / `expire-cache` | bool | `false` | Refresh cache before transaction |
| `update_only` | bool | `false` | Only update existing packages |
| `bugfix` | bool | `false` | Only bugfix updates (state=latest) |
| `security` | bool | `false` | Only security updates (state=latest) |

### Security & GPG
| Parameter | Type | Default | Description |
|---|---|---|---|
| `disable_gpg_check` | bool | `false` | Skip GPG signature check |
| `sslverify` | bool | `true` | SSL verification for repos |
| `validate_certs` | bool | `true` | Validate HTTPS certs (URL sources) |

### Paths
| Parameter | Type | Default | Description |
|---|---|---|---|
| `conf_file` | str | — | Custom dnf config file path |
| `installroot` | str | `/` | Alternative install root |
| `releasever` | str | — | Release version |

### Plugins
| Parameter | Type | Description |
|---|---|---|
| `disable_plugin` | list/str | Plugins to disable |
| `enable_plugin` | list/str | Plugins to enable |

### Other
| Parameter | Type | Default | Description |
|---|---|---|---|
| `autoremove` | bool | `false` | Remove orphaned leaf packages |
| `exclude` | list/str | — | Packages to exclude |
| `lock_timeout` | int | `30` | Lock wait timeout (seconds) |
| `use_backend` | str | `auto` | `auto` / `dnf` / `dnf4` / `dnf5` |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |
| `list` | str | — | Non-idempotent list commands |

## Output

```json
{
  "changed": true,
  "failed": false,
  "msg": "Package operation(s) completed successfully",
  "rc": 0,
  "results": [
    "Installed: curl-8.0.1-1.fc38.x86_64"
  ],
  "invocation": {
    "module_args": {
      "name": ["curl"],
      "state": "present"
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code; dnf exit codes are in `results`)
- `results` (list) — per-package outcome messages
- `stdout` (str) — raw stdout from dnf (when present)
- `stderr` (str) — raw stderr from dnf (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `dnf` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `dnf` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific `dnf` commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/dnf install *, /usr/bin/dnf remove *`
- ✅ **Non-root users** can run package management with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare dnf if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run dnf directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage packages without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/dnf install *, /usr/bin/dnf remove *, /usr/bin/dnf update *, /usr/bin/dnf list *, /usr/bin/dnf makecache
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Install package
      dnf:
        name: httpd
        state: present
```

## State Mapping

| Playbook State | dnf Command | Behavior |
|---|---|---|
| `present` | `dnf install` | Install if missing, no-op if present |
| `latest` | `dnf update` / `dnf install` | Update to newest (install if missing) |
| `absent` | `dnf remove` | Remove if present, no-op if absent |
| `latest` + `update_only` | `dnf update` | Update existing only, skip new |
| `present` + `autoremove` | `dnf install` + `dnf autoremove` | Install + clean orphans |
