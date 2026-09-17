///|
test "parse：export --agents 与坏参" {
  @debug.assert_eq(
    @cli.parse(["export", "--agents"]),
    @cli.Export({ agents: true, }),
  )
  @debug.assert_eq(
    @cli.parse(["export"]),
    @cli.Unknown("export: 缺少 --agents"),
  )
  @debug.assert_eq(@cli.parse(["export", "--bogus"]), @cli.Unknown("--bogus"))
  @debug.assert_eq(
    @cli.parse(["export", "--agents", "--extra"]),
    @cli.Unknown("--extra"),
  )
}
