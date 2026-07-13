# bash.service.sh — Bash Service Module (callable as `bash.service:`)

## Overview

A pure Bash replacement for `ansible.builtin.service` — callable as **`bash.service:`** in Ansible playbooks. Manages a systemd unit's runtime state (start/stop/restart/reload) and enablement (enable/disable at boot). Designed for environments with fine-grained sudo policies.

The module delegates to `systemctl` and handles privilege escalation internally via `sudo -n`, so playbooks do not need `become: yes`.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Start and enable nginx
      bash.service:
        name: nginx.service
        state: started
        enabled: true
```

## Parameters

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | Unit name, e.g. `nginx.service`. **Required** unless `daemon_reload` alone is used. |
| `state` | str | — | Desired runtime state: `started`, `stopped`, `restarted`, `reloaded`. |
| `enabled` | bool | — | Whether the unit should be enabled or disabled at boot. |

### State Aliases

| Alias | Resolves to |
|---|---|
| `start` | `started` |
| `stop` | `stopped` |
| `restart` | `restarted` |
| `reload` | `reloaded` |

### Control

| Parameter | Type | Default | Description |
|---|---|---|---|
| `daemon_reload` | bool | `false` | Run `systemctl daemon-reload` before other operations. Can be used alone (without `name`) to reload all unit files. |
| `use_sudo` | str/bool | `auto` | Sudo policy — see [Sudo](#sudo--privilege-escalation) section. |

### State Mapping

| State | systemctl Command | Behavior |
|---|---|---|
| `started` | `systemctl is-active` → `systemctl start` | Starts only if not already active (idempotent) |
| `stopped` | `systemctl is-active` → `systemctl stop` | Stops only if currently active (idempotent) |
| `restarted` | `systemctl restart` | Always restarts (not idempotent) |
| `reloaded` | `systemctl reload-or-restart` | Reloads config; falls back to restart if no reload method |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Service nginx.service state updated",
  "rc": 0,
  "state_changed": true,
  "enabled_changed": true,
  "invocation": {
    "args": {
      "name": "nginx.service",
      "state": "started",
      "enabled": "true",
      "daemon_reload": "false",
      "use_sudo": "auto"
    }
  }
}
```

| Return | Type | Description |
|---|---|---|
| `changed` | bool | Whether any change occurred (state or enablement) |
| `failed` | bool | Whether the operation failed |
| `msg` | str | Human-readable summary |
| `rc` | int | Always `0` (module-level exit code) |
| `state_changed` | bool | Whether the runtime state was changed |
| `enabled_changed` | bool | Whether the enablement state was changed |
| `stdout` | str | Raw stdout from systemctl (when present) |
| `stderr` | str | Raw stderr from systemctl (when present) |
| `invocation` | dict | Original module arguments for callback plugins |

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo` before every `systemctl` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `service` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific `systemctl` commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/systemctl start nginx.service, /usr/bin/systemctl stop nginx.service`
- ✅ **Non-root users** can manage services with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare systemctl if running as root |
| `true` | Always use `sudo`, even if already root |
| `false` | Never use sudo — run systemctl directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage specific services without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl start nginx.service, /usr/bin/systemctl stop nginx.service, /usr/bin/systemctl restart nginx.service, /usr/bin/systemctl reload nginx.service, /usr/bin/systemctl is-active nginx.service, /usr/bin/systemctl enable nginx.service, /usr/bin/systemctl disable nginx.service, /usr/bin/systemctl is-enabled nginx.service
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Restart nginx
      bash.service:
        name: nginx.service
        state: restarted
```

### Daemon-reload only (no name required)

```yaml
    - name: Reload systemd after dropping unit file
      bash.service:
        daemon_reload: true
```
