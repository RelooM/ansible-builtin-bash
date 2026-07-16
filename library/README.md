# Module Library

Each file in this directory is an executable Ansible module written in Bash — no Python, no `jq`, no external dependencies.

## All Modules

| Module | File | Lines | Distro | Replaces | Description |
|--------|------|------:|--------|----------|-------------|
| `bash.dnf` | `bash.dnf.sh` | 980 | 🔴 RHEL | `ansible.builtin.dnf` | Package management — install, remove, update, repos, groups, security/bugfix filters, autoremove, download-only, dnf4/dnf5 auto-detection |
| `bash.yum` | `bash.yum.sh` | 1053 | 🔴 RHEL | `ansible.builtin.yum` | Install, remove, update, repos, groups, excludes, gpg, cache, autoremove. Auto-detects `yum` (EL7) vs `dnf`; dnf-only flags skipped on legacy yum |
| `bash.apt` | `bash.apt.sh` | 725 | 🟢 Debian | `ansible.builtin.apt` | Package management — install, remove, upgrade, dist-upgrade, local `.deb`, autoremove, purge, cache, lock timeout |
| `bash.dpkg` | `bash.dpkg.sh` | 494 | 🟢 Debian | `ansible.builtin.dpkg_selections` | Package selection state (`hold`/`install`/`deinstall`/`purge`) and `.deb` file install/remove |
| `bash.deb822_repository` | `bash.deb822_repository.sh` | 799 | 🟢 Debian | `ansible.builtin.deb822_repository` | Manage deb822 `.sources` files in `/etc/apt/sources.list.d/` |
| `bash.debconf` | `bash.debconf.sh` | 171 | 🟢 Debian | `ansible.builtin.debconf` | Pre-seed debconf database for non-interactive package install |
| `bash.systemd` | `bash.systemd.sh` | 550 | 🔀 Cross | `ansible.builtin.systemd_service` | systemd unit lifecycle — start, stop, restart, reload, enable, disable, daemon-reload, mask/unmask |
| `bash.service` | `bash.service.sh` | 237 | 🔀 Cross | `ansible.builtin.service` | Service wrapper — delegates to `systemctl` (systemd) or `service` (sysvinit) |
| `bash.user` | `bash.user.sh` | 690 | 🔀 Cross | `ansible.builtin.user` | User management — create, modify, remove, UID, groups, shell, home, password |
| `bash.group` | `bash.group.sh` | 502 | 🔀 Cross | `ansible.builtin.group` | Group management — create, modify, remove, GID, system groups |
| `bash.hostname` | `bash.hostname.sh` | 78 | 🔀 Cross | `ansible.builtin.hostname` | Set hostname via `hostnamectl` |
| `bash.timezone` | `bash.timezone.sh` | 143 | 🔀 Cross | `ansible.builtin.timezone` | Set timezone via `timedatectl set-timezone` |
| `bash.reboot` | `bash.reboot.sh` | 92 | 🔀 Cross | `ansible.builtin.reboot` | Reboot system via `shutdown -r` |
| `bash.sysctl` | `bash.sysctl.sh` | 119 | 🔀 Cross | `ansible.builtin.sysctl` | Kernel parameters — runtime and persistent config |
| `bash.known_hosts` | `bash.known_hosts.sh` | 73 | 🔀 Cross | `ansible.builtin.known_hosts` | SSH host keys in `known_hosts` files |
| `bash.get_url` | `bash.get_url.sh` | 112 | 🔀 Cross | `ansible.builtin.get_url` | Download URL with checksum, atomic move, mode setting |
| `bash.lineinfile` | `bash.lineinfile.sh` | 213 | 🔀 Cross | `ansible.builtin.lineinfile` | Ensure a line is present/absent in a file |
| `bash.firewalld` | `bash.firewalld.sh` | 393 | 🔴 RHEL | `ansible.posix.firewalld` | Firewall management via `firewall-cmd` |
| `bash.selinux` | `bash.selinux.sh` | 213 | 🔴 RHEL | `ansible.posix.selinux` | SELinux mode, policy, booleans |
| `bash.iptables` | `bash.iptables.sh` | 428 | 🔀 Cross | `ansible.builtin.iptables` | iptables rule management — tables, chains, rules, ipv4/ipv6 |
| `bash.rpm_key` | `bash.rpm_key.sh` | 281 | 🔴 RHEL | `ansible.builtin.rpm_key` | RPM GPG key import/remove |
| `bash.yum_repository` | `bash.yum_repository.sh` | 99 | 🔴 RHEL | `ansible.builtin.yum_repository` | Manage `.repo` files in `/etc/yum.repos.d/` |
| `bash.subscription_manager` | `bash.subscription_manager.sh` | 292 | 🔴 RHEL | `community.general.redhat_subscription` | RHSM registration, pools, repos |
| `bash.tuned` | `bash.tuned.sh` | 202 | 🔴 RHEL | `community.general.tuned` | Performance profile management via `tuned-adm` |
| `sample_bash` | `sample_bash.sh` | 33 | — | — | Working example demonstrating the module contract |

## Per-Module Documentation

| Module | Doc File | Module | Doc File |
|--------|----------|--------|----------|
| `bash.dnf` | [`bash.dnf.md`](../docs/bash.dnf.md) | `bash.apt` | [`bash.apt.md`](../docs/bash.apt.md) |
| `bash.yum` | [`bash.yum.md`](../docs/bash.yum.md) | | |
| `bash.systemd` | [`bash.systemd.md`](../docs/bash.systemd.md) | `bash.service` | [`bash.service.md`](../docs/bash.service.md) |
| `bash.group` | [`bash.group.md`](../docs/bash.group.md) | `bash.user` | [`bash.user.md`](../docs/bash.user.md) |
| `bash.dpkg` | [`bash.dpkg.md`](../docs/bash.dpkg.md) | `bash.deb822_repository` | [`bash.deb822_repository.md`](../docs/bash.deb822_repository.md) |
| `bash.debconf` | [`bash.debconf.md`](../docs/bash.debconf.md) | `bash.firewalld` | [`bash.firewalld.md`](../docs/bash.firewalld.md) |
| `bash.selinux` | [`bash.selinux.md`](../docs/bash.selinux.md) | `bash.iptables` | [`bash.iptables.md`](../docs/bash.iptables.md) |
| `bash.hostname` | [`bash.hostname.md`](../docs/bash.hostname.md) | `bash.reboot` | [`bash.reboot.md`](../docs/bash.reboot.md) |
| `bash.sysctl` | [`bash.sysctl.md`](../docs/bash.sysctl.md) | `bash.timezone` | [`bash.timezone.md`](../docs/bash.timezone.md) |
| `bash.tuned` | [`bash.tuned.md`](../docs/bash.tuned.md) | `bash.yum_repository` | [`bash.yum_repository.md`](../docs/bash.yum_repository.md) |
| `bash.rpm_key` | [`bash.rpm_key.md`](../docs/bash.rpm_key.md) | `bash.subscription_manager` | [`bash.subscription_manager.md`](../docs/bash.subscription_manager.md) |
| `bash.known_hosts` | [`bash.known_hosts.md`](../docs/bash.known_hosts.md) | `bash.get_url` | [`bash.get_url.md`](../docs/bash.get_url.md) |
| `bash.lineinfile` | [`bash.lineinfile.md`](../docs/bash.lineinfile.md) | | |

## Module Template

```bash
#!/usr/bin/env bash
# ansible-module: <module_name>
# description: <one-line description>
# options:
#   param_name:
#     description: <what this param does>
#     required: true/false
#     type: str/bool/int

set -euo pipefail

# ---- Parse arguments ----
for arg in "$@"; do
  case "${arg}" in *=*)
    key="${arg%%=*}"; val="${arg#*=}"
    eval "$key=\"$val\""
  ;; esac
done

# ---- Main logic ----
echo '{"changed": false, "msg": "Module stub — replace with real logic"}'
```

## Output Convention

- **Always** output a single JSON object on stdout.
- **Always** set `"changed"` to `true` or `false`, and `"failed"` to `true` or `false`.
- On failure, exit non-zero. On success, exit zero.
- Include `"invocation": {"module_args": {...}}` with the original arguments.
- Include `"results": [...]` with per-item outcome messages where applicable.
