// 路径规范化测试

///|
test "绝对路径：解析 .. 与 ." {
  @debug.assert_eq(@core.resolve_path("/a/b/../c", "/"), "/a/c")
  @debug.assert_eq(@core.resolve_path("/a/./b", "/"), "/a/b")
  @debug.assert_eq(@core.resolve_path("/a//b", "/"), "/a/b")
}

///|
test "相对路径：基于当前目录拼接" {
  @debug.assert_eq(@core.resolve_path("a/b", "/x/y"), "/x/y/a/b")
  @debug.assert_eq(@core.resolve_path("./a", "/x/y"), "/x/y/a")
  @debug.assert_eq(@core.resolve_path("../a", "/x/y"), "/x/a")
  @debug.assert_eq(@core.resolve_path("../..", "/x/y"), "/")
}

///|
test "越界 ..：停在根" {
  @debug.assert_eq(@core.resolve_path("/..", "/"), "/")
  @debug.assert_eq(@core.resolve_path("/../../a", "/"), "/a")
}

///|
test "空路径与根" {
  @debug.assert_eq(@core.resolve_path("", "/x/y"), "/x/y")
  @debug.assert_eq(@core.resolve_path("/", "/x/y"), "/")
  @debug.assert_eq(@core.resolve_path(".", "/x/y"), "/x/y")
}
