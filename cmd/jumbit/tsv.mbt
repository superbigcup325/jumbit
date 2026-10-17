///|
/// The writer layer for query --tsv (a jumbit extension with no upstream equivalent): headerless, one
/// `path\tscore\tlast_accessed\tmatched_by` per line, in the same column order as the --json keys.
/// The path is written verbatim and unescaped -- a path containing a tab (legal but pathological) makes that line ambiguous, a known limitation
/// (noted in the README; the golden dataset includes such a path, freezing the behaviour).

///|
/// The score column: finite values use the shortest form shared with --json (4.0 -> "4"); NaN/±Infinity have no
/// null semantics (that is JSON\'s move), so they emit Double::to_string verbatim
/// ("NaN"/"Infinity"/"-Infinity"; the golden nan-entry case freezes the actual bytes)
fn tsv_number(v : Double) -> String {
  double_short(v)
}

///|
/// A single TSV line (path\tscore\tlast_accessed\tmatched_by).
/// The CLI streams its output through this function; the fully assembled render_tsv acts as a shape freezer in tsv_wbtest
fn tsv_row(d : @core.Dir, now : Int64, matched_by : String) -> String {
  let out : StringBuilder = StringBuilder()
  out.write_string(d.path)
  out.write_char('\t')
  out.write_string(tsv_number(d.score(now)))
  out.write_char('\t')
  out.write_string(d.last_accessed.to_string())
  out.write_char('\t')
  out.write_string(matched_by)
  out.to_string()
}
