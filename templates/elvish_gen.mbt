// 由一次性转译工具生成（源：上游 templates/elvish.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// elvish 模板渲染（自上游 templates/elvish.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_elvish(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  _resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  sb.write_string("\n\nuse builtin\nuse path\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n# cd + custom logic based on the value of _JB_ECHO.\nfn __jumbit_cd {|path|\n    builtin:cd $path",
  )
  if echo {
    sb.write_string("\n    builtin:echo $pwd")
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Hook configuration for jumbit.\n#\n\n# Initialize hook to track previous directory.\nvar oldpwd = $builtin:pwd\nset builtin:before-chdir = [$@builtin:before-chdir {|_| set oldpwd = $builtin:pwd }]\n\n# Initialize hook to add directories to jumbit.",
  )
  if hook is HookNone {
    sb.write_string("\n")
    sb.write_string(not_configured)
  } else {
    sb.write_string(
      "\nif (builtin:not (builtin:eq $E:__jumbit_shlvl $E:SHLVL)) {\n    set E:__jumbit_shlvl = $E:SHLVL",
    )
    if hook is HookPrompt {
      sb.write_string(
        "\n    set edit:before-readline = [$@edit:before-readline {|| jumbit add -- $pwd }]",
      )
    } else if hook is HookPwd {
      sb.write_string(
        "\n    set builtin:after-chdir = [$@builtin:after-chdir {|_| jumbit add -- $pwd }]",
      )
    }
    sb.write_string("\n}")
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\nfn __jumbit_z {|@rest|\n    if (builtin:eq [] $rest) {\n        __jumbit_cd ~\n    } elif (builtin:eq [-] $rest) {\n        __jumbit_cd $oldpwd\n    } elif (and ('builtin:==' (builtin:count $rest) 1) (path:is-dir &follow-symlink=$true $rest[0])) {\n        __jumbit_cd $rest[0]\n    } else {\n        var path\n        try {\n            set path = (jumbit query --exclude $pwd -- $@rest)\n        } catch {\n        } else {\n            __jumbit_cd $path\n        }\n    }\n}\nedit:add-var __jumbit_z~ $__jumbit_z~\n\n# Jump to a directory using interactive search.\nfn __jumbit_zi {|@rest|\n    var path\n    try {\n        set path = (jumbit query --interactive -- $@rest)\n    } catch {\n    } else {\n        __jumbit_cd $path\n    }\n}\nedit:add-var __jumbit_zi~ $__jumbit_zi~\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nedit:add-var ")
      sb.write_string(cmd)
      sb.write_string("~ $__jumbit_z~\nedit:add-var ")
      sb.write_string(cmd)
      sb.write_string("i~ $__jumbit_zi~\n\n# Load completions.\n")
      sb.write_string(
        "\nfn __jumbit_z_complete {|@rest|\n    if (!= (builtin:count $rest) 2) {\n        builtin:return\n    }\n    edit:complete-filename $rest[1] |\n        builtin:each {|completion|\n            var dir = $completion[stem]\n            if (path:is-dir $dir) {\n                builtin:put $dir\n            }\n        }\n}\nset edit:completion:arg-completer[",
      )
      sb.write_string(cmd)
      sb.write_string("] = $__jumbit_z_complete~")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your configuration (usually\n# ~/.elvish/rc.elv):\n#\n#   eval (jumbit init elvish | slurp)\n#\n# Note: jumbit only supports elvish v0.18.0 and above.\n",
  )
  sb.to_string()
}
