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
  Unknown(String)
  /// 参数值语义错误（flag 组合冲突/值非法）：文案原样上报，不带「未知命令」前缀
  Invalid(String)
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
    "status" => parse_status(rest)
    "edit" => parse_edit(rest)
    "mcp" => parse_mcp(rest)
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
  "    --tsv                                Tab 分隔输出 path/score/last_accessed/matched_by（jumbit 扩展，与 --json/--interactive 互斥）\n" +
  "    --limit <n>                           只输出前 n 条（与 --list/--json/--tsv 组合，jumbit 扩展）\n" +
  "  jumbit init <shell>                     生成 shell 集成脚本（默认定义 j/ji，hook=pwd）\n" +
  "    [--cmd C] [--hook pwd|prompt|none] [--no-cmd]\n" +
  "  jumbit import <plugin> [--merge]        从其他工具导入历史数据（空库直灌，--merge 合并进非空库）\n" +
  "  jumbit describe <path> [--note text]     查看/设置人工标注（--note \"\" 清除，jumbit 扩展）\n" +
  "  jumbit export --agents                   输出项目地图 Markdown（贴进 AGENTS.md，jumbit 扩展）\n" +
  "    plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z（坏行逐条上报不中止）\n" +
  "  jumbit status [--json] [--check]         数据库自检：条目/标注/版本/阈值（--check 扫存在性，--json 给 agent，jumbit 扩展）\n" +
  "  jumbit mcp                              启动 stdio MCP 服务器（agent 通道，tool：jumbit_query / jumbit_export_agents，jumbit 扩展）\n" +
  "  jumbit edit                             用 $VISUAL/$EDITOR 编辑数据库（jumbit 扩展）\n" +
  "    [--rename <old> <new>] | [--prune]    改路径（标注跟随）/ 清除不存在条目；三形态互斥\n" +
  "  jumbit help                             显示本帮助\n\n" +
  "环境变量：\n" +
  "  _JB_DATA_DIR                            数据目录（默认 $HOME/.local/share/jumbit，须绝对路径）\n" +
  "  _JB_ECHO=1                              add 时回显记录的目录\n" +
  "  _JB_EXCLUDE_DIRS                        冒号分隔的 glob 列表，命中即从库中移除\n" +
  "  _JB_FZF_OPTS                            透传给 fzf 的自定义参数\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  add 时解析符号链接（查询时反向不跟随）\n" +
  "  _JB_MAXAGE=N                            数据库总分老化阈值（默认 10000）\n" +
  "import 读取各插件标准数据文件，可经 _Z_DATA/_FASD_DATA/ZSHZ_DATA/_ZL_DATA/XDG_DATA_HOME 定位"
}
