# bash.known_hosts.sh — Bash known_hosts Module (callable as `bash.known_hosts:`)

## Overview

A pure Bash replacement for `ansible.builtin.known_hosts` — callable as **`bash.known_hosts:`** in Ansible playbooks. Manages entries in SSH `known_hosts` files without requiring `ssh-keyscan` or SSH client tools. Designed for environments with fine-grained sudo policies or minimal SSH tooling.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Add host key
      bash.known_hosts:
        name: example.com
        key: "ssh-rsa AAAAB3NzaC1yc2EAAA... user@host"
        state: present
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | — | **Required.** Hostname or `[host]:port` to manage in the known_hosts file. |
| `key` | str | — | SSH public key line to add (e.g. `ssh-rsa AAAA...`). Required when `state=present`. Ignored when `state=absent`. |
| `state` | str | `present` | `present` — ensure the key entry exists; `absent` — remove any entry for this host. |
| `path` | str | `~/.ssh/known_hosts` | Path to the known_hosts file to manage. Parent directories are created automatically. |
| `hash_host` | bool | `false` | When `true`, hashes the hostname (using SHA-1 + base64) before writing, matching the format of `ssh-keygen -H`. Protects hostnames from casual inspection. |
| `use_sudo` | str/bool | `auto` | Privilege escalation: `auto` (use sudo if non-root), `true` (always sudo), `false` (never sudo). |

## Return values

```json
{
  "changed": true,
  "name": "example.com",
  "state": "present",
  "path": "/root/.ssh/known_hosts",
  "invocation": {
    "module_args": {
      "name": "example.com",
      "state": "present"
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `name` (str) — the hostname that was managed
- `state` (str) — the requested state (`present` / `absent`)
- `path` (str) — path to the known_hosts file that was modified
- `invocation` (dict) — original module arguments for callback plugins

On error, the following additional fields are returned:
- `failed` (bool) — always `true` on error
- `msg` (str) — error description (e.g. "name is required", "key is required when state=present")
- `rc` (int) — always `0`

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before file operations when running as a non-root user. This is the key design difference vs. Ansible's built-in `known_hosts` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific file-write commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /bin/mv /root/.ssh/*, /bin/cp /root/.ssh/*`
- ✅ **Non-root users** can manage known_hosts with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, runs directly if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage SSH known_hosts without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/install -m 0644 /tmp/* /home/deploy/.ssh/known_hosts
deploy ALL=(root) NOPASSWD: /bin/mv /home/deploy/.ssh/known_hosts*
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Add build server to known_hosts
      bash.known_hosts:
        name: build.internal.example.com
        key: "{{ lookup('pipe', 'ssh-keyscan build.internal.example.com') }}"
        state: present
```
