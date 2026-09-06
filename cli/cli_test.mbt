// 子命令解析测试

///|
fn query_opts(
  keywords? : Array[String] = [],
  all? : Bool = false,
  list? : Bool = false,
  score? : Bool = false,
  exclude? : String? = None,
) -> @cli.QueryOptions {
  { keywords, all, list, score, exclude, }
}

///|
test "parse：add/query 收集参数" {
  @debug.assert_eq(@cli.parse(["add", "/a", "/b"]), @cli.Add(["/a", "/b"]))
  @debug.assert_eq(@cli.parse(["query"]), @cli.Query(query_opts()))
  @debug.assert_eq(
    @cli.parse(["query", "foo", "bar"]),
    @cli.Query(query_opts(keywords=["foo", "bar"])),
  )
}

///|
test "parse：query 四个 flag" {
  @debug.assert_eq(
    @cli.parse(["query", "--list"]),
    @cli.Query(query_opts(list=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--score", "--all"]),
    @cli.Query(query_opts(score=true, all=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--exclude", "/tmp/x", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some("/tmp/x"))),
  )
  // flag 与关键词混排
  @debug.assert_eq(
    @cli.parse(["query", "kw", "--list"]),
    @cli.Query(query_opts(keywords=["kw"], list=true)),
  )
}

///|
test "parse：未知 flag 与缺值归 Unknown" {
  @debug.assert_eq(@cli.parse(["query", "--bogus"]), @cli.Unknown("--bogus"))
  @debug.assert_eq(
    @cli.parse(["query", "--exclude"]),
    @cli.Unknown("--exclude 缺少路径参数"),
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
test "parse：add 的 -- 被剥离，其后路径原样保留" {
  @debug.assert_eq(
    @cli.parse(["add", "--", "-weird-dir"]),
    @cli.Add(["-weird-dir"]),
  )
  // 多个 -- 只有首个是分隔符
  @debug.assert_eq(
    @cli.parse(["add", "--", "--also-literal"]),
    @cli.Add(["--also-literal"]),
  )
  @debug.assert_eq(@cli.parse(["add", "x", "--", "--"]), @cli.Add(["x", "--"]))
}

///|
test "parse：query 的 -- 结束 flag 解析" {
  // -- 之后的 --list 是关键词不是 flag
  @debug.assert_eq(
    @cli.parse(["query", "--", "--list"]),
    @cli.Query(query_opts(keywords=["--list"])),
  )
  @debug.assert_eq(
    @cli.parse(["query", "kw", "--", "-dash"]),
    @cli.Query(query_opts(keywords=["kw", "-dash"])),
  )
}
