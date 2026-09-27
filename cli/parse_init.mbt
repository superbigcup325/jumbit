///|
/// init 参数解析：shell ∈ {bash, zsh, fish, elvish, nushell, posix, powershell, tcsh, xonsh}；
/// --cmd C / --hook pwd|prompt|none / --no-cmd。
/// flag 与 positional 任意穿插（对齐上游 clap：`init --cmd zz bash` 合法）；
/// 首个非 flag token 为 shell，其余非 flag token 报意外参数；`--` 之后一律按 positional
fn parse_init(args : Array[String]) -> Command {
  let supported = "bash, elvish, fish, nushell, posix, powershell, tcsh, xonsh"
  let mut shell : String? = None
  let mut bad : String? = None
  let mut cmd : String? = Some("j")
  let mut hook : @tpl.Hook = HookPwd
  let mut no_cmd = false
  let n = args.length()
  let mut i = 0
  let mut dd = false
  while i < n {
    let raw = args[i]
    if !dd && raw == "--" {
      // clap 转义符：其后 token 一律按 positional（首个仍可为 shell）
      dd = true
      i += 1
      continue
    }
    let pair = split_eq_flag(raw)
    let is_flag = !dd && (pair is Some(_) || raw.has_prefix("--"))
    if !is_flag {
      match shell {
        None => shell = Some(raw)
        Some(_) => bad = Some("unexpected argument '\{raw}'")
      }
      i += 1
      continue
    }
    // 等号形式只认带值 flag；--no-cmd/未知 flag 的等号形式报原文归 Unknown
    match pair {
      Some((name, _)) =>
        if name != "--cmd" && name != "--hook" {
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
    match name {
      "--no-cmd" => no_cmd = true
      "--cmd" =>
        match eq_val {
          Some(value) => cmd = Some(value)
          None =>
            if i + 1 < n {
              cmd = Some(args[i + 1])
              i += 1
            } else {
              bad = Some(
                "a value is required for '--cmd <C>' but none was supplied",
              )
            }
        }
      "--hook" =>
        match eq_val {
          Some(value) =>
            match parse_hook(value) {
              Some(h) => hook = h
              None =>
                bad = Some(
                  "invalid value '\{value}' for '--hook <HOOK>'\n  [possible values: pwd, prompt, none]",
                )
            }
          None =>
            if i + 1 < n {
              match parse_hook(args[i + 1]) {
                Some(h) => hook = h
                None =>
                  bad = Some(
                    "invalid value '\{args[i + 1]}' for '--hook <HOOK>'\n  [possible values: pwd, prompt, none]",
                  )
              }
              i += 1
            } else {
              bad = Some(
                "a value is required for '--hook <HOOK>' but none was supplied",
              )
            }
        }
      s => bad = Some("unexpected argument '\{s}'")
    }
    i += 1
  }
  match bad {
    Some(msg) => Invalid(msg)
    None =>
      match shell {
        None =>
          Invalid(
            "missing required argument '<SHELL>'\n  [possible values: \{supported}]",
          )
        Some(sh) =>
          if sh != "bash" &&
            sh != "zsh" &&
            sh != "fish" &&
            sh != "elvish" &&
            sh != "nushell" &&
            sh != "posix" &&
            sh != "powershell" &&
            sh != "tcsh" &&
            sh != "xonsh" {
            Invalid(
              "invalid value '\{sh}' for '<SHELL>'\n  [possible values: \{supported}]",
            )
          } else {
            // 默认对齐上游 cmd.rs：--cmd 默认定义命令（jumbit → "j"），--hook 默认 pwd
            Init({ shell: sh, cmd, hook, no_cmd, })
          }
      }
  }
}
