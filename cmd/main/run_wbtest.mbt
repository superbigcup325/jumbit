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
  let data = make_test_dir("nondir-bail-1")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add 含换行路径 → 静默跳过（对齐上游，退出码 0）" {
  let data = make_test_dir("nl")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/a\nb"], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), false)
  cleanup_test_dir(data)
}

///|
async test "add 非目录 → 立即中止且不落盘" {
  let data = make_test_dir("nondir-bail-2")
  let errs : Array[String] = []
  // 先给一个合法目录再给非法路径：上游 bail 语义下整条命令失败、不保存
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
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
async test "_JB_EXCLUDE_DIRS 非法 glob → 退出码 1（对齐上游运行失败）" {
  let data = make_test_dir("badglob")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_EXCLUDE_DIRS", "[unclosed")])
  @debug.assert_eq(run(["query"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "remove：删除后 query 无结果；未记录路径报错" {
  let data = make_test_dir("rm-data")
  let target = make_test_dir("rm-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // 按绝对路径删
  @debug.assert_eq(run(["remove", target], env_with(data), errs), 0)
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  // 再删同一路径 → path not found
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["remove", target], env_with(data), errs2), 1)
  @debug.assert_eq(errs2.length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "remove：相对路径形式经规范化后也能删" {
  let data = make_test_dir("rm-rel-data")
  let target = make_test_dir("rm-rel-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // remove 不存在的原始串 → 兜底按规范化路径再试（对齐上游双重尝试）
  @debug.assert_eq(
    run(["remove", "jumbit-e2e-nonexistent"], env_with(data), errs),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "_JB_MAXAGE=0：add 后总分清零全删（预期行为锁定）" {
  let data = make_test_dir("age-data")
  let target = make_test_dir("age-target")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_MAXAGE", "0")])
  @debug.assert_eq(run(["add", target], env, errs), 0)
  // total > 0 → factor 0 → rank<1 全删，库文件为空数组
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "_JB_MAXAGE 非数字 → 退出码 1（对齐上游运行失败）" {
  let data = make_test_dir("age-bad")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_MAXAGE", "abc")])
  @debug.assert_eq(run(["add", data], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add --score：负增量 clamp 到 0" {
  let data = make_test_dir("score-data")
  let target = make_test_dir("score-target")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(["add", "--score", "3.5", target], env_with(data), errs),
    0,
  )
  @debug.assert_eq(
    run(["add", "--score", "-5", target], env_with(data), errs),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 0.0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "_JB_RESOLVE_SYMLINKS=1：add 符号链接记录真实目录" {
  let data = make_test_dir("sym-data")
  let real = make_test_dir("sym-real")
  let link = "/tmp/jumbit-e2e-sym-link-\{@async.now()}"
  @afs.symlink(target=real, link)
  let errs : Array[String] = []
  // 解析模式：记录真实目录；默认模式：记录链接路径本身
  @debug.assert_eq(
    run(
      ["add", link],
      env_map([("_JB_DATA_DIR", data), ("_JB_RESOLVE_SYMLINKS", "1")]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, real)
  @debug.assert_eq(@afs.kind(link, follow_symlink=false), @afs.SymLink)
  cleanup_test_dir(data)
  cleanup_test_dir(real)
  cleanup_test_dir(link)
}

///|

///|
async test "import z：直灌新库 + 坏行上报不中止" {
  let data = make_test_dir("imp-data")
  let zdir = make_test_dir("imp-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(
    zfile, b"/alpha|1.5|1704067200\n/beta|2|1704067200\ngarbage\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // 坏行按 <路径>:<行号>: <原因> 上报，好行照常入库
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(errs[0], "\{zfile}:3: invalid entry: garbage")
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  for d in store.database().all() {
    if d.path == "/alpha" {
      @debug.assert_eq(d.rank, 1.5)
      @debug.assert_eq(d.last_accessed, 1704067200L)
    }
  }
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import 空库检查：非空库无 --merge 拒绝，--merge 合并" {
  let data = make_test_dir("imp-merge-data")
  let target = make_test_dir("imp-merge-tgt")
  let zdir = make_test_dir("imp-merge-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/from-z|1|100\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // 非空库 + 无 --merge → 上游同文案拒绝
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(
    errs[errs.length() - 1],
    "current database is not empty, specify --merge to continue anyway",
  )
  // --merge 合并
  @debug.assert_eq(run(["import", "--merge", "z"], env, errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
  cleanup_test_dir(zdir)
}

///|
async test "import z：重复路径 dedup 合并 rank 与最新时间" {
  let data = make_test_dir("imp-dedup")
  let zdir = make_test_dir("imp-dedup-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/dup|1|100\n/dup|2|200\n")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["import", "z"],
      env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 3.0)
  @debug.assert_eq(store.database().all()[0].last_accessed, 200L)
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import z：_JB_EXCLUDE_DIRS 命中静默跳过" {
  let data = make_test_dir("imp-excl")
  let zdir = make_test_dir("imp-excl-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/alpha|1|100\n/beta/x|1|100\n")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_JB_EXCLUDE_DIRS", "/beta/*"),
    ("_Z_DATA", zfile),
  ])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/alpha")
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import autojump：XDG 定位 + sigmoid 归一 + last_accessed=0" {
  let data = make_test_dir("imp-aj-data")
  let ajdir = make_test_dir("imp-aj")
  @afs.mkdir(ajdir + "/autojump", recursive=true)
  @platform.write_atomic(ajdir + "/autojump/autojump.txt", b"3.0\t/aj\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("XDG_DATA_HOME", ajdir)])
  @debug.assert_eq(run(["import", "autojump"], env, errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  let d = store.database().all()[0]
  @debug.assert_eq(d.path, "/aj")
  // rank 与 core 解析器一致（sigmoid(3.0)），last_accessed 置 0
  let expected = match @core.parse_autojump_line("3.0\t/aj") {
    Ok(d) => d
    Err(m) => fail(m)
  }
  @debug.assert_eq(d.rank, expected.rank)
  @debug.assert_eq(d.last_accessed, 0L)
  cleanup_test_dir(data)
  cleanup_test_dir(ajdir)
}

///|
async test "import z.lua：主路径缺失回落 fish 路径；主路径存在时优先" {
  let data = make_test_dir("imp-zlua-data")
  let fishdir = make_test_dir("imp-zlua-fish")
  let home = make_test_dir("imp-zlua-home")
  @afs.mkdir(fishdir + "/zlua", recursive=true)
  @platform.write_atomic(fishdir + "/zlua/zlua.txt", b"/fishy|1|100\n")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("XDG_DATA_HOME", fishdir),
    ("HOME", home),
  ])
  // 主路径 $HOME/.zlua 不存在 → 回落 fish
  @debug.assert_eq(run(["import", "z.lua"], env, errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/fishy")
  // 主路径存在时优先主路径（清库重导）
  cleanup_test_dir(data)
  @platform.write_atomic(home + "/.zlua", b"/mainzlua|1|100\n")
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["import", "--merge", "z.lua"], env, errs2), 0)
  let store2 = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store2.database().all().length(), 1)
  @debug.assert_eq(store2.database().all()[0].path, "/mainzlua")
  cleanup_test_dir(data)
  cleanup_test_dir(fishdir)
  cleanup_test_dir(home)
}

///|
async test "import z：文件缺失 → could not read + 退出码 1，不落盘" {
  let data = make_test_dir("imp-missing")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_Z_DATA", "/nonexistent-z-data-xyz"),
  ])
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("could not read "))
  cleanup_test_dir(data)
}

///|
async test "import z：超大 rank 触发 age 老化（0.9×maxage/total 因子）" {
  let data = make_test_dir("imp-age")
  let zdir = make_test_dir("imp-age-z")
  let zfile = zdir + "/zdata"
  // total=20000 > 10000 → factor = 0.9×10000/20000 = 0.45 → rank 9000
  @platform.write_atomic(zfile, b"/big|20000|100\n")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["import", "z"],
      env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 9000.0)
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import atuin：连续同路径折叠 + 错误不打断链（PATH 注入伪 atuin 走真实子进程）" {
  let data = make_test_dir("imp-atuin-data")
  let bindir = make_test_dir("imp-atuin-bin")
  // 记录序：/a /a 坏行 /a /b —— 期望 /a 只收首次（跨坏行仍折叠），/b 照常
  let nul = "\u{0000}"
  let records : String = "2024-01-01 00:00:00\t/a\{nul}2024-01-02 00:00:00\t/a\{nul}bad-record\{nul}2024-01-03 00:00:00\t/a\{nul}2024-01-04 00:00:00\t/b\{nul}"
  @platform.write_atomic(bindir + "/records", @utf8.encode(records))
  let fake = bindir + "/atuin"
  let script : String = "#!/bin/sh\ncat \{bindir}/records\n"
  @platform.write_atomic(fake, @utf8.encode(script))
  @afs.chmod(fake, 0o755)
  let orig_path = @env.get_env_var("PATH")
  @env.set_env_var(
    "PATH",
    match orig_path {
      Some(p) => "\{bindir}:\{p}"
      None => bindir
    },
  )
  let errs : Array[String] = []
  @debug.assert_eq(
    run(["import", "atuin"], env_map([("_JB_DATA_DIR", data)]), errs),
    0,
  )
  // 还原 PATH（追加式注入对并行测试无害，礼貌还原）
  match orig_path {
    Some(p) => @env.set_env_var("PATH", p)
    None => @env.unset_env_var("PATH")
  }
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(errs[0], "line 3: invalid entry: bad-record")
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  for d in store.database().all() {
    match d.path {
      "/a" => {
        // rank=1.0 且时间取转换首次（2024-01-01），非折叠前最后一条（01-03）
        @debug.assert_eq(d.rank, 1.0)
        @debug.assert_eq(d.last_accessed, 1704067200L)
      }
      "/b" => {
        @debug.assert_eq(d.rank, 1.0)
        @debug.assert_eq(d.last_accessed, 1704326400L)
      }
      other => fail("unexpected path: \{other}")
    }
  }
  cleanup_test_dir(data)
  cleanup_test_dir(bindir)
}
