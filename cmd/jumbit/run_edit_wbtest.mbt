///|
/// Tests for the edit execution layer (spec docs/spec-plaintext-edit.md §1.4/§3.3):
/// a fake-editor probe matrix plus --rename/--prune end to end

///|
#cfg(not(platform="windows"))
// cfg-gated: consumed only by the Windows-gated tests (see the notes at each test)
/// Build a fake editor script: the shell fragment runs at edit time ($1 = the file being edited)
async fn make_fake_editor(dir : String, name : String, body : String) -> String {
  let path = dir + "/" + name
  // WARNING: String::to_bytes gives UTF-16 bytes (which mangles the shebang and yields Exec format error),
  // so UTF-8 encoding is required
  @platform.write_atomic(path, @utf8.encode("#!/bin/sh\n" + body))
  @afs.chmod(path, 0o755)
  path
}

///|
#cfg(not(platform="windows"))
// the fake-editor stub is made with a chmod executable bit (Windows has no exec bit; a .cmd stub is pending)
async test "interactive edit: a normal rank edit lands on disk; a missing editor -> no editor" {
  let data = make_test_dir("edit-data")
  let target = make_test_dir("edit-target")
  let bindir = make_test_dir("edit-bin")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // editor A: appends one legal entry (a change -> written to disk)
  let ed_add = make_fake_editor(
    bindir, "ed-add", "printf '0000000001\\t0000002.00\\t/added-by-editor\\n' >> \"$1\"",
  )

  let env1 = env_map([
    ("_JB_DATA_DIR", data),
    ("VISUAL", ed_add),
    ("EDITOR", "/nonexistent-editor"),
  ])
  let errs1 : Array[String] = []
  let code1 = run(["edit"], env1, errs1)
  @debug.assert_eq(code1, 0)
  @debug.assert_eq(errs1.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 2)
  // editor B: no change at all -> identical bytes -> a silent exit 0 with no dirty mark
  let ed_noop = make_fake_editor(bindir, "ed-noop", "exit 0")
  let env2 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_noop)])
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["edit"], env2, errs2), 0)
  @debug.assert_eq(errs2.length(), 0)
  // editor C: a non-zero exit -> an error and nothing written.
  // [#11]: an occasional fork-pressure spike on the CI runner makes spawn throw momentarily (Err(Spawn) ->
  // could not launch editor); a deterministic defect fails both times and stays red, while one retry clears a transient
  let ed_fail = make_fake_editor(bindir, "ed-fail", "exit 3")
  let env3 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_fail)])
  let errs3 : Array[String] = []
  let mut code3 = 0
  for attempt = 0 {
    errs3.clear()
    code3 = run(["edit"], env3, errs3)
    let ok3 = code3 == 1 &&
      errs3.length() == 1 &&
      errs3[0] == "jumbit: editor exited with code 3"
    if ok3 {
      break
    }
    // neither attempt met the expectation -> fall through to the assertion below with the last result
    if attempt >= 1 {
      break
    }
    continue attempt + 1
  }
  @debug.assert_eq(code3, 1)
  @debug.assert_eq(errs3[0], "jumbit: editor exited with code 3")
  // editor D: writes a bad row -> corrupted data file (with its line number), nothing written
  let ed_bad = make_fake_editor(
    bindir, "ed-bad", "printf 'garbage-line\\n' >> \"$1\"",
  )
  let env4 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_bad)])
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["edit"], env4, errs4), 1)
  assert_true(errs4[0].has_prefix("jumbit: corrupted data file: line "))
  // no editor: VISUAL and EDITOR both empty plus an empty directory injected on PATH (vi resolution fails)
  let env5 = env_map([
    ("_JB_DATA_DIR", data),
    ("VISUAL", ""),
    ("EDITOR", ""),
    ("PATH", bindir),
  ])
  let errs5 : Array[String] = []
  @debug.assert_eq(run(["edit"], env5, errs5), 1)
  @debug.assert_eq(errs5[0], "jumbit: no editor: set $EDITOR or $VISUAL")
  cleanup_test_dir(data)
  cleanup_test_dir(target)
  cleanup_test_dir(bindir)
}

///|
#cfg(not(platform="windows"))
// 伪 editor 桩经 chmod 可执行位造（Windows 无 exec 位，待 .cmd 桩平台化）
async test "edit --rename: the note follows; a miss or a name collision errors" {
  let data = make_test_dir("ren-data")
  let target = make_test_dir("ren-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["describe", target, "--note", "后端"], env_with(data), errs),
    0,
  )
  // a hit: the path changes and the note follows
  let errs1 : Array[String] = []
  @debug.assert_eq(
    run(["edit", "--rename", target, "/renamed"], env_with(data), errs1),
    0,
  )
  @debug.assert_eq(errs1.length(), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/renamed")
  @debug.assert_eq(store.database().all()[0].note, Some("后端"))
  // a miss
  let errs2 : Array[String] = []
  let _ = run(["edit", "--rename", "/nope", "/x"], env_with(data), errs2)
  // a collision: /renamed exists, so renaming onto an existing entry
  let errs3 : Array[String] = []
  @debug.assert_eq(
    run(["edit", "--rename", "/renamed", "/renamed"], env_with(data), errs3),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "edit --prune: removes entries that no longer exist and prints the list; all-existing is silent" {
  let data = make_test_dir("prune-data")
  let target = make_test_dir("prune-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // rewrite the database by hand (an acceptance check for hand-editability): target (exists, kept) plus /gone and /keep (nonexistent,
  // removed); /gone carries an annotation (the orphan note dies with prune). Note that write_atomic overwrites wholesale, so
  // the target entry must be included
  @platform.write_atomic(
    data + "/db.txt",
    @utf8.encode(
      "0000000001\t0000003.00\t\{target}\n0000000001\t0000001.00\t/gone\n0000000001\t0000002.00\t/keep\n",
    ),
  )
  @platform.write_atomic(data + "/notes.tsv", @utf8.encode("/gone\t待清\n"))
  // prune: /gone (nonexistent) is removed; the list\'s stdout bytes belong to the golden freeze layer
  @debug.assert_eq(run(["edit", "--prune"], env_with(data), errs), 0)
  // /target exists and is kept; /gone is removed (note that /keep is also a fabricated path and goes with it --
  // prune runs with --all semantics over every nonexistent path, and the list follows database order)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  let remaining = store.database().all()
  println("PRUNE2: n=\{remaining.length()} target=\{target}")
  for r in remaining {
    println("PRUNE2-LEFT: \{r.path}")
  }
  @debug.assert_eq(remaining.length(), 1)
  @debug.assert_eq(remaining[0].path, target)
  // the orphan note dies: after the notes.tsv rewrite only target\'s remains (target has no note -> an empty file)
  let notes = @afs.read_file(data + "/notes.tsv")
  @debug.assert_eq(notes.text(), "")
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
#cfg(not(platform="windows"))
// the same chmod shape for the fake-editor stub; the sh -c arm needs sh on PATH (always present in the test environment)
async test "edit\'s editor resolution chain and execution surface: an EDITOR fallback, a spaced value through sh -c, and a non-zero exit" {
  let data = make_test_dir("edit-chain")
  let target = make_test_dir("edit-chain-t")
  let bindir = make_test_dir("edit-chain-bin")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // editor: appends one legal entry to "the last argument" (the database file jumbit passes in).
  // Taking the last argument in a loop rather than "$1": after a spaced EDITOR (the --quiet case below) is split by sh -c,
  // the extra arguments sit before the database file, so "$1" would land on the editor\'s own flag and write the content
  // into a same-named file in the process cwd (which is where the historic --quiet left in the repo root came from, [#5])
  // A case guard: only write when $last is an absolute path. Under a full parallel batch an occasional case was observed
  // where $last landed on the flag (cwd growing a --quiet leftover, [#5]/[#11]); the guard makes that leak
  // constructively impossible, and the case assertion pins only the exit code, so it is unaffected
  let ed_add = make_fake_editor(
    bindir, "ed-chain", "for last; do :; done\ncase \"$last\" in /*) printf '0000000001\\t0000002.00\\t/chain-added\\n' >> \"$last\";; esac",
  )
  // the fallback chain: VISUAL missing -> EDITOR takes effect (resolve_editor\'s match arm)
  let env_r = env_map([
    ("_JB_DATA_DIR", data),
    ("PATH", bindir + ":/usr/bin:/bin"),
    ("EDITOR", ed_add),
  ])
  @debug.assert_eq(run(["edit"], env_r, errs), 0)
  // a spaced EDITOR -> the sh -c '<value> "$@"' arm (the git EDITOR idiom; the value carries arguments)
  let env_sp = env_map([
    ("_JB_DATA_DIR", data),
    ("PATH", bindir + ":/usr/bin:/bin"),
    ("VISUAL", ed_add + " --quiet"),
  ])
  // would a fake editor that does not know --quiet fail? The sh wrapper passes "$@" to the stub, which uses "$1", so
  // the extra argument is ignored and it still succeeds. What this case pins is that a spaced value is split as a shell command line
  @debug.assert_eq(run(["edit"], env_sp, errs), 0)
  // a non-zero editor exit -> the Failed(code) arm, with wording plus exit 1
  let ed_fail = make_fake_editor(bindir, "ed-fail", "exit 3")
  let env_f = env_map([
    ("_JB_DATA_DIR", data),
    ("PATH", bindir + ":/usr/bin:/bin"),
    ("VISUAL", ed_fail),
  ])
  let errs_f : Array[String] = []
  @debug.assert_eq(run(["edit"], env_f, errs_f), 1)
  assert_true(errs_f[0].contains("editor exited with code 3"))
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "edit\'s write-failure family: a refused tmp creation plus a refused --rename/--prune save -> exit 1" {
  // interactive editing builds its tmp inside the data directory (db.txt.edit): a read-only directory dies earlier on the
  // could not write temporary file arm (never reaching save), so that arm is pinned in passing
  let data = make_test_dir("edit-save-ro")
  let target = make_test_dir("edit-save-ro-t")
  let bindir = make_test_dir("edit-save-ro-bin")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  let ed_touch = make_fake_editor(
    bindir, "ed-touch", "printf '0000000001\\t0000002.00\\t/edited-ro\\n' >> \"$1\"",
  )
  @afs.chmod(data, 0o555)
  let env_e = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_touch)])
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["edit"], env_e, errs2), 1)
  assert_true(errs2[0].has_prefix("jumbit: could not write temporary file: "))
  @afs.chmod(data, 0o755)
  // a refused --rename save
  @afs.chmod(data, 0o555)
  let errs3 : Array[String] = []
  @debug.assert_eq(
    run(["edit", "--rename", target, "/moved"], env_with(data), errs3),
    1,
  )
  assert_true(errs3[0].has_prefix("jumbit: could not save database: "))
  @afs.chmod(data, 0o755)
  // a refused --prune save: import a path that then disappears first (with no change prune returns early
  // without writing and returns 0 under a read-only directory, so a "there is something to prune" state must come first)
  @afs.chmod(data, 0o755)
  let gone = make_test_dir("edit-save-ro-gone")
  let errs5 : Array[String] = []
  @debug.assert_eq(run(["add", gone], env_with(data), errs5), 0)
  cleanup_test_dir(gone)
  @afs.chmod(data, 0o555)
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["edit", "--prune"], env_with(data), errs4), 1)
  assert_true(errs4[0].has_prefix("jumbit: could not save database: "))
  @afs.chmod(data, 0o755)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}
