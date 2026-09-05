///|
/// 数据库：条目数组 + dirty 标志（对齐上游 src/db/mod.rs；MoonBit 无借用约束，直接持数组）
pub(all) struct Database {
  dirs : Array[Dir]
  mut dirty : Bool
} derive(Debug)

///|
pub fn Database::new() -> Database {
  { dirs: [], dirty: false, }
}

///|
/// 增加权重：已存在则 rank 累加（负增量 clamp 到 0），不存在则新建。
/// 与 add_update 的区别：不更新 last_accessed（上游语义）。
pub fn Database::add(
  self : Database,
  path : String,
  by : Double,
  now : Int64,
) -> Unit {
  match self.find_idx(path) {
    Some(i) => {
      let d = self.dirs[i]
      d.rank = if d.rank + by > 0.0 { d.rank + by } else { 0.0 }
    }
    None =>
      self.dirs.push({
        path,
        rank: if by > 0.0 {
          by
        } else {
          0.0
        },
        last_accessed: now,
      })
  }
  self.dirty = true
}

///|
/// 增加权重并更新最后访问时间：已存在则 rank 累加 + last_accessed = now，不存在则新建。
pub fn Database::add_update(
  self : Database,
  path : String,
  by : Double,
  now : Int64,
) -> Unit {
  match self.find_idx(path) {
    Some(i) => {
      let d = self.dirs[i]
      d.rank = if d.rank + by > 0.0 { d.rank + by } else { 0.0 }
      d.last_accessed = now
    }
    None =>
      self.dirs.push({
        path,
        rank: if by > 0.0 {
          by
        } else {
          0.0
        },
        last_accessed: now,
      })
  }
  self.dirty = true
}

///|
/// 按 path 查条目下标（不存在返回 None）
pub fn Database::find_idx(self : Database, path : String) -> Int? {
  for i, d in self.dirs {
    if d.path == path {
      return Some(i)
    }
  }
  None
}

///|
/// 只读访问条目数组
pub fn Database::all(self : Database) -> Array[Dir] {
  self.dirs
}

///|
pub fn Database::is_dirty(self : Database) -> Bool {
  self.dirty
}

///|
pub fn Database::mark_clean(self : Database) -> Unit {
  self.dirty = false
}

///|
/// 按得分升序原地排序（对齐上游：Stream 从尾部倒序取最高分）
pub fn Database::sort_by_score(self : Database, now : Int64) -> Unit {
  self.dirs.sort_by(fn(a, b) { a.score(now).compare(b.score(now)) })
  self.dirty = true
}
