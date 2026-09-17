///|
/// import 支持的插件（对齐上游 ImportFrom 枚举；z.lua / zsh-z 带点与连字符）
pub fn import_plugins() -> Array[String] {
  ["atuin", "autojump", "fasd", "z", "z.lua", "zsh-z"]
}

///|
/// import 参数解析：一个插件名位置参数 + 任意位置的 --merge；
/// 未知 flag / 多余位置参数 / 非法插件名归 Unknown（对齐 clap 退出码 2）
fn parse_import(args : Array[String]) -> Command {
  let mut plugin : String? = None
  let mut merge = false
  let mut bad : String? = None
  for a in args {
    if a == "--merge" {
      merge = true
    } else if a.has_prefix("-") && a != "-" {
      bad = Some(a)
    } else if plugin is None {
      plugin = Some(a)
    } else {
      bad = Some(a)
    }
  }
  match bad {
    Some(flag) => Unknown(flag)
    None =>
      match plugin {
        Some(p) =>
          if import_plugins().contains(p) {
            Import({ plugin: p, merge, })
          } else {
            Unknown(
              "import: 不支持的插件: \{p}（支持 \{import_plugins().join("/")}）",
            )
          }
        None =>
          Unknown(
            "import: 缺少插件参数（\{import_plugins().join("/")}）",
          )
      }
  }
}
