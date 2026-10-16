// parse_f64: pinning the Rust f64::from_str-compatible semantics (probed with rustc + zoxide 0.10.0)

///|
/// Take the Ok value or fail
fn f64_ok(r : Result[Double, Unit]) -> Double raise {
  match r {
    Ok(v) => v
    Err(_) => fail("expected ok")
  }
}

///|
/// Assert Err
fn f64_err(r : Result[Double, Unit]) -> Unit raise {
  match r {
    Ok(_) => fail("expected err")
    Err(_) => ()
  }
}

///|
test "parse_f64: the special literals are case-insensitive with an optional sign" {
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
test "parse_f64: nan is a positive NaN (sign bit 0)" {
  // 0.0/0.0 folds at compile time into a negative NaN (sign bit 1, the totalOrder minimum,
  // flipping its total_cmp sort position), while Rust\'s "nan".parse() is a positive NaN. Payload bits
  // carry no semantics (the runtime\'s is 0x7FF8000000000001), so only the sign bit is pinned
  let nan = f64_ok(@core.parse_f64("nan"))
  assert_true(nan.is_nan() && nan.reinterpret_as_uint64() >> 63 == 0UL)
}

///|
test "parse_f64: ordinary grammar (+/.5/5./leading zeros/exponents)" {
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
test "parse_f64: overflow saturates to ±inf (where parse_double errors)" {
  // E >= 309 takes inf directly
  assert_true(f64_ok(@core.parse_f64("1e400")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("1e309")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("1.8e308")).is_pos_inf())
  assert_true(f64_ok(@core.parse_f64("-1e400")).is_neg_inf())
  // an overlong exponent saturates the accumulator and is an overflow too (Rust gives inf as well)
  assert_true(f64_ok(@core.parse_f64("1e99999999999999999999")).is_pos_inf())
  // E == 308 is the boundary band: finite when parse_double can represent it
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
test "parse_f64: underflow saturation and signed zero" {
  @debug.assert_eq(f64_ok(@core.parse_f64("1e-400")), 0.0)
  let nz = f64_ok(@core.parse_f64("-0.0"))
  assert_true(nz == 0.0 && (1.0 / nz).is_neg_inf())
  let pz = f64_ok(@core.parse_f64("0"))
  assert_true(pz == 0.0 && (1.0 / pz).is_pos_inf())
}

///|
test "parse_f64: grammar rejections (underscores/whitespace/a dangling exponent/hex/incomplete)" {
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
