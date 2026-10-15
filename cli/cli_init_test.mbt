///|
test "parse: init defaults (cmd=j, hook=pwd, matching upstream default_value)" {
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
test "parse: init --cmd/--hook/--no-cmd override the defaults" {
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
  // flags interleaved
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
test "parse: init usage errors go Unknown" {
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
test "parse: init flags and the shell interleave freely (matching clap intermix)" {
  fn expect(shell : String, cmd : String) -> @cli.Command {
    @cli.Init({ shell, cmd: Some(cmd), hook: @tpl.HookPwd, no_cmd: false, })
  }
  // a flag before the positional (this repo used to report an unsupported shell; upstream clap allows it)
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
  // a flag after the positional (pinning the existing behaviour)
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd=zz"]),
    expect("bash", "zz"),
  )
  // `--` escapes: everything after it is a positional
  @debug.assert_eq(@cli.parse(["init", "--", "bash"]), expect("bash", "j"))
  // a second non-flag token reports an unexpected argument
  @debug.assert_eq(
    @cli.parse(["init", "bash", "zsh"]),
    @cli.Invalid("unexpected argument 'zsh'"),
  )
  // flags but no shell -> a missing shell
  @debug.assert_eq(
    @cli.parse(["init", "--cmd", "zz"]),
    @cli.Invalid(
      "missing required argument '<SHELL>'\n  [possible values: bash, elvish, fish, nushell, posix, powershell, tcsh, xonsh]",
    ),
  )
}
