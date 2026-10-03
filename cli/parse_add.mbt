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
            None => bad = Some("invalid value '\{value}' for '--score <N>'")
          }
        None =>
          if i + 1 < n {
            match parse_double_opt(args[i + 1]) {
              Some(v) => opts.score = v
              None =>
                bad = Some("invalid value '\{args[i + 1]}' for '--score <N>'")
            }
            i += 1
          } else {
            bad = Some(
              "a value is required for '--score <N>' but none was supplied",
            )
          }
      }
    } else if !escaped && raw.has_prefix("-") && raw != "-" {
      bad = Some("unexpected argument '\{raw}'")
    } else {
      opts.paths.push(raw)
    }
    i += 1
  }
  match bad {
    Some(msg) => Invalid(msg)
    // 缺必选位置参数属用法错误：parse 层统一走 Invalid（run.mbt 集中加
    // `error: ` 前缀，对齐 TROUBLESHOOTING 文案表），不在运行时层自行输出
    None =>
      if opts.paths.is_empty() {
        Invalid("add: missing required argument '<PATHS>'")
      } else {
        Add(opts)
      }
  }
}

///|
/// remove 参数解析：裸 `--` 剥离后全部为路径；空集为用法错误（同 add）
fn parse_remove(args : Array[String]) -> Command {
  let paths = strip_double_dash(args)
  if paths.is_empty() {
    Invalid("remove: missing required argument '<PATHS>'")
  } else {
    Remove(paths)
  }
}
