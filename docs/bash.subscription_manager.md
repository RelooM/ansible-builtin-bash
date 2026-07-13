# bash.subscription_manager.sh — Bash Subscription Manager Module (callable as `bash.subscription_manager:`)

## Overview

A pure Bash replacement for `community.general.redhat_subscription` — callable as **`bash.subscription_manager:`** in Ansible playbooks. Manages Red Hat Subscription Manager (RHSM) registration, unregistration, subscription attachment, release version, and repository enablement. Designed for environments with fine-grained sudo policies.

- ✅ **Registers / unregisters** systems from RHSM
- ✅ **Supports** username/password and activation-key authentication
- ✅ **Attaches** specific subscription pools or auto-attaches compatible subscriptions
- ✅ **Sets** OS release version and enables repositories
- ✅ **Internal sudo** — runs `sudo -n` for individual `subscription-manager` commands, no `become` required

## Quick Start

### Register with username and password

```yaml
- name: Register system with RHSM
  hosts: redhat_servers
  tasks:
    - name: Register and attach pool
      bash.subscription_manager:
        username: "{{ rhsm_user }}"
        password: "{{ rhsm_pass }}"
        pool: "{{ rhsm_pool_id }}"
        state: present
```

### Register with activation key

```yaml
- name: Register with activation key
  hosts: redhat_servers
  tasks:
    - name: Register via activation key
      bash.subscription_manager:
        activationkey: "my-activation-key"
        org_id: "12345678"
        auto_attach: true
        state: present
```

### Unregister a system

```yaml
- name: Unregister from RHSM
  hosts: redhat_servers
  tasks:
    - name: Unregister system
      bash.subscription_manager:
        state: absent
```

### Register with custom server, release, and repos

```yaml
- name: Full registration with repo enablement
  hosts: redhat_servers
  tasks:
    - name: Register and configure repos
      bash.subscription_manager:
        username: "{{ rhsm_user }}"
        password: "{{ rhsm_pass }}"
        server_hostname: "subscription.rhsm.redhat.com"
        release: "9.2"
        repos: "rhel-9-for-x86_64-baseos-rpms,rhel-9-for-x86_64-appstream-rpms"
        auto_attach: true
        state: present
```

## Parameters

### Authentication

| Parameter | Type | Default | Description |
|---|---|---|---|
| `username` | str | — | RHSM account username (for password-based registration). Required unless `activationkey` is set. |
| `password` | str | — | RHSM account password. Required unless `activationkey` is set. |
| `activationkey` | str | — | Activation key for registration (used with `org_id` instead of username/password). |
| `org_id` | str | — | Organization ID. Required when using `activationkey`. Optional otherwise. |

### Subscription Control

| Parameter | Type | Default | Description |
|---|---|---|---|
| `pool` | str | — | Pool ID to attach (comma-separated list supported for multiple pools). |
| `auto_attach` | bool | `false` | Auto-attach compatible subscriptions after registration. |
| `release` | str | — | Set the OS release version (e.g. `9.2`). |
| `repos` | str | — | Comma-separated list of repository IDs to enable (e.g. `"rhel-9-for-x86_64-baseos-rpms,rhel-9-for-x86_64-appstream-rpms"`). |

### Server Configuration

| Parameter | Type | Default | Description |
|---|---|---|---|
| `server_hostname` | str | — | Subscription server hostname (e.g. `subscription.rhsm.redhat.com`). |
| `server_insecure` | bool | `false` | Skip SSL certificate verification when connecting to the subscription server. |

### Behavior

| Parameter | Type | Default | Description |
|---|---|---|---|
| `state` | str | `present` | `present` = register (and optionally attach/repos/release), `absent` = unregister. |
| `force_register` | bool | `false` | Re-register even if the system is already registered. Unregisters first, then registers again. |
| `use_sudo` | str/bool | `auto` | `auto` (auto-detect: sudo if non-root), `true` (always), `false` (never). |

## Return values

```json
{
  "changed": true,
  "failed": false,
  "msg": "System registered with RHSM.",
  "rc": 0,
  "invocation": {
    "args": {
      "state": "present",
      "username": "admin",
      "activationkey": "",
      "org_id": "12345678",
      "pool": "8a85f98181db5c2c0181db6d12340015",
      "auto_attach": true,
      "release": "9.2",
      "repos": "rhel-9-for-x86_64-baseos-rpms",
      "server_hostname": "subscription.rhsm.redhat.com",
      "force_register": false,
      "use_sudo": "auto"
    }
  }
}
```

Return values:

- `changed` (bool) — whether any change occurred
- `failed` (bool) — whether the operation failed
- `msg` (str) — human-readable summary (e.g. "System registered with RHSM." or "System already registered.")
- `rc` (int) — always 0 (module exit code; `subscription-manager` exit codes are reported in `msg` on failure)
- `invocation` (dict) — original module arguments for callback plugins

## Sudo / Privilege Escalation

This module handles privilege escalation **internally** — it calls `sudo -n` before every `subscription-manager` command when running as a non-root user. This is the key design difference vs. Ansible's built-in `community.general.redhat_subscription` module:

- ✅ **No `become` required** — the playbook runs as the regular user, and the module escalates only the specific `subscription-manager` commands via sudo
- ✅ **Fine-grained sudoers policies work** — e.g. `deploy ALL=(root) NOPASSWD: /usr/bin/subscription-manager *`
- ✅ **Non-root users** can manage RHSM subscriptions with limited, auditable permissions
- ✅ **No password prompts** — uses `sudo -n` (non-interactive), so the user must have NOPASSWD in sudoers

### `use_sudo` parameter

| Value | Behavior |
|---|---|
| `auto` (default) | Automatically detects: uses `sudo -n` if running as non-root, bare command if running as root |
| `true` | Always use `sudo -n`, even if already root |
| `false` | Never use sudo — run `subscription-manager` directly |

### Example sudoers configuration

```sudo
# Allow deploy user to manage RHSM without full root access
deploy ALL=(root) NOPASSWD: /usr/bin/subscription-manager *
```

### Playbook usage (no become)

```yaml
- hosts: all
  # No become: yes  ← not needed!
  tasks:
    - name: Register with RHSM
      bash.subscription_manager:
        username: "{{ rhsm_user }}"
        password: "{{ rhsm_pass }}"
        state: present
```

## State Mapping

| Playbook State | Behavior |
|---|---|
| `present` + not registered | Register system, optionally attach pools, set release, enable repos |
| `present` + already registered | No-op for registration; still reconciles release and repos if specified |
| `present` + `force_register` + already registered | Unregister first, then re-register with specified options |
| `absent` + registered | Unregister system from RHSM |
| `absent` + not registered | No-op |
