///|
/// add\'s argument parsing: an optional single `--score <n>`; after a bare `--` is stripped, everything is a path
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
    // a missing required positional is a usage error: the parse layer uniformly returns Invalid (run.mbt adds
    // the `error: ` prefix in one place, matching TROUBLESHOOTING\'s wording table), never printing it at runtime level
    None =>
      if opts.paths.is_empty() {
        Invalid("add: missing required argument '<PATHS>'")
      } else {
        Add(opts)
      }
  }
}

///|
/// remove\'s argument parsing: after a bare `--` is stripped, everything is a path; an empty set is a usage error (as with add)
fn parse_remove(args : Array[String]) -> Command {
  let paths = strip_double_dash(args)
  if paths.is_empty() {
    Invalid("remove: missing required argument '<PATHS>'")
  } else {
    Remove(paths)
  }
}
