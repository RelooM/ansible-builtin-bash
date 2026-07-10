# Ansible Bash Modules

A collection of Ansible modules written entirely in **Bash**. These modules follow Ansible's module contract — accepting input via environment variables or stdin and returning JSON results on stdout.

## Why Bash Modules?

- **Zero runtime deps** — No Python, no pip installs, no virtualenvs. Just standard POSIX tools.
- **Target minimal systems** — Works on embedded Linux, containers, routers, or any environment where Python isn't available.
- **Simple to audit** — Each module is a single Bash script. What you see is what runs.
- **Fast execution** — No interpreter startup overhead beyond Bash itself.

## Project Structure

```
ansible-bash-modules/
├── library/          # Ansible modules (each is an executable Bash script)
├── playbooks/        # Test and example playbooks
├── tests/            # Unit and integration test scripts
└── README.md
```

## Ansible Module Contract (Bash)

Every module in `library/` follows these conventions:

| Requirement | Details |
|---|---|
| **Input** | Arguments passed as `key=value` pairs on the command line |
| **Output** | A single JSON object on **stdout** — exactly what Ansible expects |
| **Exit code** | `0` = success, non-zero = failure |
| **Error messages** | Stderr is captured by Ansible as the module's stderr |

### Output format

```json
{
  "changed": true,
  "msg": "operation completed",
  "rc": 0,
  "stdout": "...",
  "stderr": ""
}
```

The `changed` key is the minimum requirement. All other keys are optional but recommended.

## Usage with Ansible

Add the `library/` directory to your Ansible module path and reference modules by name:

```yaml
- hosts: all
  vars:
    ansible_shell_type: cmd
    ansible_shell_executable: /bin/bash
  tasks:
    - name: Run a bash-powered module
      my_bash_module:
        param1: value1
        param2: value2
```

Or set `ANSIBLE_LIBRARY=./library` before running your playbook.

## Sudo & Privilege Escalation

The `dnf.sh` module handles privilege escalation **internally** — no Ansible `become` needed. When running as a non-root user, it automatically prefixes `dnf` commands with `sudo -n`, leveraging whatever fine-grained sudoers rules are in place.

This is the key architectural difference vs. Ansible's built-in `dnf` module: the module itself escalates only the specific package manager commands, not the entire task.

```yaml
- hosts: all
  # No become required — dnf.sh calls sudo internally
  tasks:
    - name: Install packages using sudoers-granted permissions
      dnf:
        name: httpd
        state: present
```

The `use_sudo` parameter controls this behavior:
- **`auto`** (default) — uses `sudo -n` when running as non-root, bare `dnf` when root
- **`true`** — always uses `sudo -n`
- **`false`** — never uses sudo

See [`library/dnf.md`](library/dnf.md) for detailed sudoers configuration examples.

## Available Modules

| Module | Description |
|---|---|
| `dnf.sh` | Full replacement for `ansible.builtin.dnf` — pure Bash, sudo-aware. Supports all major parameters: `present`/`absent`/`latest`, multi-package, repos, groups, security/bugfix filters, autoremove, download-only, and more. |
| `sample_bash.sh` | Working example demonstrating the Ansible module contract in Bash |

## Development

1. Write your module as a single Bash script in `library/`.
2. Test it directly: `./library/my_module.sh param1=val1 param2=val2`
3. Run the full test suite: `./tests/run_all.sh`
4. Validate JSON output: `./library/my_module.sh arg=val | jq .`

## License

MIT
