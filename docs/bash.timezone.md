# bash.timezone.sh — Bash Timezone Module (callable as `bash.timezone:`)

## Overview

A pure Bash replacement for `ansible.builtin.timezone` — callable as **`bash.timezone:`** in Ansible playbooks. Sets the system timezone via `timedatectl` on systemd hosts. Designed for environments with fine-grained sudo policies.

Supports any timezone string accepted by `timedatectl set-timezone` (e.g. `America/New_York`, `Europe/London`, `UTC`).

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Set timezone to New York
      bash.timezone:
        name: America/New_York
```

```yaml
    - name: Set timezone (using alias)
      bash.timezone:
        timezone: Europe/Berlin
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `timezone` | str | — | Timezone to set (e.g. `America/New_York`, `UTC`). Required. |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Set timezone to 'America/New_York'",
  "rc": 0,
  "invocation": {
    "args": {
      "name": "America/New_York",
      "use_sudo": "auto"
    }
  }
}
```

- `changed` (bool) — whether the timezone was changed
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — exit code from `timedatectl` (0 on success)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before the `timedatectl` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `timezone` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the `timedatectl` commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/timedatectl *`
- ✅ **Non-root users** can manage timezones with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare `timedatectl` if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run `timedatectl` directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage timezone without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/timedatectl set-timezone *, /usr/bin/timedatectl show *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Set timezone
      bash.timezone:
        name: America/Chicago
```

## Requirements

- `timedatectl` must be available (systemd-based host)
- `sudo` is only required when running as a non-root user with `use_sudo` set to `auto` or `true`
