# Ansible Bash Modules

A collection of Ansible modules written entirely in **Bash** — no Python, no pip, no virtualenvs. Designed for minimal and embedded Linux systems where standard Ansible builtins can't run.

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
| `bash.systemd` | [`docs/bash.systemd.md`](docs/bash.systemd.md) | `bash.group` | [`docs/bash.group.md`](docs/bash.group.md) |
| `bash.user` | [`docs/bash.user.md`](docs/bash.user.md) | `bash.dpkg` | [`docs/bash.dpkg.md`](docs/bash.dpkg.md) |

See also the full design document [`DRAFT-LINUX-MODULES.md`](DRAFT-LINUX-MODULES.md) for architecture decisions, cross-reference of all Ansible built-in modules, and implementation patterns.

## Verification

All 23 modules have been verified on live systems:

| Host | OS | Result |
|------|----|--------|
| `el-host.example.com` | AlmaLinux 9 | `ok=66 changed=29 failed=0` |
| `deb-host.example.com` | Ubuntu 22.04 | `ok=57 changed=27 failed=0` |
| Non-root (uid 1000, passwordless sudo) | Both | All modules self-escalate via internal sudo. `failed=0` |

## License

MIT
