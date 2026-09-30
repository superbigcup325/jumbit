///|
async test "describe：设置/显示/清除/未记录/换行拒绝" {
  let data = make_test_dir("desc-data")
  let target = make_test_dir("desc-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // 设置
  @debug.assert_eq(
    run(
      ["describe", target, "--note", "MoonBit 重写的 zoxide"],
      env_with(data),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(
    store.database().all()[0].note,
    Some("MoonBit 重写的 zoxide"),
  )
  // 清除后再显示 → 无标注退出码 1
  @debug.assert_eq(
    run(["describe", target, "--note", ""], env_with(data), errs),
    0,
  )
  @debug.assert_eq(run(["describe", target], env_with(data), errs), 1)
  // 未记录路径
  @debug.assert_eq(
    run(["describe", "/not-in-db", "--note", "x"], env_with(data), errs),
    1,
  )
  // 参数层换行拒绝（退出码 2，不落盘）
  @debug.assert_eq(
    run(["describe", target, "--note", "多\n行"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "notes.tsv 读失败不阻塞主库加载（best-effort 容错承诺锁定）" {
  let data = make_test_dir("notes-ro")
  let target = make_test_dir("notes-ro-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // notes.tsv 造成目录形态：attach_notes 的 read_file catch 归零臂被触发，
  // 主库加载须照常成功。直调 load 锁加载面（CLI 路不合适：query 排序恒
  // 标脏 → 结尾 save 的 notes.tsv 写入对目录必败 → exit 1，那是写面语义，
  // 与本容错承诺无关）
  @afs.remove(data + "/notes.tsv")
  @afs.mkdir(data + "/notes.tsv", recursive=false, allow_exist=false) catch {
    e => fail("mkdir 失败: \{e}")
  }
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("notes.tsv 读失败不得阻塞加载: \{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, target)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
