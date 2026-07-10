#!/usr/bin/env bash
# ansible-module: sample_bash
# description: Demonstrates the Bash module contract — accepts a "message" param and returns it.
# options:
#   message:
#     description: The message to echo back
#     required: false
#     type: str

set -euo pipefail

# ---- Parse arguments ----
message="Hello from Bash"

for arg in "$@"; do
  case "${arg}" in
    *=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      eval "$key=\"$val\""
      ;;
  esac
done

# ---- Main ----
cat <<JSON
{
  "changed": false,
  "msg": "$message",
  "module": "sample_bash",
  "source": "ansible-bash-modules"
}
JSON
