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
