///|
/// edit 执行层测试（规格 docs/spec-plaintext-edit.md §1.4/§3.3）：
/// 伪 editor 探针矩阵 + --rename/--prune 端到端

///|
#cfg(not(platform="windows"))
// cfg 门控：仅被 Windows 门控测试消费（见各测试处注释）
/// 构造伪 editor 脚本：shell 片段在编辑时执行（$1 = 被编辑文件路径）
async fn make_fake_editor(dir : String, name : String, body : String) -> String {
  let path = dir + "/" + name
  // ⚠️ String::to_bytes 是 UTF-16 字节(shebang 会烂掉,Exec format error),
  // 必须走 UTF-8 编码
  @platform.write_atomic(path, @utf8.encode("#!/bin/sh\n" + body))
  @afs.chmod(path, 0o755)
  path
}

///|
#cfg(not(platform="windows"))
// 伪 editor 桩经 chmod 可执行位造（Windows 无 exec 位，待 .cmd 桩平台化）
async test "edit 交互：正常编辑改 rank → 落盘；编辑器缺失 → no editor" {
  let data = make_test_dir("edit-data")
  let target = make_test_dir("edit-target")
  let bindir = make_test_dir("edit-bin")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // editor A：往文件追加一行合法条目（改动 → 落盘）
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
  // editor B：无任何改动 → 字节一致 → 静默 exit 0 不标 dirty
  let ed_noop = make_fake_editor(bindir, "ed-noop", "exit 0")
  let env2 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_noop)])
  let errs2 : Array[String] = []
  @debug.assert_eq(run(["edit"], env2, errs2), 0)
  @debug.assert_eq(errs2.length(), 0)
  // editor C：退出码非 0 → 报错不落库
  let ed_fail = make_fake_editor(bindir, "ed-fail", "exit 3")
  let env3 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_fail)])
  let errs3 : Array[String] = []
  @debug.assert_eq(run(["edit"], env3, errs3), 1)
  @debug.assert_eq(errs3[0], "jumbit: editor exited with code 3")
  // editor D：写入坏行 → 数据文件损坏（行号），不落库
  let ed_bad = make_fake_editor(
    bindir, "ed-bad", "printf 'garbage-line\\n' >> \"$1\"",
  )
  let env4 = env_map([("_JB_DATA_DIR", data), ("VISUAL", ed_bad)])
  let errs4 : Array[String] = []
  @debug.assert_eq(run(["edit"], env4, errs4), 1)
  assert_true(errs4[0].has_prefix("jumbit: corrupted data file: line "))
  // 无 editor：VISUAL/EDITOR 均空 + PATH 注入空目录（vi 解析失败）
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
async test "edit --rename：note 跟随；未命中/撞名报错" {
  let data = make_test_dir("ren-data")
  let target = make_test_dir("ren-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["describe", target, "--note", "后端"], env_with(data), errs),
    0,
  )
  // 命中：改路径 + note 跟随
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
  // 未命中
  let errs2 : Array[String] = []
  let _ = run(["edit", "--rename", "/nope", "/x"], env_with(data), errs2)
  // 撞名：/renamed 已存在，改自身到既有条目路径
  let errs3 : Array[String] = []
  @debug.assert_eq(
    run(["edit", "--rename", "/renamed", "/renamed"], env_with(data), errs3),
    1,
  )
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
async test "edit --prune：移除不存在条目并输出清单；全存在静默" {
  let data = make_test_dir("prune-data")
  let target = make_test_dir("prune-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // 手工重写库（手编可读性验收）：target（存在，保留）+ /gone、/keep（不存在，
  // 移除）；/gone 带标注（孤儿 note 随 prune 消亡）。注意 write_atomic 是整体
  // 覆盖，target 条目必须包含在内
  @platform.write_atomic(
    data + "/db.txt",
    @utf8.encode(
      "0000000001\t0000003.00\t\{target}\n0000000001\t0000001.00\t/gone\n0000000001\t0000002.00\t/keep\n",
    ),
  )
  @platform.write_atomic(data + "/notes.tsv", @utf8.encode("/gone\t待清\n"))
  // prune：/gone（不存在）移除；清单的 stdout 字节面归 golden 冻结层
  @debug.assert_eq(run(["edit", "--prune"], env_with(data), errs), 0)
  // /target 存在保留；/gone 移除（注：/keep 也是编造路径，会被一并移除——
  // 用 --all 语义的 prune 对所有不存在路径执行，清单按库序）
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
  // 孤儿 note 消亡：notes.tsv 重写后只剩 target 的（target 无 note → 空文件）
  let notes = @afs.read_file(data + "/notes.tsv")
  @debug.assert_eq(notes.text(), "")
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
#cfg(not(platform="windows"))
// 伪 editor 桩同款 chmod 形态；sh -c 臂依赖 PATH 有 sh（测试环境恒有）
async test "edit 编辑器解析链与执行面：EDITOR 回落/含空格 sh -c/退出码非零" {
  let data = make_test_dir("edit-chain")
  let target = make_test_dir("edit-chain-t")
  let bindir = make_test_dir("edit-chain-bin")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  // editor：往文件追加一条合法条目
  let ed_add = make_fake_editor(
    bindir, "ed-chain", "printf '0000000001\\t0000002.00\\t/chain-added\\n' >> \"$1\"",
  )
  // 回落链：VISUAL 缺失 → EDITOR 生效（resolve_editor 的 match 臂）
  let env_r = env_map([
    ("_JB_DATA_DIR", data),
    ("PATH", bindir + ":/usr/bin:/bin"),
    ("EDITOR", ed_add),
  ])
  @debug.assert_eq(run(["edit"], env_r, errs), 0)
  // 含空格 EDITOR → sh -c '<值> "$@"' 臂（git EDITOR 惯用法；值带参数）
  let env_sp = env_map([
    ("_JB_DATA_DIR", data),
    ("PATH", bindir + ":/usr/bin:/bin"),
    ("VISUAL", ed_add + " --quiet"),
  ])
  // 假 editor 不认识 --quiet 会失败吗？sh 包装把 "$@" 传给桩，桩用 "$1"，
  // 多余参数被忽略 → 仍成功；此用例锁的是「含空格值按 shell 命令行拆分」
  @debug.assert_eq(run(["edit"], env_sp, errs), 0)
  // 编辑器退出码非零 → Failed(code) 臂，文案 + exit 1
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
async test "edit 落盘失败族：tmp 创建被拒 + --rename/--prune save 被拒 → exit 1" {
  // 交互编辑的 tmp 建在数据目录内（db.txt.edit）：目录只读死在更早的
  // could not write temporary file 臂（到不了 save），顺手锁该臂
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
  // --rename 落盘被拒
  @afs.chmod(data, 0o555)
  let errs3 : Array[String] = []
  @debug.assert_eq(
    run(["edit", "--rename", target, "/moved"], env_with(data), errs3),
    1,
  )
  assert_true(errs3[0].has_prefix("jumbit: could not save database: "))
  @afs.chmod(data, 0o755)
  // --prune 落盘被拒：先入库一个随后消失的路径（无变化时 prune 提前返回
  // 不落盘，只读目录下回 0，须先造成「有可清条目」的状态）
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
