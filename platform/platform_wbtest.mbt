// 原子写与存取的真实 FS 测试（async test）

///|

///|
async fn make_tmp_dir() -> String {
  let dir = "/tmp/jumbit-test-\{@async.now()}-\{rand_name()}"
  @afs.mkdir(dir, recursive=true)
  dir
}

///|
async test "atomic_write：写入一致、覆盖、无 tmp 残留" {
  let dir = make_tmp_dir()
  let path = dir + "/db.zo"
  write_atomic(path, b"hello-1")
  write_atomic(path, b"hello-2-longer")
  let data = @afs.read_file(path)
  @debug.assert_eq(data.text(), "hello-2-longer")
  let entries = @afs.readdir(dir)
  @debug.assert_eq(entries.length(), 1)
  @debug.assert_eq(entries[0], "db.zo")
}

///|
async test "atomic_write：只读目录报错且无残留" {
  let dir = make_tmp_dir()
  @afs.chmod(dir, 0o555)
  let failed = try {
    write_atomic(dir + "/db.zo", b"x")
    false
  } catch {
    err => {
      ignore(err)
      true
    }
  }
  @debug.assert_eq(failed, true)
  let entries = @afs.readdir(dir)
  @debug.assert_eq(entries.length(), 0)
  @afs.chmod(dir, 0o755)
  @afs.rmdir(dir)
}

///|
async test "store：空库加载 → 保存 → 重载一致" {
  let dir = make_tmp_dir()
  let store = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 0)
  store.database().add_update("/foo", 1.0, 100L)
  match store.save() {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  let reloaded = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(reloaded.database().all().length(), 1)
  @debug.assert_eq(reloaded.database().all()[0].path, "/foo")
  @debug.assert_eq(reloaded.database().all()[0].rank, 1.0)
  @debug.assert_eq(reloaded.database().all()[0].last_accessed, 100L)
}

///|
async test "store：未修改时 save 不产生文件" {
  let dir = make_tmp_dir()
  let store = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  match store.save() {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  // 上游语义：空库且未修改 → 不创建 db.zo，只建目录
  @debug.assert_eq(@afs.exists(dir + "/db.zo"), false)
}

///|
async test "store：损坏的库文件报 Codec 错误" {
  let dir = make_tmp_dir()
  write_atomic(dir + "/db.zo", b"garbage-not-a-db")
  match load(dir) {
    Err(Codec(_)) => ()
    other => fail("\{Repr(other)}")
  }
}

///|
async test "read_import_lines：按行切分、剥 \\r、空行占位计行号" {
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  write_atomic(path, b"/a|1|100\n\n/b|2|200\r\n/c|3|300")
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  // 空行（第 2 行）保留占位，行号连续（对齐上游逐行读取语义）
  @debug.assert_eq(records.length(), 4)
  @debug.assert_eq(records[0].line_num, 1)
  @debug.assert_eq(records[0].result, Ok("/a|1|100"))
  @debug.assert_eq(records[1].line_num, 2)
  @debug.assert_eq(records[1].result, Ok(""))
  @debug.assert_eq(records[2].line_num, 3)
  @debug.assert_eq(records[2].result, Ok("/b|2|200"))
  @debug.assert_eq(records[3].line_num, 4)
  @debug.assert_eq(records[3].result, Ok("/c|3|300"))
  @afs.rmdir(dir, recursive=true)
}

///|
async test "read_import_lines：无尾随换行也能取末行，坏 UTF-8 只标记该行" {
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  write_atomic(path, b"/a|1|100\n\xff\xfe")
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(records.length(), 2)
  @debug.assert_eq(records[0].result, Ok("/a|1|100"))
  @debug.assert_eq(records[1].line_num, 2)
  // 文案对齐上游 str::from_utf8 + anyhow 链式 Display（zoxide 0.10.0 探针实测）
  @debug.assert_eq(
    records[1].result,
    Err("invalid utf-8: invalid utf-8 sequence of 1 bytes from index 0"),
  )
  @afs.rmdir(dir, recursive=true)
}

///|
async test "read_import_lines：坏 UTF-8 逐类文案对齐 std 定位语义" {
  // 各类的期望值均为与真 zoxide 0.10.0 逐字节探针实测（2026-09-09）
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  write_atomic(
    path,
    // 1 起始坏/双字节次字节坏/三字节 E0 域坏/ED 代理区/四字节 F4 域坏 → 1 字节；
    // 三字节第三字节坏 → 2 字节；四字节第四字节坏 → 3 字节；中文为合法对照；
    // 行尾 C3 在剥 \r 后成切片末尾 → incomplete
     b"/a|1.5|100\xff\n/b|\xc3cd|100\n/c|\xe0\x80\x80|100\n/d|\xed\xa0\x80|100\n/e|\xf4\x90\x80\x80|100\n/f|\xe0\xa0\x41|100\n/g|\xf0\x9f\x92\x41|100\n/h|\xe4\xb8\xad|1.5|100\n/i|1.5|100\xc3\r\n",
  )
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  let expect = fn(idx : Int, msg : String) -> Unit raise {
    match records[idx].result {
      Err(m) => @debug.assert_eq(m, msg)
      Ok(_) => fail("行 \{idx + 1} 应报坏行")
    }
  }
  expect(0, "invalid utf-8: invalid utf-8 sequence of 1 bytes from index 10")
  expect(1, "invalid utf-8: invalid utf-8 sequence of 1 bytes from index 3")
  expect(2, "invalid utf-8: invalid utf-8 sequence of 1 bytes from index 3")
  expect(3, "invalid utf-8: invalid utf-8 sequence of 1 bytes from index 3")
  expect(4, "invalid utf-8: invalid utf-8 sequence of 1 bytes from index 3")
  expect(5, "invalid utf-8: invalid utf-8 sequence of 2 bytes from index 3")
  expect(6, "invalid utf-8: invalid utf-8 sequence of 3 bytes from index 3")
  match records[7].result {
    Ok("/h|中|1.5|100") => ()
    other => fail("\{Repr(other)}")
  }
  expect(8, "invalid utf-8: incomplete utf-8 byte sequence from index 10")
  @afs.rmdir(dir, recursive=true)
}

///|
async test "read_import_lines：文件缺失报 could not read" {
  match read_import_lines("/nonexistent-import-file-xyz") {
    Err(msg) => assert_true(msg.has_prefix("could not read "))
    Ok(_) => fail("expected error")
  }
}

///|
async test "records_from_process：NUL 切分 + stderr 原文透传" {
  // printf 的 \0 输出 NUL；stderr 经 echo >&2 产生
  let result = records_from_process("sh", [
    "-c", "printf 'A\\0BB\\0'; echo atuin-err >&2",
  ])
  match result {
    Ok((records, err_text)) => {
      @debug.assert_eq(records.length(), 2)
      @debug.assert_eq(records[0].line_num, 1)
      @debug.assert_eq(records[0].result, Ok("A"))
      @debug.assert_eq(records[1].line_num, 2)
      @debug.assert_eq(records[1].result, Ok("BB"))
      assert_true(err_text.contains("atuin-err"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
async test "records_from_process：命令不存在报可读错误" {
  match records_from_process("definitely-not-a-real-cmd-xyz", []) {
    Err(msg) =>
      @debug.assert_eq(
        msg, "failed to run `definitely-not-a-real-cmd-xyz`; is it installed and on PATH?",
      )
    Ok(_) => fail("expected error")
  }
}
