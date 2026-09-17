///|
/// status 参数解析（jumbit 扩展）：--json / --check，无位置参数
fn parse_status(args : Array[String]) -> Command {
  let opts : StatusOptions = { json: false, check: false, }
  let mut bad : String? = None
  for a in args {
    if a == "--json" {
      opts.json = true
    } else if a == "--check" {
      opts.check = true
    } else {
      bad = Some(a)
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None => Status(opts)
  }
}
