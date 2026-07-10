# Module Library

Each file in this directory is an executable Ansible module written in Bash.

## Module Template

Use the following skeleton when creating a new module:

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
# Arguments arrive as key=value positional params

for arg in "$@"; do
  case "${arg}" in
    *=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      eval "$key=\"$val\""
      ;;
  esac
done

# ---- Validate required params ----
# if [[ -z "${param_name:-}" ]]; then
#   echo '{"failed": true, "msg": "Missing required argument: param_name"}'
#   exit 1
# fi

# ---- Main logic ----

# Example:
# if some_command; then
#   echo '{"changed": true, "msg": "Operation completed successfully"}'
# else
#   echo "{\"failed\": true, \"msg\": \"Operation failed: $?\"}"
#   exit 1
# fi

echo '{"changed": false, "msg": "Module stub — replace with real logic"}'
```

## Argument Parsing

Ansible passes arguments as positional `key=value` pairs. The `library/` modules use simple inline parsing — no external argument parsers needed.

## Output Convention

- **Always** output a single JSON object on stdout.
- **Always** set `"changed"` to `true` or `false`.
- On failure, set `"failed": true` and **exit non-zero**.
