// 端到端测试：经 run() 全链路（真实 FS，_JB_DATA_DIR 注入临时目录，stderr 消息可断言）

///|
/// 递归清理测试目录（rmdir 失败静默：断言失败场景下残留可接受）
async fn cleanup_test_dir(dir : String) -> Unit {
  @afs.rmdir(dir, recursive=true) catch {
    err => ignore(err)
  }
}

///|
/// 测试临时根目录：平台 temp（Windows TEMP/TMP、UNIX TMPDIR）回落 /tmp；
/// 硬编码 /tmp 在 Windows 会落 C:\tmp 触发 mkdir EEXIST 上游问题
/// （moonbitlang/async recursive mkdir 非幂等，probe run 36044327191）
fn test_temp_root() -> String {
  for key in ["TEMP", "TMP", "TMPDIR"] {
    match @env.get_env_var(key) {
      Some(v) => return v
      None => ()
    }
  }
  "/tmp"
}

///|
async fn make_test_dir(prefix : String) -> String {
  // rand_name 不可见（platform 私有），用毫秒 + exists 重试保证并发测试不撞名
  for _attempt = 0 {
    let dir = "\{test_temp_root()}/jumbit-e2e-\{@async.now()}-\{prefix}-\{_attempt}"
    if !@afs.exists(dir) {
      // 非递归：temp 根父目录恒存在；recursive=true 在 Windows 对已存在
      // 组件报 EEXIST（async 上游 bug，probe run 36064860009 全量复现）
      @afs.mkdir(dir)
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
  @debug.assert_eq(@afs.exists(data + "/db.txt"), true)
  @debug.assert_eq(errs.length(), 0)
  @debug.assert_eq(run(["query"], env_with(data), errs), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
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
test "finish_interactive：fzf 结果映射表（上游探针矩阵 2026-09-13 实测）" {
  // 选中：剥 7 字符得分前缀后原样输出（含 fzf 尾换行，不追加），exit 0
  let o1 : Array[String] = []
  let e1 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Ok("  40.0\t/picked\n"), false, e1, o1),
    0,
  )
  @debug.assert_eq(o1, ["/picked\n"])
  @debug.assert_eq(e1.length(), 0)
  // --score：整行输出
  let o2 : Array[String] = []
  let e2 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("  40.0\t/picked\n"), true, e2, o2), 0)
  @debug.assert_eq(o2, ["  40.0\t/picked\n"])
  @debug.assert_eq(e2.length(), 0)
  // len==7：上游 get(7..) = Some("")，空串原样输出 exit 0
  let o3 : Array[String] = []
  let e3 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("1234567"), false, e3, o3), 0)
  @debug.assert_eq(o3, [""])
  @debug.assert_eq(e3.length(), 0)
  // len<7：上游错误路，无输出
  let o4 : Array[String] = []
  let e4 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("abc\n"), false, e4, o4), 1)
  @debug.assert_eq(o4.length(), 0)
  @debug.assert_eq(e4[0], "could not read selection from fzf")
  // NotFound
  let o5 : Array[String] = []
  let e5 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.NotFound), false, e5, o5),
    1,
  )
  @debug.assert_eq(e5[0], "could not find fzf, is it installed?")
  @debug.assert_eq(o5.length(), 0)
  // NoMatch：静默 exit 1（与上游的差异，README 注明）
  let o6 : Array[String] = []
  let e6 : Array[String] = []
  @debug.assert_eq(finish_interactive(Err(@platform.NoMatch), false, e6, o6), 1)
  @debug.assert_eq(e6.length(), 0)
  @debug.assert_eq(o6.length(), 0)
  // fzf 自身错误族
  let o7 : Array[String] = []
  let e7 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.ReturnedAnError), false, e7, o7),
    1,
  )
  @debug.assert_eq(e7[0], "fzf returned an error")
  let o8 : Array[String] = []
  let e8 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.Terminated), false, e8, o8),
    1,
  )
  @debug.assert_eq(e8[0], "fzf was terminated")
  let o9 : Array[String] = []
  let e9 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.UnknownExit(42)), false, e9, o9),
    1,
  )
  @debug.assert_eq(e9[0], "fzf returned an unknown error")
  // 用户中断：静默透传 130
  let o10 : Array[String] = []
  let e10 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.Interrupted), false, e10, o10),
    130,
  )
  @debug.assert_eq(e10.length(), 0)
  @debug.assert_eq(o10.length(), 0)
}

///|
async test "等号形式 --flag=value 端到端（clap 双形态对齐）" {
  let data = make_test_dir("eq-data")
  let target = make_test_dir("eq-target")
  let errs : Array[String] = []
  // init --cmd= （README 记载的写法，此前实际被拒 exit 2）
  @debug.assert_eq(run(["init", "bash", "--cmd=zj"], env_with(data), errs), 0)
  // add --score= / describe --note=
  @debug.assert_eq(run(["add", "--score=2.5", target], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["describe", target, "--note=后端"], env_with(data), errs),
    0,
  )
  // query --exclude= / --limit=
  @debug.assert_eq(
    run(["query", "--all", "--list", "--limit=1"], env_with(data), errs),
    0,
  )
  @debug.assert_eq(
    run(
      ["query", "--all", "--list", "--exclude=/nonexistent-x"],
      env_with(data),
      errs,
    ),
    0,
  )
  // 值非法 → Invalid 退出码 2
  @debug.assert_eq(
    run(["query", "--list", "--limit=x"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
#cfg(not(platform="windows"))
// // Windows 门控：只读目录依赖 chmod 权限位（Windows 无效），待平台化
async test "save 失败：数据目录不可写 → 清晰文案 exit 1（Repr 不再外泄）" {
  let data = make_test_dir("save-ro")
  let target = make_test_dir("save-ro-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @afs.chmod(data, 0o555)
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs2), 1)
  @debug.assert_eq(
    errs2[0],
    "保存数据库失败: 读写失败: Permission denied (os error 13)",
  )
  @afs.chmod(data, 0o755)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
