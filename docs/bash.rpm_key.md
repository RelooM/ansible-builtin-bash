# bash.rpm_key — Bash RPM Key Module (callable as `bash.rpm_key:`)

## Overview

A pure Bash replacement for `ansible.builtin.rpm_key` — callable as **`bash.rpm_key:`** in Ansible playbooks. Manages RPM GPG key imports and removals on any RPM-based distro (RHEL, Fedora, CentOS, Rocky, Alma, Amazon Linux).

Designed for environments with fine-grained sudo policies. Calls `sudo -n` internally when running as a non-root user, so no Ansible `become` is needed.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Import a GPG key from URL
      bash.rpm_key:
        key: https://www.redhat.com/security/data/fd431d51.txt
        state: present

    - name: Import a local GPG key
      bash.rpm_key:
        key: /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
        state: present

    - name: Remove a key by ID
      bash.rpm_key:
        key_id: fd431d51
        state: absent
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `key` | str | — | URL (`http://`, `https://`, `file://`) or absolute local path of the GPG key to import. **Required when `state=present`.** |
| `state` | str | `present` | `present` — import the key. `absent` — remove the key. |
| `key_id` | str | — | Key ID or fingerprint (short 8-char or long form). Used to locate the key for removal when `state=absent` and `key` is not supplied. When `state=present`, optionally verifies the imported key matches this ID. |
| `validate_certs` | bool | `true` | Validate TLS certificates when fetching an HTTPS key URL. Set to `false` to skip verification (passes `-k` to curl). |
| `use_sudo` | str/bool | `auto` | Sudo policy — see [Sudo / Privilege Escalation](#sudo--privilege-escalation). |

### `state=present`

The `key` parameter is **required**. The module fetches the key (from a URL or local file) and imports it via `rpm --import`. If `key_id` is provided, the module verifies the imported key matches and short-circuits with no change if it is already present.

### `state=absent`

Either `key_id` or `key` must be supplied:

- **`key_id` given** — locates the imported `gpg-pubkey` RPM package by matching the ID (long or short form) and removes it with `rpm -e`.
- **`key` given (no `key_id`)** — derives the key ID from the URL/path basename (stripping common `RPM-GPG-KEY-` / `GPG-KEY-` prefixes) and removes the matching package.

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "RPM key a1b2c3d4 imported from https://example.com/RPM-GPG-KEY-example.",
  "rc": 0,
  "invocation": {
    "args": {
      "key": "https://example.com/RPM-GPG-KEY-example",
      "state": "present",
      "key_id": "",
      "validate_certs": true,
      "use_sudo": "auto"
    }
  }
}
```

- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code; rpm exit codes are embedded in `msg` on failure)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `rpm` and `curl` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `rpm_key` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific rpm/curl commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/rpm --import *, /usr/bin/rpm -e gpg-pubkey-*`
- ✅ **Non-root users** can manage GPG keys with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, runs directly if already root |
| `true` | Always use `sudo`, even if already root |
| `false` | Never use sudo — run rpm/curl directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage RPM GPG keys without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/rpm --import *, /usr/bin/rpm -e gpg-pubkey-*, /usr/bin/rpm -q gpg-pubkey-*, /usr/bin/curl -fsSL *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Import GPG key
      bash.rpm_key:
        key: https://www.redhat.com/security/data/fd431d51.txt
        state: present
```
