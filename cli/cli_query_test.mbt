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
test "parse：query --json 与 --interactive 互斥" {
  @debug.assert_eq(
    @cli.parse(["query", "--json", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], json=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--interactive"]),
    @cli.Invalid("--json 与 --interactive 互斥"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--interactive", "--json"]),
    @cli.Invalid("--json 与 --interactive 互斥"),
  )
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

///|
test "parse：query --fuzzy" {
  @debug.assert_eq(
    @cli.parse(["query", "--fuzzy", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], fuzzy=true)),
  )
  // 与 --json 可组合（agent 通道：模糊结果带 matched_by=fuzzy）
  @debug.assert_eq(
    @cli.parse(["query", "--fuzzy", "--json", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], fuzzy=true, json=true)),
  )
}

///|
test "parse：query --limit 合法值与覆盖语义" {
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "3"]),
    @cli.Query(query_opts(list=true, limit=Some(3))),
  )
  // 重复出现后者覆盖
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit", "1", "--limit", "2"]),
    @cli.Query(query_opts(json=true, limit=Some(2))),
  )
  // --list --json 组合下 limit 合法；0 合法
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--json", "--limit", "0"]),
    @cli.Query(query_opts(list=true, json=true, limit=Some(0))),
  )
}

///|
test "parse：query --limit 非法值与缺值 → Invalid" {
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit", "abc"]),
    @cli.Invalid("--limit 需要非负整数参数: abc"),
  )
  // 负数/浮点/前导 +（parse_uint64 拒 +，与 import la 同源）/超 Int 上限
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "-1"]),
    @cli.Invalid("--limit 需要非负整数参数: -1"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "1.5"]),
    @cli.Invalid("--limit 需要非负整数参数: 1.5"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "+2"]),
    @cli.Invalid("--limit 需要非负整数参数: +2"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "9999999999"]),
    @cli.Invalid("--limit 需要非负整数参数: 9999999999"),
  )
  // 缺值
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit"]),
    @cli.Invalid("--limit 缺少非负整数参数"),
  )
}

///|
test "parse：query --limit 组合限制与错误优先级" {
  // 裸 query（单结果路）/ --interactive 与 limit 组合 → Invalid
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "2"]),
    @cli.Invalid("--limit 仅在 --list/--json/--tsv 下生效"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--interactive", "--limit", "2"]),
    @cli.Invalid("--limit 仅在 --list/--json/--tsv 下生效"),
  )
  // 未知 flag 优先于组合校验（bad 优先惯例）
  @debug.assert_eq(
    @cli.parse(["query", "--bogus", "--limit", "2"]),
    @cli.Unknown("--bogus"),
  )
  // 值非法优先于组合校验（invalid 在组合检查前返回）
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "abc"]),
    @cli.Invalid("--limit 需要非负整数参数: abc"),
  )
}

///|
test "parse：query --tsv 互斥与 --list 优先先例" {
  // 与 --json/--interactive 两两互斥（顺序无关）
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--json"]),
    @cli.Invalid("--tsv 与 --json 互斥"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--tsv"]),
    @cli.Invalid("--tsv 与 --json 互斥"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--interactive"]),
    @cli.Invalid("--tsv 与 --interactive 互斥"),
  )
  // --list --tsv：--list 胜出、--tsv 被忽略（沿用 --list --json 先例，不校验）
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--tsv"]),
    @cli.Query(query_opts(list=true, tsv=true)),
  )
  // --tsv 单独使用合法；--limit 与 --tsv 组合合法
  @debug.assert_eq(
    @cli.parse(["query", "--tsv"]),
    @cli.Query(query_opts(tsv=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--limit", "1"]),
    @cli.Query(query_opts(tsv=true, limit=Some(1))),
  )
  // limit 合法集消息随 --tsv 扩展
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "2"]),
    @cli.Invalid("--limit 仅在 --list/--json/--tsv 下生效"),
  )
}
