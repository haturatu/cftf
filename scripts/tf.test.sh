#!/bin/bash
# Test completion offline without Terraform, R2, or a private checkout.
set -euo pipefail

main() {
  local repo fixture original_options
  repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/cftf completion.XXXXXX")"
  trap 'rm -rf -- "${fixture}"' EXIT
  export CFTF_DEPLOY_DIR="${fixture}"
  mkdir -p "${fixture}/deployment"
  printf '%s\n' '{"roots":[{"name":"alpha"},{"name":"beta"}]}' \
    > "${fixture}/deployment/config.json"

  original_options="${SHELLOPTS}"
  # shellcheck source=scripts/tf-completion.bash
  source "${repo}/scripts/tf-completion.bash"
  [[ "${SHELLOPTS}" == "${original_options}" ]]
  complete -p ./scripts/tf.sh > /dev/null
  complete -p "${repo}/scripts/tf.sh" > /dev/null

  cd -- "${repo}"
  COMP_WORDS=(./scripts/tf.sh '')
  COMP_CWORD=1
  _cftf_tf_complete
  [[ "${COMPREPLY[*]}" == 'alpha beta' ]]

  # The loaded completion must observe edits without being sourced again.
  printf '%s\n' '{"roots":[{"name":"gamma"}]}' \
    > "${fixture}/deployment/config.json"
  _cftf_tf_complete
  [[ "${COMPREPLY[*]}" == 'gamma' ]]
  COMP_WORDS[1]=g
  _cftf_tf_complete
  [[ "${COMPREPLY[*]}" == 'gamma' ]]
  COMP_WORDS[1]=a
  _cftf_tf_complete
  [[ "${#COMPREPLY[@]}" -eq 0 ]]

  COMP_WORDS=("${repo}/scripts/tf.sh" gamma '')
  COMP_CWORD=2
  _cftf_tf_complete
  [[ "${COMPREPLY[*]}" == 'plan apply' ]]
  COMP_WORDS[2]=ap
  _cftf_tf_complete
  [[ "${COMPREPLY[*]}" == 'apply' ]]

  COMP_WORDS=("${repo}/scripts/tf.sh" gamma plan '')
  COMP_CWORD=3
  _cftf_tf_complete
  [[ "${#COMPREPLY[@]}" -eq 0 ]]

  printf '%s\n' '{"roots":[{"name":"private.invalid"}]}' \
    > "${fixture}/deployment/config.json"
  COMP_WORDS=("${repo}/scripts/tf.sh" '')
  COMP_CWORD=1
  _cftf_tf_complete
  [[ "${#COMPREPLY[@]}" -eq 0 ]]
  rm -- "${fixture}/deployment/config.json"
  _cftf_tf_complete
  [[ "${#COMPREPLY[@]}" -eq 0 ]]
  printf 'INFO: dynamic target and operation completion tests passed.\n'
  rm -rf -- "${fixture}"
  trap - EXIT
}

main "$@"
