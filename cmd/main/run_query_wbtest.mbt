///|
async test "空库 query → 退出码 1 + 提示语，不 panic" {
  let data = make_test_dir("empty")
  let errs : Array[String] = []
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "query 关键词：命中末组件的目录" {
  let data = make_test_dir("kw-data")
  let foo_dir = make_test_dir("foo-project")
  let bar_dir = make_test_dir("bar-project")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", foo_dir, bar_dir], env_with(data), errs), 0)
  // foo 命中 foo-project（末组件），不命中 bar-project
  @debug.assert_eq(run(["query", "foo"], env_with(data), errs), 0)
  // 无匹配关键词 → 退出码 1 + 提示
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["query", "zzz"], env_with(data), errs2), 1)
  @debug.assert_eq(errs2.length(), 1)
  // 关键词落在首组件（tmp）不满足末组件锚定 → 无匹配
  @debug.assert_eq(run(["query", "tmp"], env_with(data), errs2), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(foo_dir)
  cleanup_test_dir(bar_dir)
}

///|
async test "query --list 与 --score 退出码" {
  let data = make_test_dir("list-data")
  let t1 = make_test_dir("alpha-list")
  let t2 = make_test_dir("beta-list")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", t1, t2], env_with(data), errs), 0)
  @debug.assert_eq(run(["query", "--list"], env_with(data), errs), 0)
  @debug.assert_eq(run(["query", "--list", "--score"], env_with(data), errs), 0)
  @debug.assert_eq(run(["query", "--score", "alpha"], env_with(data), errs), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(t1)
  cleanup_test_dir(t2)
}

///|
#cfg(not(platform="windows"))
// // Windows 门控：exclude 精确比对对混合分隔符敏感（win32 resolve 归一反斜杠 vs TEMP 环境变量原样），Phase-2 语义决策后恢复
async test "query --exclude 精确路径：唯一命中被排除报 only match" {
  let data = make_test_dir("excl-data")
  let only = make_test_dir("only-dir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", only], env_with(data), errs), 0)
  @debug.assert_eq(run(["query", "--exclude", only], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(only)
}

///|
async test "query --all 跳过存在性检查" {
  let data = make_test_dir("all-data")
  let gone = make_test_dir("gone-dir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", gone], env_with(data), errs), 0)
  // 目录被删：默认 exists 检查 → 无匹配；--all → 仍返回
  @afs.rmdir(gone)
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(run(["query", "--all"], env_with(data), errs), 0)
  cleanup_test_dir(data)
}

///|
#cfg(not(platform="windows"))
// // Windows 门控：_JB_EXCLUDE_DIRS 冒号分隔与盘符冒号冲突 + /tmp/*victim* 字面 pattern 锁死 POSIX 形态，Phase-2 语义决策后恢复
async test "_JB_EXCLUDE_DIRS glob 命中懒删除（重载后条目消失）" {
  let data = make_test_dir("glob-data")
  let victim = make_test_dir("victim-dir")
  let keeper = make_test_dir("keeper-dir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", victim, keeper], env_with(data), errs), 0)
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_JB_EXCLUDE_DIRS", "/tmp/*victim*"),
  ])
  @debug.assert_eq(run(["query", "--list"], env, errs), 0)
  // 懒删除已落盘：重载后只剩 keeper
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, keeper)
  cleanup_test_dir(data)
  cleanup_test_dir(victim)
  cleanup_test_dir(keeper)
}

///|
async test "_JB_EXCLUDE_DIRS 非法 glob → 退出码 1（对齐上游运行失败）" {
  let data = make_test_dir("badglob")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_EXCLUDE_DIRS", "[unclosed")])
  @debug.assert_eq(run(["query"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "query --json：--all 可查假路径、miss 退出码 1、--interactive 互斥退出码 2" {
  let data = make_test_dir("json-data")
  let zdir = make_test_dir("json-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(
    zfile, b"/imp-json-alpha|1.0|0\n/imp-json-beta|2.0|0\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // --all 跳过存在性检查：假路径不被懒删除（JSON 字节形状由 json_wbtest 与 smoke 锁定）
  @debug.assert_eq(run(["query", "--json", "--all"], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["query", "--json", "--all", "nosuch"], env_with(data), errs),
    1,
  )
  @debug.assert_eq(
    run(["query", "--json", "--interactive"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "query --fuzzy：精确零命中兜底组件子串（扩展语义，默认行为不变）" {
  let data = make_test_dir("fz-data")
  let zdir = make_test_dir("fz-z")
  let zfile = zdir + "/zdata"
  // 关键词落在非末组件：exact 末组件锚定 miss，fuzzy 兜底
  @platform.write_atomic(zfile, b"/imp-fz/blog/work|1|0\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // 默认语义不变：exact miss → 退出码 1
  @debug.assert_eq(run(["query", "--all", "blog"], env_with(data), errs), 1)
  // --fuzzy 兜底命中
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blog"], env_with(data), errs),
    0,
  )
  // 组件内子串（拼错场景）同样兜底
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blo"], env_with(data), errs),
    0,
  )
  // 多关键词缺一不命中
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blog", "zzz"], env_with(data), errs),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "query --limit：三路截断与 0=空输出（扩展语义）" {
  let data = make_test_dir("lim-data")
  let zdir = make_test_dir("lim-z")
  let zfile = zdir + "/zdata"
  // 三条不同得分：beta 8.0 / mid 4.0×?——la=0 全 ×0.25：2.0→0.5、1.0→0.25
  @platform.write_atomic(
    zfile, b"/imp-lim-alpha|1.0|0\n/imp-lim-beta|2.0|1099511627776\n/imp-lim-mid|4.0|0\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // --list --limit 2：截前两条（排序后），不重排
  @debug.assert_eq(
    run(
      ["query", "--list", "--score", "--all", "--limit", "2"],
      env_with(data),
      errs,
    ),
    0,
  )
  // --json --limit 0：空数组 + 退出码 0（不走空检查错误路）
  @debug.assert_eq(
    run(["query", "--json", "--all", "--limit", "0"], env_with(data), errs),
    0,
  )
  // --limit 大于结果数：全量输出不报错
  @debug.assert_eq(
    run(["query", "--list", "--all", "--limit", "99"], env_with(data), errs),
    0,
  )
  // 裸 query + limit 已被 parse 层拒绝（cli_test 锁定），此处不再覆盖
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
test "take_limit：None 不截断、取排序后前 n 条、0=空、超界取全量" {
  let dir = (p : String, r : Double) => @core.Dir::{
    path: p,
    rank: r,
    last_accessed: 0L,
    note: None,
  }
  // 模拟 remaining：已按得分降序
  let dirs = [dir("/a", 8.0), dir("/b", 1.0), dir("/c", 0.5)]
  @debug.assert_eq(take_limit(dirs, None).length(), 3)
  let two = take_limit(dirs, Some(2))
  @debug.assert_eq(two.length(), 2)
  @debug.assert_eq(two[0].path, "/a")
  @debug.assert_eq(two[1].path, "/b")
  @debug.assert_eq(take_limit(dirs, Some(0)).length(), 0)
  @debug.assert_eq(take_limit(dirs, Some(99)).length(), 3)
}
