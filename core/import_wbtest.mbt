// Import line-parsing tests: the normal path plus bad-row cases pinned to upstream semantics

///|
/// Take the Ok value or fail (Dir has no Eq, so the fields are asserted one by one)
fn expect_dir(r : Result[Dir, String]) -> Dir raise {
  match r {
    Ok(d) => d
    Err(msg) => fail("unexpected err: \{msg}")
  }
}

///|
/// Assert a bad-row reason
fn expect_err(r : Result[Dir, String], reason : String) -> Unit raise {
  match r {
    Ok(_) => fail("should report a bad row: \{reason}")
    Err(msg) => @debug.assert_eq(msg, reason)
  }
}

///|
test "parse_z_line: the basic three fields" {
  let d = expect_dir(parse_z_line("/home/user|1.5|1700000000"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, 1.5)
  @debug.assert_eq(d.last_accessed, 1700000000L)
}

///|
test "parse_z_line: a path containing | is split into three from the right (upstream rsplitn semantics)" {
  let d = expect_dir(parse_z_line("/a|b|2.0|100"))
  @debug.assert_eq(d.path, "/a|b")
  @debug.assert_eq(d.rank, 2.0)
  @debug.assert_eq(d.last_accessed, 100L)
}

///|
test "parse_z_line: whitespace belongs to the path and is not trimmed (upstream keeps it)" {
  let d = expect_dir(parse_z_line(" /a |1|2"))
  @debug.assert_eq(d.path, " /a ")
}

///|
test "parse_z_line: an empty path is legal (upstream passes it through)" {
  let d = expect_dir(parse_z_line("|1.0|0"))
  @debug.assert_eq(d.path, "")
}

///|
test "parse_z_line: a negative rank is legal (upstream imports the f64 as is)" {
  let d = expect_dir(parse_z_line("/a|-2.5|0"))
  @debug.assert_eq(d.rank, -2.5)
}

///|
test "parse_z_line: the bad-row family (a missing field / a bad number / a negative timestamp / an empty field)" {
  expect_err(parse_z_line("no-pipe-at-all"), "invalid entry: no-pipe-at-all")
  expect_err(parse_z_line("/a|1.5"), "invalid entry: /a|1.5")
  expect_err(parse_z_line("/a|x|1"), "invalid entry: /a|x|1")
  expect_err(parse_z_line("/a|1.5|y"), "invalid entry: /a|1.5|y")
  // upstream parses last_accessed as u64, so a negative is a bad row
  expect_err(parse_z_line("/a|1.5|-1"), "invalid entry: /a|1.5|-1")
  expect_err(parse_z_line("|1.5|"), "invalid entry: |1.5|")
  expect_err(parse_z_line("||"), "invalid entry: ||")
}

///|
test "parse_z_line: last_accessed is a u64 domain (probed against 0.10.0)" {
  // u64::MAX is accepted and stored bitwise as -1 in the i64 field; the score lands in the x4 bucket under the u64 domain
  let d = expect_dir(parse_z_line("/a|1.5|18446744073709551615"))
  @debug.assert_eq(
    d.last_accessed.reinterpret_as_uint64(),
    18446744073709551615UL,
  )
  @debug.assert_eq(d.score(1000L), 6.0)
  // a leading + is legal (Rust u64::from_str semantics)
  let d2 = expect_dir(parse_z_line("/a|1.5|+5"))
  @debug.assert_eq(d2.last_accessed, 5L)
  // overflowing u64 is a bad row
  expect_err(
    parse_z_line("/a|1.5|18446744073709551616"),
    "invalid entry: /a|1.5|18446744073709551616",
  )
}

///|
test "parse_autojump_line: the rank goes through sigmoid, last_accessed=0" {
  let d = expect_dir(parse_autojump_line("3.7\t/home/user"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, sigmoid(3.7))
  @debug.assert_eq(d.last_accessed, 0L)
}

///|
test "sigmoid: endpoints and monotonicity" {
  @debug.assert_eq(sigmoid(0.0), 0.5)
  assert_true(sigmoid(1.0) > 0.5 && sigmoid(1.0) < 1.0)
  assert_true(sigmoid(-1.0) > 0.0 && sigmoid(-1.0) < 0.5)
}

///|
test "parse_autojump_line: a path containing \t splits at the first \t (upstream split_once semantics)" {
  let d = expect_dir(parse_autojump_line("1.0\t/a\tb"))
  @debug.assert_eq(d.path, "/a\tb")
}

///|
test "parse_autojump_line: the bad-row family" {
  expect_err(parse_autojump_line("/a"), "invalid entry: /a")
  expect_err(
    parse_autojump_line("abc\t/a"),
    "invalid rank: abc: invalid float literal",
  )
  expect_err(
    parse_autojump_line("\t/a"),
    "invalid rank: : cannot parse float from empty string",
  )
}

///|
test "parse_atuin_line: the timestamp becomes a UTC epoch, rank=1.0" {
  let d = expect_dir(parse_atuin_line("2024-01-01 00:00:00\t/home/user"))
  @debug.assert_eq(d.path, "/home/user")
  @debug.assert_eq(d.rank, 1.0)
  // 2024-01-01T00:00:00Z
  @debug.assert_eq(d.last_accessed, 1704067200L)
}

///|
test "parse_atuin_line: the epoch boundary (1970-01-01 and 1969-12-31)" {
  let d = expect_dir(parse_atuin_line("1970-01-01 00:00:00\t/a"))
  @debug.assert_eq(d.last_accessed, 0L)
  let d2 = expect_dir(parse_atuin_line("1969-12-31 23:59:59\t/a"))
  @debug.assert_eq(d2.last_accessed, -1L)
}

///|
test "parse_atuin_line: leap days (2000-02-29 is a legal leap year; 1900 is not, and 2100 is not since century years need a 400)" {
  let d = expect_dir(parse_atuin_line("2000-02-29 12:00:00\t/a"))
  // 2000-02-29T12:00:00Z
  @debug.assert_eq(d.last_accessed, 951825600L)
  expect_err(
    parse_atuin_line("1900-02-29 00:00:00\t/a"),
    "invalid timestamp: \"1900-02-29 00:00:00\": day was not in range: day was not in range: day was not in range",
  )
}

///|
test "parse_atuin_line: a path with spaces and colons is kept as is" {
  let d = expect_dir(parse_atuin_line("2024-06-01 07:08:09\t/my dir:x"))
  @debug.assert_eq(d.path, "/my dir:x")
}

///|
test "parse_atuin_line: the bad-row family (no \t / out of range / a format error)" {
  expect_err(
    parse_atuin_line("2024-01-01 00:00:00"),
    "invalid entry: 2024-01-01 00:00:00",
  )
  expect_err(
    parse_atuin_line("2024-13-01 00:00:00\t/a"),
    "invalid timestamp: \"2024-13-01 00:00:00\": the 'month' component could not be parsed: the 'month' component could not be parsed",
  )
  expect_err(
    parse_atuin_line("2023-02-29 00:00:00\t/a"),
    "invalid timestamp: \"2023-02-29 00:00:00\": day was not in range: day was not in range: day was not in range",
  )
  expect_err(
    parse_atuin_line("2024-01-01 24:00:00\t/a"),
    "invalid timestamp: \"2024-01-01 24:00:00\": the 'hour' component could not be parsed: the 'hour' component could not be parsed",
  )
  expect_err(
    parse_atuin_line("2024-01-01 00:60:00\t/a"),
    "invalid timestamp: \"2024-01-01 00:60:00\": the 'minute' component could not be parsed: the 'minute' component could not be parsed",
  )
  expect_err(
    parse_atuin_line("2024-4-01 00:00:00\t/a"),
    "invalid timestamp: \"2024-4-01 00:00:00\": the 'month' component could not be parsed: the 'month' component could not be parsed",
  )
  expect_err(
    parse_atuin_line("2024/01/01 00:00:00\t/a"),
    "invalid timestamp: \"2024/01/01 00:00:00\": a character literal was not valid: a character literal was not valid",
  )
  expect_err(
    parse_atuin_line("2024-01-01T00:00:00\t/a"),
    "invalid timestamp: \"2024-01-01T00:00:00\": a character literal was not valid: a character literal was not valid",
  )
}

///|
test "days_from_civil: cross-checked against known epochs" {
  @debug.assert_eq(days_from_civil(1970, 1, 1), 0L)
  // 2024-01-01 -> 1704067200 / 86400 = 19723 days
  @debug.assert_eq(days_from_civil(2024, 1, 1), 19723L)
  // 2000-03-01 (the day after a leap day) -> 951868800 / 86400 = 11017 days
  @debug.assert_eq(days_from_civil(2000, 3, 1), 11017L)
  // 1969-12-31 -> -1 day
  @debug.assert_eq(days_from_civil(1969, 12, 31), -1L)
}

///|
/// Fold-test helper: a path -> a located entry (rank/time are invisible to folding, so placeholders are used)
fn loc(path : String) -> LocatedDir {
  {
    location: path,
    result: Ok({ path, rank: 1.0, last_accessed: 0L, note: None, }),
  }
}

///|
/// Fold-test helper: a bad-row entry
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
      result: Ok({ path: "/x", rank: 1.0, last_accessed: 0L, note: None, }),
    },
    {
      location: "line 2",
      result: Ok({ path: "/x", rank: 1.0, last_accessed: 5L, note: None, }),
    },
  ]
  let out = collapse_consecutive(items)
  @debug.assert_eq(out.length(), 1)
  @debug.assert_eq(out[0].location, "line 1")
  @debug.assert_eq(expect_dir(out[0].result).last_accessed, 0L)
}

///|
test "parse_autojump_line：坏 rank 消息带 Rust ParseFloatError 后缀（上游对拍）" {
  expect_err(
    parse_autojump_line("\t/a"),
    "invalid rank: : cannot parse float from empty string",
  )
}
