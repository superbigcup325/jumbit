///|
/// query 的选项与关键词（--exclude 为精确路径，对齐上游语义；glob 排除走 _JB_EXCLUDE_DIRS；
/// --json/--fuzzy/--limit/--tsv 为 jumbit 扩展，上游无此语义）
pub(all) struct QueryOptions {
  keywords : Array[String]
  mut all : Bool
  mut list : Bool
  mut score : Bool
  mut interactive : Bool
  mut exclude : String?
  mut json : Bool
  mut fuzzy : Bool
  /// --limit <n>：列表型输出（--list/--json/--tsv）的前 n 条截断，None=未设
  mut limit : Int?
  /// --tsv：无表头 Tab 分隔数据通道（jumbit 扩展）
  mut tsv : Bool
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
/// status 的选项（jumbit 扩展）：--json 单行 JSON 对象；--check 显式触发
/// O(N) 存在性扫描（默认快查不做文件系统遍历）
pub(all) struct StatusOptions {
  mut json : Bool
  mut check : Bool
} derive(Debug, Eq)

///|

///|
/// edit 参数解析（jumbit 扩展，规格 docs/spec-plaintext-edit.md §1.4）：
/// 无 flag = $EDITOR 交互编辑；--rename <old> <new> 改路径（note 跟随）；
/// --prune 清除不存在条目。三形态互斥
pub(all) struct EditOptions {
  mut rename_old : String?
  mut rename_new : String?
  mut prune : Bool
} derive(Debug, Eq)

///|
/// 子命令（add / query / remove / init / import / describe / export / help）
pub(all) enum Command {
  Add(AddOptions)
  Query(QueryOptions)
  Remove(Array[String])
  Init(InitOptions)
  Import(ImportOptions)
  Describe(DescribeOptions)
  Export(ExportOptions)
  Status(StatusOptions)
  /// 数据库编辑（jumbit 扩展，上游无；规格 §1.4）
  Edit(EditOptions)
  /// stdio MCP 服务器（jumbit 扩展，上游无）
  Mcp
  Help
  /// 版本输出（--version/-V，对齐上游 clap 顶层面）
  Version
  /// 无参数调用：帮助全文走 stderr、退出码 2（对齐上游 clap 无子命令）；
  /// 与 Help（help/--help/-h 显式请求，stdout + 0）区分
  Usage
  Unknown(String)
  /// 参数值语义错误（flag 组合冲突/值非法）：文案原样上报，不带「未知命令」前缀
  Invalid(String)
} derive(Debug, Eq)

///|
/// 子命令解析（args 不含程序名，@env.args() 已验证）
pub fn parse(args : Array[String]) -> Command {
  if args.is_empty() {
    return Usage
  }
  // 顶层面 --version/-V（对齐上游 clap）：独立使用输出版本退出 0；
  // 后随多余参数按用法错误退出 2（clap unexpected argument）
  if args[0] == "--version" || args[0] == "-V" {
    if args.length() == 1 {
      return Version
    }
    return Invalid("unexpected argument '\{args[1]}'")
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
    "status" => parse_status(rest)
    "edit" => parse_edit(rest)
    "mcp" => parse_mcp(rest)
    "help" | "--help" | "-h" => Help
    // 顶层 flag 形态的未知 token：clap 报 unexpected argument（实测上游
    // zoxide --bogus 同文案），裸 token 才是 unrecognized subcommand
    other if other.has_prefix("-") => Invalid("unexpected argument '\{other}'")
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
/// `--flag=value` 等号形式剥离（对齐上游 clap 双形态）：`--` 前缀且名部
/// 非 `--` 的 token 切首个 `=`，返回 (名部, 值部)；其余原样返回 None。
/// 值部可含 `=`、可为空串；`--=x` 不是 flag，交还坏参路
fn split_eq_flag(token : String) -> (String, String)? {
  if !token.has_prefix("--") {
    return None
  }
  match token.split_once("=") {
    Some((name, value)) => {
      let name = name.to_owned()
      if name == "--" {
        None
      } else {
        Some((name, value.to_owned()))
      }
    }
    None => None
  }
}

///|
/// flag 匹配：空格形式 token 等名，或等号形式名部等名
fn eq_flag_match(raw : String, pair : (String, String)?, name : String) -> Bool {
  if raw == name {
    return true
  }
  match pair {
    Some((flag, _)) => flag == name
    None => false
  }
}

///|
/// --hook 值 → Hook 枚举（空格/等号两形态共用的取值校验）
fn parse_hook(v : String) -> @tpl.Hook? {
  match v {
    "pwd" => Some(@tpl.HookPwd)
    "prompt" => Some(@tpl.HookPrompt)
    "none" => Some(@tpl.HookNone)
    _ => None
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
/// 版本行（--version/-V 输出，与 usage 首行同源）
pub fn version() -> String {
  "jumbit \{@jumbit.VERSION}"
}

///|
pub fn usage() -> String {
  "jumbit \{@jumbit.VERSION} — a MoonBit rewrite of zoxide\n\n" +
  "Usage:\n" +
  "  jumbit add [--score N] <path>...        record directories (--score sets this visit's weight)\n" +
  "  jumbit remove <path>...                 remove directories from the database\n" +
  "  jumbit query [kw]...                    print the highest-scoring match\n" +
  "    --list                                print all matches (by score, descending)\n" +
  "    --score                               prefix each line with its score\n" +
  "    --all                                 skip the existence check\n" +
  "    --exclude <path>                      exclude a path (exact match)\n" +
  "    --interactive                         select interactively with fzf\n" +
  "    --json                                print all matches as a single-line JSON array (agent channel, mutually exclusive with --interactive)\n" +
  "    --fuzzy                               fall back to component substrings when exact matching finds nothing (jumbit extension)\n" +
  "    --tsv                                 print Tab-separated path/score/last_accessed/matched_by (jumbit extension, mutually exclusive with --json/--interactive)\n" +
  "    --limit <n>                           print only the first n entries (with --list/--json/--tsv, jumbit extension)\n" +
  "  jumbit init <shell>                     generate shell integration code (defines j/ji by default, hook=pwd)\n" +
  "    [--cmd C] [--hook pwd|prompt|none] [--no-cmd]\n" +
  "  jumbit import <plugin> [--merge]        import history data from other tools (empty database imports directly, --merge merges into a non-empty one)\n" +
  "  jumbit describe <path> [--note text]    show or set a human note (--note \"\" clears, jumbit extension)\n" +
  "  jumbit export --agents                  print the project map as Markdown (paste into AGENTS.md, jumbit extension)\n" +
  "    plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z (bad lines are reported one by one, never aborting)\n" +
  "  jumbit status [--json] [--check]        database self-check: entries/notes/format/threshold (--check scans existence, --json for agents, jumbit extension)\n" +
  "  jumbit mcp                              start the stdio MCP server (agent channel, tools: jumbit_query / jumbit_export_agents, jumbit extension)\n" +
  "  jumbit edit                             edit the database with $VISUAL/$EDITOR (jumbit extension)\n" +
  "    [--rename <old> <new>] | [--prune]    rename a path (notes follow) / drop nonexistent entries; mutually exclusive\n" +
  "  jumbit help                             print this help\n" +
  "  jumbit --version                        print version (-V works too)\n\n" +
  "Environment variables:\n" +
  "  _JB_DATA_DIR                            data directory (default $HOME/.local/share/jumbit, must be absolute)\n" +
  "  _JB_ECHO=1                              echo directories as they are recorded\n" +
  "  _JB_EXCLUDE_DIRS                        colon-separated glob list, matched paths are kept out of the database\n" +
  "  _JB_FZF_OPTS                            extra arguments passed through to fzf\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  resolve symlinks when recording (queries do not follow them)\n" +
  "  _JB_MAXAGE=N                            aging threshold for the database total score (default 10000)\n" +
  "import reads each plugin's standard data file, located via _Z_DATA/_FASD_DATA/ZSHZ_DATA/_ZL_DATA/XDG_DATA_HOME"
}
