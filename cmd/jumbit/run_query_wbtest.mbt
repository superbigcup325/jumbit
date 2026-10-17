///|
async test "query on an empty database -> exit code 1 with a hint, no panic" {
  let data = make_test_dir("empty")
  let errs : Array[String] = []
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "query keywords: the directory whose final component matches" {
  let data = make_test_dir("kw-data")
  let foo_dir = make_test_dir("foo-project")
  let bar_dir = make_test_dir("bar-project")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", foo_dir, bar_dir], env_with(data), errs), 0)
  // foo hits foo-project (the final component), not bar-project
  @debug.assert_eq(run(["query", "foo"], env_with(data), errs), 0)
  // a non-matching keyword -> exit code 1 with a hint
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["query", "zzz"], env_with(data), errs2), 1)
  @debug.assert_eq(errs2.length(), 1)
  // a keyword in the first component (tmp) does not satisfy final-component anchoring -> no match
  @debug.assert_eq(run(["query", "tmp"], env_with(data), errs2), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(foo_dir)
  cleanup_test_dir(bar_dir)
}

///|
async test "query --list and --score exit codes" {
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
#cfg(not(platform="windows"))
// // Windows-gated: the exact exclude comparison is sensitive to mixed separators (win32 resolve normalizes to backslashes while the TEMP env var is as is); restore after the phase-2 semantic decision
async test "query --exclude exact path: excluding the only match reports only match" {
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
async test "query --all skips the existence check" {
  let data = make_test_dir("all-data")
  let gone = make_test_dir("gone-dir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", gone], env_with(data), errs), 0)
  // the directory is deleted: the default exists check -> no match; --all -> still returned
  @afs.rmdir(gone)
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  @debug.assert_eq(run(["query", "--all"], env_with(data), errs), 0)
  cleanup_test_dir(data)
}

///|
#cfg(not(platform="windows"))
// // Windows-gated: the _JB_EXCLUDE_DIRS colon separator collides with drive-letter colons, and the literal /tmp/*victim* pattern pins POSIX form; restore after phase 2
async test "a _JB_EXCLUDE_DIRS glob hit is lazily deleted (the entry is gone after a reload)" {
  let data = make_test_dir("glob-data")
  let victim = make_test_dir("victim-dir")
  let keeper = make_test_dir("keeper-dir")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", victim, keeper], env_with(data), errs), 0)
  // the pattern is derived from the same source: victim\'s parent plus *victim* (the literal /tmp form has no standing
  // once the temp root is made platform-agnostic)
  let parent_end = match victim.rev_find("/") {
    Some(i) => i
    None => 0
  }
  let exclude_pattern = victim[0:parent_end].to_owned() + "/*victim*"
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_JB_EXCLUDE_DIRS", exclude_pattern),
  ])
  @debug.assert_eq(run(["query", "--list"], env, errs), 0)
  // the lazy deletion is on disk: only keeper remains after a reload
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
async test "an illegal glob in _JB_EXCLUDE_DIRS -> exit code 1 (matching upstream\'s runtime failure)" {
  let data = make_test_dir("badglob")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_EXCLUDE_DIRS", "[unclosed")])
  @debug.assert_eq(run(["query"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "query --json: --all can query a fake path, a miss exits 1, and --interactive is exclusive with exit code 2" {
  let data = make_test_dir("json-data")
  let zdir = make_test_dir("json-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(
    zfile, b"/imp-json-alpha|1.0|0\n/imp-json-beta|2.0|0\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // --all skips the existence check, so the fake path is not lazily deleted (the JSON byte shape is pinned by json_wbtest and smoke)
  @debug.assert_eq(run(["query", "--json", "--all"], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["query", "--json", "--all", "nosuch"], env_with(data), errs),
    1,
  )
  @debug.assert_eq(
    run(["query", "--json", "--interactive"], env_with(data), errs),
    2,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "query --fuzzy: the component-substring fallback on an exact zero-hit (extension semantics; default behaviour unchanged)" {
  let data = make_test_dir("fz-data")
  let zdir = make_test_dir("fz-z")
  let zfile = zdir + "/zdata"
  // a keyword in a non-final component: exact misses on final-component anchoring, fuzzy falls back
  @platform.write_atomic(zfile, b"/imp-fz/blog/work|1|0\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // the default semantics are unchanged: an exact miss -> exit code 1
  @debug.assert_eq(run(["query", "--all", "blog"], env_with(data), errs), 1)
  // --fuzzy\'s fallback hits
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blog"], env_with(data), errs),
    0,
  )
  // an in-component substring (the typo case) falls back too
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blo"], env_with(data), errs),
    0,
  )
  // with several keywords, a missing one means no match
  @debug.assert_eq(
    run(["query", "--all", "--fuzzy", "blog", "zzz"], env_with(data), errs),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "query --limit: truncation on all three paths, and 0 gives empty output (extension semantics)" {
  let data = make_test_dir("lim-data")
  let zdir = make_test_dir("lim-z")
  let zfile = zdir + "/zdata"
  // three different scores: beta 8.0 / mid 4.0x? -- la=0 makes everything x0.25: 2.0 -> 0.5, 1.0 -> 0.25
  @platform.write_atomic(
    zfile, b"/imp-lim-alpha|1.0|0\n/imp-lim-beta|2.0|1099511627776\n/imp-lim-mid|4.0|0\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // --list --limit 2: the first two after sorting, without re-sorting
  @debug.assert_eq(
    run(
      ["query", "--list", "--score", "--all", "--limit", "2"],
      env_with(data),
      errs,
    ),
    0,
  )
  // --json --limit 0: an empty array with exit code 0 (never the empty-check error path)
  @debug.assert_eq(
    run(["query", "--json", "--all", "--limit", "0"], env_with(data), errs),
    0,
  )
  // --limit above the result count: full output, no error
  @debug.assert_eq(
    run(["query", "--list", "--all", "--limit", "99"], env_with(data), errs),
    0,
  )
  // a bare query with limit is already rejected at the parse layer (pinned by cli_test), so it is not covered again
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
test "take_limit: None means no truncation, it takes the first n after sorting, 0 is empty and an over-large n takes everything" {
  let dir = (p : String, r : Double) => @core.Dir::{
    path: p,
    rank: r,
    last_accessed: 0L,
    note: None,
  }
  // a simulated remaining, already descending by score
  let dirs = [dir("/a", 8.0), dir("/b", 1.0), dir("/c", 0.5)]
  @debug.assert_eq(take_limit(dirs, None).length(), 3)
  let two = take_limit(dirs, Some(2))
  @debug.assert_eq(two.length(), 2)
  @debug.assert_eq(two[0].path, "/a")
  @debug.assert_eq(two[1].path, "/b")
  @debug.assert_eq(take_limit(dirs, Some(0)).length(), 0)
  @debug.assert_eq(take_limit(dirs, Some(99)).length(), 3)
}
