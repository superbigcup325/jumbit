// 子命令解析测试

///|
fn query_opts(
  keywords? : Array[String] = [],
  all? : Bool = false,
  list? : Bool = false,
  score? : Bool = false,
  exclude? : String? = None,
  json? : Bool = false,
  fuzzy? : Bool = false,
  limit? : Int? = None,
  tsv? : Bool = false,
) -> @cli.QueryOptions {
  {
    keywords,
    all,
    list,
    score,
    interactive: false,
    exclude,
    json,
    fuzzy,
    limit,
    tsv,
  }
}

///|
fn add_opts(paths~ : Array[String], score? : Double = 1.0) -> @cli.AddOptions {
  { paths, score, }
}

///|
test "parse：add/query 收集参数" {
  @debug.assert_eq(
    @cli.parse(["add", "/a", "/b"]),
    @cli.Add(add_opts(paths=["/a", "/b"])),
  )
  @debug.assert_eq(@cli.parse(["query"]), @cli.Query(query_opts()))
  @debug.assert_eq(
    @cli.parse(["query", "foo", "bar"]),
    @cli.Query(query_opts(keywords=["foo", "bar"])),
  )
}

///|
test "parse：help 三种写法" {
  @debug.assert_eq(@cli.parse(["help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["--help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["-h"]), @cli.Help)
}

///|
test "parse：--version/-V 与无参数用法错误（对齐上游 clap 顶层面）" {
  @debug.assert_eq(@cli.parse(["--version"]), @cli.Version)
  @debug.assert_eq(@cli.parse(["-V"]), @cli.Version)
  // 版本 flag 后随多余参数 → 用法错误（clap unexpected argument）
  @debug.assert_eq(
    @cli.parse(["--version", "x"]),
    @cli.Invalid("意外参数: x"),
  )
  @debug.assert_eq(@cli.parse(["-V", "x"]), @cli.Invalid("意外参数: x"))
  // 无参数 = 用法错误（帮助全文走 stderr、退出码 2，对齐上游）
  @debug.assert_eq(@cli.parse([]), @cli.Usage)
  // 版本 flag 不劫持子命令命名空间：作子命令参数时照常走子命令解析
  @debug.assert_eq(
    @cli.parse(["query", "--version"]),
    @cli.Unknown("--version"),
  )
}

///|
test "parse：未知命令回显原名" {
  @debug.assert_eq(@cli.parse(["frobnicate"]), @cli.Unknown("frobnicate"))
  @debug.assert_eq(@cli.parse(["--bogus"]), @cli.Unknown("--bogus"))
}

///|
test "parse：remove 收集路径" {
  @debug.assert_eq(
    @cli.parse(["remove", "/a", "/b"]),
    @cli.Remove(["/a", "/b"]),
  )
  @debug.assert_eq(@cli.parse(["remove"]), @cli.Remove([]))
}

///|
test "parse：--flag=value 等号形式（对齐上游 clap 双形态）" {
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd=zj"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("zj"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["init", "zsh", "--hook=none"]),
    @cli.Init({
      shell: "zsh",
      cmd: Some("j"),
      hook: @tpl.HookNone,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=/tmp/x", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some("/tmp/x"))),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit=3"]),
    @cli.Query(query_opts(list=true, limit=Some(3))),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score=2.5", "/a"]),
    @cli.Add(add_opts(paths=["/a"], score=2.5)),
  )
  // 负数取值（split_once 只切首个 =）
  @debug.assert_eq(
    @cli.parse(["add", "--score=-1", "/a"]),
    @cli.Add(add_opts(paths=["/a"], score=-1.0)),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note=后端服务"]),
    @cli.Describe({ path: "/a", note: Some("后端服务"), }),
  )
  // 值本身含 =
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=/a=b"]),
    @cli.Query(query_opts(exclude=Some("/a=b"))),
  )
}

///|
test "parse：等号形式边界与原有行为不回退" {
  // 布尔 flag 的等号形式不是带值 flag，报原文归 Unknown（对齐 clap 拒收）
  @debug.assert_eq(@cli.parse(["query", "--list=x"]), @cli.Unknown("--list=x"))
  // 未知 flag 的等号形式报原文
  @debug.assert_eq(
    @cli.parse(["query", "--bogus=1"]),
    @cli.Unknown("--bogus=1"),
  )
  // 空值：--exclude= 收空路径；--cmd= 收空串；--limit= 值非法归 Invalid
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some(""))),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd="]),
    @cli.Init({
      shell: "bash",
      cmd: Some(""),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--limit="]),
    @cli.Invalid("--limit 需要非负整数参数: "),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook="]),
    @cli.Unknown("--hook 仅支持 pwd/prompt/none: "),
  )
  // --= 与 -- 语义不冲突：原样报 Unknown
  @debug.assert_eq(@cli.parse(["add", "--=1"]), @cli.Unknown("--=1"))
  // -- 之后不拆分，等号串按位置参数收录
  @debug.assert_eq(
    @cli.parse(["query", "--", "--limit=3"]),
    @cli.Query(query_opts(keywords=["--limit=3"])),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--", "--score=1", "/a"]),
    @cli.Add(add_opts(paths=["--score=1", "/a"])),
  )
}

///|
test "parse：mcp 无参数；多余参数/flag 归 Unknown" {
  @debug.assert_eq(@cli.parse(["mcp"]), @cli.Mcp)
  @debug.assert_eq(@cli.parse(["mcp", "extra"]), @cli.Unknown("extra"))
  @debug.assert_eq(@cli.parse(["mcp", "--json"]), @cli.Unknown("--json"))
}
