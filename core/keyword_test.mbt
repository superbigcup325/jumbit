// 关键词匹配测试：上游 stream.rs 全部 14 组 case 照搬 + 边界

///|
test "上游 case：大小写归一" {
  @debug.assert_eq(@core.filter_by_keywords(["fOo", "bAr"], "/foo/bar"), true)
}

///|
test "上游 case：末组件锚定" {
  @debug.assert_eq(@core.filter_by_keywords(["ba"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["fo"], "/foo/bar"), false)
}

///|
test "上游 case：slash 后缀" {
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["foo/"], "/foo/bar/baz"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo"), false)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["foo", "/"], "/foo/bar/baz"), true)
}

///|
test "上游 case：split components" {
  @debug.assert_eq(
    @core.filter_by_keywords(["/", "fo", "/", "ar"], "/foo/bar"),
    true,
  )
  @debug.assert_eq(@core.filter_by_keywords(["oo/ba"], "/foo/bar"), true)
}

///|
test "上游 case：overlap（不许重叠）" {
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
test "空关键词数组恒为 true" {
  @debug.assert_eq(@core.filter_by_keywords([], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords([], "/"), true)
}

///|
test "空串关键词：rev_find(\"\") 返回 Some(len)，与上游 rfind 语义一致" {
  @debug.assert_eq(@core.filter_by_keywords([""], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["ba", ""], "/foo/bar"), true)
}

///|
test "关键词长于路径：不匹配" {
  @debug.assert_eq(@core.filter_by_keywords(["foobarbaz"], "/foo"), false)
}

///|
test "路径以分隔符结尾：末组件锚定拒绝" {
  @debug.assert_eq(@core.filter_by_keywords(["ba"], "/foo/bar/"), false)
}

///|
test "路径只有根分隔符" {
  @debug.assert_eq(@core.filter_by_keywords([""], "/"), true)
  @debug.assert_eq(@core.filter_by_keywords(["x"], "/"), false)
}

///|
test "连续分隔符" {
  @debug.assert_eq(@core.filter_by_keywords(["//"], "/foo//bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["fo", "ba"], "/foo//bar"), true)
}

///|
test "大小写归一：仅 ASCII（全角不归一，与上游的差异锁定为规格）" {
  // 单关键词需命中末组件：BAR 落在 /foo/bar 末组件 ✓，FOO 右侧还有 /bar ✗
  @debug.assert_eq(@core.filter_by_keywords(["BAR"], "/foo/bar"), true)
  @debug.assert_eq(@core.filter_by_keywords(["FOO"], "/foo/bar"), false)
  @debug.assert_eq(@core.filter_by_keywords(["ＦＯＯ"], "/foo/bar"), false)
}

///|
test "最右命中：中间关键词取最靠右的出现，重叠即拒绝" {
  // "o" 最右出现在 "oo"（idx 2），截断后剩余 "/f" 容不下 "foo"
  @debug.assert_eq(@core.filter_by_keywords(["foo", "o"], "/foo"), false)
  // "oo" 命中后只剩 "/"，容不下 "o"
  @debug.assert_eq(@core.filter_by_keywords(["o", "oo"], "/foo"), false)
  // 与上游一致：最后 "o" 命中末字符，剩余 "/foobar" 容得下 "bar"
  @debug.assert_eq(@core.filter_by_keywords(["bar", "o"], "/foobar/o"), true)
}

///|
test "filter_by_keywords_fuzzy：各关键词独立命中组件子串（不限末组件、无序）" {
  // 关键词同组件乱序（exact 因有序消耗会 miss）
  assert_true(
    @core.filter_by_keywords_fuzzy(["work", "blog"], "/home/u/work-blog"),
  )
  // 关键词落在非末组件（exact 因末组件锚定会 miss）
  assert_true(@core.filter_by_keywords_fuzzy(["blog"], "/home/u/blog/work"))
  // ASCII 小写归一，与 exact 一致
  assert_true(@core.filter_by_keywords_fuzzy(["BLOG"], "/home/u/Work-Blog"))
  // 组件边界内的子串即可
  assert_true(@core.filter_by_keywords_fuzzy(["log"], "/home/u/work-blog"))
}

///|
test "filter_by_keywords_fuzzy：全部关键词须命中，缺一即 false" {
  assert_false(
    @core.filter_by_keywords_fuzzy(["blog", "zzz"], "/home/u/work-blog"),
  )
  assert_false(
    @core.filter_by_keywords_fuzzy(["nov1", "nov2"], "/home/u/work-blog"),
  )
}

///|
test "filter_by_keywords_fuzzy：空关键词恒 true（与 exact 一致）" {
  assert_true(@core.filter_by_keywords_fuzzy([], "/any/path"))
}
