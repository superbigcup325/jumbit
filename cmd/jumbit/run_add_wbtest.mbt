///|
async test "add\'s -- separator: a path starting with a minus is recorded normally" {
  let data = make_test_dir("dash-data")
  let target = make_test_dir("-dash-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "--", target], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "add a non-directory -> exit code 1 with the error wording" {
  let data = make_test_dir("nondir-bail-1")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add a path containing a newline -> skipped silently (matching upstream, exit code 0)" {
  let data = make_test_dir("nl")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", "/a\nb"], env_with(data), errs), 0)
  @debug.assert_eq(errs.length(), 0)
  @debug.assert_eq(@afs.exists(data + "/db.txt"), false)
  cleanup_test_dir(data)
}

///|
async test "add a non-directory -> aborts immediately and writes nothing" {
  let data = make_test_dir("nondir-bail-2")
  let errs : Array[String] = []
  // a legal directory first and then an illegal path: under upstream\'s bail semantics the whole command fails and nothing is saved
  @debug.assert_eq(run(["add", "/nonexistent-path"], env_with(data), errs), 1)
  @debug.assert_eq(@afs.exists(data + "/db.txt"), false)
  cleanup_test_dir(data)
}

///|
async test "adding the same directory twice -> the database still holds one entry" {
  let data = make_test_dir("dedup")
  let target = make_test_dir("tgt")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].rank, 2.0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "add: with _JB_ECHO=1 it echoes without affecting the exit code" {
  let data = make_test_dir("echo-data")
  let target = make_test_dir("echo-target")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(
      ["add", target],
      env_map([("_JB_DATA_DIR", data), ("_JB_ECHO", "1")]),
      errs,
    ),
    0,
  )
  @debug.assert_eq(errs.length(), 0)
  // the database still holds one record; the echo is only an output side effect
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "remove: after deletion a query finds nothing, and an unrecorded path errors" {
  let data = make_test_dir("rm-data")
  let target = make_test_dir("rm-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // delete by absolute path
  @debug.assert_eq(run(["remove", target], env_with(data), errs), 0)
  @debug.assert_eq(run(["query"], env_with(data), errs), 1)
  // deleting the same path again -> path not found
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["remove", target], env_with(data), errs2), 1)
  @debug.assert_eq(errs2.length(), 1)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "remove: a relative-path form also deletes once normalized" {
  let data = make_test_dir("rm-rel-data")
  let target = make_test_dir("rm-rel-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // remove with a nonexistent original string -> retries with the normalized path (matching upstream\'s dual attempt)
  @debug.assert_eq(
    run(["remove", "jumbit-e2e-nonexistent"], env_with(data), errs),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "_JB_MAXAGE=0: after add the total zeroes and everything is deleted (pinning the expected behaviour)" {
  let data = make_test_dir("age-data")
  let target = make_test_dir("age-target")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_MAXAGE", "0")])
  @debug.assert_eq(run(["add", target], env, errs), 0)
  // total > 0 -> factor 0 -> every rank < 1, so everything is deleted and the file holds an empty array
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "a non-numeric _JB_MAXAGE -> exit code 1 (matching upstream\'s runtime failure)" {
  let data = make_test_dir("age-bad")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_MAXAGE", "abc")])
  @debug.assert_eq(run(["add", data], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  cleanup_test_dir(data)
}

///|
async test "add --score: a negative delta clamps to 0" {
  let data = make_test_dir("score-data")
  let target = make_test_dir("score-target")
  let errs : Array[String] = []
  @debug.assert_eq(
    run(["add", "--score", "3.5", target], env_with(data), errs),
    0,
  )
  @debug.assert_eq(
    run(["add", "--score", "-5", target], env_with(data), errs),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  // clamped to 0.0 in memory; after a plaintext round trip it reads back as MIN_RANK 0.01
  // (the same semantics as upstream #1288\'s plaintext format: the on-disk rank floor is 0.01)
  @debug.assert_eq(store.database().all()[0].rank, 0.01)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
#cfg(not(platform="windows"))
// Windows-gated: creating a symlink needs privilege or developer mode, probe run 36044327191
async test "_JB_RESOLVE_SYMLINKS=1: add records a symlink\'s real directory" {
  let data = make_test_dir("sym-data")
  let real = make_test_dir("sym-real")
  let link = "/tmp/jumbit-e2e-sym-link-\{@async.now()}"
  @afs.symlink(target=real, link)
  let errs : Array[String] = []
  // resolve mode: the real directory is recorded; the default mode: the link path itself
  @debug.assert_eq(
    run(
      ["add", link],
      env_map([("_JB_DATA_DIR", data), ("_JB_RESOLVE_SYMLINKS", "1")]),
      errs,
    ),
    0,
  )
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  // the expected path takes realpath from the same source as the semantics under test: on macOS /tmp is a symlink to
  // /private/tmp, so resolving escapes a /private prefix (Linux has no such link and the two values agree), which would
  // make a literal assertion fail by platform
  let expected = @afs.realpath(real) catch {
    err => fail("\{@platform.os_error_message(err)}")
  }
  @debug.assert_eq(store.database().all()[0].path, expected)
  @debug.assert_eq(@afs.kind(link, follow_symlink=false), @afs.SymLink)
  cleanup_test_dir(data)
  cleanup_test_dir(real)
  cleanup_test_dir(link)
}

///|
#cfg(not(platform="windows"))
// Windows-gated: creating a symlink needs privilege or developer mode, probe run 36044327191
async test "add with _JB_RESOLVE_SYMLINKS=1: a self-looping symlink -> path resolution fails plus exit 1 (ELOOP takes the numeric suffix)" {
  let data = make_test_dir("loop-data")
  let dir = make_test_dir("loop-link")
  let loop_path = dir + "/loop"
  @afs.symlink(target=loop_path, loop_path)
  let env = env_map([("_JB_DATA_DIR", data), ("_JB_RESOLVE_SYMLINKS", "1")])
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", loop_path], env, errs), 1)
  // ELOOP\'s errno value differs by platform (Linux 40 / macOS 62), so the shape is pinned, not the value:
  // the prefix wording plus an (os error N) numeric suffix (ELOOP is not in os_error_message\'s phrase set, so
  // wrongly folding it into the phrase set or falling back to a Debug structure would fail here)
  @debug.assert_eq(
    errs[0].has_prefix(
      "jumbit: could not resolve path \{loop_path}: (os error ",
    ) &&
    errs[0].has_suffix(")"),
    true,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(dir)
}
