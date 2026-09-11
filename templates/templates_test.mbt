// 模板参数矩阵测试：3 shell × cmd(2) × hook(3) × echo(2) × resolve_symlinks(2)

///|
fn render_all() -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let shells = ["bash", "zsh", "fish", "elvish"]
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
              _ => "" // 不可达：shells 数组仅三种
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
test "模板矩阵：24 变体 × 4 shell 全部非空且无 zoxide 残留" {
  let all = render_all()
  @debug.assert_eq(all.length(), 96)
  for pair in all {
    let src = pair.1
    @debug.assert_eq(src.length() > 100, true)
    @debug.assert_eq(src.contains("zoxide"), false)
    @debug.assert_eq(src.contains("_ZO_"), false)
    @debug.assert_eq(src.contains("__zoxide_"), false)
  }
}

///|
test "模板矩阵：--no-cmd 不定义 j 命令并输出 not configured" {
  for pair in render_all() {
    let src = pair.1
    if pair.0.contains("nocmd=true") {
      // cmd=None 变体：不定义 j/ji 命令，输出 not configured 占位
      let defines_j = src.contains("function j(") ||
        src.contains("alias j=") ||
        src.contains("edit:add-var j~")
      if defines_j {
        fail("no-cmd 变体定义了 j 命令: \{pair.0}")
      }
      @debug.assert_eq(src.contains("# -- not configured --"), true)
    } else if src.contains("# -- not configured --") {
      // fish/elvish 语义：hook=none 时 hook 段输出 not configured（与 cmd 无关，对齐上游）
      let none_not_configured = pair.0.contains("hook=HookNone") &&
        (pair.0.contains("fish") || pair.0.contains("elvish"))
      if !none_not_configured {
        fail("有命令的变体却输出 not configured: \{pair.0}")
      }
    }
  }
}

///|
test "模板矩阵：hook=pwd/prompt 生成对应钩子，none 不生成" {
  for pair in render_all() {
    let src = pair.1
    // elvish 无 __jumbit_hook 函数（钩子内联在 init 体中，下方单独断言）
    if pair.0.contains("HookPrompt") && !pair.0.contains("elvish") {
      @debug.assert_eq(src.contains("__jumbit_hook"), true)
    }
  }
  // hook=none 的 bash 变体：__jumbit_hook 函数体不存在定义
  let none_bash = @templates.render_bash(None, HookNone, false, false)
  @debug.assert_eq(none_bash.contains("function __jumbit_hook"), false)
  // hook=pwd 的 zsh 变体挂 chpwd_functions
  let pwd_zsh = @templates.render_zsh(Some("j"), HookPwd, false, false)
  @debug.assert_eq(pwd_zsh.contains("chpwd_functions+=(__jumbit_hook)"), true)
  // hook=prompt 的 fish 变体挂 fish_prompt 事件
  let prompt_fish = @templates.render_fish(Some("j"), HookPrompt, false, false)
  @debug.assert_eq(prompt_fish.contains("--on-event fish_prompt"), true)
  // hook=prompt/pwd 的 elvish 变体挂 before-readline/after-chdir；none 输出 not configured
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
}

///|
test "模板矩阵：echo 开关控制 cd 后回显" {
  let echo_on = @templates.render_bash(Some("j"), HookNone, true, false)
  @debug.assert_eq(
    echo_on.contains("builtin cd -- \"$@\" && __jumbit_pwd"),
    true,
  )
  let echo_off = @templates.render_bash(Some("j"), HookNone, false, false)
  @debug.assert_eq(echo_off.contains("&& __jumbit_pwd"), false)
}

///|
test "模板矩阵：resolve_symlinks 切换 pwd -P/-L" {
  let resolved = @templates.render_bash(Some("j"), HookNone, false, true)
  @debug.assert_eq(resolved.contains("pwd -P"), true)
  @debug.assert_eq(resolved.contains("pwd -L"), false)
  let follow = @templates.render_bash(Some("j"), HookNone, false, false)
  @debug.assert_eq(follow.contains("pwd -L"), true)
}

///|
test "模板矩阵：--cmd=cd 循环防护（fish 专属 guard）" {
  let fish_cd = @templates.render_fish(Some("cd"), HookPwd, false, false)
  @debug.assert_eq(fish_cd.contains("__jumbit_loop"), true)
  // bash/zsh 用 \builtin cd 直调，天然无循环
  let bash_cd = @templates.render_bash(Some("cd"), HookPwd, false, false)
  @debug.assert_eq(bash_cd.contains("function cd() {"), true)
  @debug.assert_eq(bash_cd.contains("\\builtin cd --"), true)
}
