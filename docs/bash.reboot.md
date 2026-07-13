# bash.reboot.sh — Bash Reboot Module (callable as `bash.reboot:`)

## Overview

A pure Bash replacement for `ansible.builtin.reboot` — callable as **`bash.reboot:`** in Ansible playbooks. Reboots the target system using `reboot` / `shutdown -r` with internal sudo handling. Designed for environments with fine-grained sudo policies.

The module uses a **deferred reboot** approach: it schedules the reboot and returns immediately so Ansible's built-in `wait_for_connection` / reconnection logic can handle the host coming back online. This mirrors the behavior of `ansible.builtin.reboot`.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Reboot server
      bash.reboot:
        reboot_timeout: 600
```

```yaml
    - name: Reboot with a warning message
      bash.reboot:
        msg: "Rebooting for kernel update"
        pre_reboot_delay: 5
        post_reboot_delay: 2
```

```yaml
    - name: Skip reboot if not needed
      bash.reboot:
        only_if_reboot_required: true
```

## Parameters

### Timing

| Parameter | Type | Default | Description |
|---|---|---|---|
| `reboot_timeout` | int | `600` | Maximum seconds to wait for the machine to come back after issuing the reboot command |
| `pre_reboot_delay` | int | `0` | Seconds to wait before issuing the reboot command |
| `post_reboot_delay` | int | `0` | Seconds to wait after issuing the reboot command before returning |

### Messaging

| Parameter | Type | Default | Description |
|---|---|---|---|
| `msg` | str | `Reboot initiated by Ansible` | Message displayed on the system console before reboot |

### Reboot Control

| Parameter | Type | Default | Description |
|---|---|---|---|
| `reboot` | bool | `true` | Set to `false` to check if a reboot is required without actually rebooting |
| `only_if_reboot_required` | bool | `false` | When `true`, only reboot if the system indicates a reboot is pending (e.g. `/var/run/reboot-required`) |
| `boot_time` | str | — | Override expected boot time (epoch timestamp). Used by the controller to detect when the host is back |
| `connect_timeout` | int | — | Timeout (seconds) for the reconnection probe after reboot |

### Privilege

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

### Other

| Parameter | Type | Default | Description |
|---|---|---|---|
| `test_command` | str | `whoami` | Command run after reboot to verify the host is back up |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Reboot command issued",
  "rc": 0,
  "invocation": {
    "module_args": {
      "msg": "Reboot initiated by Ansible"
    }
  }
}
```

- `changed` (bool) — whether a reboot command was issued
- `failed` (bool) — whether the operation failed (e.g. `reboot` command not found)
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before the `reboot` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `reboot` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the reboot command via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /sbin/reboot`
- ✅ **Non-root users** can reboot with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare reboot if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run reboot directly |

### Example sudoers configuration

```sudo
# Allow deploy user to reboot without full root access
deploy ALL=(root) NOPASSWD: /sbin/reboot, /sbin/shutdown -r *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Reboot server
      bash.reboot:
```
