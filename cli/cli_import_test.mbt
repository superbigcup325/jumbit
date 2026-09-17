///|
fn import_opts(plugin~ : String, merge? : Bool = false) -> @cli.ImportOptions {
  { plugin, merge, }
}

///|
test "parse：import 六个插件 + --merge 任意位置" {
  @debug.assert_eq(
    @cli.parse(["import", "z"]),
    @cli.Import(import_opts(plugin="z")),
  )
  for p in ["atuin", "autojump", "fasd", "z", "z.lua", "zsh-z"] {
    @debug.assert_eq(
      @cli.parse(["import", p]),
      @cli.Import(import_opts(plugin=p)),
    )
  }
  @debug.assert_eq(
    @cli.parse(["import", "--merge", "z"]),
    @cli.Import(import_opts(plugin="z", merge=true)),
  )
  @debug.assert_eq(
    @cli.parse(["import", "z", "--merge"]),
    @cli.Import(import_opts(plugin="z", merge=true)),
  )
}

///|
test "parse：import 非法用法归 Unknown" {
  @debug.assert_eq(
    @cli.parse(["import"]),
    @cli.Unknown(
      "import: 缺少插件参数（atuin/autojump/fasd/z/z.lua/zsh-z）",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["import", "bogus"]),
    @cli.Unknown(
      "import: 不支持的插件: bogus（支持 atuin/autojump/fasd/z/z.lua/zsh-z）",
    ),
  )
  @debug.assert_eq(@cli.parse(["import", "z", "extra"]), @cli.Unknown("extra"))
  @debug.assert_eq(@cli.parse(["import", "--bogus"]), @cli.Unknown("--bogus"))
}
