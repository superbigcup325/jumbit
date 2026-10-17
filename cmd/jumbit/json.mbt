///|
/// The writer layer for query --json (a jumbit extension with no upstream equivalent): fixed key order, a single-line array,
/// testable at the byte level; no @json dependency (the writer needs only one fixed shape).

///|
/// RFC 8259 string escaping: quotes, backslashes and control characters (< 0x20); other Unicode passes through as is
/// (the output is UTF-8, and valid JSON need not \\u-escape non-ASCII)
fn json_escape(s : String) -> String {
  let out : StringBuilder = StringBuilder()
  for ch in s {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '\u{0008}' => out.write_string("\\b")
      '\u{000C}' => out.write_string("\\f")
      c =>
        if c < '\u{0020}' {
          let hex = c.to_int().to_string(radix=16).pad_start(4, '0')
          out.write_string("\\u\{hex}")
        } else {
          out.write_char(c)
        }
    }
  }
  out.to_string()
}

///|
/// JSON numbers: NaN/±Infinity are not legal JSON numbers (an import can bring in an aberrant rank), so they emit null;
/// finite values use double_short\'s shortest form (shared with --tsv\'s score column)
fn json_number(v : Double) -> String {
  if v.is_nan() || v.is_inf() {
    "null"
  } else {
    double_short(v)
  }
}

///|
/// Shortest representation of a finite float (4.0 -> "4", 0.75 -> "0.75"): the numeric shape shared by --json and --tsv
fn double_short(v : Double) -> String {
  v.to_string()
}

///|
/// One JSON object ({path, score, last_accessed, matched_by})
fn json_row(d : @core.Dir, now : Int64, matched_by : String) -> String {
  let out : StringBuilder = StringBuilder()
  out.write_string("{\"path\":\"")
  out.write_string(json_escape(d.path))
  out.write_string("\",\"score\":")
  out.write_string(json_number(d.score(now)))
  out.write_string(",\"last_accessed\":")
  out.write_string(d.last_accessed.to_string())
  out.write_string(",\"matched_by\":\"")
  out.write_string(matched_by)
  out.write_string("\"}")
  out.to_string()
}

///|
/// A single-line JSON array of {path, score, last_accessed, matched_by} objects.
/// matched_by is exact or fuzzy (fuzzy is wired through the fallback path; before this it was always exact).
/// It stays fully materialized: the single-line contract (no embedded newlines) would force a streaming flush to write
/// without a trailing newline, which conflicts with moon test\'s stdout event protocol (see docs/perf-import-optimization.md)
fn render_json(
  dirs : Array[@core.Dir],
  now : Int64,
  matched_by : String,
) -> String {
  let out : StringBuilder = StringBuilder()
  out.write_string("[")
  for i, d in dirs {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(json_row(d, now, matched_by))
  }
  out.write_string("]")
  out.to_string()
}
