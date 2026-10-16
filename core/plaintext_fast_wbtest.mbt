// Plaintext decode fast-path tests: decode_plaintext_line_fast against the slow path
// decode_plaintext_line case by case (the numeric-equivalence basis in the fast path\'s docstring lands here as
// a regression pin), plus an assertion that the writer shape really hits the fast path (guarding against a silent fallback).
// The routing entry decode_plaintext\'s behaviour (error wording / line-level aggregation) is covered by the existing
// blackbox suite and the goldens; here a single-line full-chain comparison is added

///|
/// Dir has no Eq, so the fields are asserted one by one
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
        _ => fail("Some/None disagree")
      }
    (Err(ma), Err(mb)) => @debug.assert_eq(ma, mb)
    _ => fail("Ok/Err disagree")
  }
}

///|
/// The routing entry (decode_plaintext) gives the same single-line result as the slow path
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
        Err(msg) => fail("the router should error: \{msg}")
      }
    Err(pe) =>
      match slow {
        Err(msg) => @debug.assert_eq(pe.message(), "line 1: \{msg}")
        _ => fail("the router should not error")
      }
  }
}

///|
test "the fast path hits the writer shape and equals the slow path (a ts x rank matrix)" {
  let tss = ["1700000000", "0000000000", "9999999999", "0"]
  // all in a fast-path shape (a plain-digit ts plus an integer or exactly-two-decimal rank, values <= 2^53/100)
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
        None => fail("the writer shape should hit the fast path: \{text}")
      }
    }
  }
}

///|
test "the fast path\'s single-line full chain equals the slow path (sweeping the boundary/error/fallback shapes)" {
  // (line text, whether the fast path hits)
  let cases : Array[(String, Bool)] = [
    // the blank-line family: spaces/tabs read as empty directly (the fast path hits), other whitespace shapes fall back
    ("", true),
    ("   ", true),
    ("\t\t", true),
    ("1700000000 5 /p\r", true), // a trailing CR is stripped
    // the fixed-point boundary: exactly two decimals hit the fast path; beyond 2^53 falls back
    ("1700000000 5.0 /p", false),
    ("1700000000 1.234 /p", false),
    ("1700000000 1.2 /p", false),
    ("1700000000 90071992547409.93 /p", false),
    ("1700000000 99999999999999.99 /p", false),
    ("1700000000 0.001 /p", false),
    // a non-numeric field falls back (sign/exponent/inf/nan: the parse_f64 semantic surface)
    ("1700000000 1e3 /p", false),
    ("1700000000 -3.5 /p", false),
    ("1700000000 +5 /p", false),
    ("1700000000 inf /p", false),
    ("1700000000 nan /p", false),
    ("-1 5 /p", false), // a negative timestamp (an atuin boundary row)
    ("+9 5 /p", false),
    ("abc 5 /p", false),
    ("1700000000 abc /p", false),
    ("1700000000 123abc /p", false), // a field not ending in whitespace
    // structural errors and an empty path (with no path the fast path gives the same EXPECTED wording)
    ("1700000000 5", true),
    ("1700000000 5 ", true),
    // a Unicode path (the fast path hits; the path field is UTF-8 validated)
    ("1700000000 5 /tmp/α β/中文目录", true),
    ("1700000000 5 /p", true),
  ]
  for (text, fast_expected) in cases {
    let bytes = @utf8.encode(text)
    let slow = decode_plaintext_line(bytes, 0, bytes.length())
    let fast = decode_plaintext_line_fast(bytes, 0, bytes.length())
    match (fast, fast_expected) {
      (Some(res), true) => assert_fast_slow_eq(res, slow)
      (Some(_), false) => fail("should fall back to the slow path: \{text}")
      (None, true) => fail("should hit the fast path: \{text}")
      (None, false) => ()
    }
    assert_routed_eq(bytes, slow)
  }
}

///|
test "the fast path\'s blank-line test matches the slow path (VT/FF shapes fall back, decided by trim semantics)" {
  // a pure VT line: the fast path does not call it empty (it falls back), and the slow path\'s trim semantics decide
  let vt = @utf8.encode("\u{b}")
  let slow = decode_plaintext_line(vt, 0, vt.length())
  match decode_plaintext_line_fast(vt, 0, vt.length()) {
    Some(_) => fail("a pure VT line should not hit the fast path")
    None => ()
  }
  assert_routed_eq(vt, slow)
}
