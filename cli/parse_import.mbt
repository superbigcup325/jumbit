///|
/// The plugins import supports (matching upstream\'s ImportFrom enum; z.lua and zsh-z carry a dot and a hyphen)
pub fn import_plugins() -> Array[String] {
  ["atuin", "autojump", "fasd", "z", "z.lua", "zsh-z"]
}

///|
/// import\'s argument parsing: one plugin-name positional plus --merge anywhere;
/// an unknown flag, a surplus positional or an illegal plugin name goes Unknown (matching clap\'s exit code 2)
fn parse_import(args : Array[String]) -> Command {
  let mut plugin : String? = None
  let mut merge = false
  let mut bad : String? = None
  for a in args {
    if a == "--merge" {
      merge = true
    } else if a.has_prefix("-") && a != "-" {
      bad = Some("unexpected argument '\{a}'")
    } else if plugin is None {
      plugin = Some(a)
    } else {
      bad = Some("unexpected argument '\{a}'")
    }
  }
  match bad {
    Some(flag) => Invalid(flag)
    None =>
      match plugin {
        Some(p) =>
          if import_plugins().contains(p) {
            Import({ plugin: p, merge, })
          } else {
            Invalid(
              "invalid value '\{p}' for '<PLUGIN>'\n  [possible values: \{import_plugins().join(", ")}]",
            )
          }
        None =>
          Invalid(
            "missing required argument '<PLUGIN>'\n  [possible values: \{import_plugins().join(", ")}]",
          )
      }
  }
}
