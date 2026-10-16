// Glob matcher tests

///|
test "star: crosses separators (matching upstream glob crate default require_literal_separator=false)" {
  @debug.assert_eq(@core.glob_match("*", "foo"), true)
  @debug.assert_eq(@core.glob_match("*", ""), true)
  @debug.assert_eq(@core.glob_match("*", "/foo"), true)
  @debug.assert_eq(@core.glob_match("*", "foo/bar"), true)
  @debug.assert_eq(@core.glob_match("**", "a/b"), true)
  @debug.assert_eq(@core.glob_match("/foo/*", "/foo/bar"), true)
  @debug.assert_eq(@core.glob_match("/foo/*", "/foo/bar/baz"), true)
  @debug.assert_eq(@core.glob_match("/*/bar", "/foo/bar"), true)
  // a pure literal with no wildcard still has to match exactly (crossing separators != a literal crossing them)
  @debug.assert_eq(@core.glob_match("foobar", "/foobar"), false)
}

///|
test "question mark: exactly one character (separators included, the glob crate default)" {
  @debug.assert_eq(@core.glob_match("?", "a"), true)
  @debug.assert_eq(@core.glob_match("?", "ab"), false)
  @debug.assert_eq(@core.glob_match("?", "/"), true)
  @debug.assert_eq(@core.glob_match("?", ""), false)
  @debug.assert_eq(@core.glob_match("a?c", "abc"), true)
}

///|
test "character classes: enumeration and negation" {
  @debug.assert_eq(@core.glob_match("[abc]", "a"), true)
  @debug.assert_eq(@core.glob_match("[abc]", "d"), false)
  @debug.assert_eq(@core.glob_match("[!a]", "b"), true)
  @debug.assert_eq(@core.glob_match("[!a]", "a"), false)
  @debug.assert_eq(@core.glob_match("[!a]", "/"), true)
  @debug.assert_eq(@core.glob_match("[a-z]", "m"), true)
  @debug.assert_eq(@core.glob_match("[a-z]", "M"), false)
  // a '-' at the end of a class is a literal
  @debug.assert_eq(@core.glob_match("[a-]", "-"), true)
}

///|
test "escaping: the next character matches literally" {
  @debug.assert_eq(@core.glob_match("\\*", "a"), false)
  @debug.assert_eq(@core.glob_match("\\*", "*"), true)
  @debug.assert_eq(@core.glob_match("\\?", "?"), true)
  @debug.assert_eq(@core.glob_match("a\\*b", "a*b"), true)
  @debug.assert_eq(@core.glob_match("\\[a]", "[a]"), true)
  @debug.assert_eq(@core.glob_match("\\a", "a"), true)
}

///|
test "braces: literal semantics (pinning the difference from the upstream glob crate)" {
  @debug.assert_eq(@core.glob_match("{a,b}", "{a,b}"), true)
  @debug.assert_eq(@core.glob_match("{a,b}", "a"), false)
}

///|
test "multi-component paths and literals" {
  @debug.assert_eq(@core.glob_match("foo/bar", "foo/bar"), true)
  @debug.assert_eq(@core.glob_match("foo/bar", "foo/baz"), false)
  @debug.assert_eq(@core.glob_match("/foo/ba*", "/foo/bar"), true)
}

///|
test "a zero-width star: a trailing separator and empty-segment matches (matching the glob crate per-character semantics)" {
  @debug.assert_eq(@core.glob_match("foo/*", "foo/"), true)
  @debug.assert_eq(@core.glob_match("foo/*", "foo"), false)
  @debug.assert_eq(@core.glob_match("foo/*bar", "foo/xxbar"), true)
}

///|
test "validation: an illegal pattern errors" {
  @debug.assert_eq(@core.validate_glob("[abc"), Some(@core.UnclosedBracket))
  @debug.assert_eq(@core.validate_glob("[]"), Some(@core.EmptyClass))
  @debug.assert_eq(@core.validate_glob("[!]"), Some(@core.EmptyClass))
  @debug.assert_eq(@core.validate_glob("[z-a]"), Some(@core.InvalidRange))
  @debug.assert_eq(@core.validate_glob("abc\\"), Some(@core.TrailingEscape))
  @debug.assert_eq(@core.validate_glob("/foo/*"), None)
  @debug.assert_eq(@core.validate_glob("[!a-z]x"), None)
}

///|
test "validation: an unterminated range, and a '-' at the end of a class" {
  // an unterminated '[' holding a range
  @debug.assert_eq(@core.validate_glob("[a-z"), Some(@core.UnclosedBracket))
  // a '-' at the end of a class is a literal and thus legal
  @debug.assert_eq(@core.validate_glob("[a-]"), None)
  @debug.assert_eq(@core.validate_glob("[-a]"), None)
  // a range followed by ']': the ']' terminates the class, so the range is legal
  @debug.assert_eq(@core.validate_glob("[a-z]"), None)
}

///|
test "glob_matches: a legal one matches, an illegal one returns the error" {
  @debug.assert_eq(@core.glob_matches("*", "foo"), Ok(true))
  @debug.assert_eq(@core.glob_matches("[x", "x"), Err(@core.UnclosedBracket))
}

///|
test "the boundary where the pattern and the path are equally long" {
  @debug.assert_eq(@core.glob_match("abc", "abc"), true)
  @debug.assert_eq(@core.glob_match("abc", "abcd"), false)
  @debug.assert_eq(@core.glob_match("abcd", "abc"), false)
  @debug.assert_eq(@core.glob_match("", ""), true)
  @debug.assert_eq(@core.glob_match("", "a"), false)
}

///|
test "out-of-range record check: the matcher is total over illegal patterns (no panic)" {
  // record check (2026-09-25): the four kinds of illegal pattern validate_glob rejects are fed straight to
  // glob_match (the worst case, bypassing the front gate); every index access in the matcher is bounds-guarded, so
  // garbage in, garbage out (a Bool) but never an out-of-range panic; the entry gates are config\'s per-pattern
  // validate at parse time, the escape_glob default, and the glob_matches public surface (the record is in the roadmap)
  let invalid = [
    "[abc", // unterminated
     "[]", // an empty class
     "[!]", // an empty negated class
     "[z-a]", // a reversed range
     "abc\\", // a trailing escape
     "[", // a bare [
  ]
  for p in invalid {
    let _ = @core.glob_match(p, "/usr/local/bin")
    let _ = @core.glob_match(p, "")
    let _ = @core.glob_match(p, "[abc")
  }
  // the trivial match of an empty pattern against an empty path
  inspect(@core.glob_match("", ""), content="true")
  inspect(@core.glob_match("", "/x"), content="false")
}
