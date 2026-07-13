# bash.lineinfile.sh — Bash Lineinfile Module (callable as `bash.lineinfile:`)

## Overview

A pure Bash replacement for `ansible.builtin.lineinfile` — callable as **`bash.lineinfile:`** in Ansible playbooks. Ensures a line is present or absent in a file, with optional regex matching for flexible line identification. Designed for environments with fine-grained sudo policies.

Key differences from `ansible.builtin.lineinfile`:
- ✅ **No `become` required** — the module handles privilege escalation internally via `sudo -n`
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /bin/sed -i *`
- ✅ **Zero Python dependencies** — runs anywhere Bash and basic UNIX tools (`sed`, `grep`) are available
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Ensure my config line exists
      bash.lineinfile:
        path: /etc/myapp.conf
        line: "log_level=debug"

    - name: Remove old setting
      bash.lineinfile:
        path: /etc/myapp.conf
        regex: "^log_level=.*"
        state: absent

    - name: Create file and add line
      bash.lineinfile:
        path: /etc/myapp.d/custom.conf
        line: "include /etc/myapp.d/extra.conf"
        create: true
```

## Parameters

| Parameter | Type | Default | Required | Description |
|---|---|---|---|---|
| `path` | str | — | **yes** | The absolute path to the file to modify. |
| `line` | str | — | no | The literal line to insert or ensure present. When `state=absent` with no `regex`, lines matching this literal string are removed. |
| `regex` | str | — | no | Extended regex (`grep -E` style) to match existing lines. When provided, deletion targets the regex pattern; insertion still appends the literal `line`. Use this to replace or remove lines matching a pattern rather than an exact string. |
| `state` | str | `present` | no | `present` — ensure the line is in the file. `absent` — ensure all matching lines are removed. |
| `create` | bool | `false` | no | If `true`, create the target file (and any missing parent directories) when it does not exist. If `false` (default), the module fails when the file is missing. |
| `use_sudo` | str/bool | `auto` | no | Sudo escalation policy. See [Sudo](#sudo--privilege-escalation) section. |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Line state updated in /etc/myapp.conf",
  "rc": 0,
  "invocation": {
    "args": {
      "path": "/etc/myapp.conf",
      "line": "log_level=debug",
      "regex": "",
      "state": "present",
      "create": "false",
      "use_sudo": "auto"
    }
  }
}
```

- `changed` (bool) — whether any modification was made
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary of the outcome
- `rc` (int) — always 0 on success
- `invocation` (dict) — original module arguments for callback plugins and debugging

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before file-modifying commands (`sed`, `grep`, `bash`) when running as a non-root user. This is the key design difference vs. Ansible's built-in `lineinfile` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific file operations via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /bin/sed -i *`
- ✅ **Non-root users** can manage files with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, runs directly if already root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run commands directly |

### Example sudoers configuration

```sudo
# Allow deploy user to edit application config files without full root access
deploy ALL=(root) NOPASSWD: /bin/sed -i *, /usr/bin/grep *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Ensure config line exists
      bash.lineinfile:
        path: /etc/myapp.conf
        line: "worker_count=4"
```
