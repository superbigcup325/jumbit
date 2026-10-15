///|
/// edit\'s argument parsing (a jumbit extension, spec §1.4):
/// - no flag: interactive editing with $VISUAL/$EDITOR
/// - --rename <old> <new>: change a path (the note follows)
/// - --prune: drop entries that no longer exist
/// The exclusivity matrix: --rename with --prune, a repeated --rename, --rename missing its second argument,
/// an unknown flag or a surplus positional -> Unknown (the wording style matches the existing "<flag> missing ...")
fn parse_edit(args : Array[String]) -> Command {
  let opts : EditOptions = { rename_old: None, rename_new: None, prune: false, }
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
    if eq_flag_match(raw, pair, "--rename") {
      // a two-argument flag: --rename old new; in the equals form --rename=old still needs new as a positional
      let old = match eq_val {
        Some(v) => v
        None =>
          if i + 1 < n {
            i += 1
            args[i]
          } else {
            bad = Some("--rename requires <old> <new>")
            raw // placeholder; bad is already set
          }
      }
      if bad is None {
        if opts.rename_old is Some(_) {
          bad = Some("the argument '--rename' cannot be used multiple times")
        } else if i + 1 < n {
          opts.rename_old = Some(old)
          i += 1
          opts.rename_new = Some(args[i])
        } else {
          bad = Some("--rename requires <new>")
        }
      }
    } else if raw == "--prune" {
      if opts.prune {
        bad = Some("the argument '--prune' cannot be used multiple times")
      }
      opts.prune = true
    } else if bad is None {
      // once bad is set the first error is kept (later arguments do not overwrite it)
      bad = Some("unexpected argument '\{raw}'")
    }
    i += 1
  }
  // the exclusivity matrix
  if bad is None && opts.rename_old is Some(_) && opts.prune {
    return Invalid("the argument '--prune' cannot be used with '--rename'")
  }
  match bad {
    Some(flag) => Invalid(flag)
    None => Edit(opts)
  }
}
