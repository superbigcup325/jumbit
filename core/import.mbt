///|
/// Line parsing for the import plugins (matching parse_line in upstream src/import/; pure functions, I/O lives in platform)
/// Three data formats:
/// - the z family (z / zsh-z / fasd / z.lua): `path|rank|last_accessed`
/// - autojump: `rank\tpath` (the rank sigmoid-normalized)
/// - atuin：`YYYY-MM-DD HH:MM:SS\tpath`（UTC，rank=1.0）
/// A bad row returns Err(reason), which the caller reports as `<source>:<line>: <reason>` without aborting the whole import.

///|
/// The z-family format: split into three fields right to left (rsplitn semantics); the path may contain `|`;
/// last_accessed is a non-negative integer (upstream u64; a negative one is a bad row) and rank is any float (it may be negative).
/// Note: no trimming -- whitespace is part of the path (upstream keeps it as is).
pub fn parse_z_line(line : String) -> Result[Dir, String] {
  // bad-row messages are built lazily: the success path (the vast majority of lines) no longer pre-allocates an error string per line
  fn bad() -> Result[Dir, String] {
    Err("invalid entry: \{line}")
  }
  let p1 = match line.rev_find("|") {
    Some(i) => i
    None => return bad()
  }
  // upstream parses as u64 (0..=2^64-1, a leading + is legal, overflow and negatives are bad rows); the bit pattern
  // is stored as is in an i64 field (u64::MAX is -1 in i64), and the downstream score/dedup already compare in the
  // u64 domain (measured against 0.10.0: u64::MAX is accepted and lands in the x4 bucket)
  let la_str = line[p1 + 1:]
  let la_body = if la_str.has_prefix("+") { la_str[1:] } else { la_str }
  let last_accessed : UInt64 = @string.parse_uint64(la_body) catch {
    _ => return bad()
  }
  let head = line[0:p1]
  let p2 = match head.rev_find("|") {
    Some(i) => i
    None => return bad()
  }
  let rank = match parse_f64(head[p2 + 1:]) {
    Ok(v) => v
    Err(_) => return bad()
  }
  Ok({
    path: head[0:p2].to_owned(),
    rank,
    last_accessed: last_accessed.reinterpret_as_int64(),
    note: None,
  })
}

///|
/// The autojump format: split at the first \t, rank on the left and path on the right (the path may contain \t);
/// autojump\'s scoring differs greatly from zoxide\'s, so the rank is sigmoid-normalized into (0,1) and last_accessed is 0.
pub fn parse_autojump_line(line : String) -> Result[Dir, String] {
  let t = match line.find("\t") {
    Some(i) => i
    None => return Err("invalid entry: \{line}")
  }
  let rank_str = line[0:t].to_owned()
  let rank = match parse_f64(rank_str) {
    Ok(v) => v
    Err(_) => {
      // matches the Rust ParseFloatError Display suffix in upstream\'s anyhow message
      let reason = if rank_str == "" {
        "cannot parse float from empty string"
      } else {
        "invalid float literal"
      }
      return Err("invalid rank: \{rank_str}: \{reason}")
    }
  }
  Ok({
    path: line[t + 1:].to_owned(),
    rank: sigmoid(rank),
    last_accessed: 0L,
    note: None,
  })
}

///|
/// The atuin format: split at the first \t, timestamp on the left and path on the right;
/// the timestamp is atuin\'s rendered UTC `YYYY-MM-DD HH:MM:SS` (upstream assume_utc).
pub fn parse_atuin_line(line : String) -> Result[Dir, String] {
  let t = match line.find("\t") {
    Some(i) => i
    None => return Err("invalid entry: \{line}")
  }
  let ts = line[0:t].to_owned()
  let epoch = match parse_atuin_timestamp(ts) {
    Ok(e) => e
    Err(reason) => return Err(atuin_ts_message(ts, reason))
  }
  Ok({
    path: line[t + 1:].to_owned(),
    rank: 1.0,
    last_accessed: epoch,
    note: None,
  })
}

///|
/// A parsed entry carrying its location: the caller builds `<source>:<line>` for error reporting (with no file source for atuin it
/// passes `line <N>`); bound to the entry, it can go through the folder as a whole (isomorphic to upstream ImportError)
pub(all) struct LocatedDir {
  location : String
  result : Result[Dir, String]
} derive(Debug)

///|
/// Consecutive same-path folding for an atuin import (matching prev_cwd in upstream src/import/atuin.rs Iter):
/// shell history is ordered by command, and several records staying in one directory count as one transition, so consecutive
/// repeats keep only the first; an Err passes through as is and does not update the folding chain (upstream\'s error path leaves prev_cwd), and an empty record is skipped by the caller
/// before parsing, also without affecting the chain
pub fn collapse_consecutive(items : Array[LocatedDir]) -> Array[LocatedDir] {
  let out : Array[LocatedDir] = []
  let mut prev : String? = None
  for item in items {
    match item.result {
      Err(_) => out.push(item)
      Ok(dir) => {
        let dup = match prev {
          Some(p) => p == dir.path
          None => false
        }
        if dup {
          continue
        }
        prev = Some(dir.path)
        out.push(item)
      }
    }
  }
  out
}

///|
/// The sigmoid: autojump rank normalization (matching upstream import/autojump.rs sigmoid)
fn sigmoid(x : Double) -> Double {
  1.0 / (1.0 + @math.exp(-x))
}

///|
/// Timestamp error reasons (matching upstream\'s time-crate parsing plus anyhow\'s `{:#}` chained Display;
/// each message\'s true wording was measured against zoxide 0.10.0):
/// - a component that is not numeric or out of its literal range -> "the 'X' component could not be parsed" (two links in the chain)
/// - a day within 1..=31 but past that month\'s length (a leap day) -> "day was not in range" (three links)
/// - a wrong separator in the fixed layout -> "a character literal was not valid" (two links)
/// - the first 19 characters valid but with trailing characters -> "unexpected trailing characters; ..." (two links)
pub(all) enum AtuinTsError {
  Component(String)
  CharLiteral
  Trailing
  DayRange
} derive(Debug, Eq)

///|
fn atuin_ts_message(ts : String, reason : AtuinTsError) -> String {
  let base = "invalid timestamp: \"\{ts}\""
  match reason {
    Component(name) =>
      "\{base}: the '\{name}' component could not be parsed: the '\{name}' component could not be parsed"
    CharLiteral =>
      "\{base}: a character literal was not valid: a character literal was not valid"
    Trailing =>
      "\{base}: unexpected trailing characters; the end of input was expected: unexpected trailing characters; the end of input was expected"
    DayRange =>
      "\{base}: day was not in range: day was not in range: day was not in range"
  }
}

///|
/// Parse `YYYY-MM-DD HH:MM:SS` (a fixed 19-character layout, UTC) -> Unix seconds.
/// A position-by-position state machine reproduces the upstream time-crate parsing order: an earlier component errors first;
/// a numeric field is range-checked against its literal bounds immediately, and only once all pass does the month-length/leap-year check run (DayRange).
fn parse_atuin_timestamp(ts : String) -> Result[Int64, AtuinTsError] {
  let names = ["year", "month", "day", "hour", "minute", "second"]
  let widths = [4, 2, 2, 2, 2, 2]
  // separator UTF-16 code units: '-','=45, ' '=32, ':'=58 (a String index returns code units)
  let seps : Array[UInt16] = [45, 45, 32, 58, 58, 58]
  let vals : Array[Int32] = []
  let mut pos = 0
  let n = ts.length()
  for seg in 0..<6 {
    let mut v = 0
    for _ in 0..<widths[seg] {
      if pos >= n {
        return Err(Component(names[seg]))
      }
      let c = ts[pos]
      if c < 48 || c > 57 {
        return Err(Component(names[seg]))
      }
      v = v * 10 + (c.to_int() - 48)
      pos += 1
    }
    // literal range (per component): validated as soon as this field is parsed (upstream fails per component in order)
    match seg {
      1 => if v < 1 || v > 12 { return Err(Component(names[seg])) }
      3 => if v > 23 { return Err(Component(names[seg])) }
      4 | 5 => if v > 59 { return Err(Component(names[seg])) }
      _ => ()
    }
    vals.push(v)
    if seg < 5 {
      if pos >= n || ts[pos] != seps[seg] {
        return Err(CharLiteral)
      }
      pos += 1
    }
  }
  if pos < n {
    return Err(Trailing)
  }
  let year = vals[0]
  let month = vals[1]
  let day = vals[2]
  if day < 1 || day > days_in_month(year, month) {
    return Err(DayRange)
  }
  let days = days_from_civil(year, month, day)
  let time_of_day = vals[3].to_int64() * 3600L +
    vals[4].to_int64() * 60L +
    vals[5].to_int64()
  Ok(days * 86400L + time_of_day)
}

///|
fn days_in_month(year : Int32, month : Int32) -> Int32 {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
fn is_leap_year(year : Int32) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// A Gregorian date -> days since 1970-01-01 (Howard Hinnant\'s days_from_civil algorithm; truncating division
/// toward zero matches Int semantics; only years 0000-9999 are handled, so the overflow needs no Int64)
fn days_from_civil(year : Int32, month : Int32, day : Int32) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146097L + doe.to_int64() - 719468L
}
