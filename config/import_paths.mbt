///|
/// Data-file path resolution for the import plugins (matching the data_path probing in upstream src/import/*.rs;
/// jumbit follows Linux semantics and has none of upstream\'s macOS/Windows branches).
/// Environment reads are injected through `get` (cmd/main passes @env.get_env_var, tests pass a closure).

///|
/// z: $_Z_DATA otherwise $HOME/.z (upstream does not filter empty values, so an empty string is used as the path and reports could not read when opened)
pub fn z_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_Z_DATA") {
    Some(p) => Ok(p)
    None => home_path(get, ".z")
  }
}

///|
/// zsh-z: $ZSHZ_DATA, otherwise $_Z_DATA, otherwise $HOME/.z.
/// This matches upstream\'s Rust code (var_os\'s Some("") still takes the first one); the zsh-z script\'s
/// `${ZSHZ_DATA:-$_Z_DATA}` (which lets empty values through) is a known upstream discrepancy, and the upstream code wins here.
pub fn zsh_z_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("ZSHZ_DATA") {
    Some(p) => Ok(p)
    None => z_data_path(get)
  }
}

///|
/// fasd: $_FASD_DATA otherwise $HOME/.fasd (also without filtering empty values)
pub fn fasd_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_FASD_DATA") {
    Some(p) => Ok(p)
    None => home_path(get, ".fasd")
  }
}

///|
/// autojump (Linux): $XDG_DATA_HOME otherwise $HOME/.local/share, then autojump/autojump.txt
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
/// z.lua main path: $_ZL_DATA (empty values filtered out; on non-Windows, Windows-style values are filtered too, to keep a Cygwin/MSYS
/// environment from leaking in, matching upstream looks_like_windows_path), otherwise $HOME/.zlua
pub fn zlua_data_path(get : (String) -> String?) -> Result[String, String] {
  match get("_ZL_DATA") {
    Some(p) => if p != "" && !looks_like_windows_path(p) { return Ok(p) }
    None => ()
  }
  home_path(get, ".zlua")
}

///|
/// z.lua\'s fish-variant data file (the fallback when the main path is missing):
/// $XDG_DATA_HOME otherwise $HOME/.local/share, then zlua/zlua.txt
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
/// A relative path under $HOME; an unset HOME reports the same wording as upstream
fn home_path(get : (String) -> String?, sub : String) -> Result[String, String] {
  match get("HOME") {
    Some(h) => Ok(h + "/" + sub)
    None => Err("jumbit: could not find home directory")
  }
}

///|
/// Matches Lua\'s `^%a:[/\\]`: an ASCII letter + colon + a slash or backslash
fn looks_like_windows_path(s : String) -> Bool {
  if s.length() < 3 {
    return false
  }
  let c0 = s[0]
  let is_alpha = (c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z')
  is_alpha && s[1] == ':' && (s[2] == '/' || s[2] == '\\')
}
