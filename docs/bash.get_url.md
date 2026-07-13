# bash.get_url — Bash Get URL Module (callable as `bash.get_url:`)

## Overview

A pure Bash replacement for `ansible.builtin.get_url` — callable as **`bash.get_url:`** in Ansible playbooks. Downloads a URL to a local destination with atomic move, optional checksum verification, and mode setting. The module handles privilege escalation internally via `sudo -n`, so no Ansible `become` is required.

- **Distro family**: Cross-distro (any Linux with `curl` and `install`)
- **Lines**: 112
- **Ansible equivalent**: `ansible.builtin.get_url`

## Quick Start

### Download a file

```yaml
- hosts: all
  tasks:
    - name: Download a script
      bash.get_url:
        url: https://example.com/install.sh
        dest: /usr/local/bin/install.sh
```

### Download with checksum verification

```yaml
- hosts: all
  tasks:
    - name: Download with SHA256 check
      bash.get_url:
        url: https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
        dest: /tmp/terraform.zip
        checksum: sha256:abc123...
```

### Download with custom file mode

```yaml
- hosts: all
  tasks:
    - name: Download an executable script
      bash.get_url:
        url: https://example.com/deploy.sh
        dest: /usr/local/bin/deploy.sh
        mode: 0755
```

### Download as non-root user

```yaml
- hosts: all
  tasks:
    - name: Download into world-writable temp dir
      bash.get_url:
        url: https://example.com/data.csv
        dest: /tmp/data.csv
        use_sudo: false
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `url` | str | — | Source URL to download (**required**) |
| `dest` | str | — | Local destination path (**required**) |
| `checksum` | str | — | Checksum for verification. Format: `algo:hex`, e.g. `sha256:abc...`. Supported algos: `sha256`, `sha1`, `md5` |
| `mode` | str | `0644` | Octal file mode applied on write (via `install`) |
| `tmp_dest` | str | `/tmp` | Temporary directory for the download staging file |
| `use_sudo` | str/bool | `auto` | `auto` (sudo if non-root), `true` (always), `false` (never). When `false`, runs as connecting user — useful for world-writable destinations like `/tmp` |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Downloaded https://example.com/install.sh to /usr/local/bin/install.sh",
  "rc": 0,
  "invocation": {
    "module_args": {
      "url": "https://example.com/install.sh",
      "dest": "/usr/local/bin/install.sh"
    }
  }
}
```

| Return | Type | Description |
|--------|------|-------------|
| `changed` | bool | Whether the file was downloaded or updated |
| `failed` | bool | Whether the operation failed |
| `msg` | str | Human-readable summary |
| `rc` | int | Module exit code (always 0 on success) |
| `invocation` | dict | Original module arguments for callback plugins |

## Sudo / Privilege Escalation

The module handles privilege escalation internally via the `use_sudo` parameter:

| Value | Behavior |
|---|---|
| `auto` (default) | Uses `sudo -n` when non-root, bare commands when root |
| `true` | Always uses `sudo -n`, even if already root |
| `false` | Never use sudo — run commands directly (use when writing to world-writable destinations like `/tmp`) |

### Why `use_sudo: false` matters

When the module runs as non-root with `use_sudo: auto` (default), `curl` runs under `sudo -n` as root. If the destination is a world-writable directory like `/tmp`, root-owned `curl` cannot write its temp file there. Set `use_sudo: false` in such cases so the module runs as the connecting user.

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Download script
      bash.get_url:
        url: https://example.com/deploy.sh
        dest: /usr/local/bin/deploy.sh
        mode: 0755
```

## Idempotency

- If `dest` already exists and **no checksum** is specified, the download is skipped (`changed: false`).
- If `dest` already exists and a **checksum** is provided, the existing file's checksum is computed. If it matches, the download is skipped.
- If the checksum doesn't match, the download proceeds and the checksum is verified on the staged temp file **before** moving into place.

This means re-running the same task with the same `url` and `checksum` after the file is already in place produces `changed: false`.

## Atomic Move

The downloaded file is staged in a temp location (`tmp_dest`, default `/tmp`), verified (if checksum is given), then atomically moved into place via the `install` command (which also sets the `mode`). This prevents partial/corrupt files at the destination.
