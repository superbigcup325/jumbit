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
/// 查询流：按得分降序执行完整过滤链（对齐上游 Stream::next 顺序）：
/// score 排序 → keywords → base_dir → exclude(glob, 命中懒删) → exists(最后，最慢)
/// → 不存在且超 TTL 懒删。返回按得分从高到低的全部命中。
/// exists 回调由调用方注入（platform 传文件系统检查，单测传闭包）。
pub async fn Database::query_all(
  self : Database,
  opts : StreamOptions,
  exists : async (String) -> Bool,
) -> Array[Dir] {
  self.sort_by_score(opts.now)
  // exclude glob 编译一次反复用（全库逐条目过滤，pattern 重复物化是热点）
  let globs : Array[Array[Char]] = []
  for pattern in opts.exclude {
    globs.push(compile_glob(pattern))
  }
  let out : Array[Dir] = []
  // 倒序遍历：swap_remove 把尾部元素挪到 idx，其一定已被访问过，索引安全
  let len = self.dirs.length()
  if opts.exists {
    // exists 路（默认查询）：循环含 await 点，保持原形态
    for i in len>..0 {
      let dir = self.dirs[i]
      if !filter_by_keywords(opts.keywords, dir.path) {
        continue
      }
      if !filter_base_dir(opts, dir.path) {
        continue
      }
      if !filter_exclude(globs, dir.path) {
        self.swap_remove(i)
        continue
      }
      if !exists(dir.path) {
        // TTL 比较在 u64 域（对齐上游 Epoch=u64）：纪元前负 epoch 位型上是
        // 极大值，不会被懒删除（0.10.0 混沌对拍实测）
        if dir.last_accessed.reinterpret_as_uint64() <
          opts.ttl.reinterpret_as_uint64() {
          self.swap_remove(i)
        }
        continue
      }
      out.push(dir)
    }
  } else {
    // --all 热路：无 await 点。async 下沉对循环内含 await 点的迭代有
    // ~8μs/次的固定开销（2026-09-11 变体实验实测：仅此分支之差，26.7 万
    // 条目 filter 6ms ↔ 2034ms），短路布尔挡不住下沉，必须拆出纯同步循环
    for i in len>..0 {
      let dir = self.dirs[i]
      if !filter_by_keywords(opts.keywords, dir.path) {
        continue
      }
      if !filter_base_dir(opts, dir.path) {
        continue
      }
      if !filter_exclude(globs, dir.path) {
        self.swap_remove(i)
        continue
      }
      out.push(dir)
    }
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
fn filter_exclude(globs : Array[Array[Char]], path : String) -> Bool {
  for pattern in globs {
    if glob_match_compiled(pattern, path) {
      return false
    }
  }
  true
}
