// End-to-end tests: the whole chain through run() (a real filesystem, _JB_DATA_DIR pointing at a temp directory, stderr messages assertable)

///|
/// Recursively clean the test directory (an rmdir failure is silent: leftovers are acceptable when an assertion fails)
async fn cleanup_test_dir(dir : String) -> Unit {
  @afs.rmdir(dir, recursive=true) catch {
    err => ignore(err)
  }
}

///|
/// The tests\' temporary root: the platform temp (Windows TEMP/TMP, UNIX TMPDIR) falling back to /tmp;
/// a hardcoded /tmp would land on C:\tmp under Windows and trigger the upstream mkdir EEXIST problem
/// (moonbitlang/async\'s recursive mkdir is not idempotent, probe run 36044327191)
fn test_temp_root() -> String {
  // strip the trailing slash: macOS TMPDIR ends in / and joining would produce a // double slash, which resolve_path
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
async fn make_test_dir(prefix : String) -> String {
  // rand_name is private to platform, so milliseconds plus an exists retry keep parallel tests from colliding on a name
  for _attempt = 0 {
    let dir = "\{test_temp_root()}/jumbit-e2e-\{@async.now()}-\{prefix}-\{_attempt}"
    if !@afs.exists(dir) {
      // non-recursive: the temp root\'s parent always exists; recursive=true under Windows reports EEXIST for an
      // existing component (an async upstream bug, fully reproduced in probe run 36064860009)
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
test "env_with: a hit and a miss" {
  @debug.assert_eq(env_with("/d")("_JB_DATA_DIR"), Some("/d"))
  @debug.assert_eq(env_with("/d")("HOME"), None)
}

///|
test "echo_enabled: only _JB_ECHO=1 takes effect" {
  @debug.assert_eq(echo_enabled(env_map([("_JB_ECHO", "1")])), true)
  @debug.assert_eq(echo_enabled(env_map([("_JB_ECHO", "0")])), false)
  @debug.assert_eq(echo_enabled(env_map([])), false)
}

///|
async test "the full add -> query chain" {
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
async test "an unknown command and a missing argument -> exit code 2" {
  let data = make_test_dir("unknown")
  let errs : Array[String] = []
  @debug.assert_eq(run(["frobnicate"], env_with(data), errs), 2)
  @debug.assert_eq(run(["add"], env_with(data), errs), 2)
  // a missing-argument message is now rendered as Invalid at the parse layer and, like an unknown command, carries the For more information trailer (2 each)
  @debug.assert_eq(errs.length(), 4)
  cleanup_test_dir(data)
}

///|
async test "help -> exit code 0" {
  let data = make_test_dir("help")
  let errs : Array[String] = []
  @debug.assert_eq(run(["help"], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  cleanup_test_dir(data)
}

///|
test "finish_interactive: the fzf result mapping table (measured with the upstream probe matrix 2026-09-13)" {
  // a selection: the 7-character score prefix is stripped and the rest printed as is (including fzf\'s trailing newline, no extra), exit 0
  let o1 : Array[String] = []
  let e1 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Ok("  40.0\t/picked\n"), false, e1, o1),
    0,
  )
  @debug.assert_eq(o1, ["/picked\n"])
  @debug.assert_eq(e1.length(), 0)
  // --score: the whole line is printed
  let o2 : Array[String] = []
  let e2 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("  40.0\t/picked\n"), true, e2, o2), 0)
  @debug.assert_eq(o2, ["  40.0\t/picked\n"])
  @debug.assert_eq(e2.length(), 0)
  // len==7: upstream get(7..) = Some(""), so an empty string is printed, exit 0
  let o3 : Array[String] = []
  let e3 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("1234567"), false, e3, o3), 0)
  @debug.assert_eq(o3, [""])
  @debug.assert_eq(e3.length(), 0)
  // len<7: upstream\'s error path, no output
  let o4 : Array[String] = []
  let e4 : Array[String] = []
  @debug.assert_eq(finish_interactive(Ok("abc\n"), false, e4, o4), 1)
  @debug.assert_eq(o4.length(), 0)
  @debug.assert_eq(e4[0], "jumbit: could not read selection from fzf")
  // NotFound
  let o5 : Array[String] = []
  let e5 : Array[String] = []
  @debug.assert_eq(
    finish_interactive(Err(@platform.NotFound), false, e5, o5),
    1,
  )
  @debug.assert_eq(e5[0], "jumbit: could not find fzf, is it installed?")
  @debug.assert_eq(o5.length(), 0)
  // NoMatch: a silent exit 1 (a difference from upstream, noted in the README)
  let o6 : Array[String] = []
  let e6 : Array[String] = []
  @debug.assert_eq(finish_interactive(Err(@platform.NoMatch), false, e6, o6), 1)
  @debug.assert_eq(e6.length(), 0)
  @debug.assert_eq(o6.length(), 0)
  // the fzf-side error family
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
  // a user interrupt: 130 passes through silently
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
async test "the equals form --flag=value end to end (matching clap\'s two forms)" {
  let data = make_test_dir("eq-data")
  let target = make_test_dir("eq-target")
  let errs : Array[String] = []
  // init --cmd= (the form the README documents, which used to be rejected with exit 2)
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
  // an invalid value -> Invalid with exit code 2
  @debug.assert_eq(
    run(["query", "--list", "--limit=x"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
#cfg(not(platform="windows"))
// // Windows-gated: the read-only directory relies on a chmod permission bit (a no-op on Windows), pending platform work
async test "a failed save: an unwritable data directory -> clear wording and exit 1 (no Repr leak)" {
  let data = make_test_dir("save-ro")
  let target = make_test_dir("save-ro-t")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @afs.chmod(data, 0o555)
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs2), 1)
  @debug.assert_eq(
    errs2[0],
    "jumbit: could not save database: io failure: Permission denied (os error 13)",
  )
  @afs.chmod(data, 0o755)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "top-level dispatch: --version/-V, no arguments, a bad top-level flag, and the run-layer seam" {
  let data = make_test_dir("toplevel")
  // --version / -V: the version line goes to stdout, exit 0, no stderr
  let errs1 : Array[String] = []
  @debug.assert_eq(run(["--version"], env_with(data), errs1), 0)
  @debug.assert_eq(errs1.length(), 0)
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["-V"], env_with(data), errs2), 0)
  @debug.assert_eq(errs2.length(), 0)
  // no arguments: the full help goes to stderr (the errs batch-write channel), exit 2
  let errs3 : Array[String] = []
  @debug.assert_eq(run([], env_with(data), errs3), 2)
  // the full usage is one message (containing \n) and goes through the errs batch-write channel
  @debug.assert_eq(errs3.length(), 1)
  assert_true(errs3[0].has_prefix("jumbit \{@root.VERSION}"))
  assert_true(errs3[0].contains("Usage:"))
  // a version flag followed by extra arguments: a usage error (clap unexpected argument)
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["--version", "x"], env_with(data), errs4), 2)
  assert_true(errs4[0].contains("unexpected argument 'x'"))
  // a top-level bare token: unrecognized subcommand; a flag shape: unexpected argument
  let errs5 : Array[String] = []
  @debug.assert_eq(run(["frobnicate"], env_with(data), errs5), 2)
  assert_true(errs5[0].contains("unrecognized subcommand 'frobnicate'"))
  let errs6 : Array[String] = []
  @debug.assert_eq(run(["--bogus"], env_with(data), errs6), 2)
  assert_true(errs6[0].contains("unexpected argument '--bogus'"))
  cleanup_test_dir(data)
}

///|
async test "sampling the per-subcommand config-failure arms: a bad _JB_DATA_DIR on each dispatch arm -> exit 1" {
  // a relative data_dir is rejected at the config layer, and every subcommand\'s None => return 1 arm is isomorphic, so
  // query/add/status/import stand in (edit/describe/export share the same cfg chain)
  let bad = env_map([("_JB_DATA_DIR", "relative-not-absolute")])
  @debug.assert_eq(run(["query"], bad, []), 1)
  @debug.assert_eq(run(["add", "/tmp"], bad, []), 1)
  @debug.assert_eq(run(["status"], bad, []), 1)
  @debug.assert_eq(run(["import", "z"], bad, []), 1)
}

///|
async test "run-layer dispatch: the unknown-plugin arm and init\'s seven template arms" {
  let data = make_test_dir("dispatch")
  // an unknown import plugin (the parse layer already blocks it; this pins that the run-layer fallback arm is neither reached nor crashes)
  let errs : Array[String] = []
  @debug.assert_eq(run(["init", "zsh"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "fish"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "elvish"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "nushell"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "posix"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "powershell"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "tcsh"], env_with(data), errs), 0)
  @debug.assert_eq(run(["init", "xonsh"], env_with(data), errs), 0)
  cleanup_test_dir(data)
}

///|
test "cli-layer arm leftovers: an explicit --hook pwd, double --, a bad equals value, a repeated --prune" {
  // parse_hook\'s pwd arm (the default path does not enter the match, so it must be passed explicitly)
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook", "pwd"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("j"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  // strip_double_dash\'s dropped=true arm: what follows -- is taken as a positional
  @debug.assert_eq(@cli.parse(["remove", "--", "/a"]), @cli.Remove(["/a"]))
  @debug.assert_eq(
    @cli.parse(["remove", "/a", "--", "--b"]),
    @cli.Remove(["/a", "--b"]),
  )
  // a bad value in the --score=abc equals form (the space form is already covered)
  @debug.assert_eq(
    @cli.parse(["add", "--score=abc", "/tmp"]),
    @cli.Invalid("invalid value 'abc' for '--score <N>'"),
  )
  // a repeated --prune (a repeated --rename is already covered)
  @debug.assert_eq(
    @cli.parse(["edit", "--prune", "--prune"]),
    @cli.Invalid("the argument '--prune' cannot be used multiple times"),
  )
}

///|
/// [#2] regression: a read-only query writes nothing -- reading a legacy database does not migrate and an empty directory materializes nothing.
/// The old implementation dirtied unconditionally in sort_by_score and marked dirty in load(legacy), so every query exited
/// dirty: the first legacy query migrated (breaking "a read-only command triggers no migration"), a query against a read-only
/// data directory failed outright, and an empty directory grew empty db.txt and notes.tsv files.
/// Red verification: before the fix this test failed at three assertions (db.txt had been created)
async test "a read-only query writes nothing: legacy is not migrated and an empty directory materializes nothing" {
  // the legacy state: a db.zo (built through core.encode, sharing the legacy format\'s version) and no db.txt;
  // the entry points at a real directory, the query hits, and the filter chain deletes nothing
  let data = make_test_dir("legacy-readonly")
  let hit = make_test_dir("legacy-hit")
  let db = @core.Database::new()
  db.add_update(hit, 2.0, 1791000000L)
  @platform.write_atomic(data + "/db.zo", @core.encode(db.all()))
  let errs : Array[String] = []
  @debug.assert_eq(run(["query", "legacy-hit"], env_with(data), errs), 0)
  @debug.assert_eq(@afs.exists(data + "/db.txt"), false)
  // an empty data directory: a miss materializes no file
  let empty = make_test_dir("empty-readonly")
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["query", "nope"], env_with(empty), errs2), 1)
  @debug.assert_eq(@afs.exists(empty + "/db.txt"), false)
  @debug.assert_eq(@afs.exists(empty + "/notes.tsv"), false)
  cleanup_test_dir(data)
  cleanup_test_dir(hit)
  cleanup_test_dir(empty)
}

///|
/// [#2] regression: legacy + a query lazy deletion (a real data change) -> the migration lands on disk with the content preserved;
/// db.zo is kept (the migration convention; it can be deleted by hand)
async test "legacy plus a query lazy deletion migrates to disk with the content preserved" {
  let keep = make_test_dir("legacy-migrate-keep")
  let data = make_test_dir("legacy-migrate")
  let db = @core.Database::new()
  db.add_update(keep, 9.0, 1791000000L)
  db.add_update("/nonexistent/stale", 1.0, 1791000000L - 100L * 86400L)
  @platform.write_atomic(data + "/db.zo", @core.encode(db.all()))
  let errs : Array[String] = []
  // stale does not exist and is past the 3-month TTL -> lazily deleted -> dirty -> save migrates to plaintext.
  // --list brings stale into the candidate set (with a keyword the chain prunes by keyword first, so a non-matching
  // entry never reaches the exists/TTL check)
  @debug.assert_eq(run(["query", "--list"], env_with(data), errs), 0)
  @debug.assert_eq(@afs.exists(data + "/db.txt"), true)
  let reloaded = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(reloaded.database().all().length(), 1)
  @debug.assert_eq(reloaded.database().all()[0].path, keep)
  @debug.assert_eq(@afs.exists(data + "/db.zo"), true)
  cleanup_test_dir(data)
  cleanup_test_dir(keep)
}

///|
/// [#2] regression: a read-only data directory plus a query (the filter chain deletes nothing) -> exit 0, no longer hitting
/// EACCES on "save even without changes". Red verification: before the fix, exit 1 with could not save
#cfg(not(platform="windows"))
async test "a read-only data directory with a query exits 0" {
  let data = make_test_dir("ro-query")
  let hit = make_test_dir("ro-query-hit")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", hit], env_with(data), errs), 0)
  @afs.chmod(data, 0o555)
  @debug.assert_eq(run(["query", "ro-query-hit"], env_with(data), errs), 0)
  @afs.chmod(data, 0o755)
  cleanup_test_dir(data)
  cleanup_test_dir(hit)
}

///|
/// [#3] regression: add --score inf lands in the database as the ceiling 9999999.99 (the documented rule),
/// no longer poisoned by aging down to the 0.01 floor. Red verification: before the fix rank == 0.01
async test "add score inf clamps to the ceiling" {
  let data = make_test_dir("inf-score")
  let target = make_test_dir("inf-target")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(["add", "--score", "inf", target], env_with(data), errs),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  // clamped to the ceiling 9999999.99 on import, then aged healthily before the write (total=MAX > 10000):
  // factor = 0.9x10000/MAX, so rank = MAX x factor = exactly 9000 (lossless in the two-decimal plaintext)
  @debug.assert_eq(store.database().all()[0].rank, 9000.0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
