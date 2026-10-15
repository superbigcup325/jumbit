///|
fn import_opts(plugin~ : String, merge~ : Bool = false) -> @cli.ImportOptions {
  { plugin, merge, }
}

///|
test "parse: import\'s six plugins + --merge anywhere" {
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
test "parse: import\'s illegal usages go Unknown" {
  @debug.assert_eq(
    @cli.parse(["import"]),
    @cli.Invalid(
      "missing required argument '<PLUGIN>'\n  [possible values: atuin, autojump, fasd, z, z.lua, zsh-z]",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["import", "bogus"]),
    @cli.Invalid(
      "invalid value 'bogus' for '<PLUGIN>'\n  [possible values: atuin, autojump, fasd, z, z.lua, zsh-z]",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["import", "z", "extra"]),
    @cli.Invalid("unexpected argument 'extra'"),
  )
  @debug.assert_eq(
    @cli.parse(["import", "--bogus"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
}
