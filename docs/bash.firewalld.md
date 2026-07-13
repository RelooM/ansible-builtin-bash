# bash.firewalld.sh — Bash Firewalld Module (callable as `bash.firewalld:`)

## Overview

A pure Bash replacement for `ansible.posix.firewalld` — callable as **`bash.firewalld:`** in Ansible playbooks. Manages firewalld zones, services, ports, rich rules, and network configuration via `firewall-cmd`. Designed for environments with fine-grained sudo policies — escalates only the specific firewall commands rather than requiring full root access.

## Quick Start

```yaml
- hosts: all
  tasks:
    - name: Allow HTTPS traffic in the default zone
      bash.firewalld:
        service: https
        state: enabled

    - name: Open port 8443/tcp permanently
      bash.firewalld:
        port: 8443/tcp
        state: enabled
        permanent: true
        immediate: true

    - name: Block an ICMP type
      bash.firewalld:
        icmp_block: echo-request
        state: enabled
        zone: public
```

### Parameters

#### Zone
| Parameter | Type | Default | Description |
|---|---|---|---|
| `zone` | str | — | Firewalld zone to manage. Omit for the default zone. |

#### Services & Ports
| Parameter | Type | Default | Description |
|---|---|---|---|
| `service` | str | — | Service name to add/remove (e.g. `ssh`, `http`, `https`). |
| `port` | str | — | Port and protocol to add/remove (e.g. `80/tcp`, `5000-5100/udp`). |
| `protocol` | str | — | Protocol to add/remove (e.g. `igmp`). |
| `forward_port` | str | — | Port forward rule. Format: `port=<port>:proto=<proto>:toport=<port>` (e.g. `port=80:proto=tcp:toport=8080`). |

#### Sources & Interfaces
| Parameter | Type | Default | Description |
|---|---|---|---|
| `source` | str | — | Source address or CIDR range to add/remove (e.g. `192.168.1.0/24`). |
| `interface` | str | — | Network interface to add/remove from the zone (e.g. `eth0`). |

#### Rich Rules & Advanced
| Parameter | Type | Default | Description |
|---|---|---|---|
| `rich_rule` | str | — | A firewalld rich rule string (e.g. `'rule family="ipv4" source address="10.0.0.0/8" service name="ssh" accept'`). |
| `masquerade` | bool | — | Enable or disable masquerading for the zone. |
| `icmp_block` | str | — | ICMP type to block (e.g. `echo-request`, `router-solicitation`). |
| `icmp_block_inversion` | bool | — | Enable or disable ICMP block inversion (block all types *except* those listed). |
| `target` | str | — | Zone target: `default`, `ACCEPT`, `DROP`, or `REJECT`. |

#### Timeouts
| Parameter | Type | Default | Description |
|---|---|---|---|
| `timeout` | int | — | Timeout in seconds for the rule when using non-permanent changes. Only applies when `permanent` is `false`. |

#### Persistence & Lifecycle
| Parameter | Type | Default | Description |
|---|---|---|---|
| `permanent` | bool | `false` | Whether the change should persist across firewalld reloads. When `true`, writes to the permanent configuration. |
| `immediate` | bool | `true` | When `permanent` is `true`, also apply the change to the running firewall immediately. Ignored when `permanent` is `false`. |
| `offline` | bool | `false` | Use `firewall-offline-cmd` instead of `firewall-cmd`. Use when the firewalld daemon is stopped. |
| `state` | str | `enabled` | `enabled`/`present` to add the item, `disabled`/`absent` to remove it. |
| `use_sudo` | str/bool | `auto` | Privilege escalation strategy (see **Sudo** section below). |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "Firewalld configuration updated successfully",
  "rc": 0,
  "results": [
    "Added service https"
  ],
  "invocation": {
    "module_args": {
      "service": "https",
      "state": "enabled",
      "permanent": false,
      "immediate": true,
      "offline": false
    }
  }
}
```

- `changed` (bool) — whether any change was made
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary
- `rc` (int) — always 0 at module level (individual command exit codes are captured in `results`/`stderr`)
- `results` (list) — per-item outcome messages (e.g. `"Added service ssh"`, `"Port 443/tcp already present"`)
- `stdout` (str) — raw stdout from `firewall-cmd` (when present)
- `stderr` (str) — raw stderr from `firewall-cmd` (when present)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `firewall-cmd` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `ansible.posix.firewalld` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific firewall commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/firewall-cmd *`
- ✅ **Non-root users** can manage firewalld with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare `firewall-cmd` if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run `firewall-cmd` directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage firewalld without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/firewall-cmd *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Allow SSH
      bash.firewalld:
        service: ssh
        state: enabled
```
