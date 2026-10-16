///|
/// The platform path-separator test (matching std::path::is_separator, the same origin as the glob crate):
/// POSIX accepts only '/'; Windows accepts '\' as well. Keyword final-component anchoring and the fuzzy component-substring check share
/// this test (glob wildcards now follow the glob crate\'s default semantics and cross separators, so they no longer depend on it),
/// giving a single semantic authority (the same as upstream stream.rs:90)
#cfg(platform="windows")
fn is_path_separator(c : Int32) -> Bool {
  c == 47 || c == 92
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn is_path_separator(c : Int32) -> Bool {
  c == 47
}

///|
/// Separator normalization (Windows: '\' -> '/', one code unit for one code unit so the length is unchanged and the caller's
/// index logic is unaffected; component content is unaffected -- under Windows '\' is always a separator).
/// For entry points that "split and handle each component"; per-character streaming matching (glob) does not go through it
/// but uses is_path_separator. On POSIX it returns as is
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
/// Separator equivalence for a literal glob token: under Windows a literal '/' on the pattern side matches
/// any separator on the path side (the same Windows is_separator equivalence as glob crate lib.rs:1050);
/// a '\' on the pattern side (an escaped literal backslash) keeps an exact match and takes no part in the equivalence.
/// On POSIX it is always false (there is no equivalence)
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn literal_sep_equiv(sc : Int32, c : Int32) -> Bool {
  let _ = sc
  let _ = c
  false
}

///|
#cfg(platform="windows")
fn literal_sep_equiv(sc : Int32, c : Int32) -> Bool {
  c == 47 && is_path_separator(sc)
}
