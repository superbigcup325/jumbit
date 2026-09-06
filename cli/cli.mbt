///|
/// query 的选项与关键词（--exclude 为精确路径，对齐上游语义；glob 排除走 _JB_EXCLUDE_DIRS）
pub(all) struct QueryOptions {
  keywords : Array[String]
  mut all : Bool
  mut list : Bool
  mut score : Bool
  mut interactive : Bool
  mut exclude : String?
} derive(Debug, Eq)

///|
/// 子命令（MVP 命令面：add / query / help）
pub(all) struct AddOptions {
  paths : Array[String]
  mut score : Double
} derive(Debug, Eq)

///|
pub(all) struct InitOptions {
  shell : String
  mut cmd : String?
  mut hook : @tpl.Hook
  mut no_cmd : Bool
} derive(Debug, Eq)

///|
pub(all) enum Command {
  Add(AddOptions)
  Query(QueryOptions)
  Remove(Array[String])
  Init(InitOptions)
  Help
  Unknown(String)
} derive(Debug, Eq)

///|
/// 子命令解析（args 不含程序名，@env.args() 已验证）
pub fn parse(args : Array[String]) -> Command {
  if args.is_empty() {
    return Help
  }
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(args[i])
  }
  match args[0] {
    "add" => parse_add(rest)
    "query" => parse_query(rest)
    "remove" => Remove(strip_double_dash(rest))
    "init" => parse_init(rest)
    "help" | "--help" | "-h" => Help
    other => Unknown(other)
  }
}

///|
/// add 参数解析：可选一次 `--score <n>`；裸 `--` 剥离后全部为路径
fn parse_add(args : Array[String]) -> Command {
  let opts : AddOptions = { paths: [], score: 1.0, }
  let mut bad : String? = None
  let mut escaped = false
  let n = args.length()
  let mut i = 0
  while i < n {
    let a = args[i]
    if !escaped && a == "--" {
      escaped = true
    } else if !escaped && a == "--score" {
      if i + 1 < n {
        let parsed : Result[Double, String] = Ok(@strconv.from_str(args[i + 1])) catch {
          e => {
            ignore(e)
            Err("--score 必须是数字: \{args[i + 1]}")
          }
        }
        match parsed {
          Ok(v) => opts.score = v
          Err(msg) => bad = Some(msg)
        }
        i += 1
      } else {
        bad = Some("--score 缺少数值参数")
      }
    } else if !escaped && a.has_prefix("-") && a != "-" {
      bad = Some(a)
    } else {
      opts.paths.push(a)
    }
    i += 1
  }
  match bad {
    Some(msg) => Unknown(msg)
    None => Add(opts)
  }
}

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
  }
  let mut bad : String? = None
  let mut escaped = false
  let n = args.length()
  let mut i = 0
  while i < n {
    let a = args[i]
    if !escaped && a == "--" {
      escaped = true
    } else if !escaped {
      match a {
        "--all" => opts.all = true
        "--list" => opts.list = true
        "--score" => opts.score = true
        "--interactive" => opts.interactive = true
        "--exclude" =>
          if i + 1 < n {
            opts.exclude = Some(args[i + 1])
            i += 1
          } else {
            bad = Some("--exclude 缺少路径参数")
          }
        s =>
          if s.has_prefix("-") && s != "-" {
            bad = Some(s)
          } else {
            opts.keywords.push(s)
          }
      }
    } else {
      opts.keywords.push(a)
    }
    i += 1
  }
  match bad {
    Some(flag) => Unknown(flag)
    None => Query(opts)
  }
}

///|
/// init 参数解析：shell ∈ {bash, zsh, fish}；--cmd C / --hook pwd|prompt|none / --no-cmd
fn parse_init(args : Array[String]) -> Command {
  if args.is_empty() {
    return Unknown("init: 缺少 shell 参数（bash/zsh/fish）")
  }
  let shell = args[0]
  if shell != "bash" && shell != "zsh" && shell != "fish" {
    return Unknown(
      "init: 不支持的 shell: \{shell}（当前支持 bash/zsh/fish）",
    )
  }
  let opts : InitOptions = { shell, cmd: None, hook: HookNone, no_cmd: false, }
  let mut bad : String? = None
  let n = args.length()
  let mut i = 1
  while i < n {
    match args[i] {
      "--no-cmd" => opts.no_cmd = true
      "--cmd" =>
        if i + 1 < n {
          opts.cmd = Some(args[i + 1])
          i += 1
        } else {
          bad = Some("--cmd 缺少命令名参数")
        }
      "--hook" =>
        if i + 1 < n {
          match args[i + 1] {
            "pwd" => opts.hook = @tpl.HookPwd
            "prompt" => opts.hook = @tpl.HookPrompt
            "none" => opts.hook = @tpl.HookNone
            v => bad = Some("--hook 仅支持 pwd/prompt/none: \{v}")
          }
          i += 1
        } else {
          bad = Some("--hook 缺少参数")
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

///|
/// add 的 `--` 分隔符：仅剥离首个裸 `--`，其后参数原样保留（含再次出现的 `--`）
fn strip_double_dash(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut dropped = false
  for a in args {
    if !dropped && a == "--" {
      dropped = true
    } else {
      out.push(a)
    }
  }
  out
}

///|
pub fn usage() -> String {
  "jumbit \{@jumbit.VERSION} — a MoonBit rewrite of zoxide\n\n" +
  "用法：\n" +
  "  jumbit add [--score N] <path>...        记录目录（--score 指定本次增量权重）\n" +
  "  jumbit remove <path>...                 从数据库移除目录\n" +
  "  jumbit query [kw]...                    输出最高得分匹配目录\n" +
  "    --list                                输出全部匹配（按得分降序）\n" +
  "    --score                               前缀显示得分\n" +
  "    --all                                 跳过存在性检查\n" +
  "    --exclude <path>                      排除指定目录（精确路径）\n" +
  "    --interactive                         fzf 交互式选择\n" +
  "  jumbit init <shell>                     生成 shell 集成脚本\n" +
  "    [--cmd C] [--hook pwd|prompt|none] [--no-cmd]\n" +
  "  jumbit help                             显示本帮助\n\n" +
  "环境变量：\n" +
  "  _JB_DATA_DIR                            数据目录（默认 $HOME/.local/share/jumbit，须绝对路径）\n" +
  "  _JB_ECHO=1                              add 时回显记录的目录\n" +
  "  _JB_EXCLUDE_DIRS                        冒号分隔的 glob 列表，命中即从库中移除\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  add 时解析符号链接（查询时反向不跟随）\n" +
  "  _JB_MAXAGE=N                            数据库总分老化阈值（默认 10000）"
}
