///|
/// The data directory: _JB_DATA_DIR first (and it must be an absolute path), otherwise $HOME/.local/share/jumbit
/// Environment reads are injected through `get` (cmd/jumbit passes @env.get_env_var, tests pass a closure)
pub fn data_dir(get : (String) -> String?) -> Result[String, String] {
  match get("_JB_DATA_DIR") {
    Some(dir) =>
      if is_absolute(dir) {
        Ok(dir)
      } else {
        Err("jumbit: _JB_DATA_DIR must be an absolute path: \{dir}")
      }
    None =>
      match get("HOME") {
        Some(home) => Ok(home + "/.local/share/jumbit")
        None =>
          Err("jumbit: cannot determine the data directory: set _JB_DATA_DIR")
      }
  }
}

///|
/// Absolute-path test: on POSIX it starts with /. On Windows a drive root (C:\ or C:/) counts too,
/// as do UNC/device paths (leading \\ or //); a POSIX-shaped leading / is accepted by the Win32 API as well
/// (Git Bash/MSYS interop), so it passes too
#cfg(platform="windows")
fn is_absolute(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\\\") {
    return true
  }
  let rooted = path.length() >= 3 &&
    ({
      let c0 = path.get_char(0)
      (c0 is Some(c) && c >= 'a' && c <= 'z') ||
      (c0 is Some(c) && c >= 'A' && c <= 'Z')
    }) &&
    path.get_char(1) == Some(':') &&
    ({
      let c2 = path.get_char(2)
      c2 == Some('/') || c2 == Some('\\')
    })
  rooted
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// _JB_EXCLUDE_DIRS: a colon-separated glob list; a matching entry is lazily deleted at query time.
/// When unset it falls back to the home directory itself (escaped into a literal glob, matching upstream\'s default).
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
            Some(_) =>
              return Err("jumbit: invalid glob in _JB_EXCLUDE_DIRS: \{pattern}")
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
/// _JB_RESOLVE_SYMLINKS: only the value "1" takes effect (matching upstream config::resolve_symlinks)
pub fn resolve_symlinks(get : (String) -> String?) -> Bool {
  match get("_JB_RESOLVE_SYMLINKS") {
    Some("1") => true
    _ => false
  }
}

///|
/// Glob escaping: a backslash in front of `\ * ? [ ]` (matching upstream Pattern::escape)
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
/// _JB_MAXAGE: the aging threshold for the database\'s total score (10000 by default; upstream parses it as u32, so the
/// domain is 0..=4294967295 and a leading + is legal -- Rust u32::from_str semantics, probed against 0.10.0)
pub fn maxage(get : (String) -> String?) -> Result[Double, String] {
  match get("_JB_MAXAGE") {
    None => Ok(10000.0)
    Some(value) => {
      let body = if value.has_prefix("+") { value[1:] } else { value }
      let n = @string.parse_uint(body) catch {
        _ =>
          return Err(
            "jumbit: _JB_MAXAGE must be a non-negative integer: \{value}",
          )
      }
      Ok(n.to_double())
    }
  }
}

///|
/// _JB_FZF_OPTS: custom arguments passed through to fzf (via the FZF_DEFAULT_OPTS environment variable)
pub fn fzf_opts(get : (String) -> String?) -> String? {
  get("_JB_FZF_OPTS")
}
