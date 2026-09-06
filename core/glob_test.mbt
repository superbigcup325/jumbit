// glob 匹配器测试

///|
test "星号：不跨分隔符" {
  @debug.assert_eq(@core.glob_match("*", "foo"), true)
  @debug.assert_eq(@core.glob_match("*", ""), true)
  @debug.assert_eq(@core.glob_match("*", "/foo"), false)
  @debug.assert_eq(@core.glob_match("*", "foo/bar"), false)
  @debug.assert_eq(@core.glob_match("**", "a/b"), false)
  @debug.assert_eq(@core.glob_match("/foo/*", "/foo/bar"), true)
  @debug.assert_eq(@core.glob_match("/foo/*", "/foo/bar/baz"), false)
  @debug.assert_eq(@core.glob_match("/*/bar", "/foo/bar"), true)
}

///|
test "问号：恰好一字且不匹配分隔符" {
  @debug.assert_eq(@core.glob_match("?", "a"), true)
  @debug.assert_eq(@core.glob_match("?", "ab"), false)
  @debug.assert_eq(@core.glob_match("?", "/"), false)
  @debug.assert_eq(@core.glob_match("?", ""), false)
  @debug.assert_eq(@core.glob_match("a?c", "abc"), true)
}

///|
test "字符类：枚举与取反" {
  @debug.assert_eq(@core.glob_match("[abc]", "a"), true)
  @debug.assert_eq(@core.glob_match("[abc]", "d"), false)
  @debug.assert_eq(@core.glob_match("[!a]", "b"), true)
  @debug.assert_eq(@core.glob_match("[!a]", "a"), false)
  @debug.assert_eq(@core.glob_match("[!a]", "/"), false)
  @debug.assert_eq(@core.glob_match("[a-z]", "m"), true)
  @debug.assert_eq(@core.glob_match("[a-z]", "M"), false)
  // '-' 在类尾为字面量
  @debug.assert_eq(@core.glob_match("[a-]", "-"), true)
}

///|
test "转义：下一字符按字面量" {
  @debug.assert_eq(@core.glob_match("\\*", "a"), false)
  @debug.assert_eq(@core.glob_match("\\*", "*"), true)
  @debug.assert_eq(@core.glob_match("\\?", "?"), true)
  @debug.assert_eq(@core.glob_match("a\\*b", "a*b"), true)
  @debug.assert_eq(@core.glob_match("\\[a]", "[a]"), true)
  @debug.assert_eq(@core.glob_match("\\a", "a"), true)
}

///|
test "花括号：字面量语义（与上游 glob crate 的差异锁定）" {
  @debug.assert_eq(@core.glob_match("{a,b}", "{a,b}"), true)
  @debug.assert_eq(@core.glob_match("{a,b}", "a"), false)
}

///|
test "多组件路径与字面量" {
  @debug.assert_eq(@core.glob_match("foo/bar", "foo/bar"), true)
  @debug.assert_eq(@core.glob_match("foo/bar", "foo/baz"), false)
  @debug.assert_eq(@core.glob_match("/foo/ba*", "/foo/bar"), true)
}

///|
test "校验：非法 pattern 报错" {
  @debug.assert_eq(@core.validate_glob("[abc"), Some(@core.UnclosedBracket))
  @debug.assert_eq(@core.validate_glob("[]"), Some(@core.EmptyClass))
  @debug.assert_eq(@core.validate_glob("[!]"), Some(@core.EmptyClass))
  @debug.assert_eq(@core.validate_glob("[z-a]"), Some(@core.InvalidRange))
  @debug.assert_eq(@core.validate_glob("abc\\"), Some(@core.TrailingEscape))
  @debug.assert_eq(@core.validate_glob("/foo/*"), None)
  @debug.assert_eq(@core.validate_glob("[!a-z]x"), None)
}

///|
test "glob_matches：合法走匹配、非法回传错误" {
  @debug.assert_eq(@core.glob_matches("*", "foo"), Ok(true))
  @debug.assert_eq(@core.glob_matches("[x", "x"), Err(@core.UnclosedBracket))
}

///|
test "pattern 与路径等长边界" {
  @debug.assert_eq(@core.glob_match("abc", "abc"), true)
  @debug.assert_eq(@core.glob_match("abc", "abcd"), false)
  @debug.assert_eq(@core.glob_match("abcd", "abc"), false)
  @debug.assert_eq(@core.glob_match("", ""), true)
  @debug.assert_eq(@core.glob_match("", "a"), false)
}
