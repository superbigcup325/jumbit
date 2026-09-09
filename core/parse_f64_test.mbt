// parse_f64：Rust f64::from_str 兼容语义锁定（rustc + zoxide 0.10.0 探针实测）

///|
/// 取 Ok 值或 fail
fn f64_ok(r : Result[Double, Unit]) -> Double raise {
  match r {
    Ok(v) => v
    Err(_) => fail("expected ok")
  }
}

///|
/// 断言 Err
fn f64_err(r : Result[Double, Unit]) -> Unit raise {
  match r {
    Ok(_) => fail("expected err")
    Err(_) => ()
  }
}

///|
test "parse_f64：特殊字面量大小写不敏感、符号可选" {
  assert_true(f64_ok(@core.parse_f64("inf")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("Infinity")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("INF")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("+inf")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("-inf")).is_neg_inf())
  assert_true(f64_ok(@core.parse_f64("-INFINITY")).is_neg_inf())
  assert_true(f64_ok(@core.parse_f64("nan")).is_nan())
  assert_true(f64_ok(@core.parse_f64("NaN")).is_nan())
  assert_true(f64_ok(@core.parse_f64("-nan")).is_nan())
}

///|
test "parse_f64：nan 为正 NaN（符号位为 0）" {
  // 0.0/0.0 会被 MoonBit 编译期折叠成负 NaN（符号位 1，totalOrder 最小值，
  // total_cmp 排序位置随之翻转）；Rust "nan".parse() 是正 NaN。payload 位
  // 不承载语义（MoonBit 运行时为 0x7FF8000000000001），只锁符号位
  let nan = f64_ok(@core.parse_f64("nan"))
  assert_true(nan.is_nan() && nan.reinterpret_as_uint64() >> 63 == 0UL)
}

///|
test "parse_f64：常规语法（+/.5/5./前导零/指数）" {
  @debug.assert_eq(f64_ok(@core.parse_f64("+1.5")), 1.5)
  @debug.assert_eq(f64_ok(@core.parse_f64(".5")), 0.5)
  @debug.assert_eq(f64_ok(@core.parse_f64("5.")), 5.0)
  @debug.assert_eq(f64_ok(@core.parse_f64("007")), 7.0)
  @debug.assert_eq(f64_ok(@core.parse_f64("-2.5")), -2.5)
  @debug.assert_eq(f64_ok(@core.parse_f64("1e+5")), 100000.0)
  @debug.assert_eq(f64_ok(@core.parse_f64("1E5")), 100000.0)
  @debug.assert_eq(f64_ok(@core.parse_f64("1e-2")), 0.01)
}

///|
test "parse_f64：溢出饱和 ±inf（parse_double 报错处）" {
  // E ≥ 309 直接取 inf
  assert_true(f64_ok(@core.parse_f64("1e400")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("1e309")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("1.8e308")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("-1e400")).is_neg_inf())
  // 超长指数饱和累计后同为溢出（Rust 亦为 inf）
  assert_true(f64_ok(@core.parse_f64("1e99999999999999999999")).is_pos_inf())
  // E == 308 分界带：parse_double 能表则有限
  @debug.assert_eq(
    f64_ok(@core.parse_f64("1.7976931348623157e308")),
    @string.parse_double("1.7976931348623157e308"),
  )
  @debug.assert_eq(
    f64_ok(@core.parse_f64("9e307")),
    @string.parse_double("9e307"),
  )
}

///|
test "parse_f64：下溢饱和与带符号零" {
  @debug.assert_eq(f64_ok(@core.parse_f64("1e-400")), 0.0)
  let nz = f64_ok(@core.parse_f64("-0.0"))
  assert_true(nz == 0.0 && (1.0 / nz).is_neg_inf())
  let pz = f64_ok(@core.parse_f64("0"))
  assert_true(pz == 0.0 && (1.0 / pz).is_pos_inf())
}

///|
test "parse_f64：语法拒绝（下划线/空白/悬空指数/十六进制/残缺）" {
  f64_err(@core.parse_f64("1_000"))
  f64_err(@core.parse_f64(" 1.5"))
  f64_err(@core.parse_f64("1.5 "))
  f64_err(@core.parse_f64("1e"))
  f64_err(@core.parse_f64("e5"))
  f64_err(@core.parse_f64("0x10"))
  f64_err(@core.parse_f64("+."))
  f64_err(@core.parse_f64("."))
  f64_err(@core.parse_f64("+"))
  f64_err(@core.parse_f64("-"))
  f64_err(@core.parse_f64(""))
  f64_err(@core.parse_f64("1.5x"))
  f64_err(@core.parse_f64("１.５"))
}
