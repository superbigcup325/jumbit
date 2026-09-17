///|
test "parse：add 的 -- 被剥离，其后路径原样保留" {
  @debug.assert_eq(
    @cli.parse(["add", "--", "-weird-dir"]),
    @cli.Add(add_opts(paths=["-weird-dir"])),
  )
  // 多个 -- 只有首个是分隔符
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
  // --score 在 -- 之后按路径处理
  @debug.assert_eq(
    @cli.parse(["add", "--", "--score", "/a"]),
    @cli.Add(add_opts(paths=["--score", "/a"])),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score", "abc"]),
    @cli.Unknown("--score 必须是数字: abc"),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score"]),
    @cli.Unknown("--score 缺少数值参数"),
  )
}
