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
    @cli.Unknown(
      "init: 缺少 shell 参数（bash/zsh/fish/elvish/nushell/posix/powershell/tcsh）",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "csh"]),
    @cli.Unknown(
      "init: 不支持的 shell: csh（当前支持 bash/zsh/fish/elvish/nushell/posix/powershell/tcsh）",
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
test "parse：describe 基本/显示模式/清除" {
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "后端项目"]),
    @cli.Describe({ path: "/a", note: Some("后端项目"), }),
  )
  // 无 --note 为显示模式
  @debug.assert_eq(
    @cli.parse(["describe", "/a"]),
    @cli.Describe({ path: "/a", note: None, }),
  )
  // 空串即清除
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", ""]),
    @cli.Describe({ path: "/a", note: Some(""), }),
  )
}

///|
test "parse：describe 坏参族" {
  @debug.assert_eq(
    @cli.parse(["describe"]),
    @cli.Unknown("describe: 缺少路径参数"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "--note"]),
    @cli.Unknown("--note 缺少标注文本"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "多\n行"]),
    @cli.Invalid("describe: 标注不能包含换行"),
  )
  @debug.assert_eq(@cli.parse(["describe", "/a", "/b"]), @cli.Unknown("/b"))
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--bogus"]),
    @cli.Unknown("--bogus"),
  )
}

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
