///|
/// 查询流选项（对齐上游 StreamOptions）
pub(all) struct StreamOptions {
  now : Int64
  keywords : Array[String]
  /// glob 模式（已过 validate_glob），命中即懒删除
  exclude : Array[String]
  /// Some → 组件级前缀过滤（--base-dir，后续版本接入命令行）
  base_dir : String?
  /// false 跳过存在性检查（--all）
  exists : Bool
  /// 注入的 exists 回调按此决定是否跟随符号链接（对齐上游反向逻辑）
  resolve_symlinks : Bool
  /// 不存在且 last_accessed < ttl → 懒删除（默认 now - 3*MONTH）
  ttl : Int64
}

///|
pub fn StreamOptions::new(now : Int64) -> StreamOptions {
  {
    now,
    keywords: [],
    exclude: [],
    base_dir: None,
    exists: false,
    resolve_symlinks: false,
    ttl: now - 3L * MONTH,
  }
}

///|
/// 查询流：按得分降序执行完整过滤链（对齐上游 Stream::next 顺序）：
/// score 排序 → keywords → base_dir → exclude(glob, 命中懒删) → exists(最后，最慢)
/// → 不存在且超 TTL 懒删。返回按得分从高到低的全部命中。
/// exists 回调由调用方注入（platform 传文件系统检查，单测传闭包）。
pub fn Database::query_all(
  self : Database,
  opts : StreamOptions,
  exists : (String) -> Bool,
) -> Array[Dir] {
  self.sort_by_score(opts.now)
  let out : Array[Dir] = []
  // 倒序遍历：swap_remove 把尾部元素挪到 idx，其一定已被访问过，索引安全
  let len = self.dirs.length()
  for i in len>..0 {
    let dir = self.dirs[i]
    if !filter_by_keywords(opts.keywords, dir.path) {
      continue
    }
    if !filter_base_dir(opts, dir.path) {
      continue
    }
    if !filter_exclude(opts, dir.path) {
      self.swap_remove(i)
      continue
    }
    if opts.exists && !exists(dir.path) {
      if dir.last_accessed < opts.ttl {
        self.swap_remove(i)
      }
      continue
    }
    out.push(dir)
  }
  out
}

///|
fn filter_base_dir(opts : StreamOptions, path : String) -> Bool {
  match opts.base_dir {
    Some(base) => starts_with(path, base)
    None => true
  }
}

///|
fn filter_exclude(opts : StreamOptions, path : String) -> Bool {
  for pattern in opts.exclude {
    if glob_match(pattern, path) {
      return false
    }
  }
  true
}
