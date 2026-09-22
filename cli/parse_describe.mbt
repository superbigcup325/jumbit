///|
/// describe 参数解析：<path> [--note <text>]；标注拒绝换行/回车（export 的
/// Markdown 表格与 CLI 单行输出完整性）；未知 flag/缺值归 Unknown
fn parse_describe(args : Array[String]) -> Command {
  let mut path : String? = None
  let mut note : String? = None
  let mut bad : String? = None
  let n = args.length()
  let mut i = 0
  while i < n {
    let raw = args[i]
    let pair = split_eq_flag(raw)
    let eq_val : String? = match pair {
      Some((_, value)) => Some(value)
      None => None
    }
    if eq_flag_match(raw, pair, "--note") {
      match eq_val {
        Some(value) => note = Some(value)
        None =>
          if i + 1 < n {
            note = Some(args[i + 1])
            i += 1
          } else {
            bad = Some("--note 缺少标注文本")
          }
      }
    } else if raw.has_prefix("-") && raw != "-" {
      bad = Some(raw)
    } else if path is None {
      path = Some(raw)
    } else {
      bad = Some(raw)
    }
    i += 1
  }
  if bad is None && note is Some(t) {
    // 明文持久化后 note 走 notes.tsv(TSV 列分隔),tab 与换行一并拒绝
    if t.contains("\n") || t.contains("\r") || t.contains("\t") {
      return Invalid("describe: 标注不能包含换行或 tab")
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None =>
      match path {
        Some(p) => Describe({ path: p, note, })
        None => Unknown("describe: 缺少路径参数")
      }
  }
}
