// Byte-level tests for query --tsv\'s writer layer (jumbit extension semantics; now is 10_000_000L, about 115 days,
// so la=0 lands in the x0.25 bucket and la=2^40 in the future lands in x4, neither drifting with time)

///|
/// A helper for building entries
fn tsv_dir(p : String, r : Double, la : Int64) -> @core.Dir {
  @core.Dir::{ path: p, rank: r, last_accessed: la, note: None, }
}

///|
/// Full assembly (the last line has no newline, and an empty array gives an empty string) -- production switched to tsv_row streaming,
/// so this wrapper remains as the byte-level freezer for the multi-line shape
fn render_tsv(
  dirs : Array[@core.Dir],
  now : Int64,
  matched_by : String,
) -> String {
  let out : StringBuilder = StringBuilder()
  for i, d in dirs {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string(tsv_row(d, now, matched_by))
  }
  out.to_string()
}

///|
test "render_tsv: an empty array gives an empty string" {
  @debug.assert_eq(render_tsv([], 10000000L, "exact"), "")
}

///|
test "render_tsv: column order and tab separation (path/score/last_accessed/matched_by)" {
  let dirs = [tsv_dir("/a", 2.0, 1099511627776), tsv_dir("/b", 1.5, 0)]
  // score: 2.0x4=8 -> "8"; 1.5x0.25=0.375 -> "0.375" (the same numeric shape as --json)
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/a\t8\t1099511627776\texact\n/b\t0.375\t0\texact",
  )
}

///|
test "render_tsv: the short score form and the raw NaN/Inf tokens (null on the JSON side, never nulled here)" {
  let dirs = [
    tsv_dir("/int", 4.0, 0),
    tsv_dir("/frac", 0.75, 0),
    tsv_dir("/neg", -0.75, 0),
    tsv_dir("/nan", @string.parse_double("nan") catch { _ => 1.0 }, 0),
    tsv_dir("/inf", @string.parse_double("inf") catch { _ => 1.0 }, 0),
    tsv_dir("/ninf", @string.parse_double("-inf") catch { _ => 1.0 }, 0),
  ]
  // ×0.25：1 / 0.1875 / -0.1875 / NaN / Infinity / -Infinity
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/int\t1\t0\texact\n/frac\t0.1875\t0\texact\n/neg\t-0.1875\t0\texact\n/nan\tNaN\t0\texact\n/inf\tInfinity\t0\texact\n/ninf\t-Infinity\t0\texact",
  )
}

///|
test "render_tsv: the path passes through with no escaping at all (tab/quote/non-ASCII)" {
  let dirs = [
    tsv_dir("/a\tb", 1.0, 0),
    tsv_dir("c\"d|e", 1.0, 0),
    tsv_dir("/中文", 1.0, 0),
  ]
  // a tab path makes that line\'s column count ambiguous -- a known limitation (noted in the README), frozen here
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/a\tb\t0.25\t0\texact\nc\"d|e\t0.25\t0\texact\n/中文\t0.25\t0\texact",
  )
}

///|
test "render_tsv: the matched_by value passes through" {
  let dirs = [tsv_dir("/x", 1.0, 0)]
  @debug.assert_eq(render_tsv(dirs, 10000000L, "fuzzy"), "/x\t0.25\t0\tfuzzy")
}
