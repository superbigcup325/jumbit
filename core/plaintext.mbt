///|
/// The plaintext database format (matching upstream ajeetdsouza/zoxide#1288\'s src/db/mod.rs,
/// read line by line against the source on 2026-09-22; spec in docs/spec-plaintext-edit.md §1.1):
/// each line is `<timestamp>\t<rank>\t<path>`: the timestamp is 10 zero-padded epoch seconds,
/// rank is zero-padded fixed-point with two decimals and clamped to [MIN_RANK, MAX_RANK] on serialize, and the path is
/// everything left on the line (only leading whitespace is stripped -- the same as upstream\'s deserialize, so a path with
/// leading whitespace loses it in a round trip, which is upstream semantics; noted in the README\'s differences list)

///|
/// The column width (the zero-padding width for timestamp and rank; upstream COL_WIDTH=10)
const PLAINTEXT_COL_WIDTH : Int32 = 10

///|
/// The line-level error aggregate cap: at most 8 lines are listed, and beyond that they fold to "... and N more"
/// (matching upstream deserialize\'s MAX_ERRORS=8)
const PLAINTEXT_MAX_ERRORS : Int32 = 8

///|
/// A plaintext decode line-level error (aggregated at the end of the decode, rejecting the whole database; matching upstream\'s errors collection).
/// lines is the display surface: decode_plaintext has already truncated to PLAINTEXT_MAX_ERRORS
pub(all) struct PlaintextError {
  lines : Array[String]
} derive(Debug)

///|
/// The aggregate wording joins the lines with newlines (matching the multi-line stderr shape of upstream errors.join("\n"))
pub fn PlaintextError::message(self : PlaintextError) -> String {
  let sb = StringBuilder()
  for i, line in self.lines {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(line)
  }
  sb.to_string()
}

///|
/// Exact decimal formatting of a rank to two decimals (Rust `{:.2}` semantics: round decimally against the double\'s exact
/// binary value, with half-to-even on the boundary).
///
/// Implementation: x = mant x 2^(unbiased-52) (a 53-bit mantissa with an implicit leading one);
/// the integer and fractional parts of x x 100 come from pure UInt64 integer shifts (after the rank domain is clamped,
/// the shift is <= 59 and M x 100 < 2^60, so no floating-point rounding occurs anywhere); the fraction is compared against
/// the half boundary to carry, with half-to-even on an exact tie.
///
/// WARNING: do not scale with a `x * 100.0` binary multiply -- the product\'s own rounding flips values near the half boundary
/// (proved by probe: 2.675 x100 lands exactly on 267.5 and wrongly carries to 2.68, where 2.67 is correct;
/// and 999.995\'s exact value is slightly above the half boundary, correctly carrying to 1000.00). A half-boundary battery
/// plus a 20000-value comparison (Python\'s f"{:.2f}" = Rust\'s {:.2}, both correctly rounded) went all green on 2026-09-22
fn plaintext_fmt_rank(rank : Double) -> String {
  let bits = rank.reinterpret_as_uint64()
  let biased = (bits >> 52).to_int() & 0x7FF
  let frac52 = bits & 0x000FFFFFFFFFFFFFUL
  let unbiased = biased - 1023
  let mant = frac52 + 0x0010000000000000UL // the implicit leading one of the 53-bit mantissa
  let pair : (UInt64, UInt64, UInt64) = if unbiased >= 52 {
    // after the rank clamp this is < 2^24 so this branch is unreachable; defensive: a direct integer multiply with no fraction
    ((mant * 100UL) << (unbiased - 52), 0UL, 1UL)
  } else {
    let shift = 52 - unbiased
    let m100 = mant * 100UL
    (m100 >> shift, m100 & ((1UL << shift) - 1UL), (1UL << shift) - 1UL)
  }
  let q = pair.0
  let rem = pair.1
  let mask = pair.2
  // the half boundary = (mask+1)/2: compare rem x2 against mask+1; an exact tie (rem x2 == mask+1) rounds to even
  let twice = rem * 2UL
  let carry = if twice > mask + 1UL {
    true
  } else if twice == mask + 1UL {
    q % 2UL == 1UL
  } else {
    false
  }
  let scaled = q + (if carry { 1UL } else { 0UL })
  let int_part = (scaled / 100UL).to_string()
  let dec = (scaled % 100UL).to_string()
  int_part + "." + (if dec.length() == 1 { "0" + dec } else { dec })
}

///|
/// Zero-pad a number to the given width (upstream `{:0COL_WIDTH$}`; over-wide stays as is -- from the year 2286 epoch is
/// 11 digits, and upstream {:010} does not truncate either, so the behaviour matches)
fn plaintext_pad10(n : Int64) -> String {
  // negatives match Rust `{:010}`: the sign first, zero padding after ("-1" -> "-000000001");
  // i64::MIN overflows on negation, so it passes through as is (over-wide, no padding, as Rust does)
  if n < 0 {
    let s = n.to_string()
    let digits = s[1:].to_owned()
    if digits.length() >= PLAINTEXT_COL_WIDTH {
      s
    } else {
      "-" + plaintext_pad_str(digits)
    }
  } else {
    plaintext_pad_str(n.to_string())
  }
}

///|
/// Zero-pad a string to the column width (over-wide stays as is)
fn plaintext_pad_str(s : String) -> String {
  if s.length() >= PLAINTEXT_COL_WIDTH {
    s
  } else {
    String::make(PLAINTEXT_COL_WIDTH - s.length(), '0') + s
  }
}

///|
/// Plaintext serialization: each line is `timestamp\trank\tpath\n` (the same structure as upstream\'s serialize;
/// pre-allocation is skipped -- a single StringBuilder pass is already linear).
///
/// A NaN rank goes to RANK_MIN: upstream already rejects NaN through deserialize_line so it never reaches
/// this state; jumbit\'s legacy bincode decode does not reject it, so the plaintext migration falls back to the lowest weight
/// (rescue semantics, spec §1.3) -- which is how the CHANGELOG\'s known issue (the non-finite poison) was closed out
pub fn encode_plaintext(dirs : Array[Dir]) -> Bytes {
  let sb = StringBuilder()
  for dir in dirs {
    // an empty-path entry is skipped: the plaintext line format cannot express it (an empty-path line is rejected on decode,
    // so writing one would make the database permanently unreadable -- upstream #1288 does not address this self-lock). The migration\'s
    // rescue semantics are the same family as NaN going to the floor (spec §1.3). An empty path can come only from chaos data (add rejects one)
    if dir.path.is_empty() {
      continue
    }
    let rank = if dir.rank.is_nan() {
      RANK_MIN
    } else {
      dir.rank.clamp(min=RANK_MIN, max=RANK_MAX)
    }
    sb.write_string(plaintext_pad10(dir.last_accessed))
    sb.write_char('\t')
    sb.write_string(plaintext_pad_str(plaintext_fmt_rank(rank)))
    sb.write_char('\t')
    sb.write_string(dir.path)
    sb.write_char('\n')
  }
  @utf8.encode(sb.to_string())
}

///|
/// Parse i64 decimal text (a subset of Rust i64::from_str semantics): an optional single +/-,
/// all remaining characters digits (leading zeros legal), the domain [i64::MIN, i64::MAX]; empty/garbage/overflow rejected
fn plaintext_parse_i64(s : String) -> Result[Int64, Unit] {
  let n = s.length()
  if n == 0 {
    return Err(())
  }
  let mut i = 0
  let neg = s[0] == 45 // '-'
  if s[0] == 43 || s[0] == 45 { // '+' '-'
    i += 1
  }
  if i >= n {
    return Err(())
  }
  // the digit cap: i64 decimal is at most 20 digits (the sign counted separately); anything longer must overflow, so reject early
  if n - i > 20 {
    return Err(())
  }
  let mut v : UInt64 = 0
  while i < n {
    let c = s[i]
    if c < 48 || c > 57 {
      return Err(())
    }
    v = v * 10UL + (c - 48).to_uint64()
    i += 1
  }
  let limit : UInt64 = if neg {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  if v > limit {
    return Err(())
  }
  if neg {
    // -0 -> 0; two\'s-complement negation is safe (v <= 2^63)
    Ok(if v == 0UL { 0L } else { (0UL - v).reinterpret_as_int64() })
  } else {
    Ok(v.reinterpret_as_int64())
  }
}

///|
/// An in-line ASCII whitespace test (matching the ASCII subset of Rust char::is_whitespace:
/// 0x09 tab, 0x0A LF (already consumed by the line split), 0x0B, 0x0C, 0x0D CR, 0x20 space;
/// Unicode whitespace classes are not recognised -- a path containing U+00A0 and the like is pathological, noted in the README)

///|
/// The shared wording for a missing-column error (upstream deserialize_line\'s EXPECTED)
const PLAINTEXT_EXPECTED : String = "expected: <timestamp> <rank> <path>"

///|
fn plaintext_is_ws(b : UInt16) -> Bool {
  b == 32 || b == 9 || (b >= 11 && b <= 13)
}

///|
/// Single-line decode (isomorphic to upstream deserialize_line): UTF-8 validation -> strip a trailing CR -> a blank line
/// is skipped (Ok(None)) -> after trim_start, cut twice at the first whitespace to get timestamp/rank/path ->
/// parse the numbers, reject NaN and clamp. The path field then has its leading whitespace stripped too (upstream path.trim_start()).
/// The error wording matches upstream word for word ("could not parse timestamp/rank: X",
/// "expected: <timestamp> <rank> <path>"、"invalid UTF-8"）
fn decode_plaintext_line(
  bytes : Bytes,
  start : Int32,
  end : Int32,
) -> Result[Dir?, String] {
  // UTF-8 validation and decode (an illegal byte -> a line-level error, upstream str::from_utf8 context)
  let line : String = @utf8.decode(bytes[start:end]) catch {
    _ => return Err("invalid UTF-8")
  }
  // strip a trailing CR (CRLF tolerated; upstream strip_suffix('\r'))
  let line = if line.has_suffix("\r") {
    line[0:line.length() - 1].to_owned()
  } else {
    line
  }
  // a blank line is skipped (upstream line.trim().is_empty() -> Ok(None))
  if line.trim().is_empty() {
    return Ok(None)
  }
  // after trim_start (upstream line.trim_start()), cut at the first whitespace
  let n = line.length()
  let mut i = 0
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // field one: the timestamp
  let ts_start = i
  while i < n && !plaintext_is_ws(line[i]) {
    i += 1
  }
  if i >= n {
    return Err(PLAINTEXT_EXPECTED)
  }
  let ts_str = line[ts_start:i].to_owned()
  // skip the separator
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // field two: the rank
  let rank_start = i
  while i < n && !plaintext_is_ws(line[i]) {
    i += 1
  }
  if i >= n {
    return Err(PLAINTEXT_EXPECTED)
  }
  let rank_str = line[rank_start:i].to_owned()
  // skip the separator
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // field three: the path (upstream path.trim_start(); leading whitespace is already covered by the separator skip above)
  let path = line[i:n].to_owned()
  if path.is_empty() {
    return Err(PLAINTEXT_EXPECTED)
  }
  // the timestamp: Rust i64::from_str semantics (an optional +/-, leading zeros legal, overflow rejected --
  // upstream parse::<Epoch>; the atuin dataset holds an epoch=-1 boundary row, so it must round-trip)
  let last_accessed = match plaintext_parse_i64(ts_str) {
    Ok(v) => v
    Err(_) => return Err("could not parse timestamp: \{ts_str}")
  }
  // the rank: Rust f64::from_str semantics (the inf/nan literals parse) -> NaN rejected
  // (upstream\'s clamp returning NaN then bailing on isnan is equivalent) -> clamp the domain
  let rank = match parse_f64(rank_str) {
    Ok(v) => v
    Err(_) => return Err("could not parse rank: \{rank_str}")
  }
  if rank.is_nan() {
    return Err("could not parse rank: \{rank_str}")
  }
  let rank = rank.clamp(min=RANK_MIN, max=RANK_MAX)
  Ok(Some({ path, rank, last_accessed, note: None, }))
}

///|
/// An in-line byte whitespace test (the same set as plaintext_is_ws applied to bytes: all ASCII, so a byte is a code unit)
fn plaintext_is_ws_byte(b : Byte) -> Bool {
  let c = b.to_int()
  c == 32 || c == 9 || (c >= 11 && c <= 13)
}

///|
/// The line-level fast path: for a shape encode_plaintext produces (a plain-digit timestamp of <=18 digits, and a rank
/// that is plain digits or "digits.exactly 2 decimals" fixed-point) it parses the bytes directly, skipping the whole-line UTF-8
/// decode and parse_f64 (the hot section of every full query load). None means the shape does not apply (a sign / an
/// exponent / inf / nan / other whitespace / bad structure), and the caller falls back to decode_plaintext_line, whose
/// error wording and precedence (whole-line UTF-8 before field parsing) the slow path guarantees as is. The blank-line test
/// calls only spaces and tabs empty directly (the intersection trim always strips); other whitespace shapes go to the slow path.
/// The numeric bit-level equivalence basis: for k <= 2^53 the Int64->Double conversion is exact, and N/100.0 is a single IEEE
/// division (correctly rounded), agreeing with parse_f64\'s round-to-nearest-even on the same fixed-point decimal
fn decode_plaintext_line_fast(
  bytes : Bytes,
  start : Int32,
  end : Int32,
) -> Result[Dir?, String]? {
  // a trailing CR is stripped (as on the slow path, before the blank-line test)
  let e = if end > start && bytes[end - 1] == 0x0D { end - 1 } else { end }
  // skip leading whitespace; if the whole line is consumed, the blank-line test accepts only spaces/tabs (other shapes fall back)
  let mut i = start
  let mut only_std_ws = true
  while i < e {
    let b = bytes[i]
    if b == 32 || b == 9 {
      i += 1
    } else if plaintext_is_ws_byte(b) {
      only_std_ws = false
      i += 1
    } else {
      break
    }
  }
  if i >= e {
    if only_std_ws {
      return Some(Ok(None))
    }
    return None
  }
  // the timestamp: a plain-digit field (<=18 digits cannot overflow Int64, and leading zeros are legal as in from_str)
  let ts_start = i
  let mut ts : Int64 = 0L
  while i < e {
    let c = bytes[i].to_int()
    if c >= 48 && c <= 57 {
      ts = ts * 10L + (c - 48).to_int64()
      i += 1
    } else {
      break
    }
  }
  let ts_len = i - ts_start
  if ts_len == 0 || ts_len > 18 || i >= e || !plaintext_is_ws_byte(bytes[i]) {
    return None
  }
  while i < e && plaintext_is_ws_byte(bytes[i]) {
    i += 1
  }
  // the rank: an integer or "integer.exactly 2 decimals" fixed-point; an integer field over 16 digits (guarding against a x100 overflow)
  // or a value past 2^53 falls back
  let r_start = i
  let mut k : Int64 = 0L
  while i < e && i - r_start < 16 {
    let c = bytes[i].to_int()
    if c >= 48 && c <= 57 {
      k = k * 10L + (c - 48).to_int64()
      i += 1
    } else {
      break
    }
  }
  if i == r_start ||
    (i < e && bytes[i].to_int() >= 48 && bytes[i].to_int() <= 57) {
    return None // the field is empty, or an integer field over 16 digits was truncated
  }
  // N = the integer field x100 + the two decimals (k <= 16 digits -> k x100 <= ~1e18, safe in Int64)
  let mut n : Int64 = k * 100L
  if i < e && bytes[i] == 46 {
    // '.': only exactly 2 decimals take the fast path
    i += 1
    let mut f : Int64 = 0L
    let mut fd = 0
    while fd < 2 && i < e {
      let c = bytes[i].to_int()
      if c >= 48 && c <= 57 {
        f = f * 10L + (c - 48).to_int64()
        i += 1
        fd += 1
      } else {
        break
      }
    }
    if fd != 2 {
      return None
    }
    n = n + f
  }
  if i < e && !plaintext_is_ws_byte(bytes[i]) {
    return None
  }
  if n > 9007199254740992L {
    return None
  }
  while i < e && plaintext_is_ws_byte(bytes[i]) {
    i += 1
  }
  if i >= e {
    return Some(Err(PLAINTEXT_EXPECTED)) // an empty path (the same wording as the slow path)
  }
  // UTF-8 validation covers only the path field: ts and rank are already limited to ASCII digits, so validating the whole line
  // would not differ from the slow path (non-ASCII must land in the path field or trigger a fallback)
  let path : String = @utf8.decode(bytes[i:e]) catch {
    _ => return Some(Err("invalid UTF-8"))
  }
  let rank = (n.to_double() / 100.0).clamp(min=RANK_MIN, max=RANK_MAX)
  Some(Ok(Some({ path, rank, last_accessed: ts, note: None, })))
}

///|
/// Plaintext deserialization: split on 0x0A and decode line by line, with line numbers from 1; all line-level errors are collected and,
/// if any exist, the whole database is rejected with at most PLAINTEXT_MAX_ERRORS listed and the rest folded into
/// "... and N more" (matching upstream deserialize)
pub fn decode_plaintext(bytes : Bytes) -> Result[Array[Dir], PlaintextError] {
  let dirs : Array[Dir] = []
  let errors : Array[String] = []
  let n = bytes.length()
  let mut start = 0
  let mut line_no = 0
  while start <= n {
    let mut end = start
    while end < n && bytes[end] != 0x0A {
      end += 1
    }
    line_no += 1
    // the fast path goes first (the shape encode produces); an inapplicable shape falls back to the slow path
    let line = match decode_plaintext_line_fast(bytes, start, end) {
      Some(res) => res
      None => decode_plaintext_line(bytes, start, end)
    }
    match line {
      Ok(Some(dir)) => dirs.push(dir)
      Ok(None) => ()
      Err(msg) => errors.push("line \{line_no}: \{msg}")
    }
    if end >= n {
      break
    }
    start = end + 1
  }
  if errors.is_empty() {
    Ok(dirs)
  } else {
    let shown = if errors.length() > PLAINTEXT_MAX_ERRORS {
      let rest = errors.length() - PLAINTEXT_MAX_ERRORS
      let head = errors[0:PLAINTEXT_MAX_ERRORS].to_owned()
      head.push("... and \{rest} more")
      head
    } else {
      errors
    }
    Err({ lines: shown, })
  }
}
