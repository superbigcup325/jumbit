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
/// 单行多行 TSV 文本（末行不带换行，调用方 println 收尾）：空数组出空串
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
    out.write_string(d.path)
    out.write_char('\t')
    out.write_string(tsv_number(d.score(now)))
    out.write_char('\t')
    out.write_string(d.last_accessed.to_string())
    out.write_char('\t')
    out.write_string(matched_by)
  }
  out.to_string()
}
