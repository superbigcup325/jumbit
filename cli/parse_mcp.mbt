///|
/// mcp 参数解析（jumbit 扩展）：无常服 flag，任何位置参数/flag 归 Unknown
fn parse_mcp(args : Array[String]) -> Command {
  let mut bad : String? = None
  for a in args {
    bad = Some(a)
  }
  match bad {
    Some(arg) => Unknown(arg)
    None => Mcp
  }
}
