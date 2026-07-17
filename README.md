# Ansible Bash Modules

A collection of Ansible modules written entirely in **Bash** — no Python, no pip, no virtualenvs. Designed for minimal and embedded Linux systems where standard Ansible builtins can't run.

[![License: GPL v3](https://img.shields.io/github/license/RelooM/ansible-builtin-bash)](LICENSE)
![Built with Bash](https://img.shields.io/badge/built%20with-Bash-1f425f)
![Platform](https://img.shields.io/badge/platform-Linux%20%2F%20POSIX-lightgrey)
[![Modules](https://img.shields.io/badge/modules-25%20pure%20Bash-1f425f)](library)
![RHEL7 / yum](https://img.shields.io/badge/RHEL%207%20%2F%20yum-supported-blue)
![Ansible](https://img.shields.io/badge/Ansible-FQCN--ready-000000)
[![Tested on](https://img.shields.io/badge/tested%20on-AlmaLinux%20%2F%20Ubuntu-blue)](playbooks)

## Features

- **Zero runtime dependencies** — Only Bash and standard POSIX tools
- **Minimal system support** — Embedded Linux, containers, routers, or any system without Python
- **Internal privilege escalation** — Modules call `sudo -n` themselves. No Ansible `become` required
- **No `jq` needed** — All JSON output is built with pure Bash string quoting
- **Ansible-native args bridge** — Modules accept the standard args-file invocation used by modern ansible-core

## Quick Start

```bash
# Copy into your project or set the module path:
cp -r library/ /path/to/your/project/library/
ansible-playbook -i inventory playbook.yml --module-path /path/to/ansible-bash-modules/library
# or: export ANSIBLE_LIBRARY=/path/to/ansible-bash-modules/library
```

```yaml
- hosts: web_servers
  tasks:
    - bash.apt:
        name: nginx
        state: present
    - bash.systemd:
        name: nginx
        state: started
        enabled: true
    - bash.group:
        name: deploy
        state: present
        gid: 5000
```

## All Modules

### Package Management

| Module | Distro | Replaces | Description |
|--------|--------|----------|-------------|
| `bash.dnf` | 🔴 RHEL/Fedora | `ansible.builtin.dnf` | Install, remove, update, repos, groups, security/bugfix filters, autoremove, download-only. Auto-detects dnf4 vs dnf5 |
| `bash.yum` | 🔴 RHEL/CentOS 7 | `ansible.builtin.yum` | Install, remove, update, repos, groups, excludes, gpg, cache, autoremove. Auto-detects `yum` (EL7) vs `dnf`; dnf-only flags skipped on legacy yum |
| `bash.apt` | 🟢 Debian/Ubuntu | `ansible.builtin.apt` | Install, remove, upgrade, dist-upgrade, local `.deb` files, autoremove, purge, cache management, lock timeout |
| `bash.dpkg` | 🟢 Debian/Ubuntu | `ansible.builtin.dpkg_selections` | Package selection state (`hold`/`install`/`deinstall`/`purge`) and `.deb` file install/remove |
| `bash.deb822_repository` | 🟢 Debian/Ubuntu | `ansible.builtin.deb822_repository` | Manage deb822 `.sources` files in `/etc/apt/sources.list.d/`. Replaces legacy `apt_repository` |
| `bash.rpm_key` | 🔴 RHEL/Fedora | `ansible.builtin.rpm_key` | Import and remove RPM GPG keys (`rpm --import`) |
| `bash.yum_repository` | 🔴 RHEL/Fedora | `ansible.builtin.yum_repository` | Manage `.repo` files in `/etc/yum.repos.d/`. INI-style repo definitions |
| `bash.subscription_manager` | 🔴 RHEL | `community.general.redhat_subscription` | Register/unregister with RHSM, attach pools, set release, enable repos |

### System Services

| Module | Distro | Replaces | Description |
|--------|--------|----------|-------------|
| `bash.systemd` | 🔀 Cross-distro | `ansible.builtin.systemd_service` | systemd unit lifecycle — start, stop, restart, reload, enable, disable, daemon-reload, mask/unmask. System and user scope |
| `bash.service` | 🔀 Cross-distro | `ansible.builtin.service` | Service wrapper — delegates to `systemctl` (systemd) or `service` (sysvinit/OpenRC). Alias for `bash.systemd` on modern systems |

### System Management

| Module | Distro | Replaces | Description |
|--------|--------|----------|-------------|
| `bash.group` | 🔀 Cross-distro | `ansible.builtin.group` | Create, modify, remove groups. Set GID, system groups, non-unique GID, force removal |
| `bash.user` | 🔀 Cross-distro | `ansible.builtin.user` | Create, modify, remove users. UID, groups, shell, home, password, comment, system users, force removal |
| `bash.hostname` | 🔀 Cross-distro | `ansible.builtin.hostname` | Set system hostname via `hostnamectl`. Supports static, pretty, transient |
| `bash.timezone` | 🔀 Cross-distro | `ansible.builtin.timezone` | Set system timezone via `timedatectl set-timezone` |
| `bash.reboot` | 🔀 Cross-distro | `ansible.builtin.reboot` | Reboot system via `shutdown -r`. Deferred approach: schedules reboot and returns, letting Ansible reconnect |
| `bash.sysctl` | 🔀 Cross-distro | `ansible.builtin.sysctl` | Manage kernel parameters — runtime (`sysctl -w`) and persistent config files |
| `bash.tuned` | 🔴 RHEL/Fedora | `community.general.tuned` | Manage tuned performance profiles via `tuned-adm` |
| `bash.debconf` | 🟢 Debian/Ubuntu | `ansible.builtin.debconf` | Pre-seed debconf database values for non-interactive package installation |

### Security & Network

| Module | Distro | Replaces | Description |
|--------|--------|----------|-------------|
| `bash.firewalld` | 🔴 RHEL/Fedora | `ansible.posix.firewalld` | Manage firewalld zones, services, ports, rich rules, masquerade, ICMP blocks via `firewall-cmd` |
| `bash.selinux` | 🔴 RHEL/Fedora | `ansible.posix.selinux` | Manage SELinux mode, policy type, and booleans |
| `bash.iptables` | 🔀 Cross-distro | `ansible.builtin.iptables` | Manage iptables rules — chain, table, protocol, source/dest, jump target, comment, conntrack. Supports ipv4 and ipv6 |

### Utilities

| Module | Distro | Replaces | Description |
|--------|--------|----------|-------------|
| `bash.known_hosts` | 🔀 Cross-distro | `ansible.builtin.known_hosts` | Manage SSH host keys in `known_hosts` files via `ssh-keygen`. Supports hashed hosts |
| `bash.get_url` | 🔀 Cross-distro | `ansible.builtin.get_url` | Download a URL to a local destination with atomic move, checksum verification, and mode setting |
| `bash.lineinfile` | 🔀 Cross-distro | `ansible.builtin.lineinfile` | Ensure a line is present or absent in a file. Supports regex matching, file creation |

## Privilege Escalation

All modules handle `sudo` internally — **no `become: yes`** in your playbooks. When running as non-root, they prefix commands with `sudo -n` (non-interactive). Each module escalates only the specific commands it needs, enabling fine-grained sudoers policies:

```sudo
# /etc/sudoers.d/ansible-bash-modules
deploy ALL=(root) NOPASSWD: /usr/bin/dnf install *, /usr/bin/dnf remove *, /usr/bin/dnf update *
deploy ALL=(root) NOPASSWD: /usr/bin/yum install *, /usr/bin/yum remove *, /usr/bin/yum update *
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get *, /usr/bin/dpkg -i *
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl *, /usr/sbin/service *
deploy ALL=(root) NOPASSWD: /usr/sbin/useradd *, /usr/sbin/userdel *, /usr/sbin/usermod *
deploy ALL=(root) NOPASSWD: /usr/sbin/groupadd *, /usr/sbin/groupmod *, /usr/sbin/groupdel *
deploy ALL=(root) NOPASSWD: /usr/bin/firewall-cmd *
deploy ALL=(root) NOPASSWD: /usr/sbin/iptables *, /usr/sbin/sysctl *
deploy ALL=(root) NOPASSWD: /usr/bin/hostnamectl *, /usr/bin/timedatectl *
deploy ALL=(root) NOPASSWD: /usr/sbin/shutdown -r *
deploy ALL=(root) NOPASSWD: /usr/bin/rpm --import *, /usr/bin/ssh-keygen -R *
```

Every module supports the `use_sudo` parameter:

| Value | Behavior |
|-------|----------|
| `auto` (default) | Uses `sudo -n` when non-root, bare command when root |
| `true` | Always uses `sudo -n` |
| `false` | Never uses sudo |

## Playbook Test Suite

There is **one self-reverting test playbook per module** in [`playbooks/`](playbooks/)
(`test_<module>.yml`). Each plays through a module's arguments/use cases, asserts
idempotency, and **reverts its own changes** (created users/groups/files are
removed; stateful changes like hostname/timezone/SELinux/tuned/sysctl are
restored to their original value). `test_reboot.yml` is gated — it never reboots
unless you explicitly confirm.

Full index, invocation styles, and the design pattern are in
[`playbooks/README.md`](playbooks/README.md). Example:

```bash
ansible-playbook -i inventory playbooks/test_dnf.yml --module-path library --limit redhat
```

## Module Output

All modules return standard Ansible-compatible JSON on stdout:

```json
{
  "changed": true,
  "failed": false,
  "msg": "Operation completed successfully",
  "rc": 0,
  "results": [],
  "invocation": {
    "module_args": { }
  }
}
```

## Documentation

Each module's full parameter reference, state mapping, idempotency strategy, and sudoers examples are in its own `.md` file:

| Module | Doc | Module | Doc |
|--------|-----|--------|-----|
| `bash.dnf` | [`docs/bash.dnf.md`](docs/bash.dnf.md) | `bash.apt` | [`docs/bash.apt.md`](docs/bash.apt.md) |
| `bash.yum` | [`docs/bash.yum.md`](docs/bash.yum.md) | | |
| `bash.dpkg` | [`docs/bash.dpkg.md`](docs/bash.dpkg.md) | `bash.deb822_repository` | [`docs/bash.deb822_repository.md`](docs/bash.deb822_repository.md) |
| `bash.rpm_key` | [`docs/bash.rpm_key.md`](docs/bash.rpm_key.md) | `bash.yum_repository` | [`docs/bash.yum_repository.md`](docs/bash.yum_repository.md) |
| `bash.subscription_manager` | [`docs/bash.subscription_manager.md`](docs/bash.subscription_manager.md) | `bash.systemd` | [`docs/bash.systemd.md`](docs/bash.systemd.md) |
| `bash.service` | [`docs/bash.service.md`](docs/bash.service.md) | `bash.group` | [`docs/bash.group.md`](docs/bash.group.md) |
| `bash.user` | [`docs/bash.user.md`](docs/bash.user.md) | `bash.hostname` | [`docs/bash.hostname.md`](docs/bash.hostname.md) |
| `bash.timezone` | [`docs/bash.timezone.md`](docs/bash.timezone.md) | `bash.reboot` | [`docs/bash.reboot.md`](docs/bash.reboot.md) |
| `bash.sysctl` | [`docs/bash.sysctl.md`](docs/bash.sysctl.md) | `bash.tuned` | [`docs/bash.tuned.md`](docs/bash.tuned.md) |
| `bash.debconf` | [`docs/bash.debconf.md`](docs/bash.debconf.md) | `bash.firewalld` | [`docs/bash.firewalld.md`](docs/bash.firewalld.md) |
| `bash.selinux` | [`docs/bash.selinux.md`](docs/bash.selinux.md) | `bash.iptables` | [`docs/bash.iptables.md`](docs/bash.iptables.md) |
| `bash.known_hosts` | [`docs/bash.known_hosts.md`](docs/bash.known_hosts.md) | `bash.get_url` | [`docs/bash.get_url.md`](docs/bash.get_url.md) |
| `bash.lineinfile` | [`docs/bash.lineinfile.md`](docs/bash.lineinfile.md) | | |

## Verification

All 25 modules have been verified on live systems (regression pass — see commit history):

| Host | OS | Result |
|------|----|--------|
| Red Hat family (EL9/EL10) | AlmaLinux / Rocky / RHEL | all `bash.*` modules + 23 self-reverting playbooks `failed=0` |
| Debian family (Debian 12+ / Ubuntu 22.04+) | Ubuntu / Debian | all `bash.*` modules + 23 self-reverting playbooks `failed=0` |
| RHEL / CentOS 7 (legacy `yum`) | yum-based hosts | `bash.yum` exercises the identical playbook path; dnf-only flags are skipped so the generated yum command is always valid |
| Non-root (with passwordless sudo) | Both | All modules self-escalate via internal sudo. `failed=0` |

Test playbooks skip gracefully on hosts missing the relevant tooling (e.g. `systemctl`, `iptables`, `firewall-cmd`, `tuned-adm`) and leave no artifacts (verified: no stray test user/group/unit/rule/binary).

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)** — see the [`LICENSE`](LICENSE) file for the full text.

Copyright (C) 2026 — ansible-bash-modules contributors.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. This program is distributed WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See
the LICENSE file for details.
