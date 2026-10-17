///|
async test "describe: set / show / clear / not recorded / newline rejected" {
  let data = make_test_dir("desc-data")
  let target = make_test_dir("desc-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // set
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
  // after clearing, showing again -> no annotation, exit code 1
  @debug.assert_eq(
    run(["describe", target, "--note", ""], env_with(data), errs),
    0,
  )
  @debug.assert_eq(run(["describe", target], env_with(data), errs), 1)
  // an unrecorded path
  @debug.assert_eq(
    run(["describe", "/not-in-db", "--note", "x"], env_with(data), errs),
    1,
  )
  // the parse layer rejects a newline (exit code 2, nothing written)
  @debug.assert_eq(
    run(["describe", target, "--note", "多\n行"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "a failed notes.tsv read does not block the main load (pinning the best-effort promise)" {
  let data = make_test_dir("notes-ro")
  let target = make_test_dir("notes-ro-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // notes.tsv is made a directory: attach_notes\'s read_file catch arm fires, and the main load must still succeed.
  // load is called directly to pin the load surface (the CLI path is unsuitable: a query sort always dirties, so the
  // final save\'s notes.tsv write to a directory must fail -> exit 1, which is write-surface semantics and unrelated
  // to this tolerance promise)
  @afs.remove(data + "/notes.tsv")
  @afs.mkdir(data + "/notes.tsv", recursive=false, allow_exist=false) catch {
    e => fail("mkdir failed: \{e}")
  }
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) =>
      fail("a failed notes.tsv read must not block the load: \{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, target)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
