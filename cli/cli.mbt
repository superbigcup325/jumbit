///|
/// query 的选项与关键词（--exclude 为精确路径，对齐上游语义；glob 排除走 _JB_EXCLUDE_DIRS）
pub(all) struct QueryOptions {
  keywords : Array[String]
  mut all : Bool
  mut list : Bool
  mut score : Bool
  mut exclude : String?
} derive(Debug, Eq)

///|
/// 子命令（MVP 命令面：add / query / help）
pub(all) enum Command {
  Add(Array[String])
  Query(QueryOptions)
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
    "add" => Add(rest)
    "query" => parse_query(rest)
    "help" | "--help" | "-h" => Help
    other => Unknown(other)
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
    exclude: None,
  }
  let mut bad : String? = None
  let n = args.length()
  let mut i = 0
  while i < n {
    match args[i] {
      "--all" => opts.all = true
      "--list" => opts.list = true
      "--score" => opts.score = true
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
    i += 1
  }
  match bad {
    Some(flag) => Unknown(flag)
    None => Query(opts)
  }
}

///|
pub fn usage() -> String {
  "jumbit \{@jumbit.VERSION} — a MoonBit rewrite of zoxide\n\n" +
  "用法：\n" +
  "  jumbit add <path>...                    记录目录\n" +
  "  jumbit query [kw]...                    输出最高得分匹配目录\n" +
  "    --list                                输出全部匹配（按得分降序）\n" +
  "    --score                               前缀显示得分\n" +
  "    --all                                 跳过存在性检查\n" +
  "    --exclude <path>                      排除指定目录（精确路径）\n" +
  "  jumbit help                             显示本帮助\n\n" +
  "环境变量：\n" +
  "  _JB_DATA_DIR                            数据目录（默认 $HOME/.local/share/jumbit，须绝对路径）\n" +
  "  _JB_ECHO=1                              add 时回显记录的目录\n" +
  "  _JB_EXCLUDE_DIRS                        冒号分隔的 glob 列表，命中即从库中移除\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  add 时解析符号链接（查询时反向不跟随）"
}
