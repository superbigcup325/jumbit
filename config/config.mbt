///|
/// 数据目录：_JB_DATA_DIR 优先（必须绝对路径），否则回落 $HOME/.local/share/jumbit
/// get 注入环境变量读取（cmd/main 传 @env.get_env_var，测试传闭包）
pub fn data_dir(get : (String) -> String?) -> Result[String, String] {
  match get("_JB_DATA_DIR") {
    Some(dir) =>
      if is_absolute(dir) {
        Ok(dir)
      } else {
        Err("_JB_DATA_DIR 必须是绝对路径: \{dir}")
      }
    None =>
      match get("HOME") {
        Some(home) => Ok(home + "/.local/share/jumbit")
        None => Err("无法确定数据目录：请设置 _JB_DATA_DIR")
      }
  }
}

///|
/// 绝对路径判定（Linux：以 / 开头）
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// _JB_EXCLUDE_DIRS：冒号分隔的 glob 列表，命中条目在查询时被懒删除。
/// 未设置时回落 home 目录本身（转义为字面 glob，对齐上游默认值）。
pub fn exclude_dirs(
  get : (String) -> String?,
  home : String?,
) -> Result[Array[String], String] {
  match get("_JB_EXCLUDE_DIRS") {
    Some(value) => {
      let out : Array[String] = []
      for part in value.split(":") {
        let pattern = part.to_owned()
        if pattern != "" {
          match @core.validate_glob(pattern) {
            Some(_) => return Err("非法 glob in _JB_EXCLUDE_DIRS: \{pattern}")
            None => out.push(pattern)
          }
        }
      }
      Ok(out)
    }
    None =>
      match home {
        Some(h) => Ok([escape_glob(h)])
        None => Ok([])
      }
  }
}

///|
/// _JB_RESOLVE_SYMLINKS：仅值 "1" 生效（对齐上游 config::resolve_symlinks）
pub fn resolve_symlinks(get : (String) -> String?) -> Bool {
  match get("_JB_RESOLVE_SYMLINKS") {
    Some("1") => true
    _ => false
  }
}

///|
/// glob 转义：对 `\ * ? [ ]` 前置反斜杠（对齐上游 Pattern::escape）
pub fn escape_glob(path : String) -> String {
  let sb = StringBuilder()
  for c in path {
    if c == '\\' || c == '*' || c == '?' || c == '[' || c == ']' {
      sb.write_char('\\')
    }
    sb.write_char(c)
  }
  sb.to_string()
}

///|
/// _JB_MAXAGE：数据库总分老化阈值（默认 10000；上游解析为 u32，这里同限制）
pub fn maxage(get : (String) -> String?) -> Result[Double, String] {
  match get("_JB_MAXAGE") {
    None => Ok(10000.0)
    Some(value) => {
      let n = @string.parse_int(value) catch {
        _ => return Err("_JB_MAXAGE 必须是非负整数: \{value}")
      }
      if n < 0 {
        Err("_JB_MAXAGE 必须是非负整数: \{value}")
      } else {
        Ok(n.to_double())
      }
    }
  }
}

///|
/// _JB_FZF_OPTS：透传给 fzf 的自定义参数（经 FZF_DEFAULT_OPTS 环境变量）
pub fn fzf_opts(get : (String) -> String?) -> String? {
  get("_JB_FZF_OPTS")
}
