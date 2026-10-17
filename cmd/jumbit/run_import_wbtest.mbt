///|

///|
async test "import z: pour into a new database, reporting bad rows without aborting" {
  let data = make_test_dir("imp-data")
  let zdir = make_test_dir("imp-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(
    zfile, b"/alpha|1.5|1704067200\n/beta|2|1704067200\ngarbage\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // bad rows are reported as <path>:<line>: <reason>, and good rows still import
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(errs[0], "\{zfile}:3: invalid entry: garbage")
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  for d in store.database().all() {
    if d.path == "/alpha" {
      @debug.assert_eq(d.rank, 1.5)
      @debug.assert_eq(d.last_accessed, 1704067200L)
    }
  }
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import\'s empty check: a non-empty database refuses without --merge, and --merge merges" {
  let data = make_test_dir("imp-merge-data")
  let target = make_test_dir("imp-merge-tgt")
  let zdir = make_test_dir("imp-merge-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/from-z|1|100\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // a non-empty database with no --merge -> the refusal with upstream\'s wording
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(
    errs[errs.length() - 1],
    "jumbit: current database is not empty, specify --merge to continue anyway",
  )
  // --merge merges
  @debug.assert_eq(run(["import", "--merge", "z"], env, errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
  cleanup_test_dir(zdir)
}

///|
async test "import z: duplicate paths dedup, merging the rank and the newest time" {
  let data = make_test_dir("imp-dedup")
  let zdir = make_test_dir("imp-dedup-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/dup|1|100\n/dup|2|200\n")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["import", "z"],
      env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 3.0)
  @debug.assert_eq(store.database().all()[0].last_accessed, 200L)
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import z: a _JB_EXCLUDE_DIRS hit is skipped silently" {
  let data = make_test_dir("imp-excl")
  let zdir = make_test_dir("imp-excl-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/alpha|1|100\n/beta/x|1|100\n")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_JB_EXCLUDE_DIRS", "/beta/*"),
    ("_Z_DATA", zfile),
  ])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/alpha")
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "import autojump: XDG lookup + sigmoid normalization + last_accessed=0" {
  let data = make_test_dir("imp-aj-data")
  let ajdir = make_test_dir("imp-aj")
  @afs.mkdir(ajdir + "/autojump", recursive=true)
  @platform.write_atomic(ajdir + "/autojump/autojump.txt", b"3.0\t/aj\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("XDG_DATA_HOME", ajdir)])
  @debug.assert_eq(run(["import", "autojump"], env, errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  let d = store.database().all()[0]
  @debug.assert_eq(d.path, "/aj")
  // the rank matches core\'s parser (sigmoid(3.0)=0.9525741...), and last_accessed is set to 0;
  // the plaintext persist keeps two decimals (as upstream #1288 does) and the read-back quantizes to 0.95
  @debug.assert_eq(d.rank, 0.95)
  @debug.assert_eq(d.last_accessed, 0L)
  cleanup_test_dir(data)
  cleanup_test_dir(ajdir)
}

///|
async test "import z.lua: a missing main path falls back to the fish path, and the main path wins when present" {
  let data = make_test_dir("imp-zlua-data")
  let fishdir = make_test_dir("imp-zlua-fish")
  let home = make_test_dir("imp-zlua-home")
  @afs.mkdir(fishdir + "/zlua", recursive=true)
  @platform.write_atomic(fishdir + "/zlua/zlua.txt", b"/fishy|1|100\n")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("XDG_DATA_HOME", fishdir),
    ("HOME", home),
  ])
  // the main path $HOME/.zlua is absent -> fall back to fish
  @debug.assert_eq(run(["import", "z.lua"], env, errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/fishy")
  // with the main path present it wins (clearing the database and re-importing)
  cleanup_test_dir(data)
  @platform.write_atomic(home + "/.zlua", b"/mainzlua|1|100\n")
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["import", "--merge", "z.lua"], env, errs2), 0)
  let store2 = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store2.database().all().length(), 1)
  @debug.assert_eq(store2.database().all()[0].path, "/mainzlua")
  cleanup_test_dir(data)
  cleanup_test_dir(fishdir)
  cleanup_test_dir(home)
}

///|
async test "import z: a missing file -> could not read plus exit code 1, nothing written" {
  let data = make_test_dir("imp-missing")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_Z_DATA", "/nonexistent-z-data-xyz"),
  ])
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("jumbit: could not read "))
  cleanup_test_dir(data)
}

///|
async test "import z: a huge rank triggers age (the 0.9 x maxage/total factor)" {
  let data = make_test_dir("imp-age")
  let zdir = make_test_dir("imp-age-z")
  let zfile = zdir + "/zdata"
  // total=20000 > 10000 → factor = 0.9×10000/20000 = 0.45 → rank 9000
  @platform.write_atomic(zfile, b"/big|20000|100\n")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["import", "z"],
      env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 9000.0)
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
#cfg(not(platform="windows"))
// the fake-atuin stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "import atuin: consecutive same-path folding, with an error not breaking the chain (a fake atuin injected on PATH runs as a real subprocess)" {
  let data = make_test_dir("imp-atuin-data")
  let bindir = make_test_dir("imp-atuin-bin")
  // record order: /a /a badrow /a /b -- /a is expected to keep only the first (still folding across the bad row), and /b as usual
  let nul = "\u{0000}"
  let records : String = "2024-01-01 00:00:00\t/a\{nul}2024-01-02 00:00:00\t/a\{nul}bad-record\{nul}2024-01-03 00:00:00\t/a\{nul}2024-01-04 00:00:00\t/b\{nul}"
  @platform.write_atomic(bindir + "/records", @utf8.encode(records))
  let fake = bindir + "/atuin"
  let script : String = "#!/bin/sh\ncat \{bindir}/records\n"
  @platform.write_atomic(fake, @utf8.encode(script))
  @afs.chmod(fake, 0o755)
  let orig_path = @env.get_env_var("PATH")
  @env.set_env_var(
    "PATH",
    match orig_path {
      Some(p) => "\{bindir}:\{p}"
      None => bindir
    },
  )
  let errs : Array[String] = []
  @debug.assert_eq(
    run(["import", "atuin"], env_map([("_JB_DATA_DIR", data)]), errs),
    0,
  )
  // restore PATH (an append-only injection is harmless to parallel tests, but restore politely anyway)
  match orig_path {
    Some(p) => @env.set_env_var("PATH", p)
    None => @env.unset_env_var("PATH")
  }
  @debug.assert_eq(errs.length(), 1)
  @debug.assert_eq(errs[0], "line 3: invalid entry: bad-record")
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  for d in store.database().all() {
    match d.path {
      "/a" => {
        // rank=1.0 and the time is the transition\'s first (2024-01-01), not the last record before folding (01-03)
        @debug.assert_eq(d.rank, 1.0)
        @debug.assert_eq(d.last_accessed, 1704067200L)
      }
      "/b" => {
        @debug.assert_eq(d.rank, 1.0)
        @debug.assert_eq(d.last_accessed, 1704326400L)
      }
      other => fail("unexpected path: \{other}")
    }
  }
  cleanup_test_dir(data)
  cleanup_test_dir(bindir)
}

///|
test "forward_atuin_stderr: strip the source\'s trailing newline before passing it on (upstream inherits stderr byte-verbatim)" {
  let errs : Array[String] = []
  forward_atuin_stderr(errs, "a\nb\n")
  @debug.assert_eq(errs, ["a\nb"])
  let errs2 : Array[String] = []
  forward_atuin_stderr(errs2, "no-eol")
  @debug.assert_eq(errs2, ["no-eol"])
  let errs3 : Array[String] = []
  forward_atuin_stderr(errs3, "")
  @debug.assert_eq(errs3, [])
}
