# bash.group.sh — Bash Group Module (callable as `bash.group:`)

## Overview

A pure Bash replacement for `ansible.builtin.group` — callable as **`bash.group:`** in Ansible playbooks. Manages Linux groups across all distributions. Handles privilege escalation internally via `sudo -n`.

- **Distro family**: Universal (all Linux distributions)
- **Backend**: `groupadd` / `groupmod` / `groupdel` / `getent`
- **Lines**: 502
- **Ansible equivalent**: `ansible.builtin.group`

## Usage

### Create a group

```yaml
- name: Ensure deployers group exists
  bash.group:
    name: deployers
    state: present
```

### Create a group with a specific GID

```yaml
- name: Create a group with GID 5000
  bash.group:
    name: deployers
    state: present
    gid: 5000
```

### Create a system group

```yaml
- name: Create a system group
  bash.group:
    name: myservice
    state: present
    system: true
```

### Change a group's GID

```yaml
- name: Set GID to 6000
  bash.group:
    name: deployers
    state: present
    gid: 6000
```

### Allow non-unique GID

```yaml
- name: Create group with a duplicate GID
  bash.group:
    name: secondary-group
    state: present
    gid: 5000
    non_unique: true
```

### Remove a group

```yaml
- name: Remove old group
  bash.group:
    name: legacy-users
    state: absent
```

### Force-remove a group (even if it's a primary group)

```yaml
- name: Force remove a group
  bash.group:
    name: stale-group
    state: absent
    force: true
```

## Parameters

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | Group name (required) |
| `state` | str | `present` | `present` (ensure group exists) or `absent` (ensure group is removed) |
| `gid` | int | — | Group ID. If the group exists with a different GID, `groupmod -g <gid>` is run. |

### Group Type

| Parameter | Type | Default | Description |
|---|---|---|---|
| `system` | bool | `false` | Create as a system group (`--system` / `-r`). Only applies when creating the group or changing GID. |
| `local` | bool | `false` | Force local group (not LDAP/NIS). Ignored — this module only manages local `/etc/group` entries, but accepted for Ansible compatibility. |
| `non_unique` | bool | `false` | Allow duplicate GID (`--non-unique` / `-o`). Only applies when `gid` is specified. |

### Removal

| Parameter | Type | Default | Description |
|---|---|---|---|
| `force` | bool | `false` | Force removal even if the group is a primary group for an existing user (`groupdel -f`). |

### Privilege Escalation

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never) |

## Output

```json
{
  "changed": true,
  "failed": false,
  "msg": "Group 'deployers' created with GID 5000",
  "rc": 0,
  "invocation": {
    "module_args": {
      "name": "deployers",
      "state": "present",
      "gid": 5000
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code)
- `stdout` (str) — raw command stdout (when present)
- `stderr` (str) — raw command stderr (when present)
- `invocation` (dict) — original module arguments

## Sudo / Privilege Escalation

This module handles privilege escalation **internally**:

- **Mutating commands** (`groupadd`, `groupmod`, `groupdel`) → prefixed with `sudo -n` when running as non-root
- **Read-only queries** (`getent group <name>`) → run without sudo (no root access needed for checking group existence)

### Example sudoers configuration

```sudo
deploy ALL=(root) NOPASSWD: /usr/sbin/groupadd *, /usr/sbin/groupmod *, /usr/sbin/groupdel *
```

## Idempotency

| Operation | Check | Action if matching | Action if different |
|---|---|---|---|
| `state: present` (new group) | `getent group <name>` | — | `groupadd` (with gid/system if specified) |
| `state: present` (existing, GID mismatch) | `getent group <name>` → compare GID | No-op (changed=false) | `groupmod -g <gid>` |
| `state: absent` (group exists) | `getent group <name>` | `groupdel` | No-op (changed=false) |
| `state: absent` (group doesn't exist) | `getent group <name>` | No-op (changed=false) | — |

### How it works

1. **Existence check**: `getent group <name>` — return code 0 means the group exists, non-zero means it doesn't.
2. **GID comparison**: If the group exists and `gid` is specified, the current GID is extracted from the `getent` output and compared. Only `groupmod -g` is run if the GID differs.
3. **Force removal**: When `force: true` and `state: absent`, the module uses `groupdel -f` to remove the group even if it's a primary group for existing users.

## Cross-distribution notes

- The `system` flag translates to `-r` / `--system` for `groupadd` (RHEL/Debian/Ubuntu) — creates a group with a GID from the system range (typically < 1000).
- The `local` flag is accepted but ignored — this module only manages local groups via `/etc/group`. It exists for Ansible playbooks that use `local: true` for compatibility.
- The `non_unique` flag only takes effect when `gid` is also specified and the group already exists with a different GID. It passes `-o` / `--non-unique` to allow a duplicate GID.
