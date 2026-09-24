///|
/// 平台路径分隔符判定（对齐 std::path::is_separator，glob crate 同源）：
/// POSIX 仅 '/'；Windows 额外认 '\'。关键词末组件锚定/fuzzy 组件子串/
/// glob 不跨分隔符共用此判定，语义权威单一（上游 stream.rs:90 同款）
#cfg(platform="windows")
fn is_path_separator(c : Int) -> Bool {
  c == 47 || c == 92
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn is_path_separator(c : Int) -> Bool {
  c == 47
}

///|
/// 分隔符归一（Windows：'\' → '/'，单码元换单码元长度不变，调用方的
/// 索引逻辑不受影响；组件内容不受影响——Windows 下 '\' 恒为分隔符）。
/// 供「切分后逐组件处理」的入口归一；逐字符流式匹配（glob）不走此函数，
/// 用 is_path_separator 判定。POSIX 原样返回
#cfg(platform="windows")
fn normalize_separators(path : String) -> String {
  if path.find("\\") is None {
    return path
  }
  let sb = StringBuilder()
  for i in 0..<path.length() {
    match path.get_char(i) {
      Some('\\') => sb.write_char('/')
      Some(ch) => sb.write_char(ch)
      None => ()
    }
  }
  sb.to_string()
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn normalize_separators(path : String) -> String {
  path
}

///|
/// glob 字面量 token 的分隔符等价：Windows 下 pattern 侧字面 '/' 匹配
/// path 侧任意分隔符（glob crate lib.rs:1050 Windows 同款 is_separator
/// 互等）；pattern 侧 '\'（经转义的字面反斜杠）保持精确匹配不参与等价。
/// POSIX 恒 false（无等价）
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn literal_sep_equiv(sc : Int, c : Int) -> Bool {
  let _ = sc
  let _ = c
  false
}

///|
#cfg(platform="windows")
fn literal_sep_equiv(sc : Int, c : Int) -> Bool {
  c == 47 && is_path_separator(sc)
}
