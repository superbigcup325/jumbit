// 端到端测试：经 run() 全链路（真实 FS，_JB_DATA_DIR 注入临时目录，stderr 消息可断言）

///|
/// 递归清理测试目录（rmdir 失败静默：断言失败场景下残留可接受）
async fn cleanup_test_dir(dir : String) -> Unit {
  @afs.rmdir(dir, recursive=true) catch {
    err => ignore(err)
  }
}

///|
async fn make_test_dir(prefix : String) -> String {
  // rand_name 不可见（platform 私有），用毫秒 + exists 重试保证并发测试不撞名
  for _attempt = 0 {
    let dir = "/tmp/jumbit-e2e-\{@async.now()}-\{prefix}-\{_attempt}"
    if !@afs.exists(dir) {
      @afs.mkdir(dir, recursive=true)
      break dir
    } else {
      continue _attempt + 1
    }
  }
}

///|
fn env_map(pairs : Array[(String, String)]) -> (String) -> String? {
  fn(key : String) -> String? {
    for pair in pairs {
      if pair.0 == key {
        return Some(pair.1)
      }
    }
    None
  }
}

///|
fn env_with(data_dir : String) -> (String) -> String? {
  env_map([("_JB_DATA_DIR", data_dir)])
}

///|
test "env_with：命中与未命中" {
  @debug.assert_eq(env_with("/d")("_JB_DATA_DIR"), Some("/d"))
  @debug.assert_eq(env_with("/d")("HOME"), None)
}

///|
test "echo_enabled：仅 _JB_ECHO=1 生效" {
  @debug.assert_eq(echo_enabled(env_map([("_JB_ECHO", "1")])), true)
  @debug.assert_eq(echo_enabled(env_map([("_JB_ECHO", "0")])), false)
  @debug.assert_eq(echo_enabled(env_map([])), false)
}

///|
async test "add → query 全链路" {
  let data = make_test_dir("data")
  let target = make_test_dir("target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), true)
  @debug.assert_eq(errs.length(), 0)
  @debug.assert_eq(run(["query"], env_with(data), errs), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "空库 query → 退出码 1 + 提示语，不 panic" {
  let data = make_test_dir("empty")
  let errs : Array[String] = []
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add 的 -- 分隔符：负号开头路径可正常记录" {
  let data = make_test_dir("dash-data")
  let target = make_test_dir("-dash-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "--", target], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "add 非目录 → 退出码 1 且报错文案" {
  let data = make_test_dir("nondir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add 含换行路径 → 跳过且不建库文件" {
  let data = make_test_dir("nl")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/a\nb"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), false)
  cleanup_test_dir(data)
}

///|
async test "未知命令与缺参数 → 退出码 2" {
  let data = make_test_dir("unknown")
  let errs : Array[String] = []
  @debug.assert_eq(run(["frobnicate"], env_with(data), errs), 2)
  @debug.assert_eq(run(["add"], env_with(data), errs), 2)
  @debug.assert_eq(errs.length(), 3)
  cleanup_test_dir(data)
}

///|
async test "help → 退出码 0" {
  let data = make_test_dir("help")
  let errs : Array[String] = []
  @debug.assert_eq(run(["help"], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  cleanup_test_dir(data)
}

///|
async test "两次 add 同目录 → 数据库仍单条目" {
  let data = make_test_dir("dedup")
  let target = make_test_dir("tgt")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 2.0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
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
async test "add：_JB_ECHO=1 时回显且退出码不受影响" {
  let data = make_test_dir("echo-data")
  let target = make_test_dir("echo-target")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["add", target],
      env_map([("_JB_DATA_DIR", data), ("_JB_ECHO", "1")]),
      errs,
    ),
    0,
  )
  @debug.assert_eq(errs.length(), 0)
  // 目录里仍只一条记录，echo 只是输出副作用
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
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
async test "_JB_EXCLUDE_DIRS 非法 glob → 退出码 2" {
  let data = make_test_dir("badglob")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_EXCLUDE_DIRS", "[unclosed")])
  @debug.assert_eq(run(["query"], env, errs), 2)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}
