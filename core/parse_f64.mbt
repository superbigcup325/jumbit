///|
/// Float parsing compatible with Rust\'s `f64::from_str` (shared by the rank and `--score` numeric surfaces).
/// Semantics match Rust std item by item (probed with rustc and zoxide 0.10.0 on 2026-09-09):
/// - the special literals are case-insensitive: inf / infinity / nan, each with an optional leading sign;
///   nan and inf are constructed at run time through parse_double -- MoonBit folds 0.0/0.0 at compile time into
///   a negative NaN, whose bit pattern differs from Rust\'s +NaN and flips the sort position under total_cmp
/// - grammar `[+-]?( digits [. digits?] | . digits )( [eE] [+-]? digits )?`;
///   underscores, surrounding whitespace and hexadecimal are not accepted (@string.parse_double allows underscores
///   and errors on overflow rather than saturating, so it cannot be delegated to directly)
/// - overflow saturates to ±inf: branched on the adjusted decimal exponent E (value in [10^E, 10^(E+1))) --
///   E <= 307 must be finite and goes straight to parse_double; E >= 309 must overflow to ±inf;
///   E == 308 is left to parse_double (its error threshold sits at the same place as the rounding-overflow threshold,
///   so a theoretical deviation exists only in the half-ulp band around f64::MAX)
/// - underflow saturates to ±0 as parse_double does; a zero keeps its sign ("-0.0" -> -0.0)
pub fn parse_f64(s : StringView) -> Result[Double, Unit] {
  let n = s.length()
  if n == 0 {
    return Err(())
  }
  let neg = s[0] == 45 // '-'
  let mut i = 0
  if s[0] == 43 || s[0] == 45 { // '+' '-'
    i = 1
  }
  // special literals (case-insensitive): infinity / inf / nan
  if i < n && eq_lower_ascii(s, i, "infinity") {
    return Ok(f64_inf(neg))
  }
  if i < n && eq_lower_ascii(s, i, "inf") {
    return Ok(f64_inf(neg))
  }
  if i < n && eq_lower_ascii(s, i, "nan") {
    return Ok(f64_nan())
  }
  // the significand: an integer part [. a fraction part]
  let int_start = i
  while i < n && s[i] >= 48 && s[i] <= 57 {
    i += 1
  }
  let int_digits = i - int_start
  let mut frac_digits = 0
  let mut frac_start = 0
  if i < n && s[i] == 46 { // '.'
    i += 1
    frac_start = i
    while i < n && s[i] >= 48 && s[i] <= 57 {
      i += 1
    }
    frac_digits = i - frac_start
  }
  if int_digits + frac_digits == 0 {
    return Err(()) // "+"/"-"/"."/"e5" and the like carry no digits
  }
  // the exponent (a dangling one errors; an overlong one saturates the accumulator to avoid Int overflow, and only 309 is needed)
  let mut exp = 0
  if i < n && (s[i] == 101 || s[i] == 69) { // e E
    i += 1
    let mut exp_sign = 1
    if i < n && (s[i] == 43 || s[i] == 45) {
      if s[i] == 45 {
        exp_sign = -1
      }
      i += 1
    }
    let exp_start = i
    while i < n && s[i] >= 48 && s[i] <= 57 {
      i += 1
    }
    if i == exp_start {
      return Err(())
    }
    let mut v = 0
    for j in exp_start..<i {
      if v <= 100000 {
        v = v * 10 + (s[j].to_int() - 48)
      }
    }
    exp = exp_sign * v
  }
  if i != n {
    return Err(()) // trailing debris (underscore / space / an illegal letter)
  }
  // the adjusted decimal exponent: located at the first non-zero digit (start of the integer part / start of the fraction)
  let mut found = false
  let mut adj_exp = 0
  for k in 0..<int_digits {
    if s[int_start + k] != 48 {
      adj_exp = int_digits - 1 - k + exp
      found = true
      break
    }
  }
  if !found {
    for j in 0..<frac_digits {
      if s[frac_start + j] != 48 {
        adj_exp = exp - j - 1
        found = true
        break
      }
    }
  }
  if !found {
    // all zeros: keep the sign (Rust\'s "-0.0".parse() -> -0.0)
    return Ok(if neg { -0.0 } else { 0.0 })
  }
  if adj_exp >= 309 {
    return Ok(f64_inf(neg))
  }
  if adj_exp <= 307 {
    let v = @string.parse_double(s) catch { _ => return Err(()) }
    return Ok(v)
  }
  // adj_exp == 308: the boundary band between finite and overflow
  let v = @string.parse_double(s) catch { _ => return Ok(f64_inf(neg)) }
  Ok(v)
}

///|
/// Construct ±inf at run time (bit patterns matching Rust; the folded 1.0/0.0 value was measured to have the right sign,
/// so everything goes through parse_double to drop the dependency on folding)
fn f64_inf(neg : Bool) -> Double {
  let p = @string.parse_double("inf") catch { _ => 1.0 / 0.0 }
  if neg {
    -p
  } else {
    p
  }
}

///|
/// Construct +NaN at run time: 0.0/0.0 folds at compile time into a negative NaN (the totalOrder minimum, which
/// flips the sort position), so parse_double is required to get Rust\'s positive NaN
fn f64_nan() -> Double {
  @string.parse_double("nan") catch {
    _ => 0.0 / 0.0
  }
}

///|
/// Compare the remaining string against a lowercase ASCII literal code unit by code unit (for the inf/nan literals)
fn eq_lower_ascii(s : StringView, from : Int32, lit : String) -> Bool {
  if s.length() - from != lit.length() {
    return false
  }
  for k in 0..<lit.length() {
    let c = s[from + k].to_int()
    let lc = if c >= 65 && c <= 90 { c + 32 } else { c }
    if lc != lit[k].to_int() {
      return false
    }
  }
  true
}
