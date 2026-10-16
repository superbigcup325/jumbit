// Platform separator-layer tests (sep.mbt): two cfg-symmetric groups, each platform running its own assertions.
// The semantic authority = std::path::is_separator plus the glob crate (separator equivalence at lib.rs:1050),
// the same origin as upstream stream.rs:90. Note that a '\' on the pattern side is always an escape (platform-independent), so
// a Windows-shaped pattern is always written with forward slashes

///|
// The POSIX group: not compiled in a Windows build (under double-recognition 92 is a separator too, so the assertion would not hold)
#cfg(not(platform="windows"))
test "posix: is_path_separator is only '/', normalization is the identity" {
  assert_eq(is_path_separator(47), true) // '/'
  assert_eq(is_path_separator(92), false) // '\'
  assert_eq(normalize_separators("C:\\a\\b"), "C:\\a\\b")
  assert_eq(normalize_separators("/a/b"), "/a/b")
  assert_eq(literal_sep_equiv(92, 47), false)
}

///|
// The Windows group: the full-chain semantics of backslash paths in the database
#cfg(platform="windows")
test "win32: is_path_separator recognises both, and normalization" {
  assert_eq(is_path_separator(47), true)
  assert_eq(is_path_separator(92), true)
  assert_eq(normalize_separators("C:\\a\\b"), "C:/a/b")
  // keyword final-component anchoring: a backslash path in the database is judged by the platform separator
  assert_eq(filter_by_keywords(["user", "work"], "C:\\home\\user\\work"), true)
  assert_eq(filter_by_keywords(["work", "user"], "C:\\home\\user\\work"), false)
  // fuzzy component substrings: the backslash splits components
  assert_eq(filter_by_keywords_fuzzy(["ork"], "C:\\home\\user\\work"), true)
}

///|
#cfg(platform="windows")
test "win32: glob wildcards cross separators, and literal equivalence" {
  // a backslash on the pattern side is always an escape, so a Windows-shaped pattern uses forward slashes
  // '*' crosses separators (the glob crate default require_literal_separator=false;
  // while the old implementation blocked separators this case was a #skip open question, dissolved once the default semantics were adopted)
  assert_eq(glob_match("C:/*", "C:\\a\\b"), true)
  assert_eq(glob_match("C:/*/*", "C:\\a\\b"), true)
  // a literal '/' on the pattern side matches a backslash on the path side (the glob crate's Windows behaviour)
  assert_eq(glob_match("C:/home/*", "C:\\home\\user"), true)
  assert_eq(glob_match("C:/home/*", "C:\\home\\a\\b"), true)
  // '?' and [...] match any single character (the separator included)
  assert_eq(glob_match("C:/?ome", "C:\\home"), true)
  // starts_with is a component-level prefix (backslash form)
  assert_eq(starts_with("C:\\foo\\bar\\baz", "C:\\foo\\bar"), true)
  assert_eq(starts_with("C:\\foo\\ba", "C:\\foo\\bar"), false)
}
