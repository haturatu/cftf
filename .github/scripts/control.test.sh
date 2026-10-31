#!/bin/bash
# Run offline controller tests using the Python standard library.
set -euo pipefail

main() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  exec python3 -m unittest discover \
    --start-directory "${script_dir}" --pattern 'test_control.py' --verbose
}

main "$@"
