#!/bin/bash
# Run an approved Terraform target through the private deployment runner.
set -euo pipefail
umask 077

# Print only anonymous names from the current private allowlist.
# Arguments: private deployment checkout directory.
# Returns: 1 if the configuration cannot provide valid target names.
list_targets() {
  if ! jq -er '
    .roots | select(type == "array") | map(.name)
    | if length > 0 and all(.[];
        type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
      then unique[] else error("Invalid target names") end
  ' "$1/deployment/config.json" 2> /dev/null; then
    printf 'ERROR: cannot read the private target allowlist.\n' >&2
    return 1
  fi
}

main() {
  local repo deploy_repo python
  repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  deploy_repo="${CFTF_DEPLOY_DIR:-${repo}/../cftf-deploy}"

  if [[ "$#" -eq 1 && "$1" == --list-targets ]]; then
    list_targets "${deploy_repo}"
    return
  fi
  if [[ "$#" -ne 2 ]] || [[ "$2" != plan && "$2" != apply ]]; then
    printf 'ERROR: usage: scripts/tf.sh <approved-target> <plan|apply>\n' >&2
    exit 1
  fi

  python="${CFTF_DEPLOY_PYTHON:-${deploy_repo}/.venv/bin/python}"
  if [[ ! -x "${python}" ]] || [[ ! -d "${deploy_repo}/deployment" ]]; then
    printf '%s\n' \
      'ERROR: prepare the private checkout and its virtual environment.' >&2
    exit 1
  fi

  # The private runner owns the allowlist, R2 fetching, TF_DATA_DIR isolation,
  # hidden diagnostics, plan inspection, and saved-plan application.
  cd -- "${deploy_repo}"
  exec "${python}" -m deployment.local \
    --source "${repo}" --target "$1" --operation "$2"
}

main "$@"
