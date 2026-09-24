///|
/// 路径规范化：相对路径基于 base（当前目录）绝对化，解析 `.` 与 `..`，
/// 不解析符号链接（对齐上游 util::resolve_path）。分隔符语义按目标平台
/// 编译期分发：Windows 走 win32 组件模型（盘符/双分隔符），其余走 POSIX。
/// cfg 只挂在 private 实现的选择上，公共签名与 .mbti 冻结面平台不变
/// （pub 项被 cfg 掉会从 .mbti 消失，接口闸门随平台漂移，故不得上提）。
#cfg(platform="windows")
pub fn resolve_path(path : String, base : String) -> String {
  resolve_path_windows(path, base)
}

///|
/// 非 Windows 侧含全部非 native 后端（platform 取反会匹配 wasm/js，
/// 官方文档 WARNING：platform 条件隐含 target="native"）
#cfg(not(platform="windows"))
pub fn resolve_path(path : String, base : String) -> String {
  resolve_path_posix(path, base)
}

///|
/// POSIX 实现：`/` 为唯一分隔符，空栈回落根 `/`（对齐上游 cfg!(windows)
/// 之外的分支）。在 Windows 构建下唯一调用者（pub twin）被 cfg 掉会报
/// unused，故关闭该 lint；语义由 path_test.mbt 经 pub 面锁定
#warnings("-unused_value")
fn resolve_path_posix(path : String, base : String) -> String {
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
/// win32 前缀扫描结果。consumed 只含前缀字符；rooted 指前缀后紧跟根分隔符
priv struct WinPrefix {
  drive : Char?
  verbatim : Bool
  unc : String?
  rooted : Bool
  consumed : Int
}

///|
/// win32 前缀扫描（对齐上游 get_drive_letter 分支所依赖的
/// std::path::Prefix 子集）：Disk（`C:`）、VerbatimDisk（`\\?\C:`，上游
/// 同款转换为普通盘符）；UNC/设备前缀 best-effort 保留原文（上游
/// bail!("invalid path")，公共签名无错误通道，差异注记 README）。
/// 盘符只认路径起始处（Rust Prefix 语义），`/` 与 `\` 均为分隔符
fn scan_windows_prefix(path : String) -> WinPrefix {
  let len = path.length()
  if len >= 2 && is_windows_sep(path, 0) && is_windows_sep(path, 1) {
    // VerbatimDisk：`\\?\C:`（6 字符）
    let verbatim_disk = len >= 6 &&
      path.get_char(2) == Some('?') &&
      is_windows_sep(path, 3) &&
      is_ascii_alpha(path.get_char(4)) &&
      path.get_char(5) == Some(':')
    if verbatim_disk {
      return {
        drive: path.get_char(4),
        verbatim: true,
        unc: None,
        rooted: len > 6 && is_windows_sep(path, 6),
        consumed: 6,
      }
    }
    // UNC（`\\server\share`）/设备（`\\.\`）：消费 server + share 段
    let mut i = 2
    while i < len && !is_windows_sep(path, i) {
      i += 1
    }
    if i < len {
      let mut j = i + 1
      while j < len && !is_windows_sep(path, j) {
        j += 1
      }
      return {
        drive: None,
        verbatim: false,
        unc: Some(path[0:j].to_owned()),
        rooted: j < len,
        consumed: j,
      }
    }
    return {
      drive: None,
      verbatim: false,
      unc: Some(path),
      rooted: false,
      consumed: len,
    }
  }
  if len >= 2 &&
    is_ascii_alpha(path.get_char(0)) &&
    path.get_char(1) == Some(':') {
    return {
      drive: path.get_char(0),
      verbatim: false,
      unc: None,
      rooted: len > 2 && is_windows_sep(path, 2),
      consumed: 2,
    }
  }
  {
    drive: None,
    verbatim: false,
    unc: None,
    rooted: len > 0 && is_windows_sep(path, 0),
    consumed: 0,
  }
}

///|
/// win32 规范化（对齐上游 util::resolve_path 的 cfg!(windows) 分支）。
/// 与上游的两处注记差异（公共签名无错误/env 通道，README 差异清单跟进）：
/// 1. 盘符相对路径跨盘时直接回落 `D:\`，上游另查 `=D:` 环境变量
/// 2. UNC/设备前缀 best-effort 规范化，上游报错
/// 在非 Windows 构建下唯一调用者（pub twin）被 cfg 掉会报 unused（wbtest
/// 引用不参与主代码判定），故关闭该 lint；语义由 path_wbtest.mbt 锁定
#warnings("-unused_value")
fn resolve_path_windows(path : String, base : String) -> String {
  let p = scan_windows_prefix(path)
  let mut drive : Char? = p.drive
  let mut unc : String? = p.unc
  let mut rooted = p.rooted
  let normals : Array[String] = []
  // 种子：对齐上游 stack 初始化的三分支
  if p.unc is Some(_) {
    // UNC 前缀即根，无种子
  } else if p.drive is Some(d) {
    if p.verbatim {
      // 上游同款：VerbatimDisk 消费可选根后强制 `X:\` 种子
      rooted = true
    } else if !p.rooted {
      // 盘符相对（`D:foo`）：同盘回落 base，跨盘回落 `D:\`
      let b = scan_windows_prefix(base)
      if b.drive == Some(d) {
        drive = b.drive
        rooted = b.rooted
        unc = b.unc
        push_windows_segments(normals, base, b.consumed, base.length())
      } else {
        rooted = true
      }
    }
  } else if p.rooted {
    // `\foo`：借 base 的盘符（上游取 cwd 盘符，cwd 恒有盘符）
    drive = scan_windows_prefix(base).drive
  } else {
    // 纯相对：从 base 全量种子
    let b = scan_windows_prefix(base)
    drive = b.drive
    rooted = b.rooted
    unc = b.unc
    push_windows_segments(normals, base, b.consumed, base.length())
  }
  push_windows_segments(normals, path, p.consumed, path.length())
  let joined = normals.join("\\")
  if unc is Some(u) {
    if normals.is_empty() {
      u
    } else {
      u + "\\" + joined
    }
  } else if drive is Some(d) {
    // 盘符恒带根（上游各种子路径均 rooted）
    d.to_string() + ":\\" + joined
  } else if rooted {
    if normals.is_empty() {
      "\\"
    } else {
      "\\" + joined
    }
  } else if normals.is_empty() {
    "\\"
  } else {
    joined
  }
}

///|
/// 段推送：`.` 丢弃、`..` 带根保护弹出（对齐上游 ParentDir 的
/// pop-unless-RootDir；base 为真实 cwd 时不含点段，种子与主循环同规则）
fn push_windows_segments(
  normals : Array[String],
  path : String,
  start : Int,
  end : Int,
) -> Unit {
  let mut seg_start = start
  let mut i = start
  while i < end {
    let ch = path.get_char(i)
    if ch == Some('/') || ch == Some('\\') {
      if i > seg_start {
        push_one_segment(normals, path[seg_start:i].to_owned())
      }
      seg_start = i + 1
    }
    i += 1
  }
  if end > seg_start {
    push_one_segment(normals, path[seg_start:end].to_owned())
  }
}

///|
fn push_one_segment(normals : Array[String], seg : String) -> Unit {
  if seg == "." {
    return
  }
  if seg == ".." {
    ignore(normals.pop())
    return
  }
  normals.push(seg)
}

///|
fn is_windows_sep(path : String, i : Int) -> Bool {
  path.get_char(i) == Some('/') || path.get_char(i) == Some('\\')
}

///|
fn is_ascii_alpha(ch : Char?) -> Bool {
  ch is Some(c) && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
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
