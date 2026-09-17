///|

///|
async test "import z：直灌新库 + 坏行上报不中止" {
  let data = make_test_dir("imp-data")
  let zdir = make_test_dir("imp-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(
    zfile, b"/alpha|1.5|1704067200\n/beta|2|1704067200\ngarbage\n",
  )
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["import", "z"], env, errs), 0)
  // 坏行按 <路径>:<行号>: <原因> 上报，好行照常入库
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
async test "import 空库检查：非空库无 --merge 拒绝，--merge 合并" {
  let data = make_test_dir("imp-merge-data")
  let target = make_test_dir("imp-merge-tgt")
  let zdir = make_test_dir("imp-merge-z")
  let zfile = zdir + "/zdata"
  @platform.write_atomic(zfile, b"/from-z|1|100\n")
  let errs : Array[String] = []
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // 非空库 + 无 --merge → 上游同文案拒绝
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(
    errs[errs.length() - 1],
    "current database is not empty, specify --merge to continue anyway",
  )
  // --merge 合并
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
async test "import z：重复路径 dedup 合并 rank 与最新时间" {
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
async test "import z：_JB_EXCLUDE_DIRS 命中静默跳过" {
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
async test "import autojump：XDG 定位 + sigmoid 归一 + last_accessed=0" {
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
  // rank 与 core 解析器一致（sigmoid(3.0)），last_accessed 置 0
  let expected = match @core.parse_autojump_line("3.0\t/aj") {
    Ok(d) => d
    Err(m) => fail(m)
  }
  @debug.assert_eq(d.rank, expected.rank)
  @debug.assert_eq(d.last_accessed, 0L)
  cleanup_test_dir(data)
  cleanup_test_dir(ajdir)
}

///|
async test "import z.lua：主路径缺失回落 fish 路径；主路径存在时优先" {
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
  // 主路径 $HOME/.zlua 不存在 → 回落 fish
  @debug.assert_eq(run(["import", "z.lua"], env, errs), 0)
  let store = match @platform.load(data) {
    Ok(s) => s
    Err(e) => fail("\{Repr(e)}")
  }
  @debug.assert_eq(store.database().all().length(), 1)
  @debug.assert_eq(store.database().all()[0].path, "/fishy")
  // 主路径存在时优先主路径（清库重导）
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
async test "import z：文件缺失 → could not read + 退出码 1，不落盘" {
  let data = make_test_dir("imp-missing")
  let errs : Array[String] = []
  let env = env_map([
    ("_JB_DATA_DIR", data),
    ("_Z_DATA", "/nonexistent-z-data-xyz"),
  ])
  @debug.assert_eq(run(["import", "z"], env, errs), 1)
  @debug.assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("could not read "))
  cleanup_test_dir(data)
}

///|
async test "import z：超大 rank 触发 age 老化（0.9×maxage/total 因子）" {
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
async test "import atuin：连续同路径折叠 + 错误不打断链（PATH 注入伪 atuin 走真实子进程）" {
  let data = make_test_dir("imp-atuin-data")
  let bindir = make_test_dir("imp-atuin-bin")
  // 记录序：/a /a 坏行 /a /b —— 期望 /a 只收首次（跨坏行仍折叠），/b 照常
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
  // 还原 PATH（追加式注入对并行测试无害，礼貌还原）
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
        // rank=1.0 且时间取转换首次（2024-01-01），非折叠前最后一条（01-03）
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
test "forward_atuin_stderr：剥原文尾换行再透传（上游继承 stderr 字节原样）" {
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
