# bash.sysctl.sh — Bash Sysctl Module (callable as `bash.sysctl:`)

## Overview

A pure Bash replacement for `ansible.builtin.sysctl` — callable as **`bash.sysctl:`** in Ansible playbooks. Manages kernel parameters both persistently (via config files) and at runtime (via `sysctl -w`). Designed for environments with fine-grained sudo policies.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Enable IP forwarding
      bash.sysctl:
        name: net.ipv4.ip_forward
        value: "1"
        state: present
```

### Parameters

#### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `key` | str | — | **(required)** Sysctl key, e.g. `net.ipv4.ip_forward` |
| `value` | str | — | Desired value. **Required** when `state=present` |
| `state` | str | `present` | `present` — set the value; `absent` — remove the entry from the config file |

#### Application

| Parameter | Type | Default | Description |
|---|---|---|---|
| `sysctl_set` | bool | `false` | Apply the value to the running kernel immediately via `sysctl -w` |
| `reload` | bool | `false` | Run `sysctl -p <file>` after modifying the config file (loads all settings from that file) |

#### Paths & Error Handling

| Parameter | Type | Default | Description |
|---|---|---|---|
| `sysctl_file` | str | `/etc/sysctl.d/99-ansible.conf` | Persistence file to write the sysctl entry into |
| `ignoreerrors` | bool | `false` | Ignore errors when applying the sysctl value |

#### Privilege Escalation

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

## Return values

```json
{
  "changed": true,
  "name": "net.ipv4.ip_forward",
  "value": "1",
  "state": "present",
  "sysctl_set": "true",
  "invocation": {
    "args": {
      "name": "net.ipv4.ip_forward",
      "value": "1",
      "state": "present",
      "sysctl_set": "true",
      "sysctl_file": "/etc/sysctl.d/99-ansible.conf",
      "reload": "false"
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary (on failure)
- `name` (str) — the sysctl key that was operated on
- `value` (str) — the value that was set (or the empty string for `state=absent`)
- `state` (str) — the requested state (`present` or `absent`)
- `sysctl_set` (str) — whether live application was requested (`true` or `false`)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo

This module handles privilege escalation **internally** — it calls `sudo` before system commands (`sysctl`, file writes, `mkdir`) when running as a non-root user. This is the key design difference vs. Ansible's built-in `sysctl` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only specific commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/sysctl -w *`
- ✅ **Non-root users** can manage kernel parameters with limited, auditable permissions
- ✅ **No password prompts** — uses non-interactive sudo, so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo` if running as non-root, runs directly if running as root |
| `true` | Always use `sudo`, even if already root |
| `false` | Never use `sudo` — run commands directly (requires root) |

### Example sudoers configuration

```sudo
# Allow deploy user to manage kernel parameters without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/sysctl -w *, /usr/bin/sysctl -p /etc/sysctl.d/99-ansible.conf
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Enable IP forwarding
      bash.sysctl:
        name: net.ipv4.ip_forward
        value: "1"
```
