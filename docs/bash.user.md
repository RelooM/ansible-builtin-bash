# bash.user.sh — Bash User Module (callable as `bash.user:`)

## Overview

A pure Bash replacement for `ansible.builtin.user` — callable as **`bash.user:`** in Ansible playbooks. Designed for environments with fine-grained sudo policies. Mirrors the core parameter surface of the original Python module.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Create user
      bash.user:
        name: deploy
        state: present
        shell: /bin/bash
        groups: sudo,docker
        comment: "Deploy User"
```

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | Username (**required**) |
| `state` | str | `present` | `present` / `absent` |

### Identity

| Parameter | Type | Default | Description |
|---|---|---|---|
| `uid` | int | — | User ID (must be non-negative integer) |
| `group` | str | — | Primary group name or GID |
| `groups` | list/str | — | Supplementary groups (comma-separated) |
| `system` | bool | `false` | Create as system user (`useradd -r`) |
| `non_unique` | bool | `false` | Allow non-unique UID (only with `uid` set) |
| `uid_range` | str | — | UID range for validation (e.g., `100-999` or single number) |

### Home & Shell

| Parameter | Type | Default | Description |
|---|---|---|---|
| `home` | str | — | Home directory path |
| `shell` | str | — | Login shell path |
| `create_home` | bool | `true` | Create home directory for new users (`-m`/`-M`) |
| `move_home` | bool | `false` | Move home directory when changing home path |
| `skeleton` | str | — | Skeleton directory for new home (`-k`) |

### Account

| Parameter | Type | Default | Description |
|---|---|---|---|
| `comment` | str | — | GECOS field (full name, etc.) |
| `password` | str | — | Encrypted password string (hashed) |

### Removal

| Parameter | Type | Default | Description |
|---|---|---|---|
| `remove` | bool | `false` | Remove home directory and mail spool on `state=absent` |
| `force` | bool | `false` | Force removal even if user is logged in |

### Groups

| Parameter | Type | Default | Description |
|---|---|---|---|
| `append` | bool | `false` | Append to supplementary groups (don't replace existing) |

### Privilege

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

## Output

```json
{
  "changed": true,
  "failed": false,
  "msg": "User operation(s) completed successfully",
  "rc": 0,
  "results": [
    "Created user deploy"
  ],
  "invocation": {
    "module_args": {
      "name": "deploy",
      "state": "present",
      "shell": "/bin/bash",
      "groups": "sudo,docker",
      "system": false,
      "create_home": true
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code; command exit codes are in `results`)
- `results` (list) — per-operation outcome messages
- `stdout` (str) — raw stdout from useradd/usermod/userdel (when present)
- `stderr` (str) — raw stderr (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `useradd`/`usermod`/`userdel` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `user` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod`
- ✅ **Non-root users** can manage users with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare commands if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run commands directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage users without full root access
deploy ALL=(root) NOPASSWD: /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod, /usr/sbin/usermod *, /usr/sbin/useradd *, /usr/sbin/userdel *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Create deploy user
      bash.user:
        name: deploy
        state: present
        shell: /bin/bash
        groups: sudo
        comment: "Deploy User"
```

## State Mapping

| Playbook State | Command | Behavior |
|---|---|---|
| `present` | `useradd` | Create if missing, `usermod` if exists but differs |
| `absent` | `userdel` | Remove if present, no-op if absent |
| `absent` + `remove=true` | `userdel -r` | Remove user + home directory |
| `absent` + `force=true` | `userdel -f` | Force removal even if logged in |

## Idempotency

The module checks the current user state via `getent passwd` before making changes:
- **Create** — only runs `useradd` if the user doesn't exist
- **Modify** — compares current UID, GID, home, shell, comment, and groups; only runs `usermod` if something differs
- **Remove** — only runs `userdel` if the user exists

If no changes are needed, the module returns `changed: false` with `msg: "Nothing to do — user is already in desired state"`.

## Boolean Value Parsing

All boolean parameters accept: `1`/`yes`/`true`/`True`/`TRUE` (case-insensitive) for `true`, and `0`/`no`/`false`/`False`/`FALSE` for `false`.
