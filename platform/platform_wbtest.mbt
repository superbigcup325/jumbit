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
