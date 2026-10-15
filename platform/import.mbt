///|
/// One record from an import source: its line number (1-based; blank lines and empty records count too, matching upstream\'s line-by-line reads)
/// result holds the UTF-8 decode; a failed line carries the reason, and the caller reports `<source>:<line>`
pub(all) struct ImportRecord {
  line_num : Int32
  result : Result[String, String]
} derive(Debug)

///|
/// Read a plugin\'s data file record by record through a callback (\n separated, trailing \r stripped).
/// Byte splitting then per-line decoding: bad UTF-8 only affects its own line (matching upstream\'s per-line str::from_utf8).
/// No record array is materialized -- this is the hot path of a million-line import (the line string is dropped at once, so the peak holds only the db);
/// upstream import.rs::run is already a lazy single-pass iterator, so this is a structural return, not an optimization
pub async fn for_each_import_line(
  path : String,
  f : (Int32, Result[String, String]) -> Unit,
) -> Result[Unit, String] {
  let data = @afs.read_file(path) catch {
    err =>
      return Err("jumbit: could not read \{path}: \{os_error_message(err)}")
  }
  for_each_record(data.binary(), b'\n', true, f)
  Ok(())
}

///|
/// Split into a record array (the line semantics are identical to for_each_import_line):
/// the materialized form of the atuin folding path, and the line-semantics freezer
pub async fn read_import_lines(
  path : String,
) -> Result[Array[ImportRecord], String] {
  let out : Array[ImportRecord] = []
  match
    for_each_import_line(path, fn(line_num, result) {
      out.push({ line_num, result, })
    }) {
    Ok(_) => Ok(out)
    Err(msg) => Err(msg)
  }
}

///|
/// atuin history: spawn `atuin history list --format={time}\t{directory} --print0`
/// and read the NUL-separated records. Upstream streams and does not check the exit code; this collects first with the same semantics.
/// Returns (records, atuin\'s raw stderr): upstream inherits stderr and it is visible directly, while here the caller reports it.
pub async fn atuin_history_records() -> Result[
  (Array[ImportRecord], String),
  String,
] {
  records_from_process("atuin", [
    "history", "list", "--format={time}\t{directory}", "--print0",
  ])
}

///|
/// The testable core of subprocess record reading: NUL separated, no \r stripping (atuin does no CR handling)
async fn records_from_process(
  cmd : String,
  args : Array[String],
) -> Result[(Array[ImportRecord], String), String] {
  let (_code, stdout, stderr) = @process.collect_output(cmd, args) catch {
    _ =>
      return Err("jumbit: failed to run `\{cmd}`; is it installed and on PATH?")
  }
  let err_text : String = stderr.text() catch { _ => "" }
  let out : Array[ImportRecord] = []
  for_each_record(stdout.binary(), b'\x00', false, fn(line_num, result) {
    out.push({ line_num, result, })
  })
  Ok((out, err_text))
}

///|
/// Split a byte stream by a separator: the separator is not kept; with strip_cr a record\'s trailing \r is stripped (a file\'s \r\n line ending);
/// an empty record keeps its slot (line numbers stay consecutive and the caller skips it silently); a final partial record counts as the last one.
/// A single byte scan with per-line lazy decoding (zero-copy views): the separator is not kept, and an empty record keeps its slot.
/// Callback consumption keeps the import hot path from materializing a 1M-record array
fn for_each_record(
  bytes : Bytes,
  sep : Byte,
  strip_cr : Bool,
  f : (Int32, Result[String, String]) -> Unit,
) -> Unit {
  let n = bytes.length()
  let mut start = 0
  let mut line_num = 0
  let mut i = 0
  while i < n {
    if bytes[i] == sep {
      line_num += 1
      f(line_num, decode_view(bytes, start, i, strip_cr))
      start = i + 1
    }
    i += 1
  }
  if start < n {
    line_num += 1
    f(line_num, decode_view(bytes, start, n, strip_cr))
  }
}

///|
/// Decode one record: strip \r first (strip_cr), then UTF-8 decode (a failure does not abort; the line is marked).
/// The fast path decodes directly (one pass for valid input); only a failure enters the slow path for case-by-case location, with the wording unchanged.
/// The bad-byte wording matches upstream\'s chained Display of str::from_utf8 plus anyhow context
/// (probed case by case against zoxide 0.10.0 on 2026-09-09):
/// - bad bytes inside the line: `invalid utf-8 sequence of N bytes from index M`, where N is
///   std\'s Utf8Error::error_len -- a bad first byte or a bad second byte of a two-byte sequence = 1, a bad third byte of a three-byte
///   sequence = 2, a bad fourth byte of a four-byte sequence = 3
/// - a sequence truncated at the end of the slice: `incomplete utf-8 byte sequence from index M`
fn decode_view(
  bytes : Bytes,
  start : Int32,
  end_ : Int32,
  strip_cr : Bool,
) -> Result[String, String] {
  let mut e = end_
  if strip_cr && e > start && bytes[e - 1] == b'\r' {
    e -= 1
  }
  let text : String = @utf8.decode(bytes.exact_view(start~, end=e)) catch {
    _ => {
      let reason = match utf8_error(bytes, start, e) {
        Some(msg) => "invalid utf-8: \{msg}"
        None => "invalid utf-8"
      }
      return Err(reason)
    }
  }
  Ok(text)
}

///|
/// UTF-8 validation (RFC 3629, reproducing std validator\'s error-location semantics); None = valid.
/// Only called on the slow path after a decode failure, producing the case-by-case wording that matches std.
/// A truncation inside the line slice is the same shape as one at end of file: std reports an incomplete sequence at the end of a slice
fn utf8_error(bytes : Bytes, start : Int32, end_ : Int32) -> String? {
  let n = end_
  // the continuation-byte range 80..BF
  fn cont(i : Int32) -> Bool {
    let v = bytes[i].to_int()
    v >= 0x80 && v < 0xC0
  }
  let mut i = start
  while i < n {
    let b = bytes[i].to_int()
    if b < 0x80 {
      i += 1
      continue
    }
    if b < 0xC2 {
      // a misplaced 80-BF start / a C0-C1 overlong start
      return Some("invalid utf-8 sequence of 1 bytes from index \{i - start}")
    }
    if b < 0xE0 {
      // two-byte C2-DF
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      if !cont(i + 1) {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i - start}")
      }
      i += 2
      continue
    }
    if b < 0xF0 {
      // three-byte E0-EF; E0\'s second byte is A0-BF (guarding against overlong) and ED\'s is 80-9F (guarding against surrogates)
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      let b2 = bytes[i + 1].to_int()
      let ok2 = if b == 0xE0 {
        b2 >= 0xA0 && b2 < 0xC0
      } else if b == 0xED {
        b2 >= 0x80 && b2 < 0xA0
      } else {
        b2 >= 0x80 && b2 < 0xC0
      }
      if !ok2 {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i - start}")
      }
      if i + 2 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      if !cont(i + 2) {
        return Some("invalid utf-8 sequence of 2 bytes from index \{i - start}")
      }
      i += 3
      continue
    }
    if b < 0xF5 {
      // four-byte F0-F4; F0\'s second byte is 90-BF and F4\'s is 80-8F (guarding against >U+10FFFF)
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      let b2 = bytes[i + 1].to_int()
      let ok2 = if b == 0xF0 {
        b2 >= 0x90 && b2 < 0xC0
      } else if b == 0xF4 {
        b2 >= 0x80 && b2 < 0x90
      } else {
        b2 >= 0x80 && b2 < 0xC0
      }
      if !ok2 {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i - start}")
      }
      if i + 2 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      if !cont(i + 2) {
        return Some("invalid utf-8 sequence of 2 bytes from index \{i - start}")
      }
      if i + 3 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i - start}")
      }
      if !cont(i + 3) {
        return Some("invalid utf-8 sequence of 3 bytes from index \{i - start}")
      }
      i += 4
      continue
    }
    // F5-FF is an illegal start
    return Some("invalid utf-8 sequence of 1 bytes from index \{i - start}")
  }
  None
}
