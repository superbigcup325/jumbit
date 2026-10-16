// win32 path-semantics tests: matching the cfg!(windows) branch of upstream util::resolve_path
// (source reading plus Rust std::path::Component semantics; a real-machine comparison awaits the Windows dataset
// landing). The pure functions compile everywhere, so Linux can pin the semantics; the wbtest calls private names directly.

///|
test "win32: resolution of an absolute drive-letter path" {
  assert_eq(resolve_path_windows("C:\\a\\b", "C:\\w"), "C:\\a\\b")
  // both forward and backward slashes are separators, and the output normalizes to backslashes (Rust PathBuf Display)
  assert_eq(resolve_path_windows("C:/a/b", "C:\\w"), "C:\\a\\b")
  assert_eq(resolve_path_windows("C:/a\\../b", "C:\\w"), "C:\\b")
  assert_eq(resolve_path_windows("C:\\a\\..\\c", "C:\\w"), "C:\\c")
  assert_eq(resolve_path_windows("C:\\.\\a\\", "C:\\w"), "C:\\a")
  // the drive letter keeps its case (Rust Prefix semantics)
  assert_eq(resolve_path_windows("c:\\X", "C:\\w"), "c:\\X")
  // repeated separators collapse
  assert_eq(resolve_path_windows("C:\\\\a///b", "C:\\w"), "C:\\a\\b")
}

///|
test "win32: .. past the root stops at the root (pop-unless-RootDir)" {
  assert_eq(resolve_path_windows("C:\\..\\x", "C:\\w"), "C:\\x")
  assert_eq(resolve_path_windows("C:\\a\\..\\..\\x", "C:\\w"), "C:\\x")
}

///|
test "win32: a drive-relative path (D:foo)" {
  // same drive: fall back to base (upstream get_drive_relative takes the cwd)
  assert_eq(resolve_path_windows("C:foo", "C:\\work"), "C:\\work\\foo")
  // another drive: fall back to `C:\` (upstream also consults the =C: environment variable, and jumbit has no env channel, so the difference is noted)
  assert_eq(resolve_path_windows("C:foo", "D:\\x"), "C:\\foo")
  assert_eq(resolve_path_windows("C:a\\..", "D:\\x"), "C:\\")
  // a drive-relative path mixed with forward slashes
  assert_eq(resolve_path_windows("C:foo/bar", "C:\\work"), "C:\\work\\foo\\bar")
}

///|
test "win32: a root with no drive letter borrows the base\'s (upstream takes the cwd\'s)" {
  assert_eq(resolve_path_windows("\\foo", "C:\\work"), "C:\\foo")
  assert_eq(resolve_path_windows("\\..", "C:\\work"), "C:\\")
  assert_eq(resolve_path_windows("/foo/bar", "C:\\work"), "C:\\foo\\bar")
}

///|
test "win32: a purely relative path is joined onto base" {
  assert_eq(resolve_path_windows("foo\\bar", "C:\\w"), "C:\\w\\foo\\bar")
  assert_eq(resolve_path_windows("..\\bar", "C:\\w\\x"), "C:\\w\\bar")
  assert_eq(resolve_path_windows(".", "C:\\w"), "C:\\w")
  assert_eq(resolve_path_windows("..", "C:\\w\\x"), "C:\\w")
  // non-ASCII path segments are kept as is
  assert_eq(
    resolve_path_windows("目录\\子目录", "C:\\w"),
    "C:\\w\\目录\\子目录",
  )
}

///|
test "win32: VerbatimDisk becomes an ordinary drive letter (as upstream)" {
  assert_eq(resolve_path_windows("\\\\?\\C:\\a\\..\\b", "C:\\w"), "C:\\b")
  assert_eq(resolve_path_windows("\\\\?\\C:", "C:\\w"), "C:\\")
  assert_eq(resolve_path_windows("\\\\?\\C:\\x", "D:\\y"), "C:\\x")
}

///|
test "win32: UNC/device prefixes are best-effort (upstream errors; the difference is noted)" {
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
test "win32: a colon segment that is not a drive letter is an ordinary segment (Rust Prefix accepts ASCII letters only)" {
  assert_eq(resolve_path_windows("1:\\a", "C:\\w"), "C:\\w\\1:\\a")
  assert_eq(resolve_path_windows(":x", "C:\\w"), "C:\\w\\:x")
}

///|
// Migrated from the old path_test.mbt: the pub surface takes the win32 branch in a Windows build, so POSIX expectations
// can only be asserted at the implementation level (calling the private implementation, which is testable everywhere)
test "posix: resolving .. and . in an absolute path" {
  assert_eq(resolve_path_posix("/a/b/../c", "/"), "/a/c")
  assert_eq(resolve_path_posix("/a/./b", "/"), "/a/b")
  assert_eq(resolve_path_posix("/a//b", "/"), "/a/b")
}

///|
test "posix: a relative path is joined onto the current directory" {
  assert_eq(resolve_path_posix("a/b", "/x/y"), "/x/y/a/b")
  assert_eq(resolve_path_posix("./a", "/x/y"), "/x/y/a")
  assert_eq(resolve_path_posix("../a", "/x/y"), "/x/a")
  assert_eq(resolve_path_posix("../..", "/x/y"), "/")
}

///|
test "posix: .. past the root stops at the root" {
  assert_eq(resolve_path_posix("/..", "/"), "/")
  assert_eq(resolve_path_posix("/../../a", "/"), "/a")
}

///|
test "posix: an empty path and the root" {
  assert_eq(resolve_path_posix("", "/x/y"), "/x/y")
  assert_eq(resolve_path_posix("/", "/x/y"), "/")
  assert_eq(resolve_path_posix(".", "/x/y"), "/x/y")
}

///|
test "posix: base is always a normalized path, so its .. and . and empty segments are ignored" {
  // upstream base = current_dir(), which through Path::components never holds .. or . segments, so this
  // implementation silently drops such segments in base (pinned as a precondition)
  assert_eq(resolve_path_posix("a", "/x/../y/./z"), "/x/y/z/a")
  assert_eq(resolve_path_posix("a", "/x//y"), "/x/y/a")
  assert_eq(resolve_path_posix("a", "/x/y/"), "/x/y/a")
}
