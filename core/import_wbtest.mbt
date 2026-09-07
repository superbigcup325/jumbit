// 导入行解析测试：正常路径 + 上游语义锁定的坏行 case

///|
/// 取 Ok 值或 fail（Dir 无 Eq，字段逐个断言）
fn expect_dir(r : Result[Dir, String]) -> Dir raise {
  match r {
    Ok(d) => d
    Err(msg) => fail("unexpected err: \{msg}")
  }
}

///|
/// 断言坏行原因
fn expect_err(r : Result[Dir, String], reason : String) -> Unit raise {
  match r {
    Ok(_) => fail("应报坏行: \{reason}")
    Err(msg) => @debug.assert_eq(msg, reason)
  }
}

///|
test "parse_z_line：基础三段" {
  let d = expect_dir(parse_z_line("/home/user|1.5|1700000000"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, 1.5)
  @debug.assert_eq(d.last_accessed, 1700000000L)
}

///|
test "parse_z_line：路径含 | 从右切三段（上游 rsplitn 语义）" {
  let d = expect_dir(parse_z_line("/a|b|2.0|100"))
  @debug.assert_eq(d.path, "/a|b")
  @debug.assert_eq(d.rank, 2.0)
  @debug.assert_eq(d.last_accessed, 100L)
}

///|
test "parse_z_line：空白属于路径，不 trim（上游原样保留）" {
  let d = expect_dir(parse_z_line(" /a |1|2"))
  @debug.assert_eq(d.path, " /a ")
}

///|
test "parse_z_line：空路径合法（上游原样通过）" {
  let d = expect_dir(parse_z_line("|1.0|0"))
  @debug.assert_eq(d.path, "")
}

///|
test "parse_z_line：负 rank 合法（上游 f64 原样入库）" {
  let d = expect_dir(parse_z_line("/a|-2.5|0"))
  @debug.assert_eq(d.rank, -2.5)
}

///|
test "parse_z_line：坏行族（缺段/坏数/负时间戳/空串段）" {
  expect_err(parse_z_line("no-pipe-at-all"), "invalid entry: no-pipe-at-all")
  expect_err(parse_z_line("/a|1.5"), "invalid entry: /a|1.5")
  expect_err(parse_z_line("/a|x|1"), "invalid entry: /a|x|1")
  expect_err(parse_z_line("/a|1.5|y"), "invalid entry: /a|1.5|y")
  // 上游 last_accessed 按 u64 解析，负数拒为坏行
  expect_err(parse_z_line("/a|1.5|-1"), "invalid entry: /a|1.5|-1")
  expect_err(parse_z_line("|1.5|"), "invalid entry: |1.5|")
  expect_err(parse_z_line("||"), "invalid entry: ||")
}

///|
test "parse_autojump_line：rank 过 sigmoid，last_accessed=0" {
  let d = expect_dir(parse_autojump_line("3.7\t/home/user"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, sigmoid(3.7))
  @debug.assert_eq(d.last_accessed, 0L)
}

///|
test "sigmoid：端点与单调性" {
  @debug.assert_eq(sigmoid(0.0), 0.5)
  assert_true(sigmoid(1.0) > 0.5 && sigmoid(1.0) < 1.0)
  assert_true(sigmoid(-1.0) > 0.0 && sigmoid(-1.0) < 0.5)
}

///|
test "parse_autojump_line：路径含 \t 按首 \t 切（上游 split_once 语义）" {
  let d = expect_dir(parse_autojump_line("1.0\t/a\tb"))
  @debug.assert_eq(d.path, "/a\tb")
}

///|
test "parse_autojump_line：坏行族" {
  expect_err(parse_autojump_line("/a"), "invalid entry: /a")
  expect_err(parse_autojump_line("abc\t/a"), "invalid rank: abc")
  expect_err(parse_autojump_line("\t/a"), "invalid rank: ")
}

///|
test "parse_atuin_line：时间戳转 UTC epoch，rank=1.0" {
  let d = expect_dir(parse_atuin_line("2024-01-01 00:00:00\t/home/user"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, 1.0)
  // 2024-01-01T00:00:00Z
  @debug.assert_eq(d.last_accessed, 1704067200L)
}

///|
test "parse_atuin_line：纪元边界（1970-01-01 与 1969-12-31）" {
  let d = expect_dir(parse_atuin_line("1970-01-01 00:00:00\t/a"))
  @debug.assert_eq(d.last_accessed, 0L)
  let d2 = expect_dir(parse_atuin_line("1969-12-31 23:59:59\t/a"))
  @debug.assert_eq(d2.last_accessed, -1L)
}

///|
test "parse_atuin_line：闰日（2000-02-29 闰年合法；1900 非、2100 非百年不闰）" {
  let d = expect_dir(parse_atuin_line("2000-02-29 12:00:00\t/a"))
  // 2000-02-29T12:00:00Z
  @debug.assert_eq(d.last_accessed, 951825600L)
  expect_err(
    parse_atuin_line("1900-02-29 00:00:00\t/a"),
    "invalid timestamp: \"1900-02-29 00:00:00\"",
  )
}

///|
test "parse_atuin_line：路径含空格与冒号原样保留" {
  let d = expect_dir(parse_atuin_line("2024-06-01 07:08:09\t/my dir:x"))
  @debug.assert_eq(d.path, "/my dir:x")
}

///|
test "parse_atuin_line：坏行族（无 \t/超范围/格式错）" {
  expect_err(
    parse_atuin_line("2024-01-01 00:00:00"),
    "invalid entry: 2024-01-01 00:00:00",
  )
  expect_err(
    parse_atuin_line("2024-13-01 00:00:00\t/a"),
    "invalid timestamp: \"2024-13-01 00:00:00\"",
  )
  expect_err(
    parse_atuin_line("2023-02-29 00:00:00\t/a"),
    "invalid timestamp: \"2023-02-29 00:00:00\"",
  )
  expect_err(
    parse_atuin_line("2024-01-01 24:00:00\t/a"),
    "invalid timestamp: \"2024-01-01 24:00:00\"",
  )
  expect_err(
    parse_atuin_line("2024-01-01 00:60:00\t/a"),
    "invalid timestamp: \"2024-01-01 00:60:00\"",
  )
  expect_err(
    parse_atuin_line("2024-4-01 00:00:00\t/a"),
    "invalid timestamp: \"2024-4-01 00:00:00\"",
  )
  expect_err(
    parse_atuin_line("2024/01/01 00:00:00\t/a"),
    "invalid timestamp: \"2024/01/01 00:00:00\"",
  )
  expect_err(
    parse_atuin_line("2024-01-01T00:00:00\t/a"),
    "invalid timestamp: \"2024-01-01T00:00:00\"",
  )
}

///|
test "days_from_civil：与已知 epoch 交叉验证" {
  @debug.assert_eq(days_from_civil(1970, 1, 1), 0L)
  // 2024-01-01 → 1704067200 / 86400 = 19723 天
  @debug.assert_eq(days_from_civil(2024, 1, 1), 19723L)
  // 2000-03-01（闰日次日）→ 951868800 / 86400 = 11017 天
  @debug.assert_eq(days_from_civil(2000, 3, 1), 11017L)
  // 1969-12-31 → -1 天
  @debug.assert_eq(days_from_civil(1969, 12, 31), -1L)
}

///|
/// 折叠测试辅助：路径 → 带定位条目（rank/时间对折叠不可见，取占位值）
fn loc(path : String) -> LocatedDir {
  { location: path, result: Ok({ path, rank: 1.0, last_accessed: 0L, }), }
}

///|
/// 折叠测试辅助：坏行条目
fn loc_err(reason : String) -> LocatedDir {
  { location: "line 0", result: Err(reason), }
}

///|
/// 折叠结果投影为路径/坏行标记序列，便于断言
fn collapse_paths(items : Array[LocatedDir]) -> Array[String] {
  let out : Array[String] = []
  for it in items {
    match it.result {
      Ok(d) => out.push(d.path)
      Err(_) => out.push("<err>")
    }
  }
  out
}

///|
test "collapse_consecutive：连续同路径只保留首次（上游 prev_cwd 语义）" {
  let out = collapse_consecutive([
    loc("/a"),
    loc("/a"),
    loc("/a"),
    loc("/b"),
    loc("/a"),
  ])
  @debug.assert_eq(collapse_paths(out), ["/a", "/b", "/a"])
}

///|
test "collapse_consecutive：Err 原样透传且不打断折叠链" {
  // /a → 坏行 → /a：坏行不改 prev，第二个 /a 仍被折叠（上游错误路径不改 prev_cwd）
  let out = collapse_consecutive([
    loc("/a"),
    loc_err("bad"),
    loc("/a"),
    loc("/b"),
  ])
  @debug.assert_eq(collapse_paths(out), ["/a", "<err>", "/b"])
}

///|
test "collapse_consecutive：空序列与单条目" {
  @debug.assert_eq(collapse_consecutive([]).length(), 0)
  @debug.assert_eq(collapse_paths(collapse_consecutive([loc("/only")])), [
    "/only",
  ])
}

///|
test "collapse_consecutive：定位随条目保留" {
  let items = [
    {
      location: "line 1",
      result: Ok({ path: "/x", rank: 1.0, last_accessed: 0L, }),
    },
    {
      location: "line 2",
      result: Ok({ path: "/x", rank: 1.0, last_accessed: 5L, }),
    },
  ]
  let out = collapse_consecutive(items)
  @debug.assert_eq(out.length(), 1)
  @debug.assert_eq(out[0].location, "line 1")
  @debug.assert_eq(expect_dir(out[0].result).last_accessed, 0L)
}
