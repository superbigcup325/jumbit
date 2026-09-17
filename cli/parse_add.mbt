///|
/// add 参数解析：可选一次 `--score <n>`；裸 `--` 剥离后全部为路径
fn parse_add(args : Array[String]) -> Command {
  let opts : AddOptions = { paths: [], score: 1.0, }
  let mut bad : String? = None
  let mut escaped = false
  let n = args.length()
  let mut i = 0
  while i < n {
    let raw = args[i]
    let pair : (String, String)? = if !escaped {
      split_eq_flag(raw)
    } else {
      None
    }
    if !escaped && raw == "--" {
      escaped = true
    } else if !escaped && eq_flag_match(raw, pair, "--score") {
      match pair {
        Some((_, value)) =>
          match parse_double_opt(value) {
            Some(v) => opts.score = v
            None => bad = Some("--score 必须是数字: \{value}")
          }
        None =>
          if i + 1 < n {
            match parse_double_opt(args[i + 1]) {
              Some(v) => opts.score = v
              None => bad = Some("--score 必须是数字: \{args[i + 1]}")
            }
            i += 1
          } else {
            bad = Some("--score 缺少数值参数")
          }
      }
    } else if !escaped && raw.has_prefix("-") && raw != "-" {
      bad = Some(raw)
    } else {
      opts.paths.push(raw)
    }
    i += 1
  }
  match bad {
    Some(msg) => Unknown(msg)
    None => Add(opts)
  }
}
