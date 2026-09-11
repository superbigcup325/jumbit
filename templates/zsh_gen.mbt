// 由一次性转译工具生成（源：上游 templates/zsh.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// zsh 模板渲染（自上游 templates/zsh.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_zsh(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let cmd_name = match cmd {
    Some(c) => c
    None => "cd"
  }
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
  sb.write_string(
    "\n# Hook configuration for jumbit.\n#\n\n# Hook to add new entries to the database.\nfunction __jumbit_hook() {\n    # shellcheck disable=SC2312\n    \\command jumbit add -- \"$(__jumbit_pwd)\"\n}\n\n# Initialize hook.\n\\builtin typeset -ga precmd_functions\n\\builtin typeset -ga chpwd_functions\n# shellcheck disable=SC2034,SC2296\nprecmd_functions=(\"${(@)precmd_functions:#__jumbit_hook}\")\n# shellcheck disable=SC2034,SC2296\nchpwd_functions=(\"${(@)chpwd_functions:#__jumbit_hook}\")",
  )
  if hook is HookPrompt {
    sb.write_string("\nprecmd_functions+=(__jumbit_hook)")
  } else if hook is HookPwd {
    sb.write_string("\nchpwd_functions+=(__jumbit_hook)")
  }
  sb.write_string("\n\n# Report common issues.\nfunction __jumbit_doctor() {")
  if hook is HookNone {
    sb.write_string("\n    return 0")
  } else {
    sb.write_string(
      "\n    [[ ${_JB_DOCTOR:-1} -ne 0 ]] || return 0\n    [[ $- == *i* ]] || return 0",
    )
    if hook is HookPrompt {
      sb.write_string(
        "\n    [[ ${precmd_functions[(Ie)__jumbit_hook]:-} -eq 0 ]] || return 0",
      )
    } else if hook is HookPwd {
      sb.write_string(
        "\n    [[ ${chpwd_functions[(Ie)__jumbit_hook]:-} -eq 0 ]] || return 0",
      )
    }
    sb.write_string(
      "\n\n    _JB_DOCTOR=0\n    \\builtin printf '%s\\n' \\\n        'jumbit: detected a possible configuration issue.' \\\n        'Please ensure that jumbit is initialized right at the end of your shell configuration file (usually ~/.zshrc).' \\\n        '' \\\n        'If the issue persists, consider filing an issue at:' \\\n        'https://github.com/superbigcup325/jumbit/issues' \\\n        '' \\\n        'Disable this message by setting _JB_DOCTOR=0.' \\\n        '' >&2",
    )
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\nfunction __jumbit_z() {\n    __jumbit_doctor\n    if [[ \"$#\" -eq 0 ]]; then\n        __jumbit_cd ~\n    elif [[ \"$#\" -eq 1 ]] && [[ \"$1\" = '-' ]]; then\n        __jumbit_cd \"${OLDPWD}\"\n    elif [[ \"$#\" -eq 1 ]] && { [[ \"$1\" =~ ^[-+][0-9]+$ ]] || (\\builtin cd -q -- \"$1\") &>/dev/null; }; then\n        __jumbit_cd \"$1\"\n    elif [[ \"$#\" -eq 2 ]] && [[ \"$1\" = \"--\" ]]; then\n        __jumbit_cd \"$2\"\n    else\n        \\builtin local result\n        # shellcheck disable=SC2312\n        result=\"$(\\command jumbit query --exclude \"$(__jumbit_pwd)\" -- \"$@\")\" && __jumbit_cd \"${result}\"\n    fi\n}\n\n# Jump to a directory using interactive search.\nfunction __jumbit_zi() {\n    __jumbit_doctor\n    \\builtin local result\n    result=\"$(\\command jumbit query --interactive -- \"$@\")\" && __jumbit_cd \"${result}\"\n}\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nfunction ")
      sb.write_string(cmd)
      sb.write_string("() {\n    __jumbit_z \"$@\"\n}\n\nfunction ")
      sb.write_string(cmd)
      sb.write_string("i() {\n    __jumbit_zi \"$@\"\n}")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string(
    "\n\n# Completions.\nif [[ -o zle ]]; then\n    __jumbit_result=''\n\n    function __jumbit_z_complete() {\n        # Only show completions when the cursor is at the end of the line.\n        # shellcheck disable=SC2154\n        [[ \"",
  )
  sb.write_string("${#words[@]}")
  sb.write_string("\" -eq \"${CURRENT}\" ]] || return 0\n\n        if [[ \"")
  sb.write_string("${#words[@]}")
  sb.write_string(
    "\" -eq 2 ]]; then\n            # Show completions for local directories.\n            _cd -/\n\n        elif [[ \"${words[-1]}\" == '' ]]; then\n            # Show completions for Space-Tab.\n            # shellcheck disable=SC2086\n            __jumbit_result=\"$(\\command jumbit query --exclude \"$(__jumbit_pwd || \\builtin true)\" --interactive -- ${words[2,-1]} 2>/dev/null)\" || __jumbit_result=''\n\n            # Set a result to ensure completion doesn't re-run\n            compadd -Q -S \"\" -- \"\"\n\n            # Bind '\\e[0n' to helper function.\n            \\builtin bindkey '\\e[0n' '__jumbit_z_complete_helper'\n            # Sends query device status code, which results in a '\\e[0n' being sent to console input.\n            \\builtin printf '\\e[5n'\n\n            # Report that the completion was successful, so that we don't fall back\n            # to another completion function.\n            return 0\n        fi\n    }\n\n    function __jumbit_z_complete_helper() {\n        if [[ -n \"${__jumbit_result}\" ]]; then\n            # shellcheck disable=SC2034,SC2296\n            BUFFER=\"",
  )
  sb.write_string(cmd_name)
  sb.write_string(
    " ${(q-)__jumbit_result}\"\n            __jumbit_result=''\n            \\builtin zle reset-prompt\n            \\builtin zle accept-line\n        else\n            \\builtin zle reset-prompt\n        fi\n    }\n    \\builtin zle -N __jumbit_z_complete_helper",
  )
  match cmd {
    Some(cmd) => {
      sb.write_string(
        "\n\n    [[ \"${+functions[compdef]}\" -ne 0 ]] && \\compdef __jumbit_z_complete ",
      )
      sb.write_string(cmd)
    }
    None => ()
  }
  sb.write_string("\nfi\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your shell configuration file (usually ~/.zshrc):\n#\n# eval \"$(jumbit init zsh)\"\n",
  )
  sb.to_string()
}
