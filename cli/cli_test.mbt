// 子命令解析测试

///|
test "parse：add/query 收集剩余参数" {
  @debug.assert_eq(@cli.parse(["add", "/a", "/b"]), @cli.Add(["/a", "/b"]))
  @debug.assert_eq(@cli.parse(["query"]), @cli.Query([]))
  @debug.assert_eq(
    @cli.parse(["query", "foo", "bar"]),
    @cli.Query(["foo", "bar"]),
  )
}

///|
test "parse：help 三种写法" {
  @debug.assert_eq(@cli.parse(["help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["--help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["-h"]), @cli.Help)
  @debug.assert_eq(@cli.parse([]), @cli.Help)
}

///|
test "parse：未知命令回显原名" {
  @debug.assert_eq(@cli.parse(["frobnicate"]), @cli.Unknown("frobnicate"))
  @debug.assert_eq(@cli.parse(["--bogus"]), @cli.Unknown("--bogus"))
}

///|
test "parse：-- 之后的参数原样保留（负号开头路径）" {
  @debug.assert_eq(
    @cli.parse(["add", "--", "-weird-dir"]),
    @cli.Add(["--", "-weird-dir"]),
  )
}
