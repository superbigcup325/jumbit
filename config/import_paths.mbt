///|
/// 导入插件的数据文件路径解析（对齐上游 src/import/*.rs 各 data_path 的探测逻辑；
/// jumbit 按 Linux 语义，不设上游的 macOS/Windows 分支）。
/// get 注入环境变量读取（cmd/main 传 @env.get_env_var，测试传闭包）。

///|
/// z：$_Z_DATA 否则 $HOME/.z（上游不滤空值，空串原样作为路径，打开时报 could not read）
pub fn z_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_Z_DATA") {
    Some(p) => Ok(p)
    None => home_path(get, ".z")
  }
}

///|
/// zsh-z：$ZSHZ_DATA 否则 $_Z_DATA 否则 $HOME/.z。
/// 对齐上游 Rust 代码（var_os 的 Some("") 也命中第一个），与 zsh-z 脚本的
/// `${ZSHZ_DATA:-$_Z_DATA}`（空值穿透）存在上游已知差异，此处从上游代码。
pub fn zsh_z_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("ZSHZ_DATA") {
    Some(p) => Ok(p)
    None => z_data_path(get)
  }
}

///|
/// fasd：$_FASD_DATA 否则 $HOME/.fasd（同样不滤空值）
pub fn fasd_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_FASD_DATA") {
    Some(p) => Ok(p)
    None => home_path(get, ".fasd")
  }
}

///|
/// autojump（Linux）：$XDG_DATA_HOME 否则 $HOME/.local/share，再接 autojump/autojump.txt
pub fn autojump_data_path(get : (String) -> String?) -> Result[String, String] {
  let base = match get("XDG_DATA_HOME") {
    Some(x) => x
    None =>
      match home_path(get, ".local/share") {
        Ok(h) => h
        Err(e) => return Err(e)
      }
  }
  Ok(base + "/autojump/autojump.txt")
}

///|
/// z.lua 主路径：$_ZL_DATA（滤空值；非 Windows 上滤 Windows 风格值，防 Cygwin/MSYS
/// 环境泄漏，对齐上游 looks_like_windows_path）否则 $HOME/.zlua
pub fn zlua_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_ZL_DATA") {
    Some(p) => if p != "" && !looks_like_windows_path(p) { return Ok(p) }
    None => ()
  }
  home_path(get, ".zlua")
}

///|
/// z.lua 的 fish 变体数据文件（主路径缺失时的回落目标）：
/// $XDG_DATA_HOME 否则 $HOME/.local/share，再接 zlua/zlua.txt
pub fn zlua_fish_path(get : (String) -> String?) -> Result[String, String] {
  let base = match get("XDG_DATA_HOME") {
    Some(x) => x
    None =>
      match home_path(get, ".local/share") {
        Ok(h) => h
        Err(e) => return Err(e)
      }
  }
  Ok(base + "/zlua/zlua.txt")
}

///|
/// $HOME 下的相对路径；HOME 未设置报上游同文案错误
fn home_path(get : (String) -> String?, sub : String) -> Result[String, String] {
  match get("HOME") {
    Some(h) => Ok(h + "/" + sub)
    None => Err("could not find home directory")
  }
}

///|
/// 匹配 Lua `^%a:[/\\]`：ASCII 字母 + 冒号 + 斜杠或反斜杠
fn looks_like_windows_path(s : String) -> Bool {
  if s.length() < 3 {
    return false
  }
  let c0 = s[0]
  let is_alpha = (c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z')
  is_alpha && s[1] == ':' && (s[2] == '/' || s[2] == '\\')
}
