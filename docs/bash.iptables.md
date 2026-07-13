# bash.iptables — Bash IPTables Module (callable as `bash.iptables:`)

## Overview

A pure Bash replacement for `ansible.builtin.iptables` — callable as **`bash.iptables:`** in Ansible playbooks. Manages individual iptables rules with full support for tables, chains, protocols, match modules, conntrack, DNAT/SNAT, and comments. Handles privilege escalation internally via `sudo -n`, so no Ansible `become` is required.

- **Distro family**: Cross-distro (all Linux with iptables/ip6tables)
- **Lines**: 428
- **Ansible equivalent**: `ansible.builtin.iptables`

## Quick Start

### Allow HTTP traffic

```yaml
- hosts: all
  tasks:
    - name: Allow HTTP on port 80
      bash.iptables:
        chain: INPUT
        protocol: tcp
        destination_port: 80
        jump: ACCEPT
        comment: "Allow HTTP"
```

### Block an IP

```yaml
- hosts: all
  tasks:
    - name: Block a malicious IP
      bash.iptables:
        chain: INPUT
        source: 10.0.0.99
        jump: DROP
        comment: "Block malicious IP"
```

### NAT / Port forwarding

```yaml
- hosts: all
  tasks:
    - name: DNAT port 8080 to internal host
      bash.iptables:
        table: nat
        chain: PREROUTING
        protocol: tcp
        destination_port: 8080
        jump: DNAT
        to_destination: 10.0.1.50:80
        comment: "Forward port 8080"
```

### Allow established connections

```yaml
- hosts: all
  tasks:
    - name: Allow established and related traffic
      bash.iptables:
        chain: INPUT
        ctstate: ESTABLISHED,RELATED
        jump: ACCEPT
        comment: "Allow established connections"
```

### IPv6 rule

```yaml
- hosts: all
  tasks:
    - name: Allow SSH over IPv6
      bash.iptables:
        ip_version: ipv6
        chain: INPUT
        protocol: tcp
        destination_port: 22
        jump: ACCEPT
        comment: "Allow SSH IPv6"
```

### Insert rule at a specific position

```yaml
- hosts: all
  tasks:
    - name: Insert SSH allow rule at position 1
      bash.iptables:
        chain: INPUT
        protocol: tcp
        destination_port: 22
        jump: ACCEPT
        action: insert
        comment: "Allow SSH"
```

### Remove a rule

```yaml
- hosts: all
  tasks:
    - name: Remove the HTTP allow rule
      bash.iptables:
        chain: INPUT
        protocol: tcp
        destination_port: 80
        jump: ACCEPT
        state: absent
```

### Flush all rules

```yaml
- hosts: all
  tasks:
    - name: Flush all rules in filter table
      bash.iptables:
        chain: INPUT
        flush: true
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `chain` | str | — | Chain to operate on (`INPUT`, `FORWARD`, `OUTPUT`, custom chain). **Required** |
| `table` | str | `filter` | Table: `filter`, `nat`, `mangle`, `raw`, `security` |
| `state` | str | `present` | `present` (ensure rule exists), `absent` (remove rule) |
| `action` | str | `append` | `append` (add rule at end, `-A`), `insert` (insert at top, `-I`) |
| `rule_num` | int | — | Rule number for insert/delete by position |
| `ip_version` | str | `ipv4` | `ipv4` (iptables), `ipv6` (ip6tables) |
| `protocol` | str | — | Protocol: `tcp`, `udp`, `icmp`, `icmpv6`, `all` |
| `source` | str | — | Source address or CIDR range |
| `destination` | str | — | Destination address or CIDR range |
| `source_port` | str | — | Source port or port range |
| `destination_port` | str | — | Destination port or port range (`80`, `80:443`, `80,443`) |
| `jump` | str | — | Target/chain: `ACCEPT`, `DROP`, `REJECT`, `LOG`, `RETURN`, `DNAT`, `SNAT`, `MASQUERADE`, custom chain |
| `in_interface` | str | — | Input interface (`eth0`, `lo`, `+` for wildcard) |
| `out_interface` | str | — | Output interface |
| `match` | str | — | Additional match module (`state`, `conntrack`, `comment`, `tcp`, `udp`, etc.) |
| `comment` | str | — | Rule comment (uses `comment` match module) |
| `ctstate` | str | — | Conntrack state: `NEW`, `ESTABLISHED`, `RELATED`, `INVALID`, `UNTRACKED` |
| `to_destination` | str | — | DNAT target (`--to-destination`, for `jump: DNAT`) |
| `to_source` | str | — | SNAT target (`--to-source`, for `jump: SNAT`) |
| `set` | bool | `false` | Use `-I` (insert at top) instead of `-A` (append). Alternative to `action: insert` |
| `flush` | bool | `false` | Flush all rules in the specified table/chain |
| `policy` | str | — | Chain policy: `ACCEPT`, `DROP`, `QUEUE`, `RETURN` |
| `rule` | str | — | Raw rule specification (advanced — everything after the chain name) |
| `use_sudo` | str/bool | `auto` | `auto` (sudo if non-root), `true` (always), `false` (never) |

## Return Values

```json
{
  "changed": true,
  "failed": false,
  "msg": "iptables rule added: -A INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment 'Allow HTTP'",
  "rc": 0,
  "invocation": {
    "module_args": {
      "chain": "INPUT",
      "protocol": "tcp",
      "destination_port": "80",
      "jump": "ACCEPT",
      "state": "present"
    }
  }
}
```

| Return | Type | Description |
|--------|------|-------------|
| `changed` | bool | Whether a rule was added or removed |
| `failed` | bool | Whether the operation failed |
| `msg` | str | Human-readable summary of the change |
| `rc` | int | Module exit code (always 0 on success) |
| `results` | list | Per-operation outcome messages |
| `invocation` | dict | Original module arguments for callback plugins |

## Sudo / Privilege Escalation

All iptables mutations require root privileges (they interact with kernel-level networking). The module handles this internally via `use_sudo`:

| Value | Behavior |
|---|---|
| `auto` (default) | Uses `sudo -n` when non-root, bare `iptables` when root |
| `true` | Always uses `sudo -n` |
| `false` | Never uses sudo |

### Example sudoers configuration

```sudo
# Allow deploy user to manage firewall rules
deploy ALL=(root) NOPASSWD: /usr/sbin/iptables *, /usr/sbin/ip6tables *, /usr/sbin/iptables-save, /usr/sbin/iptables-restore
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Allow SSH
      bash.iptables:
        chain: INPUT
        protocol: tcp
        destination_port: 22
        jump: ACCEPT
```

## Idempotency

- Uses `iptables -C <chain> <rule-spec>` to check if a rule already exists
- `state: present`: only adds (`-A`) the rule if `iptables -C` returns non-zero (rule not found)
- `state: absent`: only removes (`-D`) the rule if `iptables -C` returns zero (rule exists)
- `flush` and `policy` operations always execute (they are explicit state-setting operations)
- Repeat runs with the same parameters produce `changed: false` when the rule is already in place
