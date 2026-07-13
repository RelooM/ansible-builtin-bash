# bash.tuned.sh — Bash Tuned Module (callable as `bash.tuned:`)

## Overview

A pure Bash replacement for `community.general.tuned` — callable as **`bash.tuned:`** in Ansible playbooks. Manages [tuned](https://tuned-project.org/) performance profiles on RHEL-family hosts via `tuned-adm`. Designed for environments with fine-grained sudo policies — the module handles privilege escalation internally, so no Ansible `become` is required.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Set throughput-performance profile
      bash.tuned:
        name: throughput-performance
        state: present

    - name: Set recommended profile
      bash.tuned:
        state: recommended

    - name: Disable tuned
      bash.tuned:
        state: absent
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `profile` | str | — | Tuned profile name (e.g. `virtual-guest`, `throughput-performance`, `latency-performance`). Alias `profile` accepted. Required when `state=present`. |
| `state` | str | `present` | `present` (enable profile), `absent` (disable tuned), `recommended` (auto-detect and enable best profile). |
| `use_sudo` | str/bool | `auto` | `auto` (sudo -n when non-root, bare commands when root), `true` (always use sudo), `false` (never use sudo). |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Set active profile to 'throughput-performance'",
  "rc": 0,
  "invocation": {
    "args": {
      "name": "throughput-performance",
      "state": "present",
      "use_sudo": "auto"
    }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `changed` | bool | Whether any change occurred |
| `failed` | bool | Whether the operation failed |
| `msg` | str | Human-readable summary |
| `rc` | int | Exit code of the last `tuned-adm` command (0 on success) |
| `invocation.args` | dict | Original module arguments echoed back for callback plugins |

### State mapping

| Playbook state | tuned-adm command | Behavior |
|---|---|---|
| `present` | `tuned-adm profile <name>` | Enable profile if not already active; no-op if already set |
| `absent` | `tuned-adm off` | Disable tuned; no-op if already off |
| `recommended` | `tuned-adm recommend` → `tuned-adm profile <name>` | Resolve best profile for hardware, then enable if not active |

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `tuned-adm` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `community.general.tuned` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific `tuned-adm` commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/tuned-adm *`
- ✅ **Non-root users** can manage tuned profiles with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare commands if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run tuned-adm directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage tuned profiles without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/tuned-adm *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Enable virtual-guest profile
      bash.tuned:
        name: virtual-guest
        state: present
```
