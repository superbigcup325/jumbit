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
    @cli.Unknown(
      "init: 缺少 shell 参数（bash/zsh/fish/elvish/nushell/posix/powershell/tcsh/xonsh）",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "csh"]),
    @cli.Unknown(
      "init: 不支持的 shell: csh（当前支持 bash/zsh/fish/elvish/nushell/posix/powershell/tcsh/xonsh）",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd"]),
    @cli.Unknown("--cmd 缺少命令名参数"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook"]),
    @cli.Unknown("--hook 缺少参数"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook", "cron"]),
    @cli.Unknown("--hook 仅支持 pwd/prompt/none: cron"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--bogus"]),
    @cli.Unknown("--bogus"),
  )
}
