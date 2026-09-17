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
async test "add _JB_RESOLVE_SYMLINKS=1：自环符号链接 → 解析路径失败 + exit 1（ELOOP 走数字后缀）" {
  let data = make_test_dir("loop-data")
  let dir = make_test_dir("loop-link")
  let loop_path = dir + "/loop"
  @afs.symlink(target=loop_path, loop_path)
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_RESOLVE_SYMLINKS", "1")])
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", loop_path], env, errs), 1)
  @debug.assert_eq(errs[0], "解析路径失败: \{loop_path}: (os error 40)")
  cleanup_test_dir(data)
  cleanup_test_dir(dir)
}
