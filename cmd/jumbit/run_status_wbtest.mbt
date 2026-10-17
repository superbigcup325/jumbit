///|
test "render_status_human: the label column and the --check appended line (byte surface)" {
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
    "data file      /home/you/.local/share/jumbit/db.txt",
  )
  @debug.assert_eq(lines[1], "file size      13854848 bytes")
  @debug.assert_eq(lines[2], "format         plaintext")
  @debug.assert_eq(lines[4], "notes          12")
  @debug.assert_eq(lines[5], "aging threshold 10000")
  // no database: the version slot is -
  let empty : DbStatus = {
    data_file: "/tmp/nodir/db.txt",
    file_size: 0,
    format: None,
    entries: 0,
    notes: 0,
    maxage: 10000.0,
    existing: None,
  }
  @debug.assert_eq(render_status_human(empty)[2], "format         -")
  // --check: the existing line is appended
  let checked = { ..r, existing: Some(210000), }
  let lines2 = render_status_human(checked)
  @debug.assert_eq(lines2.length(), 7)
  @debug.assert_eq(lines2[6], "existing        210000/266618")
}

///|
test "render_status_json: fixed key order, existing only under --check, path escaping" {
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
  // no database: format is null
  let empty = { ..r, file_size: 0, format: None, entries: 0, notes: 0, }
  assert_true(render_status_json(empty).contains("\"format\":null"))
  // --check: existing is appended at the end
  let checked = { ..r, existing: Some(210000), }
  assert_true(render_status_json(checked).contains(",\"existing\":210000}"))
  // the path goes through json_escape (verifying quote escaping)
  let weird = { ..r, data_file: "/tmp/a\"b/db.txt", }
  assert_true(
    render_status_json(weird).contains("data_file\":\"/tmp/a\\\"b/db.txt"),
  )
}

///|
async test "status: the exit codes and stderr surface for an empty / populated / corrupt database and --check" {
  let data = make_test_dir("status-data")
  let errs0 : Array[String] = []
  // an empty database (no db.zo): 0
  @debug.assert_eq(run(["status"], env_with(data), errs0), 0)
  @debug.assert_eq(errs0.length(), 0)
  // build a database: add a real directory + describe a note -> status 0
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
  // --json and --check exit 0
  @debug.assert_eq(run(["status", "--json"], env_with(data), errs2), 0)
  @debug.assert_eq(run(["status", "--check"], env_with(data), errs2), 0)
  // a corrupt database -> 1 plus stderr
  @platform.write_atomic(data + "/db.txt", b"garbage-not-a-db")
  let errs3 : Array[String] = []
  @debug.assert_eq(run(["status"], env_with(data), errs3), 1)
  @debug.assert_eq(errs3.length(), 1)
  assert_true(errs3[0].has_prefix("jumbit: corrupted data file: "))
  // a usage error -> 2 (an unknown flag)
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["status", "--nope"], env_with(data), errs4), 2)
  cleanup_test_dir(data)
  cleanup_test_dir(dir1)
}

///|
#cfg(not(platform="windows"))
// // Windows-gated: the unreadable construction relies on a chmod permission bit (a no-op on Windows), pending platform work
async test "status: an unreadable db.txt -> cannot read the data file plus exit 1 (no Repr leak)" {
  let data = make_test_dir("status-noread")
  let target = make_test_dir("status-noread-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @afs.chmod(data + "/db.txt", 0o000)
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["status"], env_with(data), errs2), 1)
  @debug.assert_eq(
    errs2[0],
    "jumbit: could not read data file: Permission denied (os error 13)",
  )
  @afs.chmod(data + "/db.txt", 0o644)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
