# bash.selinux.sh — Bash SELinux Module (callable as `bash.selinux:`)

## Overview

A pure Bash replacement for `ansible.posix.selinux` — callable as **`bash.selinux:`** in Ansible playbooks. Manages SELinux state, policy, and booleans on RHEL/CentOS/Rocky/Alma systems. Designed for environments with fine-grained sudo policies.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Set SELinux to enforcing
      bash.selinux:
        state: enforcing
        policy: targeted

    - name: Allow httpd to make network connections
      bash.selinux:
        booleans:
          httpd_can_network_connect: on

    - name: Disable SELinux
      bash.selinux:
        state: disabled
```

## Parameters

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `state` | str | — | `enforcing`, `permissive`, or `disabled`. Sets the SELinux mode. If omitted, state is not changed. |
| `policy` | str | — | SELinux policy: `targeted`, `mls`, or `minimum`. If omitted, policy is not changed. |
| `booleans` | dict | — | Dict of SELinux booleans to set. Keys are boolean names, values are `on` or `off`. Example: `{'httpd_can_network_connect': 'on'}` |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

### `state` values

| Value | Behavior |
|---|---|
| `enforcing` | SELinux enforces policy — violations are denied and logged |
| `permissive` | SELinux logs violations but does not enforce — useful for debugging |
| `disabled` | SELinux is fully disabled. **Requires a reboot.** |

### `policy` values

| Value | Behavior |
|---|---|
| `targeted` | Default policy — confines specific daemons (recommended for most servers) |
| `mls` | Multi-Level Security — strict mandatory access control |
| `minimum` | Minimal targeted policy with only selected modules active |

### `booleans` examples

| Boolean | Meaning |
|---|---|
| `httpd_can_network_connect` | Allow httpd to make outbound network connections |
| `httpd_can_network_connect_db` | Allow httpd to connect to database ports |
| `httpd_enable_homedirs` | Allow httpd to read user home directories |
| `sshd_password_auth` | Allow sshd to use password authentication |
| `ftpd_full_access` | Allow ftpd full file access |

```yaml
bash.selinux:
  booleans:
    httpd_can_network_connect: on
    httpd_can_network_connect_db: off
```

## Output

```json
{
  "changed": true,
  "failed": false,
  "msg": "SELinux state set to enforcing, booleans updated: httpd_can_network_connect=on",
  "rc": 0,
  "results": [
    "State: enforcing",
    "Policy: targeted",
    "Boolean httpd_can_network_connect set to on"
  ],
  "invocation": {
    "module_args": {
      "state": "enforcing",
      "policy": "targeted",
      "booleans": {
        "httpd_can_network_connect": "on"
      }
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code; SELinux command exit codes are in `results`)
- `results` (list) — per-operation outcome messages
- `stdout` (str) — raw stdout from SELinux commands (when present)
- `stderr` (str) — raw stderr from SELinux commands (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every SELinux command when running as a non-root user. This is the key design difference vs. Ansible's built-in `posix.selinux` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific SELinux commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/sbin/setenforce *, /usr/sbin/restorecon *`
- ✅ **Non-root users** can manage SELinux with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare commands if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run SELinux commands directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage SELinux without full root access
deploy ALL=(root) NOPASSWD: /usr/sbin/setenforce *, /usr/sbin/sestatus, /usr/sbin/semanage boolean *, /usr/sbin/restorecon *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Set SELinux to enforcing
      bash.selinux:
        state: enforcing
        policy: targeted
```
