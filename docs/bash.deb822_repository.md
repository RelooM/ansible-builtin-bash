# bash.deb822_repository.sh — Bash deb822 Repository Module (callable as `bash.deb822_repository:`)

## Overview

A pure Bash replacement for `ansible.builtin.deb822_repository` — callable as **`bash.deb822_repository:`** in Ansible playbooks. Manages deb822-format `.sources` files in `/etc/apt/sources.list.d/` on Debian 12+ and Ubuntu 22.04+ systems.

The deb822 format is the modern replacement for one-line-style `.list` files, offering better readability and support for advanced APT features like `Acquire::*` options. This module generates and manages these files idempotently, handling GPG key references, architecture filtering, and repository enable/disable states.

Designed for environments with fine-grained sudo policies — calls `sudo -n` internally for file operations when running as a non-root user, with no reliance on Ansible's `become` system.

## Quick Start

### Add a standard Debian repository with GPG key

```yaml
- hosts: all
  tasks:
    - name: Add Docker repository
      bash.deb822_repository:
        name: docker
        uris:
          - https://download.docker.com/linux/debian
        suites:
          - bookworm
        components:
          - stable
        signed_by: https://download.docker.com/linux/debian/gpg
```

### Add a repository with multiple sources and architectures

```yaml
- hosts: all
  tasks:
    - name: Add Node.js repository for arm64 and amd64
      bash.deb822_repository:
        name: nodesource
        types:
          - deb
          - deb-src
        uris:
          - https://deb.nodesource.com/node_20.x
        suites:
          - nodistro
        components:
          - main
        signed_by: /etc/apt/keyrings/nodesource.gpg
        architectures:
          - amd64
          - arm64
```

### Disable a repository without removing it

```yaml
- hosts: all
  tasks:
    - name: Disable third-party repo temporarily
      bash.deb822_repository:
        name: thirdparty
        state: present
        enabled: false
```

### Remove a repository completely

```yaml
- hosts: all
  tasks:
    - name: Remove obsolete repository
      bash.deb822_repository:
        name: legacy
        state: absent
```

## Parameters

### Core
| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | str | **required** | Repository name — used as the filename stem (e.g. `docker` → `docker.sources`). |
| `state` | str | `present` | `present` to create/update, `absent` to remove. |

### Source Definition
| Parameter | Type | Default | Description |
|---|---|---|---|
| `types` | list | `["deb"]` | Repository types — `deb` and/or `deb-src`. |
| `uris` | list | **required** | Base URIs for the repository (space-separated in the file). |
| `suites` | list | — | Suite/distribution names (e.g. `bookworm`, `noble`, `stable`). |
| `components` | list | — | Repository components (e.g. `main`, `contrib`, `non-free`, `non-free-firmware`). |

### GPG & Verification
| Parameter | Type | Default | Description |
|---|---|---|---|
| `signed_by` | str | — | GPG key source for package verification. Accepts a URL, an absolute path to an existing keyring file, an inline ASCII-armored key block, or a key fingerprint. If a URL, the key is downloaded to `/etc/apt/keyrings/` and referenced by path. |
| `allow_insecure` | bool | `false` | Allow insecure (unsigned) repositories (`Acquire::Allow-Insecure`). |
| `allow_weak` | bool | `false` | Allow weak cryptography in repositories (`Acquire::Allow-Weak`). |
| `allow_downgrade_to_insecure` | bool | `false` | Allow downgrade to insecure (`Acquire::Allow-Downgrade-To-Insecure`). |

### Filtering
| Parameter | Type | Default | Description |
|---|---|---|---|
| `architectures` | list | — | Restrict to specific architectures (e.g. `amd64`, `arm64`). |
| `enabled` | bool | `true` | Whether the repository is enabled. Set `false` to disable without removing. |

### Acquire Options
| Parameter | Type | Default | Description |
|---|---|---|---|
| `by_hash` | bool | — | Use file-hashes for package downloads (`Acquire::By-Hash`). |
| `check_date` | bool | — | Check the Release file date (`Acquire::Check-Date`). |
| `check_valid_until` | bool | — | Check Release file Valid-Until field (`Acquire::Check-Valid-Until`). |
| `date_max_future` | int | — | Maximum future date tolerance for Release file in seconds (`Acquire::Date-Max-Future`). |
| `pdiffs` | bool | — | Use pdiffs for incremental package index updates (`Acquire::Pdiffs`). |
| `languages` | str | — | Comma-separated languages to download, e.g. `"en,de"`. Use `""` for none, `"\*"` for all (`Acquire::Languages`). |
| `exclude` | str | — | Regex pattern for packages to exclude from this repo (`Acquire::Exclusion`). |
| `include` | str | — | Regex pattern for packages to include (`Acquire::Include`). |

### File & Escalation
| Parameter | Type | Default | Description |
|---|---|---|---|
| `mode` | str | `0644` | Octal file permissions for the `.sources` file. |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect), `true` (always), `false` (never). |

### GPG Key Handling — `signed_by` Examples

| Value | Behavior |
|---|---|
| `https://download.docker.com/linux/debian/gpg` | Downloads the key to `/etc/apt/keyrings/<hash>.gpg` and references it by path. |
| `/etc/apt/keyrings/myrepo.gpg` | References the existing keyring file directly. |
| `"-----BEGIN PGP PUBLIC KEY BLOCK-----\n..."` | Writes the inline armored block to a keyring file in `/etc/apt/keyrings/`. |
| `ABCD1234EFGH5678` (fingerprint) | Looks up the key via `gpg --keyserver` and imports it locally. |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Repository 'docker' created successfully",
  "rc": 0,
  "results": [
    "Created /etc/apt/sources.list.d/docker.sources",
    "Imported GPG key to /etc/apt/keyrings/docker.gpg"
  ],
  "invocation": {
    "module_args": {
      "name": "docker",
      "state": "present",
      "types": ["deb"],
      "uris": ["https://download.docker.com/linux/debian"],
      "suites": ["bookworm"],
      "components": ["stable"],
      "signed_by": "https://download.docker.com/linux/debian/gpg"
    }
  }
}
```

- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module-level exit code)
- `results` (list) — per-action outcome messages (file created, key imported, file removed, etc.)
- `stdout` (str) — raw stdout from any subprocess calls (when present)
- `stderr` (str) — raw stderr from any subprocess calls (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo & Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before file operations in `/etc/apt/sources.list.d/` and `/etc/apt/keyrings/` when running as a non-root user. This is the key design difference vs. Ansible's built-in `deb822_repository` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific file-writing commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/cp /tmp/* /etc/apt/sources.list.d/`
- ✅ **Non-root users** can manage repositories with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare commands if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run commands directly (requires write access to `/etc/apt/`) |

### Example sudoers configuration

```sudo
# Allow deploy user to manage APT sources without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/cp /tmp/* /etc/apt/sources.list.d/*, \
                            /usr/bin/cp /tmp/* /etc/apt/keyrings/*, \
                            /usr/bin/chmod 0644 /etc/apt/sources.list.d/*, \
                            /usr/bin/rm /etc/apt/sources.list.d/*, \
                            /usr/bin/rm /etc/apt/keyrings/*
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Add repository
      bash.deb822_repository:
        name: myrepo
        uris:
          - https://repo.example.com/debian
        suites:
          - bookworm
        components:
          - main
        signed_by: https://repo.example.com/repo-key.asc
```
