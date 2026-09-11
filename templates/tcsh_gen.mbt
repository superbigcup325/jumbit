// 由一次性转译工具生成（源：上游 templates/tcsh.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// tcsh 模板渲染（自上游 templates/tcsh.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_tcsh(
  cmd : String?,
  hook : Hook,
  _echo : Bool,
  resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  let mut pwd_cmd : String = ""
  if resolve_symlinks {
    pwd_cmd = "pwd -P"
  } else {
    pwd_cmd = "pwd -L"
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#")
  if !(hook is HookNone) {
    sb.write_string("\n\n# Hook to add new entries to the database.")
    if hook is HookPrompt {
      sb.write_string("\nalias __jumbit_hook 'jumbit add -- \"`")
      sb.write_string(pwd_cmd)
      sb.write_string("`\"'")
    } else if hook is HookPwd {
      sb.write_string("\nset __jumbit_pwd_old = `")
      sb.write_string(pwd_cmd)
      sb.write_string("`\nalias __jumbit_hook 'set __jumbit_pwd_tmp = \"`")
      sb.write_string(pwd_cmd)
      sb.write_string(
        "`\"; test \"$__jumbit_pwd_tmp\" != \"$__jumbit_pwd_old\" && jumbit add -- \"$__jumbit_pwd_tmp\"; set __jumbit_pwd_old = \"$__jumbit_pwd_tmp\"'",
      )
    }
    sb.write_string(
      "\n\n# Initialize hook.\nset __jumbit_precmd = \"`alias precmd`\"\nif ( \"$__jumbit_precmd\" !~ *__jumbit_hook* ) then\n    if ( \"$__jumbit_precmd\" == \"\" ) then\n        alias precmd '__jumbit_hook'\n    else\n        alias precmd \"$__jumbit_precmd\"';__jumbit_hook'\n    endif\nendif\nunset __jumbit_precmd",
    )
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\nalias __jumbit_z 'set __jumbit_args = (\\!*)\\\nif (\"$#__jumbit_args\" == 0) then\\\n    cd ~\\\nelse\\\n    if (\"$#__jumbit_args\" == 1 && \"$__jumbit_args[1]\" == \"-\") then\\\n        cd -\\\n    else if (\"$#__jumbit_args\" == 1 && -d \"$__jumbit_args[1]\") then\\\n        cd \"$__jumbit_args[1]\"\\\n    else\\\n        set __jumbit_pwd = `",
  )
  sb.write_string(pwd_cmd)
  sb.write_string(
    "`\\\n        set __jumbit_result = \"`jumbit query --exclude '\"'\"'$__jumbit_pwd'\"'\"' -- $__jumbit_args`\" && cd \"$__jumbit_result\"\\\n    endif\\\nendif'\n\n# Jump to a directory using interactive search.\nalias __jumbit_zi 'set __jumbit_args = (\\!*)\\\nset __jumbit_pwd = `",
  )
  sb.write_string(pwd_cmd)
  sb.write_string(
    "`\\\nset __jumbit_result = \"`jumbit query --exclude '\"'\"'$__jumbit_pwd'\"'\"' --interactive -- $__jumbit_args`\" && cd \"$__jumbit_result\"'\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nalias ")
      sb.write_string(cmd)
      sb.write_string(" __jumbit_z\nalias ")
      sb.write_string(cmd)
      sb.write_string("i __jumbit_zi")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your shell configuration file (usually ~/.tcshrc):\n#\n#     jumbit init tcsh > ~/.jumbit.tcsh\n#     source ~/.jumbit.tcsh\n",
  )
  sb.to_string()
}
