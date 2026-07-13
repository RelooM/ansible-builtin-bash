# Playbook Test Suite — `ansible-bash-modules`

This folder contains **one self-reverting test playbook per module**. Every
playbook exercises a module's arguments and use cases, asserts idempotency
(changed on first apply, not changed on re-apply), and **cleans up its own
changes** — e.g. created users/groups/files are removed, and stateful changes
(hostname, timezone, tuned/SELinux profile, sysctl) are restored to their
original value at the end (via an `always`/`block` cleanup).

> **No `become:` / `become_user:` anywhere.** All modules escalate internally
> via `sudo -n` when run as non-root. The connecting user only needs passwordless
> sudo on the target (or root). See the root `README.md` → *Privilege Escalation*.

## How to run

```bash
# One module:
ansible-playbook -i inventory playbooks/test_dnf.yml --module-path library --limit redhat

# All token-based module tests (skip the gated reboot + JSON-module ones first
# if you only want the FQCN modules):
for p in playbooks/test_*.yml; do
  [ "$p" = "playbooks/test_reboot.yml" ] && continue
  ansible-playbook -i inventory "$p" --module-path library
done
```

### Two invocation styles

- **Token modules (19 of 23)** — invoked as native FQCN tasks, e.g.
  `bash.dnf: { name: curl, state: present }`. Ansible resolves them through
  `--module-path library`. No file transfer needed.
- **JSON modules (4):** `bash.get_url`, `bash.hostname`, `bash.known_hosts`,
  `bash.yum_repository` — read args from the `ARGS_JSON` environment variable.
  Their playbooks **ship `library/` to `/tmp/bashmods`** on the target, then call
  the script directly with `command:` + `environment: { ARGS_JSON: ... }`. These
  must run with `connection: ssh` (not `local`) so the module can escalate via
  `sudo -n` on the remote — or, on localhost, with `connection: local` and
  `use_sudo: "false"` where the playbook already sets it.

## Test index

| Playbook | Module | Family | Covers | Self-reverts by | Notes |
|----------|--------|--------|--------|-----------------|-------|
| `test_apt.yml` | `bash.apt` | Debian | install (1 + multi), latest, absent + idempotent, `update_cache` | removes test packages (`post_tasks`) | `--limit debian` |
| `test_deb822_repository.yml` | `bash.deb822_repository` | Debian | create enabled/disabled `.sources`, idempotency | removes both repos (`always`) | `--limit debian` |
| `test_debconf.yml` | `bash.debconf` | Debian | set boolean selection, idempotency | clears value (`always`) | skipped if `debconf` tooling missing |
| `test_dpkg.yml` | `bash.dpkg` | Debian | install local `.deb`, idempotency | purges pkg + removes `.deb` (`always`) | downloads sample `.deb` via `bash.get_url`; skips gracefully if mirror differs |
| `test_dnf.yml` | `bash.dnf` | RHEL | install (1 + multi), latest, `update_cache`, `autoremove`, absent + idempotent | removes test pkgs + `autoremove` (`post_tasks`) | `--limit redhat` |
| `test_firewalld.yml` | `bash.firewalld` | RHEL | add port + service (permanent + immediate), idempotency | removes port + service (`always`) | skipped if `firewall-cmd` missing |
| `test_selinux.yml` | `bash.selinux` | RHEL | set `permissive`, idempotency | restores original state (`always`) | skipped if SELinux disabled/absent |
| `test_tuned.yml` | `bash.tuned` | RHEL | switch profile, idempotency | restores original profile (`always`) | skipped if `tuned-adm` missing |
| `test_subscription_manager.yml` | `bash.subscription_manager` | RHEL | **safe** no-op unregister (`state=absent`) | n/a | does **not** register (needs RHSM creds) |
| `test_rpm_key.yml` | `bash.rpm_key` | RHEL | remove missing key (no-op), idempotency | n/a | safe no-op only |
| `test_group.yml` | `bash.group` | Cross | create, idempotency | removes group (`always`) | |
| `test_user.yml` | `bash.user` | Cross | create, set password, idempotency | removes user + home (`always`) | generates throwaway pw hash |
| `test_sysctl.yml` | `bash.sysctl` | Cross | set param, idempotency | removes entry + restores live value (`always`) | |
| `test_lineinfile.yml` | `bash.lineinfile` | Cross | present, idempotent, absent | removes temp file (`always`) | |
| `test_iptables.yml` | `bash.iptables` | Cross | add rule (tagged), idempotency | removes rule (`always`) | skipped if `iptables` missing |
| `test_service.yml` | `bash.service` | Cross | start + enable, idempotency | stop + disable (`always`) | auto-picks `cron`/`cronie`; skips if no `systemctl` |
| `test_systemd.yml` | `bash.systemd` | Cross | create + enable unit, idempotency | disable + remove unit (`always`) | skipped if no `systemctl` |
| `test_timezone.yml` | `bash.timezone` | Cross | set TZ (UTC), idempotency | restores original TZ (`always`) | |
| `test_get_url.yml` | `bash.get_url` | Cross (JSON) | download to file + nested dir, idempotency | removes files (`always`) | ships `library/` → `/tmp/bashmods` |
| `test_hostname.yml` | `bash.hostname` | Cross (JSON) | set hostname, idempotency | restores original hostname (`always`) | ships `library/` → `/tmp/bashmods` |
| `test_known_hosts.yml` | `bash.known_hosts` | Cross (JSON) | add key, idempotency | removes key (`always`) | ships `library/` → `/tmp/bashmods` |
| `test_yum_repository.yml` | `bash.yum_repository` | RHEL (JSON) | create enabled/disabled `.repo`, idempotency | removes both repos (`always`) | ships `library/` → `/tmp/bashmods`; `--limit redhat` |
| `test_reboot.yml` | `bash.reboot` | Cross | **gated** dry-run plan + prompt + real reboot + `wait_for_connection` verify | n/a (self-contained) | see below |

## `test_reboot.yml` is gated

`bash.reboot` is **destructive** (it reboots the host). This playbook does **not**
reboot by default:

1. It prints exactly what it *would* do.
2. It pauses for explicit confirmation (`pause:` prompt) — type `yes` to proceed.
3. Only after confirmation (or `-e proceed=yes`) does it trigger the reboot,
   then `wait_for_connection` and a post-reboot `uptime` check.

```bash
# Dry run — prints the plan, prompts, does not reboot:
ansible-playbook -i inventory playbooks/test_reboot.yml --module-path library --limit redhat

# Real reboot — confirm at the prompt OR pass the var:
ansible-playbook -i inventory playbooks/test_reboot.yml --module-path library --limit redhat -e proceed=yes
```

## Designing a new test playbook

Follow the same shape so it stays self-reverting:

1. `hosts:` scoped to the right family (`redhat` / `debian` / `all`).
2. `gather_facts: true` (some tests use `ansible_os_family` / `ansible_distribution_release`).
3. **Capture originals first** for stateful modules (hostname, timezone, tuned,
   SELinux, sysctl live value) into `set_fact` vars.
4. Apply → assert `changed` on first run and `not changed` on the idempotent
   re-run via an `ansible.builtin.assert` block with `that:`.
5. **Cleanup in an `always`/post block**: delete created users/groups/files,
   remove rules/repos/keys, and restore captured originals. Mark cleanup tasks
   `failed_when: false` so a partial failure still tears down.
6. For JSON modules: `copy: src={{ playbook_dir }}/../library/ dest=/tmp/bashmods/`
   then `command: /tmp/bashmods/bash.X.sh` with `environment: { ARGS_JSON: ... }`,
   and assert on `(stdout | from_json).changed`.
