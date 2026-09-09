///|
/// query --json 的写出层（jumbit 扩展，上游无此语义）：键序固定、单行数组，
/// 字节级可测；不引 @json 依赖（写出侧只需一个固定形状）。

///|
/// RFC 8259 字符串转义：引号/反斜杠/控制字符（< 0x20），其余 Unicode 原样透传
/// （输出为 UTF-8，合法 JSON 不必 \u 化非 ASCII）
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
/// JSON 数字：NaN/±Infinity 不是合法 JSON 数值（import 可带进异常 rank），出 null；
/// 有限数走 double_short 最短表示（与 --tsv 的 score 列共用）
fn json_number(v : Double) -> String {
  if v.is_nan() || v.is_inf() {
    "null"
  } else {
    double_short(v)
  }
}

///|
/// 有限浮点最短表示（4.0→"4"、0.75→"0.75"）：--json 与 --tsv 共用的数字形态
fn double_short(v : Double) -> String {
  v.to_string()
}

///|
/// 单行 JSON 数组：每条 {path, score, last_accessed, matched_by}。
/// matched_by ∈ exact/fuzzy（fuzzy 由模糊兜底路接通，提交前恒 exact）
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
    out.write_string("{\"path\":\"")
    out.write_string(json_escape(d.path))
    out.write_string("\",\"score\":")
    out.write_string(json_number(d.score(now)))
    out.write_string(",\"last_accessed\":")
    out.write_string(d.last_accessed.to_string())
    out.write_string(",\"matched_by\":\"")
    out.write_string(matched_by)
    out.write_string("\"}")
  }
  out.write_string("]")
  out.to_string()
}
