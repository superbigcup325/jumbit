// json 写出层单测：转义/数字/整行形状（字节级断言）

///|
test "json_escape：引号反斜杠与常用控制字符" {
  @debug.assert_eq(json_escape("a\"b\\c"), "a\\\"b\\\\c")
  @debug.assert_eq(json_escape("l1\nl2\r\t"), "l1\\nl2\\r\\t")
  @debug.assert_eq(json_escape("\u{0008}\u{000C}"), "\\b\\f")
}

///|
test "json_escape：罕见控制字符 \\u 化（4 位补零）" {
  @debug.assert_eq(json_escape("\u{0001}"), "\\u0001")
  @debug.assert_eq(json_escape("\u{001F}"), "\\u001f")
}

///|
test "json_escape：非 ASCII 原样透传、普通串不变" {
  @debug.assert_eq(json_escape("/home/用户/博客"), "/home/用户/博客")
  @debug.assert_eq(json_escape("/plain/path"), "/plain/path")
  @debug.assert_eq(json_escape(""), "")
}

///|
test "json_number：有限数原样、NaN/Inf 出 null" {
  @debug.assert_eq(json_number(12.5), "12.5")
  @debug.assert_eq(json_number(4.0), "4")
  @debug.assert_eq(json_number(-0.75), "-0.75")
  @debug.assert_eq(json_number(0.0 / 0.0), "null")
  @debug.assert_eq(json_number(1.0 / 0.0), "null")
  @debug.assert_eq(json_number(-1.0 / 0.0), "null")
}

///|
test "render_json：空数组与多条目形状（键序固定）" {
  let now = 1000L
  @debug.assert_eq(render_json([], now, "exact"), "[]")
  // last_accessed 距 now 不足 1h → score 含 ×4.0 衰减乘数
  let d1 : @core.Dir = { path: "/a", rank: 1.0, last_accessed: 999L, }
  let d2 : @core.Dir = { path: "/b x\"y", rank: 2.0, last_accessed: 998L, }
  @debug.assert_eq(
    render_json([d1, d2], now, "exact"),
    "[{\"path\":\"/a\",\"score\":4,\"last_accessed\":999,\"matched_by\":\"exact\"}," +
    "{\"path\":\"/b x\\\"y\",\"score\":8,\"last_accessed\":998,\"matched_by\":\"exact\"}]",
  )
}
