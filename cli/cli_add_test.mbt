///|
test "parse: add\'s -- is stripped and what follows is kept as is" {
  @debug.assert_eq(
    @cli.parse(["add", "--", "-weird-dir"]),
    @cli.Add(add_opts(paths=["-weird-dir"])),
  )
  // with several --, only the first is a separator
  @debug.assert_eq(
    @cli.parse(["add", "--", "--also-literal"]),
    @cli.Add(add_opts(paths=["--also-literal"])),
  )
  @debug.assert_eq(
    @cli.parse(["add", "x", "--", "--"]),
    @cli.Add(add_opts(paths=["x", "--"])),
  )
}

///|
test "parse：add --score" {
  @debug.assert_eq(
    @cli.parse(["add", "--score", "2.5", "/a"]),
    @cli.Add(add_opts(paths=["/a"], score=2.5)),
  )
  // a --score after -- is treated as a path
  @debug.assert_eq(
    @cli.parse(["add", "--", "--score", "/a"]),
    @cli.Add(add_opts(paths=["--score", "/a"])),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score", "abc"]),
    @cli.Invalid("invalid value 'abc' for '--score <N>'"),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score"]),
    @cli.Invalid("a value is required for '--score <N>' but none was supplied"),
  )
}
