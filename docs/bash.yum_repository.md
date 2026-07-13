# bash.yum_repository.sh — Bash YUM Repository Module (callable as `bash.yum_repository:`)

## Overview

A pure Bash replacement for `ansible.builtin.yum_repository` — callable as **`bash.yum_repository:`** in Ansible playbooks. Manages `.repo` files in `/etc/yum.repos.d/` for yum/dnf-based distributions (RHEL, CentOS, Fedora, Rocky, Alma). Designed for environments with fine-grained sudo policies. Supports all standard repo parameters including GPG, SSL, proxy, and priority settings.

## Usage

```yaml
- hosts: all
  tasks:
    - name: Add EPEL repository
      bash.yum_repository:
        name: epel
        description: Extra Packages for Enterprise Linux
        baseurl: https://dl.fedoraproject.org/pub/epel/9/Everything/$basearch/
        gpgcheck: true
        gpgkey: https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
        enabled: true

    - name: Disable a repository
      bash.yum_repository:
        name: debuginfo
        enabled: false

    - name: Remove a repository
      bash.yum_repository:
        name: old-repo
        state: absent
```

### Core
| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` / `repoid` | str | — | Repository ID (required). Used as the filename base and `[section]` name in the `.repo` file. |
| `state` | str | `present` | `present` (create/update) or `absent` (remove the `.repo` file). |
| `file` | str | — | Custom `.repo` filename (without extension). Defaults to `name` parameter. Useful when multiple repo IDs share one file. |

### Source URLs
| Parameter | Type | Description |
|---|---|---|
| `description` | str | Human-readable description (`name=` field in the `.repo` file). |
| `baseurl` | str | Base URL for the repository (supports `$releasever` and `$basearch` variables). |
| `mirrorlist` | str | URL to a mirror list file. |
| `metalink` | str | URL to a metalink descriptor. |

### GPG & Security
| Parameter | Type | Default | Description |
|---|---|---|---|
| `gpgcheck` | bool | `true` | Enable GPG signature checking for packages from this repo. |
| `gpgkey` | str | — | URL(s) to GPG key(s) for this repository. |
| `sslverify` | bool | `true` | Verify SSL certificates when connecting to this repo. |
| `sslcacert` | str | — | Path to the directory or file containing the certificate authorities. |
| `sslclientkey` | str | — | Path to the SSL client key for certificate authentication. |
| `sslclientcert` | str | — | Path to the SSL client certificate. |

### Filtering & Priority
| Parameter | Type | Default | Description |
|---|---|---|---|
| `exclude` | list | — | List of packages to exclude from this repository. |
| `includepkgs` | list | — | List of only these packages to pull from this repository. |
| `priority` | int | — | Priority of this repository (lower = preferred). Only effective with `yum-plugin-priorities` or `dnf-plugins-core`. |
| `module_hotfixes` | bool | — | If `true`, mark this repo as a module hotfix source (dnf module streams). |

### Connectivity
| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `true` | Whether this repository is enabled. |
| `proxy` | str | — | URL to a proxy server for this repo (`http://` or `socks://`). Set to `_none_` to disable proxying. |
| `username` | str | — | Username for HTTP basic auth against this repo. |
| `password` | str | — | Password for HTTP basic auth against this repo. |
| `cost` | int | — | Relative cost/weight of this repo (lower = preferred). Used by the `cost` plugin. |
| `timeout` | int | — | Network timeout in seconds for this repository. |
| `async` | bool | — | Allow asynchronous downloads for this repo. |
| `throttle` | str | — | Bandwidth throttle for this repo (e.g. `1.5M` for 1.5 MB/s). |

### Privilege Escalation
| Parameter | Type | Default | Description |
|---|---|---|---|
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect), `true` (always sudo), `false` (never sudo). |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Repository 'epel' added to /etc/yum.repos.d/epel.repo",
  "rc": 0,
  "results": [],
  "repo_file": "/etc/yum.repos.d/epel.repo",
  "repo_id": "epel",
  "invocation": {
    "module_args": {
      "name": "epel",
      "description": "Extra Packages for Enterprise Linux",
      "baseurl": "https://dl.fedoraproject.org/pub/epel/9/Everything/$basearch/",
      "gpgcheck": true,
      "enabled": true,
      "state": "present"
    }
  }
}
```

Return values:
- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 (module exit code; errors are reported via `failed`)
- `results` (list) — informational messages (empty for repo operations)
- `repo_file` (str) — full path to the `.repo` file that was created/removed
- `repo_id` (str) — repository ID that was managed
- `stdout` (str) — raw stdout from underlying commands (when present)
- `stderr` (str) — raw stderr from underlying commands (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before file operations in `/etc/yum.repos.d/` when running as a non-root user. This is the key design difference vs. Ansible's built-in `yum_repository` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific file writes via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/cp /tmp/*.repo /etc/yum.repos.d/`
- ✅ **Non-root users** can manage repositories with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, runs directly if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run file operations directly (requires write access to `/etc/yum.repos.d/`) |

### Example sudoers configuration

```sudo
# Allow deploy user to manage yum repos without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/cp /tmp/yum-repo-*.conf /etc/yum.repos.d/*.repo, /usr/bin/rm /etc/yum.repos.d/*.repo, /usr/bin/chmod 644 /etc/yum.repos.d/*.repo
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Add EPEL repository
      bash.yum_repository:
        name: epel
        description: Extra Packages for Enterprise Linux
        baseurl: https://dl.fedoraproject.org/pub/epel/9/Everything/$basearch/
        gpgcheck: true
        gpgkey: https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
```

## State Mapping

| Playbook State | Behavior |
|---|---|
| `present` | Create or update the `.repo` file in `/etc/yum.repos.d/`. Merges specified parameters, leaves unspecified parameters unchanged on existing files. |
| `absent` | Remove the `.repo` file. No-op if the file does not exist. |
