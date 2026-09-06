// 由一次性转译工具生成（源：上游 templates/bash.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// bash 模板渲染（自上游 templates/bash.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_bash(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  sb.write_string("\n\n# shellcheck shell=bash\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n# pwd based on the value of _JB_RESOLVE_SYMLINKS.\nfunction __jumbit_pwd() {",
  )
  let mut pwd : String = ""
  if resolve_symlinks {
    pwd = "\\builtin pwd -P"
  } else {
    pwd = "\\builtin pwd -L"
  }
  sb.write_string("\n    ")
  sb.write_string(pwd)
  sb.write_string(
    "\n}\n\n# cd + custom logic based on the value of _JB_ECHO.\nfunction __jumbit_cd() {\n    # shellcheck disable=SC2164\n    \\builtin cd -- \"$@\"",
  )
  if echo {
    sb.write_string(" && __jumbit_pwd")
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#")
  if !(hook is HookNone) {
    sb.write_string("\n\n# Hook to add new entries to the database.")
    if hook is HookPrompt {
      sb.write_string(
        "\nfunction __jumbit_hook() {\n    \\builtin local -r retval=\"$?\"\n    if [[ -o history ]]; then\n        # shellcheck disable=SC2312\n        \\command jumbit add -- \"$(__jumbit_pwd)\"\n    fi\n    return \"${retval}\"\n}",
      )
    } else if hook is HookPwd {
      sb.write_string(
        "\n__jumbit_oldpwd=\"$(__jumbit_pwd)\"\n\nfunction __jumbit_hook() {\n    \\builtin local -r retval=\"$?\"\n    \\builtin local pwd_tmp\n    pwd_tmp=\"$(__jumbit_pwd)\"\n    if [[ ${__jumbit_oldpwd} != \"${pwd_tmp}\" ]]; then\n        __jumbit_oldpwd=\"${pwd_tmp}\"\n        if [[ -o history ]]; then\n            \\command jumbit add -- \"${__jumbit_oldpwd}\"\n        fi\n    fi\n    return \"${retval}\"\n}",
      )
    }
    sb.write_string(
      "\n\n# Initialize hook.\nif [[ ${PROMPT_COMMAND:=} != *'__jumbit_hook'* ]]; then\n    if [[ \"$(declare -p PROMPT_COMMAND 2>&1)\" == \"declare -a\"* ]]; then\n        PROMPT_COMMAND=(\"${PROMPT_COMMAND[@]}\" __jumbit_hook)\n    else\n        # shellcheck disable=SC2128,SC2178\n        PROMPT_COMMAND=\"${PROMPT_COMMAND%\"${PROMPT_COMMAND##*[![:space:];]}\"}\"\n        # shellcheck disable=SC2128,SC2178\n        PROMPT_COMMAND=\"${PROMPT_COMMAND:+${PROMPT_COMMAND};}__jumbit_hook\"\n    fi\nfi",
    )
  }
  sb.write_string("\n\n# Report common issues.\nfunction __jumbit_doctor() {")
  if hook is HookNone {
    sb.write_string("\n    return 0")
  } else {
    sb.write_string(
      "\n    [[ ${_JB_DOCTOR:-1} -eq 0 ]] && return 0\n    # shellcheck disable=SC2199\n    [[ ${PROMPT_COMMAND[@]:-} == *'__jumbit_hook'* ]] && return 0\n    # shellcheck disable=SC2199\n    [[ ${__vsc_original_prompt_command[@]:-} == *'__jumbit_hook'* ]] && return 0\n\n    _JB_DOCTOR=0\n    \\builtin printf '%s\\n' \\\n        'jumbit: detected a possible configuration issue.' \\\n        'Please ensure that jumbit is initialized right at the end of your shell configuration file (usually ~/.bashrc).' \\\n        '' \\\n        'If the issue persists, consider filing an issue at:' \\\n        'https://github.com/superbigcup325/jumbit/issues' \\\n        '' \\\n        'Disable this message by setting _JB_DOCTOR=0.' \\\n        '' >&2",
    )
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n__jumbit_z_prefix='j#'\n\n# Jump to a directory using only keywords.\nfunction __jumbit_z() {\n    __jumbit_doctor\n\n    # shellcheck disable=SC2199\n    if [[ $# -eq 0 ]]; then\n        __jumbit_cd ~\n    elif [[ $# -eq 1 && $1 == '-' ]]; then\n        __jumbit_cd \"${OLDPWD}\"\n    elif [[ $# -eq 1 ]] && (\\builtin cd -- \"$1\") &>/dev/null; then\n        __jumbit_cd \"$1\"\n    elif [[ $# -eq 2 && $1 == '--' ]]; then\n        __jumbit_cd \"$2\"\n    elif [[ ${@: -1} == \"${__jumbit_z_prefix}\"?* ]]; then\n        # shellcheck disable=SC2124\n        \\builtin local result=\"${@: -1}\"\n        __jumbit_cd \"",
  )
  sb.write_string("${result:${#__jumbit_z_prefix}}")
  sb.write_string(
    "\"\n    else\n        \\builtin local result\n        # shellcheck disable=SC2312\n        result=\"$(\\command jumbit query --exclude \"$(__jumbit_pwd)\" -- \"$@\")\" &&\n            __jumbit_cd \"${result}\"\n    fi\n}\n\n# Jump to a directory using interactive search.\nfunction __jumbit_zi() {\n    __jumbit_doctor\n    \\builtin local result\n    result=\"$(\\command jumbit query --interactive -- \"$@\")\" && __jumbit_cd \"${result}\"\n}\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\n\\builtin unalias ")
      sb.write_string(cmd)
      sb.write_string(" &>/dev/null || \\builtin true\nfunction ")
      sb.write_string(cmd)
      sb.write_string("() {\n    __jumbit_z \"$@\"\n}\n\n\\builtin unalias ")
      sb.write_string(cmd)
      sb.write_string("i &>/dev/null || \\builtin true\nfunction ")
      sb.write_string(cmd)
      sb.write_string(
        "i() {\n    __jumbit_zi \"$@\"\n}\n\n# Load completions.\n# - Bash 4.4+ is required to use `@Q`.\n# - Completions require line editing. Since Bash supports only two modes of\n#   line editing (`vim` and `emacs`), we check if either them is enabled.\n# - Completions don't work on `dumb` terminals.\nif [[ ${BASH_VERSINFO[0]:-0} -eq 4 && ${BASH_VERSINFO[1]:-0} -ge 4 || ${BASH_VERSINFO[0]:-0} -ge 5 ]] &&\n    [[ :\"${SHELLOPTS}\": =~ :(vi|emacs): && ${TERM} != 'dumb' ]]; then\n\n    function __jumbit_z_complete_helper() {\n        READLINE_LINE=\"",
      )
      sb.write_string(cmd)
      sb.write_string(" ${__jumbit_result@Q}\"\n        READLINE_POINT=")
      sb.write_string("${#READLINE_LINE}")
      sb.write_string(
        "\n        bind '\"\\e[0n\": accept-line'\n        \\builtin printf '\\e[5n' >/dev/tty\n    }\n\n    function __jumbit_z_complete() {\n        # Only show completions when the cursor is at the end of the line.\n        [[ ",
      )
      sb.write_string("${#COMP_WORDS[@]}")
      sb.write_string(
        " -eq $((COMP_CWORD + 1)) ]] || return\n\n        # If there is only one argument, use `cd` completions.\n        if [[ ",
      )
      sb.write_string("${#COMP_WORDS[@]}")
      sb.write_string(
        " -eq 2 ]]; then\n            \\builtin mapfile -t COMPREPLY < <(\n                \\builtin compgen -A directory -- \"${COMP_WORDS[-1]}\" || \\builtin true\n            )\n        # If there is a space after the last word, use interactive selection.\n        elif [[ -z ${COMP_WORDS[-1]} ]]; then\n            # shellcheck disable=SC2312\n            if __jumbit_result=\"$(\\command jumbit query --exclude \"$(__jumbit_pwd)\" --interactive -- \"",
      )
      sb.write_string("${COMP_WORDS[@]:1:${#COMP_WORDS[@]}-2}")
      sb.write_string(
        "\" 2>/dev/null)\"; then\n                # In case the terminal does not respond to \\e[5n or another\n                # mechanism steals the response, it is still worth completing\n                # the directory in the command line.\n                COMPREPLY=(\"${__jumbit_z_prefix}${__jumbit_result}/\")\n\n                # Note: We here call \"bind\" without prefixing \"\\builtin\" to be\n                # compatible with frameworks like ble.sh, which emulates Bash's\n                # builtin \"bind\".\n                bind -x '\"\\e[0n\": __jumbit_z_complete_helper'\n                \\builtin printf '\\e[5n' >/dev/tty\n            else\n                # The interactive selection was cancelled. fzf has drawn over\n                # the prompt, so redraw the current line.\n                bind '\"\\e[0n\": redraw-current-line'\n                \\builtin printf '\\e[5n' >/dev/tty\n            fi\n        fi\n    }\n\n    \\builtin complete -F __jumbit_z_complete -o filenames -- ",
      )
      sb.write_string(cmd)
      sb.write_string("\n    \\builtin complete -r ")
      sb.write_string(cmd)
      sb.write_string("i &>/dev/null || \\builtin true\nfi")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your shell configuration file (usually ~/.bashrc):\n#\n# eval \"$(jumbit init bash)\"\n",
  )
  sb.to_string()
}
