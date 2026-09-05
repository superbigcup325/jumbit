// 端到端测试：经 run() 全链路（真实 FS，_JB_DATA_DIR 注入临时目录，stderr 消息可断言）

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
fn env_with(data_dir : String) -> (String) -> String? {
  fn(key : String) -> String? {
    if key == "_JB_DATA_DIR" {
      Some(data_dir)
    } else {
      None
    }
  }
}

///|
test "env_with：命中与未命中" {
  @debug.assert_eq(env_with("/d")("_JB_DATA_DIR"), Some("/d"))
  @debug.assert_eq(env_with("/d")("HOME"), None)
}

///|
async test "add → query 全链路" {
  let data = make_test_dir("data")
  let target = make_test_dir("target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), true)
  @debug.assert_eq(run(["query"], env_with(data), errs), 0)
}

///|
async test "空库 query → 退出码 1 + 提示语，不 panic" {
  let data = make_test_dir("empty")
  let errs : Array[String] = []
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
}

///|
async test "add 非目录 → 退出码 1 且报错文案" {
  let data = make_test_dir("nondir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
}

///|
async test "add 含换行路径 → 跳过且不建库文件" {
  let data = make_test_dir("nl")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/a\nb"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), false)
}

///|
async test "未知命令与缺参数 → 退出码 2" {
  let data = make_test_dir("unknown")
  let errs : Array[String] = []
  @debug.assert_eq(run(["frobnicate"], env_with(data), errs), 2)
  @debug.assert_eq(run(["add"], env_with(data), errs), 2)
  @debug.assert_eq(errs.length(), 3)
}

///|
async test "help → 退出码 0" {
  let data = make_test_dir("help")
  let errs : Array[String] = []
  @debug.assert_eq(run(["help"], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
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
}
