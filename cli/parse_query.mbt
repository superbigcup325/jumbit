///|
/// query 参数解析：四个 flag + 关键词；未知 flag / 缺值归 Unknown
fn parse_query(args : Array[String]) -> Command {
  let opts : QueryOptions = {
    keywords: [],
    all: false,
    list: false,
    score: false,
    interactive: false,
    exclude: None,
    json: false,
    fuzzy: false,
    limit: None,
    tsv: false,
  }
  let mut bad : String? = None
  // 参数值语义错误（--limit 缺值/值非法）：归 Invalid 而非 Unknown
  let mut invalid : String? = None
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
    // 等号形式只认带值 flag；布尔/未知 flag 的等号形式报原文归 Unknown
    match pair {
      Some((name, _)) =>
        if name != "--limit" && name != "--exclude" {
          bad = Some(raw)
          i += 1
          continue
        }
      None => ()
    }
    let name = match pair {
      Some((n, _)) => n
      None => raw
    }
    let eq_val : String? = match pair {
      Some((_, value)) => Some(value)
      None => None
    }
    if !escaped && raw == "--" {
      escaped = true
    } else if !escaped {
      match name {
        "--all" => opts.all = true
        "--list" => opts.list = true
        "--score" => opts.score = true
        "--interactive" => opts.interactive = true
        "--json" => opts.json = true
        "--fuzzy" => opts.fuzzy = true
        "--tsv" => opts.tsv = true
        "--limit" =>
          // 值非法归 Invalid，重复出现后者覆盖
          match eq_val {
            Some(value) =>
              match parse_limit_value(value) {
                Ok(v) => opts.limit = Some(v)
                Err(msg) => invalid = Some(msg)
              }
            None =>
              if i + 1 < n {
                match parse_limit_value(args[i + 1]) {
                  Ok(v) => opts.limit = Some(v)
                  Err(msg) => invalid = Some(msg)
                }
                i += 1
              } else {
                invalid = Some("--limit 缺少非负整数参数")
              }
          }
        "--exclude" =>
          match eq_val {
            Some(value) => opts.exclude = Some(value)
            None =>
              if i + 1 < n {
                opts.exclude = Some(args[i + 1])
                i += 1
              } else {
                bad = Some("--exclude 缺少路径参数")
              }
          }
        s =>
          if s.has_prefix("-") && s != "-" {
            bad = Some(raw)
          } else {
            opts.keywords.push(raw)
          }
      }
    } else {
      opts.keywords.push(raw)
    }
    i += 1
  }
  if bad is None && invalid is Some(msg) {
    return Invalid(msg)
  }
  if bad is None {
    // 输出通道互斥（jumbit 扩展 flag 两两冲突；--list --tsv 沿用 --list --json
    // 既有先例：--list 胜出，另一通道被忽略，不校验）
    if opts.tsv && opts.json {
      return Invalid("--tsv 与 --json 互斥")
    }
    if opts.tsv && opts.interactive {
      return Invalid("--tsv 与 --interactive 互斥")
    }
    if opts.json && opts.interactive {
      return Invalid("--json 与 --interactive 互斥")
    }
    if opts.limit is Some(_) && !(opts.list || opts.json || opts.tsv) {
      return Invalid("--limit 仅在 --list/--json/--tsv 下生效")
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None => Query(opts)
  }
}

///|
/// --limit 值解析：非负十进制整数（core parse_uint64，与 import last_accessed
/// 同源——拒前导 +/负数/浮点/垃圾）；超 Int 上限同拒（截断数无更大语义）
fn parse_limit_value(s : String) -> Result[Int, String] {
  let v = @string.parse_uint64(s) catch {
    _ => return Err("--limit 需要非负整数参数: \{s}")
  }
  if v.compare(2147483647UL) > 0 {
    return Err("--limit 需要非负整数参数: \{s}")
  }
  Ok(v.to_int())
}
