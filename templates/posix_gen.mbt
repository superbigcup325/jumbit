// 由一次性转译工具生成（源：上游 templates/posix.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// posix 模板渲染（自上游 templates/posix.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_posix(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  sb.write_string("\n\n# shellcheck shell=sh\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n# pwd based on the value of _JB_RESOLVE_SYMLINKS.",
  )
  let mut pwd : String = ""
  if resolve_symlinks {
    pwd = "\\command pwd -P"
  } else {
    pwd = "\\command pwd -L"
  }
  sb.write_string("\n__jumbit_pwd() {\n    ")
  sb.write_string(pwd)
  sb.write_string("\n}")
  sb.write_string(
    "\n\n# cd + custom logic based on the value of _JB_ECHO.\n__jumbit_cd() {\n    # shellcheck disable=SC2164\n    \\command cd \"$@\"",
  )
  if echo {
    sb.write_string(" && __jumbit_pwd")
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#\n\n")
  match hook {
    HookNone => {
      sb.write_string("\n")
      sb.write_string(not_configured)
    }
    HookPrompt => {
      sb.write_string(
        "\n# Hook to add new entries to the database.\n__jumbit_hook() {\n    \\command jumbit add -- \"$(__jumbit_pwd || \\command true)\"\n}\n\n# Initialize hook.\nif [ \"${PS1:=}\" = \"${PS1#*\\$(__jumbit_hook)}\" ]; then\n    PS1=\"${PS1}\\$(__jumbit_hook)\"\nfi\n\n# Report common issues.\n__jumbit_doctor() {",
      )
      if !(hook is HookPrompt) {
        sb.write_string("\n    return 0")
      } else {
        sb.write_string(
          "\n    [ \"${_JB_DOCTOR:-1}\" -eq 0 ] && return 0\n    case \"${PS1:-}\" in\n    *__jumbit_hook*) return 0 ;;\n    *) ;;\n    esac\n\n    _JB_DOCTOR=0\n    \\command printf '%s\\n' \\\n        'jumbit: detected a possible configuration issue.' \\\n        'Please ensure that jumbit is initialized right at the end of your shell configuration file.' \\\n        '' \\\n        'If the issue persists, consider filing an issue at:' \\\n        'https://github.com/superbigcup325/jumbit/issues' \\\n        '' \\\n        'Disable this message by setting _JB_DOCTOR=0.' \\\n        '' >&2",
        )
      }
      sb.write_string("\n}")
    }
    HookPwd =>
      sb.write_string(
        "\n\\command printf \"%s\\n%s\\n\" \\\n    \"jumbit: PWD hooks are not supported on POSIX shells.\" \\\n    \"        Use 'jumbit init posix --hook prompt' instead.\"",
      )
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\n__jumbit_z() {\n    __jumbit_doctor\n\n    if [ \"$#\" -eq 0 ]; then\n        __jumbit_cd ~\n    elif [ \"$#\" -eq 1 ] && [ \"$1\" = '-' ]; then\n        if [ -n \"${OLDPWD}\" ]; then\n            __jumbit_cd \"${OLDPWD}\"\n        else\n            # shellcheck disable=SC2016\n            \\command printf 'jumbit: $OLDPWD is not set'\n            return 1\n        fi\n    elif [ \"$#\" -eq 1 ] && (\\command cd -- \"$1\") >/dev/null 2>&1; then\n        __jumbit_cd \"$1\"\n    else\n        __jumbit_result=\"$(\\command jumbit query --exclude \"$(__jumbit_pwd || \\command true)\" -- \"$@\")\" &&\n            __jumbit_cd \"${__jumbit_result}\"\n    fi\n}\n\n# Jump to a directory using interactive search.\n__jumbit_zi() {\n    __jumbit_doctor\n    __jumbit_result=\"$(\\command jumbit query --interactive -- \"$@\")\" && __jumbit_cd \"${__jumbit_result}\"\n}\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\n\\command unalias ")
      sb.write_string(cmd)
      sb.write_string(" >/dev/null 2>&1 || \\true\n")
      sb.write_string(cmd)
      sb.write_string("() {\n    __jumbit_z \"$@\"\n}\n\n\\command unalias ")
      sb.write_string(cmd)
      sb.write_string("i >/dev/null 2>&1 || \\true\n")
      sb.write_string(cmd)
      sb.write_string("i() {\n    __jumbit_zi \"$@\"\n}")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your configuration:\n#\n# eval \"$(jumbit init posix --hook prompt)\"\n",
  )
  sb.to_string()
}
