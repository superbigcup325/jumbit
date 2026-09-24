// win32 路径语义测试：对齐上游 util::resolve_path 的 cfg!(windows) 分支
// （源码阅读 + Rust std::path::Component 语义；真机对拍待 Windows dataset
// 落地后补）。纯函数全平台编译，Linux 侧即可锁定语义；wbtest 直呼私有名。

///|
test "win32：绝对盘符路径规范化" {
  assert_eq(resolve_path_windows("C:\\a\\b", "C:\\w"), "C:\\a\\b")
  // 正斜杠与反斜杠均为分隔符，输出归一为反斜杠（Rust PathBuf Display）
  assert_eq(resolve_path_windows("C:/a/b", "C:\\w"), "C:\\a\\b")
  assert_eq(resolve_path_windows("C:/a\\../b", "C:\\w"), "C:\\b")
  assert_eq(resolve_path_windows("C:\\a\\..\\c", "C:\\w"), "C:\\c")
  assert_eq(resolve_path_windows("C:\\.\\a\\", "C:\\w"), "C:\\a")
  // 盘符大小写保留（Rust Prefix 语义）
  assert_eq(resolve_path_windows("c:\\X", "C:\\w"), "c:\\X")
  // 重复分隔符折叠
  assert_eq(resolve_path_windows("C:\\\\a///b", "C:\\w"), "C:\\a\\b")
}

///|
test "win32：越界 .. 停在根（pop-unless-RootDir）" {
  assert_eq(resolve_path_windows("C:\\..\\x", "C:\\w"), "C:\\x")
  assert_eq(resolve_path_windows("C:\\a\\..\\..\\x", "C:\\w"), "C:\\x")
}

///|
test "win32：盘符相对路径（D:foo）" {
  // 同盘：回落 base（上游 get_drive_relative 取 cwd）
  assert_eq(resolve_path_windows("C:foo", "C:\\work"), "C:\\work\\foo")
  // 跨盘：回落 `C:\`（上游另查 =C: 环境变量，jumbit 无 env 通道，注记差异）
  assert_eq(resolve_path_windows("C:foo", "D:\\x"), "C:\\foo")
  assert_eq(resolve_path_windows("C:a\\..", "D:\\x"), "C:\\")
  // 盘符相对与正斜杠混用
  assert_eq(resolve_path_windows("C:foo/bar", "C:\\work"), "C:\\work\\foo\\bar")
}

///|
test "win32：根无盘符借 base 盘符（上游取 cwd 盘符）" {
  assert_eq(resolve_path_windows("\\foo", "C:\\work"), "C:\\foo")
  assert_eq(resolve_path_windows("\\..", "C:\\work"), "C:\\")
  assert_eq(resolve_path_windows("/foo/bar", "C:\\work"), "C:\\foo\\bar")
}

///|
test "win32：纯相对基于 base 拼接" {
  assert_eq(resolve_path_windows("foo\\bar", "C:\\w"), "C:\\w\\foo\\bar")
  assert_eq(resolve_path_windows("..\\bar", "C:\\w\\x"), "C:\\w\\bar")
  assert_eq(resolve_path_windows(".", "C:\\w"), "C:\\w")
  assert_eq(resolve_path_windows("..", "C:\\w\\x"), "C:\\w")
  // 非 ASCII 字符段原样保留
  assert_eq(
    resolve_path_windows("目录\\子目录", "C:\\w"),
    "C:\\w\\目录\\子目录",
  )
}

///|
test "win32：VerbatimDisk 转普通盘符（上游同款）" {
  assert_eq(resolve_path_windows("\\\\?\\C:\\a\\..\\b", "C:\\w"), "C:\\b")
  assert_eq(resolve_path_windows("\\\\?\\C:", "C:\\w"), "C:\\")
  assert_eq(resolve_path_windows("\\\\?\\C:\\x", "D:\\y"), "C:\\x")
}

///|
test "win32：UNC/设备前缀 best-effort（上游报错，注记差异）" {
  assert_eq(
    resolve_path_windows("\\\\srv\\share\\a\\..\\b", "C:\\w"),
    "\\\\srv\\share\\b",
  )
  assert_eq(
    resolve_path_windows("\\\\srv\\share\\..", "C:\\w"),
    "\\\\srv\\share",
  )
  assert_eq(resolve_path_windows("\\\\.\\C:\\x", "C:\\w"), "\\\\.\\C:\\x")
}

///|
test "win32：非盘符冒号段按普通段处理（Rust Prefix 仅认 ASCII 字母）" {
  assert_eq(resolve_path_windows("1:\\a", "C:\\w"), "C:\\w\\1:\\a")
  assert_eq(resolve_path_windows(":x", "C:\\w"), "C:\\w\\:x")
}

///|
// 原 path_test.mbt 迁入：pub 面在 Windows 构建走 win32 分支，POSIX 期望值
// 只能在实现级断言（直呼 private 实现，全平台可测）
test "posix：绝对路径解析 .. 与 ." {
  assert_eq(resolve_path_posix("/a/b/../c", "/"), "/a/c")
  assert_eq(resolve_path_posix("/a/./b", "/"), "/a/b")
  assert_eq(resolve_path_posix("/a//b", "/"), "/a/b")
}

///|
test "posix：相对路径基于当前目录拼接" {
  assert_eq(resolve_path_posix("a/b", "/x/y"), "/x/y/a/b")
  assert_eq(resolve_path_posix("./a", "/x/y"), "/x/y/a")
  assert_eq(resolve_path_posix("../a", "/x/y"), "/x/a")
  assert_eq(resolve_path_posix("../..", "/x/y"), "/")
}

///|
test "posix：越界 .. 停在根" {
  assert_eq(resolve_path_posix("/..", "/"), "/")
  assert_eq(resolve_path_posix("/../../a", "/"), "/a")
}

///|
test "posix：空路径与根" {
  assert_eq(resolve_path_posix("", "/x/y"), "/x/y")
  assert_eq(resolve_path_posix("/", "/x/y"), "/")
  assert_eq(resolve_path_posix(".", "/x/y"), "/x/y")
}

///|
test "posix：base 恒为规范路径，其中的 .. 与 . 与空段被忽略" {
  // 上游 base = current_dir()，经 Path::components 恒不含 .. / . 段，
  // 故本实现对 base 中此类段静默丢弃（锁定为前置条件规格）
  assert_eq(resolve_path_posix("a", "/x/../y/./z"), "/x/y/z/a")
  assert_eq(resolve_path_posix("a", "/x//y"), "/x/y/a")
  assert_eq(resolve_path_posix("a", "/x/y/"), "/x/y/a")
}
