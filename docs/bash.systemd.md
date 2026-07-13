# bash.systemd.sh — Bash systemd Module (callable as `bash.systemd:`)

## Overview

A pure Bash replacement for `ansible.builtin.systemd_service` — callable as **`bash.systemd:`** in Ansible playbooks. Manages systemd units (services, sockets, timers, paths, etc.) with full idempotent lifecycle control via `systemctl`. Handles privilege escalation internally via `sudo -n` — no Ansible `become` required.

- **Distro family**: Any systemd-based Linux (modern RHEL, Debian 8+, Ubuntu 15.04+, Fedora, SUSE, Arch)
- **Backend**: `systemctl`
- **Ansible equivalent**: `ansible.builtin.systemd_service`

## Quick Start

### Start and enable a service

```yaml
- name: Ensure nginx is running and starts at boot
  bash.systemd:
    name: nginx
    state: started
    enabled: true
```

### Stop and disable a service

```yaml
- name: Stop and disable httpd
  bash.systemd:
    name: httpd
    state: stopped
    enabled: false
```

### Restart a service (always executes)

```yaml
- name: Restart nginx
  bash.systemd:
    name: nginx
    state: restarted
```

### Reload config without restarting

```yaml
- name: Reload nginx config
  bash.systemd:
    name: nginx
    state: reloaded
    daemon_reload: true
```

### Enable/disable at boot only

```yaml
- name: Disable chrony at boot
  bash.systemd:
    name: chronyd
    enabled: false
```

### Mask and unmask a unit

```yaml
- name: Mask a dangerous service
  bash.systemd:
    name: rsh-server
    masked: true

- name: Unmask the service
  bash.systemd:
    name: rsh-server
    masked: false
```

### Daemon-reload only (e.g. after dropping a new unit file)

```yaml
- name: Reload systemd daemon
  bash.systemd:
    daemon_reload: true
```

### User-scope session

```yaml
- name: Start a user-scope service
  bash.systemd:
    name: my-app
    state: started
    scope: user
```

### Force stop a stubborn service

```yaml
- name: Force stop hung service
  bash.systemd:
    name: stuck-service
    state: stopped
    force: true
```

### No-block operation

```yaml
- name: Restart long-starting service asynchronously
  bash.systemd:
    name: big-app
    state: restarted
    no_block: true
```

## Parameter Reference

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | **Required.** Unit name (e.g., `httpd.service`, `sshd`, `cron.service`). The `.service` suffix is optional for service units. |
| `state` | str | — | Desired state: `started`, `stopped`, `restarted`, `reloaded`, `enabled`, `disabled`, `masked`, `unmasked`. At least one of `state`, `enabled`, `masked`, or `daemon_reload` must be specified. |
| `enabled` | bool | — | Whether the unit should start at boot (`true` = enable, `false` = disable). Independent of `state` — can be combined. |
| `daemon_reload` | bool | `false` | Run `systemctl daemon-reload` before any unit operations. Always executes when `true`. |
| `masked` | bool | — | Whether the unit should be masked (`true` = mask, `false` = unmask). Prevents the unit from being started. |

### Options

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scope` | str | `system` | Unit scope: `system` (system-wide, default) or `user` (current user's session). |
| `no_block` | bool | `false` | Non-blocking operation — passes `--no-block` to systemctl. The command returns immediately without waiting for the operation to complete. |
| `force` | bool | `false` | Force the operation — passes `--force` to `stop` and `disable` subcommands. Useful for unresponsive services. |

### Privilege Escalation

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto`: auto-detects — uses `sudo -n` if running as non-root, bare `systemctl` if root. `true`: always prefix with `sudo -n`. `false`: never use sudo. |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Unit operation(s) completed successfully",
  "rc": 0,
  "results": [
    "start nginx.service: exit=0",
    "enabled unit"
  ],
  "stdout": "",
  "stderr": "",
  "invocation": {
    "module_args": {
      "name": "nginx",
      "state": "started",
      "enabled": true,
      "daemon_reload": false,
      "scope": "system",
      "no_block": false,
      "force": false,
      "use_sudo": "auto"
    }
  }
}
```

Return values:
- `changed` (bool) — whether any state change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary of what happened
- `rc` (int) — always 0 (module exit code; systemctl exit codes are in `results`)
- `results` (list) — per-operation outcome messages (e.g., `"start nginx.service: exit=0"`)
- `stdout` (str) — raw systemctl stdout (when present)
- `stderr` (str) — raw systemctl stderr (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every systemctl command that needs it. This is the key design difference vs. Ansible's built-in `systemd_service` module:

- **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific systemctl commands via sudo
- **Fine-grained sudoers policies work** — you can grant granular permissions for specific systemctl subcommands
- **Non-root users** can manage systemd units with limited, auditable permissions
- **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### Which commands need sudo?

| systemctl subcommand | Needs sudo? | Notes |
|---|---|---|
| `start`, `stop`, `restart`, `reload` | **Yes** | Mutating service state |
| `enable`, `disable` | **Yes** | Modifies `/etc/systemd/system/` symlinks |
| `mask`, `unmask` | **Yes** | Creates/removes `/etc/systemd/system/` unit overrides |
| `daemon-reload` | **Yes** | Reloads all unit files from disk |
| `is-active`, `is-enabled` | **No** | Read-only queries — run without sudo |

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare `systemctl` if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run `systemctl` directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage specific services without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl start nginx, /usr/bin/systemctl stop nginx, /usr/bin/systemctl restart nginx, /usr/bin/systemctl reload nginx, /usr/bin/systemctl enable nginx, /usr/bin/systemctl disable nginx

# Broader pattern: allow all systemctl subcommands
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl start *, /usr/bin/systemctl stop *, /usr/bin/systemctl restart *, /usr/bin/systemctl reload *, /usr/bin/systemctl enable *, /usr/bin/systemctl disable *, /usr/bin/systemctl daemon-reload, /usr/bin/systemctl mask *, /usr/bin/systemctl unmask *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes ← not needed!
  tasks:
    - name: Manage nginx
      bash.systemd:
        name: nginx
        state: started
        enabled: true
```

## Idempotency

The module checks current unit state before acting to avoid unnecessary changes. Idempotent operations report `changed=false` when the unit is already in the desired state.

| Operation | Check | Action if matching | Action if different |
|---|---|---|---|
| `state: started` | `systemctl is-active <unit>` | No-op (`changed=false`) | `systemctl start` |
| `state: stopped` | `systemctl is-active <unit>` | No-op (`changed=false`) | `systemctl stop` |
| `state: restarted` | — | Always executes (`changed=true`) | Always executes (`changed=true`) |
| `state: reloaded` | — | Always executes (`changed=true`) | Always executes (`changed=true`) |
| `enabled: true` | `systemctl is-enabled <unit>` | No-op (`changed=false`) | `systemctl enable` |
| `enabled: false` | `systemctl is-enabled <unit>` | No-op (`changed=false`) | `systemctl disable` |
| `masked: true` | `systemctl is-enabled <unit>` (checks for `masked`) | No-op (`changed=false`) | `systemctl mask` |
| `masked: false` | `systemctl is-enabled <unit>` (checks for `masked`) | No-op (`changed=false`) | `systemctl unmask` |
| `daemon_reload: true` | — | Always executes (`changed=true`) | Always executes (`changed=true`) |

**Key design decisions:**

- `restart` and `reload` always execute and report `changed=true` — this mirrors Ansible's convention for explicit actions. If you need idempotent restart behavior, use `state: started` instead.
- `state` and `enabled` can be combined — they are checked and executed independently (e.g., `state: started` + `enabled: true` will start the service if not running AND enable it if not enabled).
- `daemon_reload` always runs first (before any unit operations) when `true`, and is reported as a separate change.
