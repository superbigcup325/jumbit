///|
/// init 参数解析：shell ∈ {bash, zsh, fish, elvish, nushell, posix, powershell, tcsh, xonsh}；--cmd C / --hook pwd|prompt|none / --no-cmd
fn parse_init(args : Array[String]) -> Command {
  if args.is_empty() {
    return Unknown(
      "init: 缺少 shell 参数（bash/zsh/fish/elvish/nushell/posix/powershell/tcsh/xonsh）",
    )
  }
  let shell = args[0]
  if shell != "bash" &&
    shell != "zsh" &&
    shell != "fish" &&
    shell != "elvish" &&
    shell != "nushell" &&
    shell != "posix" &&
    shell != "powershell" &&
    shell != "tcsh" &&
    shell != "xonsh" {
    return Unknown(
      "init: 不支持的 shell: \{shell}（当前支持 bash/zsh/fish/elvish/nushell/posix/powershell/tcsh/xonsh）",
    )
  }
  // 默认对齐上游 cmd.rs：--cmd 默认定义命令（jumbit → "j"），--hook 默认 pwd
  let opts : InitOptions = {
    shell,
    cmd: Some("j"),
    hook: HookPwd,
    no_cmd: false,
  }
  let mut bad : String? = None
  let n = args.length()
  let mut i = 1
  while i < n {
    let raw = args[i]
    let pair = split_eq_flag(raw)
    // 等号形式只认带值 flag；--no-cmd/未知 flag 的等号形式报原文归 Unknown
    match pair {
      Some((name, _)) =>
        if name != "--cmd" && name != "--hook" {
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
    match name {
      "--no-cmd" => opts.no_cmd = true
      "--cmd" =>
        match eq_val {
          Some(value) => opts.cmd = Some(value)
          None =>
            if i + 1 < n {
              opts.cmd = Some(args[i + 1])
              i += 1
            } else {
              bad = Some("--cmd 缺少命令名参数")
            }
        }
      "--hook" =>
        match eq_val {
          Some(value) =>
            match parse_hook(value) {
              Some(h) => opts.hook = h
              None => bad = Some("--hook 仅支持 pwd/prompt/none: \{value}")
            }
          None =>
            if i + 1 < n {
              match parse_hook(args[i + 1]) {
                Some(h) => opts.hook = h
                None =>
                  bad = Some("--hook 仅支持 pwd/prompt/none: \{args[i + 1]}")
              }
              i += 1
            } else {
              bad = Some("--hook 缺少参数")
            }
        }
      s => bad = Some(s)
    }
    i += 1
  }
  match bad {
    Some(msg) => Unknown(msg)
    None => Init(opts)
  }
}
