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

///|
test "base 恒为规范路径：其中的 .. 与 . 与空段被忽略" {
  // 上游 base = current_dir()，经 Path::components 恒不含 .. / . 段，
  // 故本实现对 base 中此类段静默丢弃（锁定为前置条件规格）
  @debug.assert_eq(@core.resolve_path("a", "/x/../y/./z"), "/x/y/z/a")
  @debug.assert_eq(@core.resolve_path("a", "/x//y"), "/x/y/a")
  @debug.assert_eq(@core.resolve_path("a", "/x/y/"), "/x/y/a")
}
