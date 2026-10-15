///|
/// query\'s argument parsing: four flags plus keywords; an unknown flag or a missing value goes Unknown
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
  // a semantic value error (--limit missing its value or given an invalid one): Invalid, not Unknown
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
    // the equals form is only recognised for value-taking flags; a boolean or unknown flag\'s equals form reports the original wording as Unknown
    match pair {
      Some((name, _)) =>
        if name != "--limit" && name != "--exclude" {
          bad = Some("unexpected argument '\{raw}'")
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
          // an invalid value goes Invalid; a repeat lets the last one win
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
                invalid = Some(
                  "a value is required for '--limit <n>' but none was supplied",
                )
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
                bad = Some(
                  "a value is required for '--exclude <path>' but none was supplied",
                )
              }
          }
        s =>
          if s.has_prefix("-") && s != "-" {
            bad = Some("unexpected argument '\{raw}'")
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
    // the output channels are exclusive (jumbit extension flags conflict pairwise; --list --tsv follows the --list --json
    // precedent: --list wins, the other channel is ignored, unchecked)
    if opts.tsv && opts.json {
      return Invalid("the argument '--tsv' cannot be used with '--json'")
    }
    if opts.tsv && opts.interactive {
      return Invalid("the argument '--tsv' cannot be used with '--interactive'")
    }
    if opts.json && opts.interactive {
      return Invalid(
        "the argument '--json' cannot be used with '--interactive'",
      )
    }
    if opts.limit is Some(_) && !(opts.list || opts.json || opts.tsv) {
      return Invalid("'--limit' requires '--list', '--json' or '--tsv'")
    }
  }
  match bad {
    Some(flag) => Invalid(flag)
    None => Query(opts)
  }
}

///|
/// --limit value parsing: a non-negative decimal integer (core parse_uint64, the same source as import\'s last_accessed
/// -- rejecting a leading +, negatives, floats and garbage); over the Int cap it is rejected too (a larger truncation count means nothing)
fn parse_limit_value(s : String) -> Result[Int32, String] {
  let v = @string.parse_uint64(s) catch {
    _ =>
      return Err(
        "invalid value '\{s}' for '--limit <n>': must be a non-negative integer",
      )
  }
  if v.compare(2147483647UL) > 0 {
    return Err(
      "invalid value '\{s}' for '--limit <n>': must be a non-negative integer",
    )
  }
  Ok(v.to_int())
}
