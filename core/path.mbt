///|
/// 路径规范化：相对路径基于 base（当前目录）绝对化，解析 `.` 与 `..`，
/// 不解析符号链接（对齐上游 util::resolve_path，仅 Linux 语义）。
pub fn resolve_path(path : String, base : String) -> String {
  let stack : Array[String] = []
  if !path.has_prefix("/") {
    for seg in base.split("/") {
      if seg != "" && seg != "." && seg != ".." {
        stack.push(seg.to_owned())
      }
    }
  }
  for seg in path.split("/") {
    if seg == "" || seg == "." {
      continue
    } else if seg == ".." {
      // 越过根目录时停 在根（pop 空栈无效果）
      ignore(stack.pop())
    } else {
      stack.push(seg.to_owned())
    }
  }
  if stack.is_empty() {
    "/"
  } else {
    "/" + stack.join("/")
  }
}
