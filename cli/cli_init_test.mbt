///|
test "parse：init 默认值（cmd=j、hook=pwd，对齐上游 default_value）" {
  @debug.assert_eq(
    @cli.parse(["init", "bash"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("j"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["init", "zsh"]),
    @cli.Init({
      shell: "zsh",
      cmd: Some("j"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
}

///|
test "parse：init --cmd/--hook/--no-cmd 覆盖默认" {
  @debug.assert_eq(
    @cli.parse(["init", "fish", "--cmd", "z"]),
    @cli.Init({
      shell: "fish",
      cmd: Some("z"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook", "prompt"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("j"),
      hook: @tpl.HookPrompt,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--no-cmd"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("j"),
      hook: @tpl.HookPwd,
      no_cmd: true,
    }),
  )
  // flag 混排
  @debug.assert_eq(
    @cli.parse(["init", "zsh", "--cmd", "cd", "--hook", "none"]),
    @cli.Init({
      shell: "zsh",
      cmd: Some("cd"),
      hook: @tpl.HookNone,
      no_cmd: false,
    }),
  )
}

///|
test "parse：init 用法错误归 Unknown" {
  @debug.assert_eq(
    @cli.parse(["init"]),
    @cli.Invalid(
      "missing required argument '<SHELL>'\n  [possible values: bash, elvish, fish, nushell, posix, powershell, tcsh, xonsh]",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "csh"]),
    @cli.Invalid(
      "invalid value 'csh' for '<SHELL>'\n  [possible values: bash, elvish, fish, nushell, posix, powershell, tcsh, xonsh]",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd"]),
    @cli.Invalid("a value is required for '--cmd <C>' but none was supplied"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook"]),
    @cli.Invalid(
      "a value is required for '--hook <HOOK>' but none was supplied",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook", "cron"]),
    @cli.Invalid(
      "invalid value 'cron' for '--hook <HOOK>'\n  [possible values: pwd, prompt, none]",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--bogus"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
}

///|
test "parse：init flag 与 shell 任意穿插（对齐 clap intermix）" {
  fn expect(shell : String, cmd : String) -> @cli.Command {
    @cli.Init({ shell, cmd: Some(cmd), hook: @tpl.HookPwd, no_cmd: false, })
  }
  // flag 在 positional 前（本仓旧版报「不支持的 shell: --cmd=zz」，上游 clap 合法）
  @debug.assert_eq(
    @cli.parse(["init", "--cmd", "zz", "bash"]),
    expect("bash", "zz"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "--cmd=zz", "bash"]),
    expect("bash", "zz"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "--hook", "prompt", "--no-cmd", "zsh"]),
    @cli.Init({
      shell: "zsh",
      cmd: Some("j"),
      hook: @tpl.HookPrompt,
      no_cmd: true,
    }),
  )
  // flag 在 positional 后（既有行为回归锁定）
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd=zz"]),
    expect("bash", "zz"),
  )
  // `--` 转义：其后 token 一律 positional
  @debug.assert_eq(@cli.parse(["init", "--", "bash"]), expect("bash", "j"))
  // 第二个非 flag token 报意外参数
  @debug.assert_eq(
    @cli.parse(["init", "bash", "zsh"]),
    @cli.Invalid("unexpected argument 'zsh'"),
  )
  // 只有 flag 没有 shell → 缺 shell
  @debug.assert_eq(
    @cli.parse(["init", "--cmd", "zz"]),
    @cli.Invalid(
      "missing required argument '<SHELL>'\n  [possible values: bash, elvish, fish, nushell, posix, powershell, tcsh, xonsh]",
    ),
  )
}
