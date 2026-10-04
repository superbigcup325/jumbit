// 明文解码快路径测试：decode_plaintext_line_fast 与慢路径
// decode_plaintext_line 逐案例等价对拍（快路径 docstring 的数值等价依据在
// 此处落地为回归锁定），并断言 writer 形态确实命中快路径（防静默回落）。
// 路由入口 decode_plaintext 的行为面（错误文案/行级聚合）由既有黑盒套件
// 与 golden 覆盖，此处补单行全链对拍

///|
/// Dir 无 Eq：字段逐个断言
fn assert_fast_slow_eq(
  fast : Result[Dir?, String],
  slow : Result[Dir?, String],
) -> Unit raise {
  match (fast, slow) {
    (Ok(x), Ok(y)) =>
      match (x, y) {
        (Some(dx), Some(dy)) => {
          @debug.assert_eq(dx.path, dy.path)
          @debug.assert_eq(dx.rank, dy.rank)
          @debug.assert_eq(dx.last_accessed, dy.last_accessed)
        }
        (None, None) => ()
        _ => fail("Some/None 不一致")
      }
    (Err(ma), Err(mb)) => @debug.assert_eq(ma, mb)
    _ => fail("Ok/Err 不一致")
  }
}

///|
/// 路由入口（decode_plaintext）单行结果与慢路径一致
fn assert_routed_eq(bytes : Bytes, slow : Result[Dir?, String]) -> Unit raise {
  match decode_plaintext(bytes) {
    Ok(dirs) =>
      match slow {
        Ok(Some(d)) => {
          @debug.assert_eq(dirs.length(), 1)
          @debug.assert_eq(dirs[0].path, d.path)
          @debug.assert_eq(dirs[0].rank, d.rank)
          @debug.assert_eq(dirs[0].last_accessed, d.last_accessed)
        }
        Ok(None) => @debug.assert_eq(dirs.length(), 0)
        Err(msg) => fail("路由应报错: \{msg}")
      }
    Err(pe) =>
      match slow {
        Err(msg) => @debug.assert_eq(pe.message(), "line 1: \{msg}")
        _ => fail("路由不应报错")
      }
  }
}

///|
test "快路径命中 writer 形态且与慢路径等价（ts × rank 矩阵）" {
  let tss = ["1700000000", "0000000000", "9999999999", "0"]
  // 均为快路径适用形态（纯数字 ts + 整数/恰两位定点 rank，值 ≤ 2^53/100）
  let ranks = [
    "0.01", "0.10", "1.00", "5", "007", "697.78", "9999999.99", "00.00", "0000697.78",
    "123456789.99", "90071992547409.92", "10", "0",
  ]
  for ts in tss {
    for rk in ranks {
      let text = "\{ts} \{rk} /p/q"
      let bytes = @utf8.encode(text)
      let fast = decode_plaintext_line_fast(bytes, 0, bytes.length())
      match fast {
        Some(res) =>
          assert_fast_slow_eq(
            res,
            decode_plaintext_line(bytes, 0, bytes.length()),
          )
        None => fail("writer 形态应命中快路径: \{text}")
      }
    }
  }
}

///|
test "快路径路由单行全链与慢路径等价（边界/错误/回落形态扫界）" {
  // (行文本, 快路径是否命中)
  let cases : Array[(String, Bool)] = [
    // 空行族：空格/tab 直接判空（快路径命中），其余空白形态回落
    ("", true),
    ("   ", true),
    ("\t\t", true),
    ("1700000000 5 /p\r", true), // 行尾 CR 剥离
    // 定点边界：恰 2 位才快路径；超 2^53 回落
    ("1700000000 5.0 /p", false),
    ("1700000000 1.234 /p", false),
    ("1700000000 1.2 /p", false),
    ("1700000000 90071992547409.93 /p", false),
    ("1700000000 99999999999999.99 /p", false),
    ("1700000000 0.001 /p", false),
    // 非数字段回落（符号/指数/inf/nan：parse_f64 语义面）
    ("1700000000 1e3 /p", false),
    ("1700000000 -3.5 /p", false),
    ("1700000000 +5 /p", false),
    ("1700000000 inf /p", false),
    ("1700000000 nan /p", false),
    ("-1 5 /p", false), // 负 timestamp（atuin 边界行）
    ("+9 5 /p", false),
    ("abc 5 /p", false),
    ("1700000000 abc /p", false),
    ("1700000000 123abc /p", false), // 段尾非空白
    // 结构错误与空 path（缺 path 时快路径直接给出同文案 EXPECTED）
    ("1700000000 5", true),
    ("1700000000 5 ", true),
    // Unicode path（快路径命中，path 段 UTF-8 校验）
    ("1700000000 5 /tmp/α β/中文目录", true),
    ("1700000000 5 /p", true),
  ]
  for (text, fast_expected) in cases {
    let bytes = @utf8.encode(text)
    let slow = decode_plaintext_line(bytes, 0, bytes.length())
    let fast = decode_plaintext_line_fast(bytes, 0, bytes.length())
    match (fast, fast_expected) {
      (Some(res), true) => assert_fast_slow_eq(res, slow)
      (Some(_), false) => fail("应回落慢路径: \{text}")
      (None, true) => fail("应命中快路径: \{text}")
      (None, false) => ()
    }
    assert_routed_eq(bytes, slow)
  }
}

///|
test "快路径空行判定与慢路径一致（VT/FF 形态回落由 trim 语义定夺）" {
  // 纯 VT 行：快路径不判空（回落），慢路径 trim 语义决定结果
  let vt = @utf8.encode("\u{b}")
  let slow = decode_plaintext_line(vt, 0, vt.length())
  match decode_plaintext_line_fast(vt, 0, vt.length()) {
    Some(_) => fail("纯 VT 行不应命中快路径")
    None => ()
  }
  assert_routed_eq(vt, slow)
}
