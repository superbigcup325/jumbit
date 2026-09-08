///|
/// 数据库：条目数组 + dirty 标志（对齐上游 src/db/mod.rs；MoonBit 无借用约束，直接持数组）
/// pub struct：外部可读字段但不可构造/原地修改，变更一律走方法（保 dirty 一致性）
pub struct Database {
  dirs : Array[Dir]
  mut dirty : Bool
} derive(Debug)

///|
pub fn Database::new() -> Database {
  { dirs: [], dirty: false, }
}

///|
/// 从解码结果构建（platform/load 专用；dirty=false）
pub fn Database::from_dirs(dirs : Array[Dir]) -> Database {
  { dirs, dirty: false, }
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
        note: None,
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
        note: None,
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
/// 只读访问条目数组（返回副本：外部增删/排序不影响库内部结构）
pub fn Database::all(self : Database) -> Array[Dir] {
  Array::from_iter(self.dirs.iter())
}

///|
pub fn Database::is_dirty(self : Database) -> Bool {
  self.dirty
}

///|
/// 库是否无条目（import 的空库检查用，对齐上游 db.dirs().is_empty()）
pub fn Database::is_empty(self : Database) -> Bool {
  self.dirs.length() == 0
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

///|
/// O(1) 删除指定下标（不保序，对齐上游 swap_remove）；懒删除专用
pub fn Database::swap_remove(self : Database, idx : Int) -> Unit {
  let last = self.dirs.length() - 1
  self.dirs[idx] = self.dirs[last]
  ignore(self.dirs.pop())
  self.dirty = true
}

///|
/// 按路径删除条目，返回是否确实删除了
pub fn Database::remove(self : Database, path : String) -> Bool {
  match self.find_idx(path) {
    Some(i) => {
      self.swap_remove(i)
      true
    }
    None => false
  }
}

///|
/// 新建条目且不查重（会产生重复，调用方需保证先查或随后 dedup；对齐上游 add_unchecked）
pub fn Database::add_unchecked(
  self : Database,
  path : String,
  rank : Double,
  now : Int64,
) -> Unit {
  self.dirs.push({ path, rank, last_accessed: now, note: None, })
  self.dirty = true
}

///|
/// 按路径字典序原地排序
pub fn Database::sort_by_path(self : Database) -> Unit {
  self.dirs.sort_by(fn(a, b) { a.path.compare(b.path) })
  self.dirty = true
}

///|
/// 老化（对齐上游 Database::age）：总分**严格大于** max_age 才触发
/// （total=0 与 total==max_age 均不动，天然防除零）；全体 rank 乘
/// factor = 0.9 × max_age / total，乘后 rank < 1 的条目删除。
pub fn Database::age(self : Database, max_age : Double) -> Unit {
  let mut total = 0.0
  for d in self.dirs {
    total = total + d.rank
  }
  if total > max_age {
    let factor = 0.9 * max_age / total
    for i in self.dirs.length()>..0 {
      let d = self.dirs[i]
      d.rank = d.rank * factor
      if d.rank < 1.0 {
        self.swap_remove(i)
      }
    }
    self.dirty = true
  }
}

///|
/// 合并重复路径：先按路径排序，相邻同路径条目 rank 相加、last_accessed 取最大
/// （对齐上游 Database::dedup）；note 为 jumbit 扩展，一侧有值则保留（信息不丢）
pub fn Database::dedup(self : Database) -> Unit {
  self.sort_by_path()
  for i in self.dirs.length()>..1 {
    let curr = self.dirs[i]
    let prev = self.dirs[i - 1]
    if curr.path == prev.path {
      prev.last_accessed = if prev.last_accessed > curr.last_accessed {
        prev.last_accessed
      } else {
        curr.last_accessed
      }
      prev.rank = prev.rank + curr.rank
      if prev.note is None {
        prev.note = curr.note
      }
      self.swap_remove(i)
    }
  }
}

///|
/// 设置条目标注（jumbit 扩展）：None 清除。命中返回 true 并置 dirty；
/// 路径不在库中返回 false（describe 只标注已记录条目）
pub fn Database::set_note(
  self : Database,
  path : String,
  note : String?,
) -> Bool {
  match self.find_idx(path) {
    Some(i) => {
      self.dirs[i].note = note
      self.dirty = true
      true
    }
    None => false
  }
}
