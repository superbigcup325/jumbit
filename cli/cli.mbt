///|
/// query 的选项与关键词（--exclude 为精确路径，对齐上游语义；glob 排除走 _JB_EXCLUDE_DIRS；
/// --json/--fuzzy 为 jumbit 扩展，上游无此语义）
pub(all) struct QueryOptions {
  keywords : Array[String]
  mut all : Bool
  mut list : Bool
  mut score : Bool
  mut interactive : Bool
  mut exclude : String?
  mut json : Bool
  mut fuzzy : Bool
} derive(Debug, Eq)

///|
/// 子命令（add / query / remove / init / import / describe / export / help）
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
/// import 的选项：plugin ∈ {atuin, autojump, fasd, z, z.lua, zsh-z}；
/// --merge 对齐上游 global flag，可出现在插件名前后任意位置
pub(all) struct ImportOptions {
  plugin : String
  mut merge : Bool
} derive(Debug, Eq)

///|
/// describe 的选项（jumbit 扩展）：note 为 None 表示显示模式，Some("") 表示清除
pub(all) struct DescribeOptions {
  path : String
  mut note : String?
} derive(Debug, Eq)

///|
/// export 的选项（jumbit 扩展）：--agents 输出项目地图 Markdown
pub(all) struct ExportOptions {
  mut agents : Bool
} derive(Debug, Eq)

///|
pub(all) enum Command {
  Add(AddOptions)
  Query(QueryOptions)
  Remove(Array[String])
  Init(InitOptions)
  Import(ImportOptions)
  Describe(DescribeOptions)
  Export(ExportOptions)
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
    "import" => parse_import(rest)
    "describe" => parse_describe(rest)
    "export" => parse_export(rest)
    "help" | "--help" | "-h" => Help
    other => Unknown(other)
  }
}

///|
/// 浮点解析（raise → Option）：供需要分支而非中止的解析处使用；
/// 语义对齐 Rust f64::from_str（clap 同款：溢出饱和 ±inf、拒下划线）
fn parse_double_opt(s : String) -> Double? {
  match @core.parse_f64(s) {
    Ok(v) => Some(v)
    Err(_) => None
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
        match parse_double_opt(args[i + 1]) {
          Some(v) => opts.score = v
          None => bad = Some("--score 必须是数字: \{args[i + 1]}")
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
    json: false,
    fuzzy: false,
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
        "--json" => opts.json = true
        "--fuzzy" => opts.fuzzy = true
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
  if bad is None && opts.json && opts.interactive {
    bad = Some("--json 与 --interactive 互斥")
  }
  match bad {
    Some(flag) => Unknown(flag)
    None => Query(opts)
  }
}

///|
/// describe 参数解析：<path> [--note <text>]；标注拒绝换行/回车（export 的
/// Markdown 表格与 CLI 单行输出完整性）；未知 flag/缺值归 Unknown
fn parse_describe(args : Array[String]) -> Command {
  let mut path : String? = None
  let mut note : String? = None
  let mut bad : String? = None
  let n = args.length()
  let mut i = 0
  while i < n {
    let a = args[i]
    if a == "--note" {
      if i + 1 < n {
        note = Some(args[i + 1])
        i += 1
      } else {
        bad = Some("--note 缺少标注文本")
      }
    } else if a.has_prefix("-") && a != "-" {
      bad = Some(a)
    } else if path is None {
      path = Some(a)
    } else {
      bad = Some(a)
    }
    i += 1
  }
  if bad is None && note is Some(t) {
    if t.contains("\n") || t.contains("\r") {
      bad = Some("describe: 标注不能包含换行")
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None =>
      match path {
        Some(p) => Describe({ path: p, note, })
        None => Unknown("describe: 缺少路径参数")
      }
  }
}

///|
/// export 参数解析：当前仅 --agents 一个目标；缺 --agents / 未知 flag 归 Unknown
fn parse_export(args : Array[String]) -> Command {
  let opts : ExportOptions = { agents: false, }
  let mut bad : String? = None
  for a in args {
    if a == "--agents" {
      opts.agents = true
    } else {
      bad = Some(a)
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None =>
      if opts.agents {
        Export(opts)
      } else {
        Unknown("export: 缺少 --agents")
      }
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
/// import 支持的插件（对齐上游 ImportFrom 枚举；z.lua / zsh-z 带点与连字符）
pub fn import_plugins() -> Array[String] {
  ["atuin", "autojump", "fasd", "z", "z.lua", "zsh-z"]
}

///|
/// import 参数解析：一个插件名位置参数 + 任意位置的 --merge；
/// 未知 flag / 多余位置参数 / 非法插件名归 Unknown（对齐 clap 退出码 2）
fn parse_import(args : Array[String]) -> Command {
  let mut plugin : String? = None
  let mut merge = false
  let mut bad : String? = None
  for a in args {
    if a == "--merge" {
      merge = true
    } else if a.has_prefix("-") && a != "-" {
      bad = Some(a)
    } else if plugin is None {
      plugin = Some(a)
    } else {
      bad = Some(a)
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None =>
      match plugin {
        Some(p) =>
          if import_plugins().contains(p) {
            Import({ plugin: p, merge, })
          } else {
            Unknown(
              "import: 不支持的插件: \{p}（支持 \{import_plugins().join("/")}）",
            )
          }
        None =>
          Unknown(
            "import: 缺少插件参数（\{import_plugins().join("/")}）",
          )
      }
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
  "    --json                                单行 JSON 数组输出全部匹配（agent 通道，与 --interactive 互斥）\n" +
  "    --fuzzy                               精确零命中时按组件子串兜底（jumbit 扩展）\n" +
  "  jumbit init <shell>                     生成 shell 集成脚本（默认定义 j/ji，hook=pwd）\n" +
  "    [--cmd C] [--hook pwd|prompt|none] [--no-cmd]\n" +
  "  jumbit import <plugin> [--merge]        从其他工具导入历史数据（空库直灌，--merge 合并进非空库）\n" +
  "  jumbit describe <path> [--note text]     查看/设置人工标注（--note \"\" 清除，jumbit 扩展）\n" +
  "  jumbit export --agents                   输出项目地图 Markdown（贴进 AGENTS.md，jumbit 扩展）\n" +
  "    plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z（坏行逐条上报不中止）\n" +
  "  jumbit help                             显示本帮助\n\n" +
  "环境变量：\n" +
  "  _JB_DATA_DIR                            数据目录（默认 $HOME/.local/share/jumbit，须绝对路径）\n" +
  "  _JB_ECHO=1                              add 时回显记录的目录\n" +
  "  _JB_EXCLUDE_DIRS                        冒号分隔的 glob 列表，命中即从库中移除\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  add 时解析符号链接（查询时反向不跟随）\n" +
  "  _JB_MAXAGE=N                            数据库总分老化阈值（默认 10000）\n" +
  "import 读取各插件标准数据文件，可经 _Z_DATA/_FASD_DATA/ZSHZ_DATA/_ZL_DATA/XDG_DATA_HOME 定位"
}
