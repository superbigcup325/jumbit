///|
/// Path resolution: a relative path is made absolute against a base (the current directory) and `.` and `..` are resolved;
/// symlinks are not resolved (matching upstream util::resolve_path). Separator semantics are dispatched at compile time
/// per target platform: Windows follows the win32 component model (drive letters, double separators), everything else POSIX.
/// The cfg is attached only to the private implementation choice, so the public signature and the .mbti freeze stay platform-invariant
/// (a cfg-ed-out pub item would vanish from .mbti and make the interface gate drift by platform, so it must not be lifted).
#cfg(platform="windows")
pub fn resolve_path(path : String, base : String) -> String {
  resolve_path_windows(path, base)
}

///|
/// The non-Windows side covers every non-native backend (negating platform would also match wasm/js,
/// and the official docs warn that a platform condition implies target="native")
#cfg(not(platform="windows"))
pub fn resolve_path(path : String, base : String) -> String {
  resolve_path_posix(path, base)
}

///|
/// The POSIX implementation: `/` is the only separator and an empty stack falls back to the root `/` (matching the branch
/// outside upstream cfg!(windows)). In a Windows build its only caller (the pub twin) is cfg-ed out, which would warn unused,
/// so that lint is turned off; the semantics are pinned through the pub surface by path_test.mbt
#warnings("-unused_value")
fn resolve_path_posix(path : String, base : String) -> String {
  let stack : Array[String] = []
  if !path.has_prefix("/") {
    for seg in base.split("/") {
      if seg != "" && seg != "." && seg != ".." {
        stack.push(seg.to_owned())
      }
    }
  }
  for seg in path.split("/") {
    if seg == "" || seg == "." {
      continue
    } else if seg == ".." {
      // going past the root stops at the root (popping an empty stack does nothing)
      ignore(stack.pop())
    } else {
      stack.push(seg.to_owned())
    }
  }
  if stack.is_empty() {
    "/"
  } else {
    "/" + stack.join("/")
  }
}

///|
/// The win32 prefix-scan result. consumed holds only the prefix characters; rooted means a root separator follows the prefix
priv struct WinPrefix {
  drive : Char?
  verbatim : Bool
  unc : String?
  rooted : Bool
  consumed : Int32
}

///|
/// The win32 prefix scan (matching the subset of std::path::Prefix that upstream\'s get_drive_letter branch depends on):
/// Disk (`C:`), VerbatimDisk (`\\?\C:`, which upstream normalizes to an ordinary drive letter), and a best-effort
/// pass-through of UNC/device prefixes (upstream bails with "invalid path", but the public signature has no error
/// channel, so the difference is noted in the README).
/// A drive letter counts only at the start of the path (Rust Prefix semantics), and both `/` and `\` are separators
fn scan_windows_prefix(path : String) -> WinPrefix {
  let len = path.length()
  if len >= 2 && is_windows_sep(path, 0) && is_windows_sep(path, 1) {
    // VerbatimDisk: `\\?\C:` (6 characters)
    let verbatim_disk = len >= 6 &&
      path.get_char(2) == Some('?') &&
      is_windows_sep(path, 3) &&
      is_ascii_alpha(path.get_char(4)) &&
      path.get_char(5) == Some(':')
    if verbatim_disk {
      return {
        drive: path.get_char(4),
        verbatim: true,
        unc: None,
        rooted: len > 6 && is_windows_sep(path, 6),
        consumed: 6,
      }
    }
    // UNC (`\\server\share`) / device (`\\.\`): consume the server and share segments
    let mut i = 2
    while i < len && !is_windows_sep(path, i) {
      i += 1
    }
    if i < len {
      let mut j = i + 1
      while j < len && !is_windows_sep(path, j) {
        j += 1
      }
      return {
        drive: None,
        verbatim: false,
        unc: Some(path[0:j].to_owned()),
        rooted: j < len,
        consumed: j,
      }
    }
    return {
      drive: None,
      verbatim: false,
      unc: Some(path),
      rooted: false,
      consumed: len,
    }
  }
  if len >= 2 &&
    is_ascii_alpha(path.get_char(0)) &&
    path.get_char(1) == Some(':') {
    return {
      drive: path.get_char(0),
      verbatim: false,
      unc: None,
      rooted: len > 2 && is_windows_sep(path, 2),
      consumed: 2,
    }
  }
  {
    drive: None,
    verbatim: false,
    unc: None,
    rooted: len > 0 && is_windows_sep(path, 0),
    consumed: 0,
  }
}

///|
/// win32 resolution (matching the cfg!(windows) branch of upstream util::resolve_path).
/// Two differences noted from upstream (the public signature has no error/env channel; the README\'s differences list follows):
/// 1. a drive-relative path crossing drives falls straight back to `D:\`, where upstream also consults the `=D:` environment variable
/// 2. UNC/device prefixes are resolved best-effort, where upstream errors
/// In a non-Windows build its only caller (the pub twin) is cfg-ed out and would warn unused (wbtest references do not
/// count for the main-code check), so that lint is turned off; the semantics are pinned by path_wbtest.mbt
#warnings("-unused_value")
fn resolve_path_windows(path : String, base : String) -> String {
  let p = scan_windows_prefix(path)
  let mut drive : Char? = p.drive
  let mut unc : String? = p.unc
  let mut rooted = p.rooted
  let normals : Array[String] = []
  // the seed: matching the three branches of upstream\'s stack initialization
  if p.unc is Some(_) {
    // a UNC prefix is itself the root, so there is no seed
  } else if p.drive is Some(d) {
    if p.verbatim {
      // the same as upstream: VerbatimDisk consumes an optional root and then forces an `X:\` seed
      rooted = true
    } else if !p.rooted {
      // drive-relative (`D:foo`): the same drive falls back to base, another drive to `D:\`
      let b = scan_windows_prefix(base)
      if b.drive == Some(d) {
        drive = b.drive
        rooted = b.rooted
        unc = b.unc
        push_windows_segments(normals, base, b.consumed, base.length())
      } else {
        rooted = true
      }
    }
  } else if p.rooted {
    // `\foo`: borrow the base\'s drive letter (upstream takes the cwd\'s, and a cwd always has one)
    drive = scan_windows_prefix(base).drive
  } else {
    // purely relative: seed in full from base
    let b = scan_windows_prefix(base)
    drive = b.drive
    rooted = b.rooted
    unc = b.unc
    push_windows_segments(normals, base, b.consumed, base.length())
  }
  push_windows_segments(normals, path, p.consumed, path.length())
  let joined = normals.join("\\")
  if unc is Some(u) {
    if normals.is_empty() {
      u
    } else {
      u + "\\" + joined
    }
  } else if drive is Some(d) {
    // a drive letter always carries a root (every seed path upstream is rooted)
    d.to_string() + ":\\" + joined
  } else if rooted {
    if normals.is_empty() {
      "\\"
    } else {
      "\\" + joined
    }
  } else if normals.is_empty() {
    "\\"
  } else {
    joined
  }
}

///|
/// Segment pushing: `.` is dropped and `..` pops with root protection (matching upstream\'s ParentDir
/// pop-unless-RootDir; a base that is a real cwd holds no dot segments, so the seed follows the same rule as the main loop)
fn push_windows_segments(
  normals : Array[String],
  path : String,
  start : Int32,
  end : Int32,
) -> Unit {
  let mut seg_start = start
  let mut i = start
  while i < end {
    let ch = path.get_char(i)
    if ch == Some('/') || ch == Some('\\') {
      if i > seg_start {
        push_one_segment(normals, path[seg_start:i].to_owned())
      }
      seg_start = i + 1
    }
    i += 1
  }
  if end > seg_start {
    push_one_segment(normals, path[seg_start:end].to_owned())
  }
}

///|
fn push_one_segment(normals : Array[String], seg : String) -> Unit {
  if seg == "." {
    return
  }
  if seg == ".." {
    ignore(normals.pop())
    return
  }
  normals.push(seg)
}

///|
fn is_windows_sep(path : String, i : Int32) -> Bool {
  path.get_char(i) == Some('/') || path.get_char(i) == Some('\\')
}

///|
fn is_ascii_alpha(ch : Char?) -> Bool {
  ch is Some(c) && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
}

///|
/// Component-level prefix test (matching std::path::Path::starts_with):
/// "/foo/ba" is not a prefix of "/foo/bar"; an empty base is a prefix of any path.
pub fn starts_with(path : String, base : String) -> Bool {
  let path_segs = non_empty_segments(path)
  let base_segs = non_empty_segments(base)
  if base_segs.length() > path_segs.length() {
    return false
  }
  for i in 0..<base_segs.length() {
    if path_segs[i] != base_segs[i] {
      return false
    }
  }
  true
}

///|
/// Split by separator and drop empty segments (both "/" and "" give an empty segment list);
/// under Windows the backslash is normalized first (one code unit for one, leaving component content unaffected)
fn non_empty_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in normalize_separators(path).split("/") {
    if seg != "" {
      out.push(seg.to_owned())
    }
  }
  out
}
