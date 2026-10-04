///|
/// query --tsv 的写出层（jumbit 扩展，上游无此语义）：无表头，每行
/// `path\tscore\tlast_accessed\tmatched_by`，列序与 --json 键序一致。
/// path 原样不转义——路径含 tab（合法但病态）时该行歧义，属已知限制
/// （README 注记，golden 数据集含此类路径直接冻结行为）。

///|
/// score 列：有限数用与 --json 共用的最短表示（4.0→"4"）；NaN/±Infinity
/// 无 null 语义（那是 JSON 的招），出 Double::to_string 原文
/// （"NaN"/"Infinity"/"-Infinity"，golden nan-entry 用例冻结实际字节）
fn tsv_number(v : Double) -> String {
  double_short(v)
}

///|
/// 单行 TSV（path\tscore\tlast_accessed\tmatched_by）。
/// 命令行走本函数流式输出；整体拼装的 render_tsv 在 tsv_wbtest 作形状冻结器
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
