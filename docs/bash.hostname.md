# bash.hostname.sh — Bash Hostname Module (callable as `bash.hostname:`)

## Overview

A pure Bash replacement for `ansible.builtin.hostname` — callable as **`bash.hostname:`** in Ansible playbooks. Sets the system hostname persistently via `hostnamectl`, with a `hostname` + `/etc/hostname` fallback on systems without systemd. Designed for environments with fine-grained sudo policies.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Set hostname
      bash.hostname:
        name: web-server-01
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | **(Required)** The hostname to set. Must be a valid hostname string. |
| `use` | str | `both` | Which hostname types to set via `hostnamectl set-hostname --<type>`. Values: `systemd`, `static`, `transient`, `pretty`, or `both` (sets both static and transient). Ignored on non-systemd systems. |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

## Return values

```json
{
  "changed": true,
  "name": "web-server-01",
  "previous": "old-hostname",
  "invocation": {
    "args": {
      "name": "web-server-01"
    }
  }
}
```

- `changed` (bool) — whether the hostname was actually changed
- `name` (str) — the new hostname that was set
- `previous` (str) — the hostname before the change
- `failed` (bool) — whether the operation failed (only present on error)
- `msg` (str) — human-readable error message (only present on error)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before `hostnamectl` and file writes when running as a non-root user. This is the key design difference vs. Ansible's built-in `hostname` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/hostnamectl set-hostname *, /usr/bin/tee /etc/hostname`
- ✅ **Non-root users** can manage hostnames with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, runs directly if already root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run commands directly |

### Example sudoers configuration

```sudo
# Allow deploy user to set hostname without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/hostnamectl set-hostname *, /usr/bin/tee /etc/hostname
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Set hostname
      bash.hostname:
        name: web-server-01
```
