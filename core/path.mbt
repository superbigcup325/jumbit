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

///|
/// 组件级前缀判断（对齐 std::path::Path::starts_with）：
/// "/foo/ba" 不是 "/foo/bar" 的前缀；空 base 是任意路径的前缀。
pub fn starts_with(path : String, base : String) -> Bool {
  let path_segs = non_empty_segments(path)
  let base_segs = non_empty_segments(base)
  if base_segs.length() > path_segs.length() {
    return false
  }
  for i in 0..<base_segs.length() {
    if path_segs[i] != base_segs[i] {
      return false
    }
  }
  true
}

///|
/// 按分隔符切分并丢弃空段（"/" 与 "" 的段列表均为空）
fn non_empty_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  for seg in path.split("/") {
    if seg != "" {
      out.push(seg.to_owned())
    }
  }
  out
}
