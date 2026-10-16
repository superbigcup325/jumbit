// Keyword matching tests: all 14 upstream stream.rs cases carried over, plus boundaries

///|
test "upstream case: case normalization" {
  @debug.assert_eq(@core.filter_by_keywords(["fOo", "bAr"], "/foo/bar"), true)
}

///|
test "upstream case: final-component anchoring" {
  @debug.assert_eq(@core.filter_by_keywords(["ba"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["fo"], "/foo/bar"), false)
}

///|
test "upstream case: the slash suffix" {
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo/bar/baz"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo/bar/baz"), true)
}

///|
test "upstream case: split components" {
  @debug.assert_eq(
    @core.filter_by_keywords(["/", "fo", "/", "ar"], "/foo/bar"),
    true,
  )
  @debug.assert_eq(@core.filter_by_keywords(["oo/ba"], "/foo/bar"), true)
}

///|
test "upstream case: overlap (not allowed)" {
  @debug.assert_eq(
    @core.filter_by_keywords(["foo", "o", "bar"], "/foo/bar"),
    false,
  )
  @debug.assert_eq(
    @core.filter_by_keywords(["/foo/", "/bar"], "/foo/bar"),
    false,
  )
  @debug.assert_eq(
    @core.filter_by_keywords(["/foo/", "/bar"], "/foo/baz/bar"),
    true,
  )
}

///|
test "an empty keyword array is always true" {
  @debug.assert_eq(@core.filter_by_keywords([], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords([], "/"), true)
}

///|
test "an empty-string keyword: rev_find(\"\") returns Some(len), matching upstream rfind" {
  @debug.assert_eq(@core.filter_by_keywords([""], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["ba", ""], "/foo/bar"), true)
}

///|
test "a keyword longer than the path: no match" {
  @debug.assert_eq(@core.filter_by_keywords(["foobarbaz"], "/foo"), false)
}

///|
test "a path ending in a separator: final-component anchoring rejects it" {
  @debug.assert_eq(@core.filter_by_keywords(["ba"], "/foo/bar/"), false)
}

///|
test "a path that is only the root separator" {
  @debug.assert_eq(@core.filter_by_keywords([""], "/"), true)
  @debug.assert_eq(@core.filter_by_keywords(["x"], "/"), false)
}

///|
test "consecutive separators" {
  @debug.assert_eq(@core.filter_by_keywords(["//"], "/foo//bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["fo", "ba"], "/foo//bar"), true)
}

///|
test "case normalization: ASCII only (full-width is not folded; the difference from upstream is pinned as the spec)" {
  // a single keyword must hit the final component: BAR lands in /foo/bar\'s final component (ok), FOO still has /bar to its right (no)
  @debug.assert_eq(@core.filter_by_keywords(["BAR"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["FOO"], "/foo/bar"), false)
  @debug.assert_eq(@core.filter_by_keywords(["ＦＯＯ"], "/foo/bar"), false)
}

///|
test "rightmost hit: an intermediate keyword takes its rightmost occurrence, and an overlap is rejected" {
  // "o" appears rightmost in "oo" (idx 2), and the remaining "/f" cannot hold "foo"
  @debug.assert_eq(@core.filter_by_keywords(["foo", "o"], "/foo"), false)
  // once "oo" hits, only "/" is left and cannot hold "o"
  @debug.assert_eq(@core.filter_by_keywords(["o", "oo"], "/foo"), false)
  // matching upstream: the last "o" hits the final character, leaving "/foobar" free to hold "bar"
  @debug.assert_eq(@core.filter_by_keywords(["bar", "o"], "/foobar/o"), true)
}

///|
test "filter_by_keywords_fuzzy: each keyword independently hits a component substring (no final-component anchoring, order-free)" {
  // keywords in one component out of order (exact would miss, since it consumes in order)
  assert_true(
    @core.filter_by_keywords_fuzzy(["work", "blog"], "/home/u/work-blog"),
  )
  // a keyword in a non-final component (exact would miss, since it anchors the final component)
  assert_true(@core.filter_by_keywords_fuzzy(["blog"], "/home/u/blog/work"))
  // ASCII lowercase normalization, as in exact
  assert_true(@core.filter_by_keywords_fuzzy(["BLOG"], "/home/u/Work-Blog"))
  // a substring inside a component boundary is enough
  assert_true(@core.filter_by_keywords_fuzzy(["log"], "/home/u/work-blog"))
}

///|
test "filter_by_keywords_fuzzy: every keyword must hit; one missing makes it false" {
  assert_false(
    @core.filter_by_keywords_fuzzy(["blog", "zzz"], "/home/u/work-blog"),
  )
  assert_false(
    @core.filter_by_keywords_fuzzy(["nov1", "nov2"], "/home/u/work-blog"),
  )
}

///|
test "filter_by_keywords_fuzzy: empty keywords are always true (as in exact)" {
  assert_true(@core.filter_by_keywords_fuzzy([], "/any/path"))
}
