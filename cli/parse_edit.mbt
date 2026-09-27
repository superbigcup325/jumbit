///|
/// edit 参数解析（jumbit 扩展，规格 §1.4）：
/// - 无 flag：$VISUAL/$EDITOR 交互编辑
/// - --rename <old> <new>：改路径（note 跟随）
/// - --prune：清除不存在条目
/// 互斥矩阵：--rename 与 --prune 同现、--rename 重复、--rename 缺第二参数、
/// 未知 flag/多余位置参数 → Unknown（文案风格对齐既有「<flag> 缺少…」）
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
      // 双参 flag：--rename old new；等号形态 --rename=old 仍需 new 位置参
      let old = match eq_val {
        Some(v) => v
        None =>
          if i + 1 < n {
            i += 1
            args[i]
          } else {
            bad = Some("--rename requires <old> <new>")
            raw // 占位，bad 已设
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
      // bad 已设时保留首个错误(后续参数不再覆盖)
      bad = Some("unexpected argument '\{raw}'")
    }
    i += 1
  }
  // 互斥矩阵
  if bad is None && opts.rename_old is Some(_) && opts.prune {
    return Invalid("the argument '--prune' cannot be used with '--rename'")
  }
  match bad {
    Some(flag) => Invalid(flag)
    None => Edit(opts)
  }
}
