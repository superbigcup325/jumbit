// Template argument-matrix tests: 3 shells x cmd(2) x hook(3) x echo(2) x resolve_symlinks(2)

///|
fn render_all() -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let shells = [
    "bash", "zsh", "fish", "elvish", "nushell", "posix", "powershell", "tcsh", "xonsh",
  ]
  let hooks = [@templates.HookNone, HookPrompt, HookPwd]
  for shell in shells {
    for cmd in [Some("j"), None] {
      for hook in hooks {
        for echo in [false, true] {
          for resolve in [false, true] {
            let src = match shell {
              "bash" => @templates.render_bash(cmd, hook, echo, resolve)
              "zsh" => @templates.render_zsh(cmd, hook, echo, resolve)
              "fish" => @templates.render_fish(cmd, hook, echo, resolve)
              "elvish" => @templates.render_elvish(cmd, hook, echo, resolve)
              "nushell" => @templates.render_nushell(cmd, hook, echo, resolve)
              "posix" => @templates.render_posix(cmd, hook, echo, resolve)
              "powershell" =>
                @templates.render_powershell(cmd, hook, echo, resolve)
              "tcsh" => @templates.render_tcsh(cmd, hook, echo, resolve)
              "xonsh" => @templates.render_xonsh(cmd, hook, echo, resolve)
              _ => "" // unreachable: the shells array holds only eight
            }
            out.push(
              (
                "\{shell} nocmd=\{cmd is None} hook=\{Repr(hook)} echo=\{echo} resolve=\{resolve}",
                src,
              ),
            )
          }
        }
      }
    }
  }
  out
}

///|
test "template matrix: 24 variants x 9 shells are all non-empty with no zoxide left" {
  let all = render_all()
  @debug.assert_eq(all.length(), 216)
  for pair in all {
    let src = pair.1
    @debug.assert_eq(src.length() > 100, true)
    @debug.assert_eq(src.contains("zoxide"), false)
    @debug.assert_eq(src.contains("_ZO_"), false)
    @debug.assert_eq(src.contains("__zoxide_"), false)
  }
}

///|
test "template matrix: --no-cmd defines no j command and prints not configured" {
  for pair in render_all() {
    let src = pair.1
    if pair.0.contains("nocmd=true") {
      // the cmd=None variant: no j/ji command, with the not-configured placeholder
      let defines_j = src.contains("function j(") ||
        src.contains("alias j=") ||
        src.contains("edit:add-var j~")
      if defines_j {
        fail("the no-cmd variant defined a j command: \{pair.0}")
      }
      @debug.assert_eq(src.contains("# -- not configured --"), true)
    } else if src.contains("# -- not configured --") {
      // fish/elvish semantics: with hook=none the hook section prints not configured (independent of cmd, matching upstream)
      let none_not_configured = pair.0.contains("hook=HookNone") &&
        (
          pair.0.contains("fish") ||
          pair.0.contains("elvish") ||
          pair.0.contains("nushell") ||
          pair.0.contains("posix") ||
          pair.0.contains("powershell") ||
          pair.0.contains("xonsh")
        )
      if !none_not_configured {
        fail("a variant with a command still printed not configured: \{pair.0}")
      }
    }
  }
}

///|
test "template matrix: hook=pwd/prompt emit the right hook, none emits nothing" {
  for pair in render_all() {
    let src = pair.1
    // elvish has no __jumbit_hook function (the hook is inlined in the init body; asserted separately below)
    if pair.0.contains("HookPrompt") && !pair.0.contains("elvish") {
      @debug.assert_eq(src.contains("__jumbit_hook"), true)
    }
  }
  // the hook=none bash variant: no __jumbit_hook body is defined
  let none_bash = @templates.render_bash(None, HookNone, false, false)
  @debug.assert_eq(none_bash.contains("function __jumbit_hook"), false)
  // the hook=pwd zsh variant hangs off chpwd_functions
  let pwd_zsh = @templates.render_zsh(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_zsh.contains("chpwd_functions+=(__jumbit_hook)"), true)
  // the hook=prompt fish variant hangs off the fish_prompt event
  let prompt_fish = @templates.render_fish(Some("j"), HookPrompt, false, false)
  @debug.assert_eq(prompt_fish.contains("--on-event fish_prompt"), true)
  // posix: none prints not configured; pwd is unsupported (an alternative is suggested); prompt hangs off PS1
  let none_posix = @templates.render_posix(None, HookNone, false, false)
  @debug.assert_eq(none_posix.contains("# -- not configured --"), true)
  let pwd_posix = @templates.render_posix(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_posix.contains("PWD hooks are not supported"), true)
  // tcsh: prompt aliases __jumbit_hook, pwd hangs off precmd
  let prompt_tcsh = @templates.render_tcsh(Some("j"), HookPrompt, false, false)
  @debug.assert_eq(prompt_tcsh.contains("alias __jumbit_hook"), true)
  let pwd_tcsh = @templates.render_tcsh(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_tcsh.contains("alias precmd"), true)
  // powershell: none prints not configured, prompt defines __jumbit_hook
  let none_powershell = @templates.render_powershell(
    None,
    HookNone,
    false,
    false,
  )
  @debug.assert_eq(none_powershell.contains("# -- not configured --"), true)
  let hook_powershell = @templates.render_powershell(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(
    hook_powershell.contains("function global:__jumbit_hook"),
    true,
  )
  // xonsh: none prints not configured; prompt/pwd hang off the events decorator
  let none_xonsh = @templates.render_xonsh(None, HookNone, false, false)
  @debug.assert_eq(none_xonsh.contains("# -- not configured --"), true)
  let prompt_xonsh = @templates.render_xonsh(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(prompt_xonsh.contains("on_post_prompt"), true)
  let pwd_xonsh = @templates.render_xonsh(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_xonsh.contains("on_chdir"), true)
  // the hook=prompt/pwd elvish variants hang off before-readline/after-chdir; none prints not configured
  let prompt_elvish = @templates.render_elvish(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(prompt_elvish.contains("edit:before-readline"), true)
  let pwd_elvish = @templates.render_elvish(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_elvish.contains("builtin:after-chdir"), true)
  let none_elvish = @templates.render_elvish(None, HookNone, false, false)
  @debug.assert_eq(none_elvish.contains("# -- not configured --"), true)
  // nushell: prompt hangs off pre_prompt, pwd off env_change.PWD, none prints not configured
  let prompt_nushell = @templates.render_nushell(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(prompt_nushell.contains("hooks.pre_prompt"), true)
  let pwd_nushell = @templates.render_nushell(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_nushell.contains("hooks.env_change.PWD"), true)
  let none_nushell = @templates.render_nushell(None, HookNone, false, false)
  @debug.assert_eq(none_nushell.contains("# -- not configured --"), true)
  // posix: none prints not configured; the pwd hook is unsupported (an alternative is printed); prompt hangs off PS1
  let none_posix = @templates.render_posix(None, HookNone, false, false)
  @debug.assert_eq(none_posix.contains("# -- not configured --"), true)
  let pwd_posix = @templates.render_posix(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_posix.contains("PWD hooks are not supported"), true)
  let prompt_posix = @templates.render_posix(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(prompt_posix.contains("__jumbit_hook"), true)
  // powershell: none prints not configured; both prompt and pwd define __jumbit_hook
  let none_powershell = @templates.render_powershell(
    None,
    HookNone,
    false,
    false,
  )
  @debug.assert_eq(none_powershell.contains("# -- not configured --"), true)
  let hook_powershell = @templates.render_powershell(
    Some("j"),
    HookPrompt,
    false,
    false,
  )
  @debug.assert_eq(
    hook_powershell.contains("function global:__jumbit_hook"),
    true,
  )
}

///|
test "template matrix: the echo switch controls echoing after cd" {
  let echo_on = @templates.render_bash(Some("j"), HookNone, true, false)
  @debug.assert_eq(
    echo_on.contains("builtin cd -- \"$@\" && __jumbit_pwd"),
    true,
  )
  let echo_off = @templates.render_bash(Some("j"), HookNone, false, false)
  @debug.assert_eq(echo_off.contains("&& __jumbit_pwd"), false)
}

///|
test "template matrix: resolve_symlinks switches pwd -P/-L" {
  let resolved = @templates.render_bash(Some("j"), HookNone, false, true)
  @debug.assert_eq(resolved.contains("pwd -P"), true)
  @debug.assert_eq(resolved.contains("pwd -L"), false)
  let follow = @templates.render_bash(Some("j"), HookNone, false, false)
  @debug.assert_eq(follow.contains("pwd -L"), true)
}

///|
test "template matrix: the --cmd=cd loop guard (fish only)" {
  let fish_cd = @templates.render_fish(Some("cd"), HookPwd, false, false)
  @debug.assert_eq(fish_cd.contains("__jumbit_loop"), true)
  // bash/zsh call \builtin cd directly, so there is no loop by construction
  let bash_cd = @templates.render_bash(Some("cd"), HookPwd, false, false)
  @debug.assert_eq(bash_cd.contains("function cd() {"), true)
  @debug.assert_eq(bash_cd.contains("\\builtin cd --"), true)
}
