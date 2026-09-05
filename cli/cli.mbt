///|
/// 子命令（MVP 命令面：add / query / help）
pub(all) enum Command {
  Add(Array[String])
  Query(Array[String])
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
    "query" => Query(rest)
    "help" | "--help" | "-h" => Help
    other => Unknown(other)
  }
}

///|
pub fn usage() -> String {
  "jumbit \{@jumbit.VERSION} — a MoonBit rewrite of zoxide\n\n" +
  "用法：\n" +
  "  jumbit add <path>...   记录目录\n" +
  "  jumbit query [kw]...   输出最高得分的目录\n" +
  "  jumbit help            显示本帮助\n\n" +
  "环境变量：\n" +
  "  _JB_DATA_DIR           数据目录（默认 $HOME/.local/share/jumbit，须绝对路径）"
}
