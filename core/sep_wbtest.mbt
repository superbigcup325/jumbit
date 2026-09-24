// 平台分隔符层测试（sep.mbt）：cfg 对称双组，各平台跑各自的断言组。
// 语义权威 = std::path::is_separator + glob crate（lib.rs:1050 分隔符互等），
// 上游 stream.rs:90 同源。注意 pattern 侧 '\' 恒为转义字符（与平台无关），
// Windows 形态 pattern 一律用正斜杠书写

///|
// POSIX 组：Windows 构建不编译（双认语义下 92 也是分隔符，断言不成立）
#cfg(not(platform="windows"))
test "posix：is_path_separator 仅 '/'，归一恒等" {
  assert_eq(is_path_separator(47), true) // '/'
  assert_eq(is_path_separator(92), false) // '\'
  assert_eq(normalize_separators("C:\\a\\b"), "C:\\a\\b")
  assert_eq(normalize_separators("/a/b"), "/a/b")
  assert_eq(literal_sep_equiv(92, 47), false)
}

///|
// Windows 组：反斜杠库内路径的全链路语义
#cfg(platform="windows")
test "win32：is_path_separator 双认与归一" {
  assert_eq(is_path_separator(47), true)
  assert_eq(is_path_separator(92), true)
  assert_eq(normalize_separators("C:\\a\\b"), "C:/a/b")
  // 关键词末组件锚定：反斜杠库内路径按平台分隔符判定
  assert_eq(filter_by_keywords(["user", "work"], "C:\\home\\user\\work"), true)
  assert_eq(filter_by_keywords(["work", "user"], "C:\\home\\user\\work"), false)
  // fuzzy 组件子串：反斜杠组件化
  assert_eq(filter_by_keywords_fuzzy(["ork"], "C:\\home\\user\\work"), true)
}

///|
#cfg(platform="windows")
test "win32：glob 分隔符不跨与字面量等价" {
  // pattern 侧 '\' 恒为转义字符，Windows 形态 pattern 用正斜杠书写
  // '*' 不跨分隔符（path 侧 '\'）
  assert_eq(glob_match("C:/*", "C:\\a\\b"), false)
  assert_eq(glob_match("C:/*/*", "C:\\a\\b"), true)
  // pattern 侧字面 '/' 等价匹配 path 侧 '\'（glob crate Windows 同款）
  assert_eq(glob_match("C:/home/*", "C:\\home\\user"), true)
  assert_eq(glob_match("C:/home/*", "C:\\home\\a\\b"), false)
  // '?' 与 [...] 不匹配分隔符（含 '\'）
  assert_eq(glob_match("C:/?ome", "C:\\home"), false)
  // starts_with 组件级前缀（反斜杠形态）
  assert_eq(starts_with("C:\\foo\\bar\\baz", "C:\\foo\\bar"), true)
  assert_eq(starts_with("C:\\foo\\ba", "C:\\foo\\bar"), false)
}
