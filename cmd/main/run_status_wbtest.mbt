///|
test "render_status_human：标签列与 --check 追加行（字节面）" {
  let r : DbStatus = {
    data_file: "/home/you/.local/share/jumbit/db.txt",
    file_size: 13854848,
    format: Some("plaintext"),
    entries: 266618,
    notes: 12,
    maxage: 10000.0,
    existing: None,
  }
  let lines = render_status_human(r)
  @debug.assert_eq(lines.length(), 6)
  @debug.assert_eq(
    lines[0],
    "数据文件      /home/you/.local/share/jumbit/db.txt",
  )
  @debug.assert_eq(lines[1], "文件大小      13854848 字节")
  @debug.assert_eq(lines[2], "格式          plaintext")
  @debug.assert_eq(lines[4], "标注          12")
  @debug.assert_eq(lines[5], "老化阈值      10000")
  // 无库：版本位为 -
  let empty : DbStatus = {
    data_file: "/tmp/nodir/db.txt",
    file_size: 0,
    format: None,
    entries: 0,
    notes: 0,
    maxage: 10000.0,
    existing: None,
  }
  @debug.assert_eq(render_status_human(empty)[2], "格式          -")
  // --check：追加「存在」行
  let checked = { ..r, existing: Some(210000), }
  let lines2 = render_status_human(checked)
  @debug.assert_eq(lines2.length(), 7)
  @debug.assert_eq(lines2[6], "存在          210000/266618")
}

///|
test "render_status_json：键序固定、existing 仅 --check 出现、路径转义" {
  let r : DbStatus = {
    data_file: "/home/you/.local/share/jumbit/db.txt",
    file_size: 13854848,
    format: Some("plaintext"),
    entries: 266618,
    notes: 12,
    maxage: 10000.0,
    existing: None,
  }
  @debug.assert_eq(
    render_status_json(r),
    "{\"data_file\":\"/home/you/.local/share/jumbit/db.txt\",\"file_size\":13854848,\"format\":\"plaintext\",\"entries\":266618,\"notes\":12,\"maxage\":10000}",
  )
  // 无库：format 出 null
  let empty = { ..r, file_size: 0, format: None, entries: 0, notes: 0, }
  assert_true(render_status_json(empty).contains("\"format\":null"))
  // --check：尾部追加 existing
  let checked = { ..r, existing: Some(210000), }
  assert_true(render_status_json(checked).contains(",\"existing\":210000}"))
  // 路径经 json_escape（引号转义验证）
  let weird = { ..r, data_file: "/tmp/a\"b/db.txt", }
  assert_true(
    render_status_json(weird).contains("data_file\":\"/tmp/a\\\"b/db.txt"),
  )
}

///|
async test "status：空库 / 有库 / 损坏库 / --check 的退出码与 stderr 面" {
  let data = make_test_dir("status-data")
  let errs0 : Array[String] = []
  // 空库（无 db.zo）：0
  @debug.assert_eq(run(["status"], env_with(data), errs0), 0)
  @debug.assert_eq(errs0.length(), 0)
  // 建库：add 真目录 + describe 标注 → status 0
  let dir1 = make_test_dir("status-entry")
  let errs1 : Array[String] = []
  @debug.assert_eq(run(["add", dir1], env_with(data), errs1), 0)
  @debug.assert_eq(
    run(["describe", dir1, "--note", "后端"], env_with(data), errs1),
    0,
  )
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["status"], env_with(data), errs2), 0)
  @debug.assert_eq(errs2.length(), 0)
  // --json 与 --check 退出码 0
  @debug.assert_eq(run(["status", "--json"], env_with(data), errs2), 0)
  @debug.assert_eq(run(["status", "--check"], env_with(data), errs2), 0)
  // 损坏库 → 1 + stderr
  @platform.write_atomic(data + "/db.txt", b"garbage-not-a-db")
  let errs3 : Array[String] = []
  @debug.assert_eq(run(["status"], env_with(data), errs3), 1)
  @debug.assert_eq(errs3.length(), 1)
  assert_true(errs3[0].has_prefix("数据文件损坏: "))
  // 用法错误 → 2（未知 flag）
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["status", "--nope"], env_with(data), errs4), 2)
  cleanup_test_dir(data)
  cleanup_test_dir(dir1)
}

///|
async test "status：db.txt 不可读 → 无法读取数据文件 + exit 1（Repr 不再外泄）" {
  let data = make_test_dir("status-noread")
  let target = make_test_dir("status-noread-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @afs.chmod(data + "/db.txt", 0o000)
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["status"], env_with(data), errs2), 1)
  @debug.assert_eq(
    errs2[0],
    "无法读取数据文件: Permission denied (os error 13)",
  )
  @afs.chmod(data + "/db.txt", 0o644)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
