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
test "星号零宽：尾分隔符与空段匹配（对齐上游 glob crate 逐字符语义）" {
  @debug.assert_eq(@core.glob_match("foo/*", "foo/"), true)
  @debug.assert_eq(@core.glob_match("foo/*", "foo"), false)
  @debug.assert_eq(@core.glob_match("foo/*bar", "foo/xxbar"), true)
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
test "校验：区间未闭合与类尾 '-' 的边界" {
  // 含区间的未闭合 '['
  @debug.assert_eq(@core.validate_glob("[a-z"), Some(@core.UnclosedBracket))
  // '-' 在类尾为字面量，合法
  @debug.assert_eq(@core.validate_glob("[a-]"), None)
  @debug.assert_eq(@core.validate_glob("[-a]"), None)
  // 区间后紧跟 ']'：']' 终止类，区间合法
  @debug.assert_eq(@core.validate_glob("[a-z]"), None)
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

///|
test "越界留档核实：匹配器对非法 pattern 全函数（无 panic）" {
  // 留档核实（2026-09-25）：validate_glob 拒绝的四类非法 pattern 直接喂
  // glob_match（绕过前置闸的最坏情况），匹配器所有索引访问均有边界守卫，
  // 垃圾进垃圾出（返回 Bool）但绝不越界 panic；入口闸=config 解析期逐个
  // validate + escape_glob 默认值 + glob_matches 公开面（核实记录见 roadmap）
  let invalid = [
    "[abc", // 未闭合
     "[]", // 空类
     "[!]", // 空否定类
     "[z-a]", // 倒序区间
     "abc\\", // 尾转义
     "[", // 裸 [
  ]
  for p in invalid {
    let _ = @core.glob_match(p, "/usr/local/bin")
    let _ = @core.glob_match(p, "")
    let _ = @core.glob_match(p, "[abc")
  }
  // 空 pattern 与空路径的平凡匹配
  inspect(@core.glob_match("", ""), content="true")
  inspect(@core.glob_match("", "/x"), content="false")
}
