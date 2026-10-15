///|
/// mcp\'s argument parsing (a jumbit extension): no persistent flag, so any positional or flag goes Unknown
fn parse_mcp(args : Array[String]) -> Command {
  let mut bad : String? = None
  for a in args {
    bad = Some("unexpected argument '\{a}'")
  }
  match bad {
    Some(arg) => Invalid(arg)
    None => Mcp
  }
}
