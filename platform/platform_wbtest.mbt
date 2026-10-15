// Real-filesystem tests for the atomic write and the store (async tests)

///|

///|
/// The tests\' temporary root: the platform temp (Windows TEMP/TMP, UNIX TMPDIR) falling back to /tmp;
/// a hardcoded /tmp would land on C:\tmp under Windows and trigger the upstream mkdir EEXIST problem
/// (moonbitlang/async\'s recursive mkdir is not idempotent, probe run 36044327191)
fn test_temp_root() -> String {
  // strip the trailing slash: macOS TMPDIR ends in /, and joining would produce a // double slash, which resolve_path
  // normalizes away, breaking the exact exclude comparison and the shape assertions (proved on macOS CI)
  for key in ["TEMP", "TMP", "TMPDIR"] {
    match @env.get_env_var(key) {
      Some(v) => {
        let mut s = v
        while s.has_suffix("/") && s.length() > 1 {
          s = s[0:s.length() - 1].to_owned()
        }
        if s != "" {
          return s
        }
      }
      None => ()
    }
  }
  "/tmp"
}

///|
async fn make_tmp_dir() -> String {
  // the EEXIST retry covers leftover cross-process state and extreme name collisions (the same family as [#11]: an occasional
  //  collision of temporary stubs shows up on CI as a setup-phase throw); in-process uniqueness comes from the global random source
  for attempt = 0 {
    let dir = "\{test_temp_root()}/jumbit-test-\{@async.now()}-\{rand_name()}"
    // non-recursive: the temp root\'s parent always exists; recursive=true under Windows reports EEXIST for an
    // existing component (an async upstream bug, fully reproduced in probe run 36064860009)
    @afs.mkdir(dir) catch {
      e => if attempt >= 2 { raise e } else { continue attempt + 1 }
    }
    break dir
  }
}

///|
async test "atomic_write: consistent write, overwrite, no tmp residue" {
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
#cfg(not(platform="windows"))
// the read-only directory is made with chmod 0o555 (Windows has no permission bits)
async test "atomic_write: a read-only directory errors with no residue" {
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
async test "store: load an empty database -> save -> reload consistently" {
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
async test "store: an unmodified save produces no file" {
  let dir = make_tmp_dir()
  let store = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  match store.save() {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  // upstream semantics: an empty, unmodified database -> no db.zo is created, only the directory
  @debug.assert_eq(@afs.exists(dir + "/db.zo"), false)
}

///|
async test "store: a corrupt database file reports a Codec error" {
  let dir = make_tmp_dir()
  write_atomic(dir + "/db.zo", b"garbage-not-a-db")
  match load(dir) {
    Err(Codec(_)) => ()
    other => fail("\{Repr(other)}")
  }
}

///|
async test "read_import_lines: split by line, strip \\r, blank lines keep their line number" {
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  write_atomic(path, b"/a|1|100\n\n/b|2|200\r\n/c|3|300")
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  // a blank line (line 2) keeps its slot, so line numbers stay consecutive (matching upstream\'s reads)
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
async test "read_import_lines: the last line arrives without a trailing newline, and bad UTF-8 marks only that line" {
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
  // the wording matches upstream\'s chained Display of str::from_utf8 + anyhow (probed against zoxide 0.10.0)
  @debug.assert_eq(
    records[1].result,
    Err("invalid utf-8: invalid utf-8 sequence of 1 bytes from index 0"),
  )
  @afs.rmdir(dir, recursive=true)
}

///|
async test "read_import_lines: the case-by-case bad-UTF-8 wording matches std\'s location semantics" {
  // every expected value was probed byte for byte against real zoxide 0.10.0 (2026-09-09)
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  write_atomic(
    path,
    // a bad first byte / a bad second byte of two / a bad E0 range / an ED surrogate / a bad F4 range -> 1 byte;
    // a bad third byte of three -> 2 bytes; a bad fourth byte of four -> 3 bytes; the non-ASCII case is the valid control;
    // a trailing C3 becomes the end of the slice once \r is stripped -> incomplete
     b"/a|1.5|100\xff\n/b|\xc3cd|100\n/c|\xe0\x80\x80|100\n/d|\xed\xa0\x80|100\n/e|\xf4\x90\x80\x80|100\n/f|\xe0\xa0\x41|100\n/g|\xf0\x9f\x92\x41|100\n/h|\xe4\xb8\xad|1.5|100\n/i|1.5|100\xc3\r\n",
  )
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  let expect = fn(idx : Int32, msg : String) -> Unit raise {
    match records[idx].result {
      Err(m) => @debug.assert_eq(m, msg)
      Ok(_) => fail("line \{idx + 1} should report a bad row")
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
async test "read_import_lines: a missing file reports could not read" {
  match read_import_lines("/nonexistent-import-file-xyz") {
    Err(msg) => assert_true(msg.has_prefix("jumbit: could not read "))
    Ok(_) => fail("expected error")
  }
}

///|
async test "records_from_process: NUL splitting + raw stderr passthrough" {
  // printf\'s \0 emits a NUL; stderr comes from echo >&2
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
async test "records_from_process: a missing command reports a readable error" {
  match records_from_process("definitely-not-a-real-cmd-xyz", []) {
    Err(msg) =>
      @debug.assert_eq(
        msg, "jumbit: failed to run `definitely-not-a-real-cmd-xyz`; is it installed and on PATH?",
      )
    Ok(_) => fail("expected error")
  }
}

///|
test "map_fzf_exit: upstream\'s wait exit-code table (measured with the fake-fzf probe matrix 2026-09-13)" {
  @debug.assert_eq(map_fzf_exit(0), None)
  @debug.assert_eq(map_fzf_exit(1), Some(NoMatch))
  @debug.assert_eq(map_fzf_exit(2), Some(ReturnedAnError))
  @debug.assert_eq(map_fzf_exit(130), Some(Interrupted))
  // killed by a signal: @process wait returns -signal
  @debug.assert_eq(map_fzf_exit(-9), Some(Terminated))
  // 128..=254: the terminated family
  @debug.assert_eq(map_fzf_exit(128), Some(Terminated))
  @debug.assert_eq(map_fzf_exit(200), Some(Terminated))
  @debug.assert_eq(map_fzf_exit(254), Some(Terminated))
  // 3..=127 and 255: the unknown-error family
  @debug.assert_eq(map_fzf_exit(3), Some(UnknownExit(3)))
  @debug.assert_eq(map_fzf_exit(42), Some(UnknownExit(42)))
  @debug.assert_eq(map_fzf_exit(127), Some(UnknownExit(127)))
  @debug.assert_eq(map_fzf_exit(255), Some(UnknownExit(255)))
}

///|
/// Two candidates: ranks 1 and 2 with last_accessed=now -> the x4 score bucket -> "   4.0" / "   8.0"
fn fzf_hits() -> Array[@core.Dir] {
  [
    { path: "/a", rank: 1.0, last_accessed: 1000L, note: None, },
    { path: "/b", rank: 2.0, last_accessed: 1000L, note: None, },
  ]
}

///|
#cfg(not(platform="windows"))
// cfg-gated: consumed only by the Windows-gated tests (see the notes at each test)
/// Fake-fzf scaffolding: the fzf itself is a write-once wrapper (which sources a same-directory fzf-body),
/// and each case rewrites only the body -- the wrapper is never rewritten and the body is never exec\'d, which
/// structurally avoids the ETXTBSY race of rewriting a file that is being exec\'d
async fn make_fake_fzf(bindir : String) -> String {
  let fake = bindir + "/fzf"
  write_atomic(
    fake,
    @utf8.encode("#!/bin/sh\n. \"$(dirname \"$0\")/fzf-body\"\n"),
  )
  @afs.chmod(fake, 0o755)
  fake
}

///|
#cfg(not(platform="windows"))
async fn write_fake_fzf_body(bindir : String, body : String) -> Unit {
  write_atomic(bindir + "/fzf-body", @utf8.encode(body))
}

///|
#cfg(not(platform="windows"))
/// The single entry for fzf_select_with calls expected to succeed: [#11] an occasional fork-pressure spike on the CI runner
/// makes spawn/path resolution throw momentarily, which the fzf side uniformly maps to NotFound; one retry clears a transient,
/// while a deterministic defect fails both times and stays red (only NotFound is tolerated; any other error is red as is)
async fn fzf_select_expect_ok(
  program : String,
  hits : Array[@core.Dir],
  now : Int64,
  fzf_opts : String?,
  get : (String) -> String?,
) -> String {
  for attempt = 0 {
    match fzf_select_with(program, hits, now, fzf_opts, get) {
      Ok(out) => break out
      Err(NotFound) if attempt == 0 => continue attempt + 1
      Err(e) => fail("\{Repr(e)}")
    }
  }
}

///|
#cfg(not(platform="windows"))
// the fake-fzf stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "fzf_select: the selection is passed through as stdout, candidates fed as score\\tpath\\0" {
  let bindir = make_tmp_dir()
  let fake = make_fake_fzf(bindir)
  let dump = bindir + "/stdin-dump"
  write_fake_fzf_body(bindir, "cat > \{dump}\nprintf '  40.0\\t/picked\\n'\n")
  let out = fzf_select_expect_ok(fake, fzf_hits(), 1000L, None, env_none)
  @debug.assert_eq(out, "  40.0\t/picked\n")
  // the candidate format is pinned: a 6.1f score + \t + path + NUL, in hits order
  let dumped = @afs.read_file(dump).text()
  @debug.assert_eq(dumped, "   4.0\t/a\u{0000}   8.0\t/b\u{0000}")
  @afs.rmdir(bindir, recursive=true)
}

///|
#cfg(not(platform="windows"))
// the fake-fzf stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "fzf_select: FZF_DEFAULT_OPTS is injected only when fzf_opts is given" {
  let hits = fzf_hits()
  // Some -> injected through extra_env
  let bindir = make_tmp_dir()
  let fake = make_fake_fzf(bindir)
  let dump = bindir + "/opts-dump"
  write_fake_fzf_body(
    bindir,
    "printf '%s' \"$FZF_DEFAULT_OPTS\" > \{dump}\nprintf '  40.0\\t/picked\\n'\n",
  )
  let _ = fzf_select_expect_ok(fake, hits, 1000L, Some("--border"), env_none)
  @debug.assert_eq(@afs.read_file(dump).text(), "--border")
  @afs.rmdir(bindir, recursive=true)
  // None -> not injected, and the fzf side sees the variable as unset
  let bindir2 = make_tmp_dir()
  let fake2 = make_fake_fzf(bindir2)
  let dump2 = bindir2 + "/opts-dump"
  write_fake_fzf_body(
    bindir2,
    "printf '%s' \"${FZF_DEFAULT_OPTS-UNSET}\" > \{dump2}\nprintf '  40.0\\t/picked\\n'\n",
  )
  let _ = fzf_select_expect_ok(fake2, hits, 1000L, None, env_none)
  @debug.assert_eq(@afs.read_file(dump2).text(), "UNSET")
  @afs.rmdir(bindir2, recursive=true)
}

///|
#cfg(not(platform="windows"))
// the fake-fzf stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "fzf_select: the exit-code matrix -> FzfError (upstream\'s probe table)" {
  let bindir = make_tmp_dir()
  let fake = make_fake_fzf(bindir)
  let expect_err = async fn(body : String, expected : FzfError) -> Unit {
    write_fake_fzf_body(bindir, body)
    match fzf_select_with(fake, fzf_hits(), 1000L, None, env_none) {
      Err(e) =>
        match (e, expected) {
          (NoMatch, NoMatch) => ()
          (ReturnedAnError, ReturnedAnError) => ()
          (Interrupted, Interrupted) => ()
          (Terminated, Terminated) => ()
          (UnknownExit(a), UnknownExit(b)) => @debug.assert_eq(a, b)
          (l, r) => fail("expect \{Repr(r)} got \{Repr(l)}")
        }
      Ok(s) => fail("expected error, got \{s}")
    }
  }
  expect_err("exit 1\n", NoMatch)
  expect_err("exit 2\n", ReturnedAnError)
  expect_err("exit 130\n", Interrupted)
  expect_err("exit 42\n", UnknownExit(42))
  expect_err("exit 255\n", UnknownExit(255))
  expect_err("exit 200\n", Terminated)
  expect_err("kill -9 $$\n", Terminated)
  @afs.rmdir(bindir, recursive=true)
}

///|
async test "fzf_select: a spawn failure (missing / not executable) -> NotFound" {
  let bindir = make_tmp_dir()
  // the path does not exist
  match
    fzf_select_with(bindir + "/no-such-fzf", fzf_hits(), 1000L, None, env_none) {
    Err(NotFound) => ()
    other => fail("\{Repr(other)}")
  }
  // not executable (upstream distinguishes "could not launch fzf", but the binding exposes no error class,
  // so it merges into NotFound -- noted in the README; the file name carries noexec to mark the spawn debug point)
  let fake = bindir + "/fzf-noexec"
  write_atomic(fake, @utf8.encode("#!/bin/sh\nprintf 'x\\n'\n"))
  match fzf_select_with(fake, fzf_hits(), 1000L, None, env_none) {
    Err(NotFound) => ()
    other => fail("\{Repr(other)}")
  }
  @afs.rmdir(bindir, recursive=true)
}

///|
async test "for_each_import_line: line-for-line identical to read_import_lines (line numbers / \r stripping / blank-line slots / bad-row location)" {
  let dir = make_tmp_dir()
  let path = dir + "/zdata"
  // covers: trailing \r stripping, blank lines keeping their numbers, a last line without a trailing newline, and in-line bad UTF-8 marking only its line
  write_atomic(path, b"/a|1|100\n\n/b|2|200\r\n\xff\xfe\n/c|3|300")
  let via_cb : Array[(Int32, Result[String, String])] = []
  match for_each_import_line(path, fn(n, r) { via_cb.push((n, r)) }) {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  let records = match read_import_lines(path) {
    Ok(r) => r
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(via_cb.length(), records.length())
  for i, (n, r) in via_cb {
    @debug.assert_eq(n, records[i].line_num)
    @debug.assert_eq(r, records[i].result)
  }
  // a spot check of the line semantics (matching split_records): blank-line slots and the bad-row Err wording
  @debug.assert_eq(via_cb.length(), 5)
  @debug.assert_eq(via_cb[1].1, Ok(""))
  match via_cb[3].1 {
    Err(msg) => assert_true(msg.has_prefix("invalid utf-8: "))
    Ok(_) => fail("line 4 should report bad UTF-8")
  }
  @debug.assert_eq(via_cb[4].1, Ok("/c|3|300"))
  @afs.rmdir(dir, recursive=true)
}

///|
async test "for_each_import_line: a missing file reports could not read (same wording as read_import_lines)" {
  let via_cb = for_each_import_line("/nonexistent-import-file-xyz", fn(_, _) {
    ()
  })
  match via_cb {
    Err(msg) => assert_true(msg.has_prefix("jumbit: could not read "))
    Ok(_) => fail("expected error")
  }
  let via_array = read_import_lines("/nonexistent-import-file-xyz")
  match (via_cb, via_array) {
    (Err(a), Err(b)) => @debug.assert_eq(a, b)
    _ => fail("the two paths should report the same error shape")
  }
}

///|
#cfg(not(platform="windows"))
// cfg-gated: consumed only by the Windows-gated tests (see the notes at each test)
/// The environment-read stub: only PATH is injectable (the test surface for bare-name resolution pre-checks)
fn env_path_only(path : String) -> (String) -> String? {
  fn(key : String) -> String? { if key == "PATH" { Some(path) } else { None } }
}

///|
fn env_none(key : String) -> String? {
  ignore(key)
  None
}

///|
#cfg(not(platform="windows"))
// the fake-fzf stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "fzf_select: a bare name resolves along PATH, skipping a non-executable candidate and taking the first executable one" {
  let noexec_dir = make_tmp_dir()
  let good_dir = make_tmp_dir()
  // the first candidate: same name but not executable (measured in a blackbox: the old code handed such a PATH hit straight
  // to spawn, whose exec failure went down the wait exit-code path and reported "fzf returned an error",
  // contradicting the rule that a spawn failure is uniformly NotFound)
  write_atomic(noexec_dir + "/fzf", @utf8.encode("#!/bin/sh\nprintf 'x\\n'\n"))
  // the second candidate: an executable fake fzf returning a fixed selection
  let _fake = make_fake_fzf(good_dir)
  write_fake_fzf_body(good_dir, "printf '  40.0\\t/picked\\n'\n")
  let get = env_path_only("\{noexec_dir}:\{good_dir}")
  let picked = fzf_select_expect_ok("fzf", fzf_hits(), 1000L, None, get)
  @debug.assert_eq(picked, "  40.0\t/picked\n")
  @afs.rmdir(noexec_dir, recursive=true)
  @afs.rmdir(good_dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
// the fake-fzf stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "fzf_select: a bare name with no executable candidate on PATH -> NotFound" {
  let noexec_dir = make_tmp_dir()
  // a non-executable regular file
  write_atomic(noexec_dir + "/fzf", @utf8.encode("#!/bin/sh\nexit 0\n"))
  let get1 = env_path_only(noexec_dir)
  match fzf_select_with("fzf", fzf_hits(), 1000L, None, get1) {
    Err(NotFound) => ()
    other => fail("\{Repr(other)}")
  }
  // a directory is not an executable target even with an x bit (can_execute lets directories through, so kind must exclude them)
  @afs.remove(noexec_dir + "/fzf")
  @afs.mkdir(noexec_dir + "/fzf", recursive=true)
  @afs.chmod(noexec_dir + "/fzf", 0o755)
  match fzf_select_with("fzf", fzf_hits(), 1000L, None, get1) {
    Err(NotFound) => ()
    other => fail("\{Repr(other)}")
  }
  @afs.rmdir(noexec_dir, recursive=true)
}

///|
test "codec_error_message: wording frozen through a real decode product (the pub enum is read-only and never constructed directly)" {
  let corrupted = match @core.decode(b"") {
    Err(e) => e
    Ok(_) => fail("unexpected ok")
  }
  @debug.assert_eq(Codec(corrupted).message(), "unparseable data")
  let bad_version = match @core.decode(@utf8.encode("garbage-not-a-db")) {
    Err(e) => e
    Ok(_) => fail("unexpected ok")
  }
  @debug.assert_eq(
    Codec(bad_version).message(),
    "unsupported format version: 1651663207",
  )
}

///|

///|
/// EEXIST\'s real platform values: POSIX CRT 17 / Win32 ERROR_ALREADY_EXISTS 183
/// (the predicates and the fs layer report Win32 codes under Windows, so a constructed value must be platform-real;
/// see docs/handoff-os-error-predicate.md for the correction)
#cfg(platform="windows")
fn test_eexist_errno() -> Int32 {
  183
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn test_eexist_errno() -> Int32 {
  17
}

///|
test "os_error_message: an ENOENT phrase + (os error N) suffix, with a Repr fallback for non-OSError" {
  @debug.assert_eq(
    os_error_message(@os_error.OSError(2, context="test")),
    "No such file or directory (os error 2)",
  )
  let eexist = test_eexist_errno()
  @debug.assert_eq(
    os_error_message(@os_error.OSError(eexist, context="test")),
    "File exists (os error \{eexist})",
  )
}

///|
/// [#2] regression: after loading a legacy database unmodified, save must not migrate it to disk (a read path never dirties).
/// Red verification: before the fix, load(legacy) marked dirty -> save wrote db.txt
async test "store: an unmodified legacy save does not migrate" {
  let dir = make_tmp_dir()
  let db = @core.Database::new()
  db.add_update("/legacy/a", 2.0, 100L)
  write_atomic(dir + "/db.zo", @core.encode(db.all()))
  let store = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  match store.save() {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(@afs.exists(dir + "/db.txt"), false)
  @debug.assert_eq(@afs.exists(dir + "/db.zo"), true)
  // a real write (add_update dirties) -> save migrates to plaintext with the content preserved
  store.database().add_update("/legacy/b", 1.0, 200L)
  match store.save() {
    Ok(_) => ()
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(@afs.exists(dir + "/db.txt"), true)
  let reloaded = match load(dir) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(reloaded.database().all().length(), 2)
  @afs.chmod(dir, 0o755)
  @afs.rmdir(dir, recursive=true) catch {
    err => ignore(err)
  }
}

///|
#cfg(not(platform="windows"))
/// Pinning the fzf_select_expect_ok contract: the first PATH lookup returns an empty directory (resolution fails ->
/// NotFound), the second returns the stub directory; calls==2 pins that exactly one retry turns it green. Both failing stays red
/// by construction through guard(attempt == 0); the behaviour was probed 2026-10-15 (both early lookups fail, and a scenario
/// that could have succeeded on the third lookup fails red at the second, leaving the third chance unconsumed)
async test "fzf_select_expect_ok: after one injected resolution failure a retry turns it green" {
  let bindir = make_tmp_dir()
  let _fake = make_fake_fzf(bindir)
  write_fake_fzf_body(bindir, "printf '  40.0\\t/picked\\n'\n")
  let empty = make_tmp_dir()
  let calls = [0]
  let get : (String) -> String? = fn(_key) {
    calls[0] = calls[0] + 1
    if calls[0] == 1 {
      Some(empty)
    } else {
      Some(bindir)
    }
  }
  let out = fzf_select_expect_ok("fzf", fzf_hits(), 1000L, None, get)
  @debug.assert_eq(out, "  40.0\t/picked\n")
  @debug.assert_eq(calls[0], 2)
  @afs.rmdir(bindir, recursive=true)
  @afs.rmdir(empty, recursive=true)
}
