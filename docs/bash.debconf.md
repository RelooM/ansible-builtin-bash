# bash.debconf.sh — Bash Debconf Module (callable as `bash.debconf:`)

## Overview

A pure Bash replacement for `ansible.builtin.debconf` — callable as **`bash.debconf:`** in Ansible playbooks. Pre-seeds the debconf database so packages install non-interactively with your chosen defaults. Designed for environments with fine-grained sudo policies — the module handles privilege escalation internally, so no `become:` is required.

**Use cases:** automate package installs that normally prompt (e.g. `tzdata`, `postfix`, `mariadb-server`, `phpmyadmin`) by setting answers ahead of time.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Pre-seed timezone
      bash.debconf:
        name: tzdata
        question: tzdata/Areas
        value: Europe
        vtype: select

    - name: Pre-seed MySQL root password
      bash.debconf:
        name: mariadb-server
        question: mariadb-server/root_password
        value: s3cret
        vtype: password

    - name: Mark question as unseen
      bash.debconf:
        name: postfix
        question: postfix/main_mailer_type
        value: Internet Site
        vtype: string
        unseen: true
```

## Parameters

### Core

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | **required** | Debian package name that owns the debconf question (e.g. `tzdata`). Also accepts the alias `package`. |
| `question` | str | **required** | Debconf question identifier (e.g. `tzdata/Areas`). |
| `value` | raw | `""` | Value to set for the question. Omit to leave the question untouched. |
| `vtype` | str | `string` | Debconf value type (see table below). |
| `unseen` | bool | `false` | If `true`, passes `-u` to `debconf-set-selections` so the value is set but the question remains marked *unseen* (the package's maintainer script will still display it once). |

### `vtype` reference

| Value | Description |
|---|---|
| `string` | Free-form text (default) |
| `boolean` | `true` or `false` |
| `select` | Choose one from a pre-defined list |
| `multiselect` | Choose one or more from a pre-defined list |
| `password` | Hidden input (echo suppressed) |
| `text` | Multi-line free-form text |
| `note` | Display-only informational note |
| `title` | Display-only title / heading |
| `error` | Display-only error message |
| `seen` | Marks the question as already seen (no value set) |

### Sudo

| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` — uses `sudo -n` if non-root, bare command if root. `true` — always uses `sudo -n`. `false` — never uses sudo. |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Successfully set debconf selection tzdata/tzdata/Areas to Europe",
  "rc": 0,
  "stdout": "",
  "stderr": "",
  "invocation": {
    "module_args": {
      "name": "tzdata",
      "question": "tzdata/Areas",
      "value": "Europe",
      "vtype": "select",
      "unseen": false,
      "use_sudo": "auto"
    }
  }
}
```

| Key | Type | Description |
|---|---|---|
| `changed` | bool | Whether the debconf database was modified |
| `failed` | bool | Whether the operation failed |
| `msg` | str | Human-readable summary of the action taken |
| `rc` | int | Process exit code (always `0` on success) |
| `stdout` | str | Raw stdout from `debconf-set-selections` (when present) |
| `stderr` | str | Raw stderr from `debconf-set-selections` (when present) |
| `invocation` | dict | Original module arguments — useful for callback plugins and debugging |

**Idempotency:** The module reads the current value with `debconf-show` before writing. If the value is already set to the requested value, no change is reported.

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `debconf-set-selections` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `debconf` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific debconf commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/debconf-set-selections, /usr/bin/debconf-show`
- ✅ **Non-root users** can pre-seed debconf with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare command if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run debconf commands directly |

### Example sudoers configuration

```sudo
# Allow deploy user to pre-seed debconf without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/debconf-set-selections, /usr/bin/debconf-show *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Pre-seed timezone
      bash.debconf:
        name: tzdata
        question: tzdata/Areas
        value: US
        vtype: select
```

## Note on dpkg-reconfigure and notify handlers

The `debconf-set-selections` call writes directly to the debconf database but does **not** reconfigure already-installed packages. To apply a new value to a package that is already installed, combine `bash.debconf:` with `dpkg-reconfigure` via a notify handler:

```yaml
- hosts: all
  tasks:
    - name: Pre-seed postfix configuration
      bash.debconf:
        name: postfix
        question: postfix/main_mailer_type
        value: Internet Site
        vtype: select
      notify: reconfigure postfix

    - name: Install postfix
      bash.dnf:
        name: postfix
        state: present

  handlers:
    - name: reconfigure postfix
      ansible.builtin.command: dpkg-reconfigure -f noninteractive postfix
```

`dpkg-reconfigure` reads the debconf values that `bash.debconf:` set, so the reconfiguration completes without prompts.
