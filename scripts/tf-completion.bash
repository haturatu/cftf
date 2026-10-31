#!/bin/bash
# Source this file to enable dynamic Bash completion for scripts/tf.sh.

# Complete live private target names, followed by fixed plan/apply operations.
# Uses Bash completion variables; does not change the calling shell's options.
_cftf_tf_complete() {
  local current targets
  current="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()

  case "${COMP_CWORD}" in
    1)
      targets="$("${COMP_WORDS[0]}" --list-targets 2> /dev/null)" || return 0
      mapfile -t COMPREPLY < <(compgen -W "${targets}" -- "${current}")
      ;;
    2)
      mapfile -t COMPREPLY < <(compgen -W 'plan apply' -- "${current}")
      ;;
  esac
  return 0
}

_cftf_register_completion() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  complete -F _cftf_tf_complete \
    tf.sh scripts/tf.sh ./scripts/tf.sh "${script_dir}/tf.sh"
}

_cftf_register_completion
unset -f _cftf_register_completion
