// 子命令解析测试

///|
fn query_opts(
  keywords? : Array[String] = [],
  all? : Bool = false,
  list? : Bool = false,
  score? : Bool = false,
  exclude? : String? = None,
) -> @cli.QueryOptions {
  { keywords, all, list, score, interactive: false, exclude, }
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

///|
test "parse：remove 收集路径" {
  @debug.assert_eq(
    @cli.parse(["remove", "/a", "/b"]),
    @cli.Remove(["/a", "/b"]),
  )
  @debug.assert_eq(@cli.parse(["remove"]), @cli.Remove([]))
}

///|
test "parse：init 默认值（cmd=j、hook=pwd，对齐上游 default_value）" {
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
test "parse：init --cmd/--hook/--no-cmd 覆盖默认" {
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
  // flag 混排
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
test "parse：init 用法错误归 Unknown" {
  @debug.assert_eq(
    @cli.parse(["init"]),
    @cli.Unknown("init: 缺少 shell 参数（bash/zsh/fish）"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "powershell"]),
    @cli.Unknown(
      "init: 不支持的 shell: powershell（当前支持 bash/zsh/fish）",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd"]),
    @cli.Unknown("--cmd 缺少命令名参数"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook"]),
    @cli.Unknown("--hook 缺少参数"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook", "cron"]),
    @cli.Unknown("--hook 仅支持 pwd/prompt/none: cron"),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--bogus"]),
    @cli.Unknown("--bogus"),
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
