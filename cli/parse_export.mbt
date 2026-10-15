///|
/// export\'s argument parsing: --agents is the only target for now; a missing --agents or an unknown flag goes Unknown
fn parse_export(args : Array[String]) -> Command {
  let opts : ExportOptions = { agents: false, }
  let mut bad : String? = None
  for a in args {
    if a == "--agents" {
      opts.agents = true
    } else {
      bad = Some("unexpected argument '\{a}'")
    }
  }
  match bad {
    Some(flag) => Invalid(flag)
    None =>
      if opts.agents {
        Export(opts)
      } else {
        Invalid("export: missing required argument '--agents'")
      }
  }
}
