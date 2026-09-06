// 由一次性转译工具生成（源：上游 templates/fish.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// bash 模板渲染（自上游 templates/fish.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_fish(
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
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n# pwd based on the value of _JB_RESOLVE_SYMLINKS.\nfunction __jumbit_pwd",
  )
  let mut pwd : String = ""
  if resolve_symlinks {
    pwd = "builtin pwd -P"
  } else {
    pwd = "builtin pwd -L"
  }
  sb.write_string("\n    ")
  sb.write_string(pwd)
  sb.write_string(
    "\nend\n\n# A copy of fish's internal cd function. This makes it possible to use\n# `alias cd=z` without causing an infinite loop.\nif ! builtin functions --query __jumbit_cd_internal\n    if status list-files functions/cd.fish &>/dev/null\n        status get-file functions/cd.fish | string replace --regex -- '^function cd\\s' 'function __jumbit_cd_internal ' | source\n    else\n        string replace --regex -- '^function cd\\s' 'function __jumbit_cd_internal ' <$__fish_data_dir/functions/cd.fish | source\n    end\nend\n\n# cd + custom logic based on the value of _JB_ECHO.\nfunction __jumbit_cd\n    if set -q __jumbit_loop\n        builtin echo \"jumbit: infinite loop detected\"\n        builtin echo \"Avoid aliasing `cd` to `z` directly, use `jumbit init --cmd=cd fish` instead\"\n        return 1\n    end",
  )
  sb.write_string("\n    __jumbit_loop=1 __jumbit_cd_internal $argv")
  if echo {
    sb.write_string("\n    and __jumbit_pwd")
  }
  sb.write_string("\nend\n\n")
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#\n\n")
  if hook is HookNone {
    sb.write_string("\n")
    sb.write_string(not_configured)
  } else {
    sb.write_string("\n# Initialize hook to add new entries to the database.")
    if hook is HookPrompt {
      sb.write_string("\nfunction __jumbit_hook --on-event fish_prompt")
    } else if hook is HookPwd {
      sb.write_string("\nfunction __jumbit_hook --on-variable PWD")
    }
    sb.write_string(
      "\n    test -z \"$fish_private_mode\"\n    and command jumbit add -- (__jumbit_pwd)\nend",
    )
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\nfunction __jumbit_z\n    set -l argc (builtin count $argv)\n    if test $argc -eq 0\n        __jumbit_cd $HOME\n    else if test \"$argv\" = -\n        __jumbit_cd -\n    else if test $argc -eq 1 -a -d $argv[1]\n        __jumbit_cd $argv[1]\n    else if test $argc -eq 2 -a $argv[1] = --\n        __jumbit_cd -- $argv[2]\n    else\n        set -l result (command jumbit query --exclude (__jumbit_pwd) -- $argv)\n        and __jumbit_cd $result\n    end\nend\n\n# Completions.\nfunction __jumbit_z_complete\n    set -l tokens (builtin commandline --current-process --tokenize)\n    set -l curr_tokens (builtin commandline --cut-at-cursor --current-process --tokenize)\n\n    if test (builtin count $tokens) -le 2 -a (builtin count $curr_tokens) -eq 1\n        # If there are < 2 arguments, use `cd` completions.\n        complete --do-complete \"'' \"(builtin commandline --cut-at-cursor --current-token) | string match --regex -- '.*/$'\n    else if test (builtin count $tokens) -eq (builtin count $curr_tokens)\n        # If the last argument is empty, use interactive selection.\n        set -l query $tokens[2..-1]\n        set -l result (command jumbit query --exclude (__jumbit_pwd) --interactive -- $query 2>/dev/null)\n        if test $status -eq 0\n            builtin commandline --replace -- \"",
  )
  sb.write_string(cmd_name)
  sb.write_string(
    " \"(string escape -- $result)\n            builtin commandline --function repaint execute\n        else\n            builtin commandline --function repaint\n        end\n    end\nend\ncomplete --command __jumbit_z --no-files --arguments '(__jumbit_z_complete)'\n\n# Jump to a directory using interactive search.\nfunction __jumbit_zi\n    set -l result (command jumbit query --interactive -- $argv)\n    and __jumbit_cd $result\nend\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nabbr --erase ")
      sb.write_string(cmd)
      sb.write_string(" &>/dev/null\ncomplete --erase --command ")
      sb.write_string(cmd)
      sb.write_string("\nalias ")
      sb.write_string(cmd)
      sb.write_string("=__jumbit_z\n\nabbr --erase ")
      sb.write_string(cmd)
      sb.write_string("i &>/dev/null\ncomplete --erase --command ")
      sb.write_string(cmd)
      sb.write_string("i\nalias ")
      sb.write_string(cmd)
      sb.write_string("i=__jumbit_zi")
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your configuration (usually\n# ~/.config/fish/config.fish):\n#\n#   jumbit init fish | source\n",
  )
  sb.to_string()
}
