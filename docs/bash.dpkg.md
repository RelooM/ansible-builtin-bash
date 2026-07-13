# bash.dpkg

Manage dpkg package selections and install/remove .deb files — pure Bash Ansible module.

---

## Description

This module provides two distinct operation modes for managing Debian packages:

1. **Selection mode** — Manage dpkg selection state (`install`, `hold`, `deinstall`, `purge`) using `dpkg --set-selections` and `dpkg --get-selections`
2. **Deb file mode** — Install or remove `.deb` package files using `dpkg -i`, `dpkg -r`, and `dpkg -l`

The module is a pure-Bash replacement for `ansible.builtin.dpkg_selections` and `ansible.builtin.dpkg` with internal sudo handling (no Ansible `become` required).

---

## Parameters

| Parameter | Required | Type | Default | Choices | Description |
|-----------|----------|------|---------|---------|-------------|
| `name` | Selection mode only | string | — | — | Package name for selection state operations |
| `selection` | Selection mode only | string | — | `install`, `hold`, `deinstall`, `purge` | Selection state to set for the package |
| `state` | no | string | `present` | `present`, `absent` | Whether the selection state or package should be present/absent |
| `deb` | Deb file mode only | string | — | — | Path to local `.deb` file to install or remove |
| `force` | no | string | — | comma-separated force options | Force flags for dpkg operations (e.g., `force-confold,force-overwrite`) |
| `use_sudo` | no | string | `auto` | `auto`, `true`, `false` | Whether to use `sudo -n`. `auto` = use sudo if not root |

### Force Options

Valid `force` options (comma-separated): `force-confold`, `force-confnew`, `force-confdef`, `force-confmiss`, `force-architecture`, `force-depends`, `force-depends-version`, `force-overwrite`, `force-overwrite-dir`, `force-overwrite-diverted`, `force-bad-path`, `force-bad-verify`, `force-triggers`, `force-configure-any`, `force-remove-reinstreq`, `force-all`

---

## Operations

### Selection Mode

Manage package selection state (hold, install, deinstall, purge):

```yaml
- name: Hold package at current version
  bash.dpkg:
    name: nginx
    selection: hold
    state: present

- name: Mark package for installation
  bash.dpkg:
    name: vim
    selection: install
    state: present

- name: Remove package selection (set to deinstall)
  bash.dpkg:
    name: old-package
    selection: install
    state: absent
```

### Deb File Mode

Install or remove local `.deb` files:

```yaml
- name: Install local deb package
  bash.dpkg:
    deb: /tmp/mypackage_1.0_amd64.deb
    state: present

- name: Install with force options
  bash.dpkg:
    deb: /tmp/mypackage_1.0_amd64.deb
    state: present
    force: force-confold,force-overwrite

- name: Remove package installed from deb
  bash.dpkg:
    deb: /tmp/mypackage_1.0_amd64.deb
    state: absent
    name: mypackage
```

---

## Idempotency

- **Selection mode**: Queries `dpkg --get-selections <package>` and only runs `dpkg --set-selections` if the current selection differs from the requested state.
- **Deb file mode**: 
  - `state=present`: Uses `dpkg -l <package>` to check if package from the `.deb` is already installed (status `ii`).
  - `state=absent`: Uses `dpkg -l <name>` to verify package is installed before removing.

---

## Sudo Pathway

The module handles privilege escalation internally via the `use_sudo` parameter:

| `use_sudo` | Behavior |
|------------|----------|
| `auto` (default) | If running as non-root, prefixes commands with `sudo -n` (non-interactive). If root, runs directly. |
| `true` | Always prefix with `sudo -n` (fails if sudo unavailable). |
| `false` | Never use sudo (assumes root or passwordless sudo already configured). |

No Ansible `become: yes` required.

### Sudoers Example

```sudoers
# Allow ansible user to run dpkg commands without password
ansible ALL=(ALL) NOPASSWD: /usr/bin/dpkg, /usr/bin/dpkg-deb
```

---

## Return Values

| Key | Type | Description |
|-----|------|-------------|
| `changed` | boolean | Whether a change was made |
| `failed` | boolean | Whether the module failed |
| `msg` | string | Human-readable result message |
| `rc` | integer | Module return code (always 0 on success, non-zero on module error) |
| `results` | list | List of action messages (when `changed=true`) |
| `stdout` | string | Command stdout (on failure) |
| `stderr` | string | Command stderr (on failure) |
| `invocation.module_args` | dict | Echo of input parameters |

---

## Examples

### Hold kernel packages

```yaml
- name: Hold kernel packages
  bash.dpkg:
    name: "{{ item }}"
    selection: hold
    state: present
  loop:
    - linux-image-generic
    - linux-headers-generic
```

### Install local deb with config preservation

```yaml
- name: Install custom package preserving configs
  bash.dpkg:
    deb: "/tmp/packages/myapp_2.0_amd64.deb"
    state: present
    force: force-confold
    use_sudo: true
```

### Unmark hold on packages

```yaml
- name: Unhold packages for upgrade
  bash.dpkg:
    name: "{{ item }}"
    selection: hold
    state: absent
  loop:
    - nginx
    - postgresql-14
```

---

## Requirements

- `dpkg` (standard on Debian/Ubuntu)
- `dpkg-deb` (for deb file mode, standard on Debian/Ubuntu)
- `sudo` (if `use_sudo=auto/true` and not running as root)

---

## Notes

- The `force` parameter accepts comma-separated dpkg force options without the `--force-` prefix (the module adds it automatically).
- In deb file mode with `state=absent`, the `name` parameter is required if the package name cannot be extracted from the `.deb` file.
- Selection state `purge` marks the package for complete removal including configuration files.
- The module is fully idempotent — repeated runs with the same parameters produce `changed=false` when the target state matches.