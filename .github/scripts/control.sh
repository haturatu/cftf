#!/bin/bash
# Run the trusted merge controller without requiring Node.js.
set -euo pipefail
set +x

main() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  exec python3 "${script_dir}/control.py" "$@"
}

main "$@"
