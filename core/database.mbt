///|
/// The database: an entry array plus a dirty flag (matching upstream src/db/mod.rs; MoonBit has no borrow constraints, so it holds the array directly)
/// A pub struct: the fields are readable from outside but cannot be constructed or mutated in place, and every change goes through a method (keeping dirty consistent)
pub struct Database {
  mut dirs : Array[Dir]
  mut dirty : Bool
} derive(Debug)

///|
pub fn Database::new() -> Database {
  { dirs: [], dirty: false, }
}

///|
/// Build from a decode result (for platform/load only; dirty=false)
pub fn Database::from_dirs(dirs : Array[Dir]) -> Database {
  { dirs, dirty: false, }
}

///|
/// The rank floor (upstream MIN_RANK=0.01: with two decimals it never collapses to 0)
pub const RANK_MIN : Double = 0.01

///|
/// The rank ceiling (upstream MAX_RANK=9_999_999.99)
pub const RANK_MAX : Double = 9999999.99

///|
/// Import-time normalization of non-finite and out-of-range ranks ([#3]): nan / -inf -> the floor, +inf -> the ceiling,
/// finite values clamped to [RANK_MIN, RANK_MAX]. It runs at the entry point (add_update / add_unchecked) rather than in
/// the encoding layer: aging puts the total in the denominator, so an inf in the total zeroes the factor and multiplies rank
/// into NaN (measured in a blackbox as landing on 0.01, the opposite of the documented "inf clamps to the ceiling");
/// with the clamp moved forward, both import paths (add/import) and the hand-edited database\'s save path behave alike
fn sanitize_rank(r : Double) -> Double {
  if r != r {
    RANK_MIN
  } else if r > RANK_MAX {
    RANK_MAX
  } else if r < RANK_MIN {
    RANK_MIN
  } else {
    r
  }
}

///|
/// Change a path (for edit --rename): the note, weight and time are all kept; if new collides with an existing entry it returns
/// false (no merge; the caller errors -- the ruling is in spec §1.4)
pub fn Database::rename(self : Database, old : String, new : String) -> Bool {
  match self.find_idx(old) {
    Some(i) => {
      self.dirs[i].path = new
      self.dirty = true
      true
    }
    None => false
  }
}

///|
/// Replace the whole database (for edit\'s interactive form: the edited full entry set replaces the current one; the caller has
/// already attached notes by path), marking dirty
pub fn Database::replace_all(self : Database, dirs : Array[Dir]) -> Unit {
  self.dirs = dirs
  self.dirty = true
}

///|
/// Force a dirty mark (for platform/load\'s migration): after reading a legacy db.zo it marks dirty, so the next
/// save lands as plaintext db.txt; a read-only command never saves, so it triggers no migration (spec §1.3)
pub fn Database::mark_dirty(self : Database) -> Unit {
  self.dirty = true
}

///|
/// Add weight: an existing entry accumulates the rank (a negative delta clamps to 0); otherwise a new entry is created.
/// Unlike add_update it does not update last_accessed (upstream semantics).
pub fn Database::add(
  self : Database,
  path : String,
  by : Double,
  now : Int64,
) -> Unit {
  match self.find_idx(path) {
    Some(i) => {
      let d = self.dirs[i]
      d.rank = sanitize_rank(if d.rank + by > 0.0 { d.rank + by } else { 0.0 })
    }
    None =>
      self.dirs.push({
        path,
        rank: sanitize_rank(if by > 0.0 { by } else { 0.0 }),
        last_accessed: now,
        note: None,
      })
  }
  self.dirty = true
}

///|
/// Add weight and update the last access time: an existing entry accumulates the rank and sets last_accessed = now; otherwise a new entry is created.
pub fn Database::add_update(
  self : Database,
  path : String,
  by : Double,
  now : Int64,
) -> Unit {
  match self.find_idx(path) {
    Some(i) => {
      let d = self.dirs[i]
      d.rank = sanitize_rank(if d.rank + by > 0.0 { d.rank + by } else { 0.0 })
      d.last_accessed = now
    }
    None =>
      self.dirs.push({
        path,
        rank: sanitize_rank(if by > 0.0 { by } else { 0.0 }),
        last_accessed: now,
        note: None,
      })
  }
  self.dirty = true
}

///|
/// Look up an entry\'s index by path (None when absent)
pub fn Database::find_idx(self : Database, path : String) -> Int32? {
  for i, d in self.dirs {
    if d.path == path {
      return Some(i)
    }
  }
  None
}

///|
/// Read-only access to the entry array (a copy is returned, so external add/remove/sort cannot touch the internal structure)
pub fn Database::all(self : Database) -> Array[Dir] {
  Array::from_iter(self.dirs.iter())
}

///|
pub fn Database::is_dirty(self : Database) -> Bool {
  self.dirty
}

///|
/// Whether the database has no entries (for import\'s empty-database check, matching upstream db.dirs().is_empty())
pub fn Database::is_empty(self : Database) -> Bool {
  self.dirs.length() == 0
}

///|
pub fn Database::mark_clean(self : Database) -> Unit {
  self.dirty = false
}

///|
/// Sort in place by ascending score (matching upstream: Stream takes the highest score from the tail in reverse).
/// A display-only order does not mark dirty: sorting is not a data change, which is how query keeps "no lazy deletion, no write"
/// ([#2]: an unconditional dirty mark used to make every read-only query exit dirty, so a legacy database migrated when merely
/// read and a query against a read-only data directory failed outright)
pub fn Database::sort_by_score(self : Database, now : Int64) -> Unit {
  self.dirs.sort_by(fn(a, b) { total_cmp(a.score(now), b.score(now)) })
}

///|
/// IEEE 754 totalOrder comparison (matching the bit trick in upstream f64::total_cmp):
/// compare after folding the sign bit onto the i64 bit pattern -- +NaN is above everything, -NaN below everything, -0.0 < +0.0.
/// import\'s nan/inf literals can put a NaN in a score, which is why upstream\'s sort puts NaN entries at the very
/// front of the descending output -- something an ordinary compare cannot do
fn total_cmp(a : Double, b : Double) -> Int32 {
  let la = a.reinterpret_as_uint64()
  let lb = b.reinterpret_as_uint64()
  let sa = (la.reinterpret_as_int64() >> 63).reinterpret_as_uint64() >> 1
  let sb = (lb.reinterpret_as_int64() >> 63).reinterpret_as_uint64() >> 1
  let ka = la.reinterpret_as_int64().lxor(sa.reinterpret_as_int64())
  let kb = lb.reinterpret_as_int64().lxor(sb.reinterpret_as_int64())
  ka.compare(kb)
}

///|
/// O(1) removal at an index (order not preserved, matching upstream swap_remove); for lazy deletion only
pub fn Database::swap_remove(self : Database, idx : Int32) -> Unit {
  let last = self.dirs.length() - 1
  self.dirs[idx] = self.dirs[last]
  ignore(self.dirs.pop())
  self.dirty = true
}

///|
/// Remove an entry by path, returning whether anything was removed
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
/// Create an entry without a duplicate check (duplicates result; the caller must have checked first or must dedup afterwards; matching upstream add_unchecked)
pub fn Database::add_unchecked(
  self : Database,
  path : String,
  rank : Double,
  now : Int64,
) -> Unit {
  self.dirs.push({
    path,
    rank: sanitize_rank(rank),
    last_accessed: now,
    note: None,
  })
  self.dirty = true
}

///|
/// Pure lexicographic order (matching upstream path.cmp: content code unit by code unit, a prefix sorting before the longer string).
/// String::compare cannot be used directly: MoonBit implements it as shortlex (length first), which orders entries
/// differently from upstream Rust\'s lexicographic String cmp on a mixed-length path set
/// (measured divergence: importing the same dataset left jumbit\'s first entry at /opt/golf... against upstream\'s /opt/alpha...)
fn path_lex_cmp(a : String, b : String) -> Int32 {
  let la = a.length()
  let lb = b.length()
  let n = if la < lb { la } else { lb }
  for i in 0..<n {
    let o = a.unsafe_get(i).compare(b.unsafe_get(i))
    if o != 0 {
      return o
    }
  }
  la.compare(lb)
}

///|
/// Sort in place by pure lexicographic path order (matching upstream path.cmp semantics)
pub fn Database::sort_by_path(self : Database) -> Unit {
  self.dirs.sort_by(fn(a, b) { path_lex_cmp(a.path, b.path) })
  self.dirty = true
}

///|
/// Aging (matching upstream Database::age): it fires only when the total is **strictly greater** than max_age
/// (total=0 and total==max_age do nothing, which guards against division by zero); every rank is multiplied by
/// factor = 0.9 x max_age / total, and any entry whose rank drops below 1 is deleted.
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
/// Merge duplicate paths: sort by path first, then add the ranks of adjacent same-path entries and take the maximum last_accessed
/// (matching upstream Database::dedup); the note is a jumbit extension and a value on either side is kept (no information lost)
pub fn Database::dedup(self : Database) -> Unit {
  self.sort_by_path()
  for i in self.dirs.length()>..1 {
    let curr = self.dirs[i]
    let prev = self.dirs[i - 1]
    if curr.path == prev.path {
      // taking max for la matches upstream\'s u64-domain semantics (Epoch = u64, measured against 0.10.0):
      // a negative epoch (the 1969 boundary) is the maximum in the u64 domain and wins the merge
      let prev_u = prev.last_accessed.reinterpret_as_uint64()
      let curr_u = curr.last_accessed.reinterpret_as_uint64()
      prev.last_accessed = if prev_u >= curr_u {
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
/// Set an entry\'s annotation (a jumbit extension): None clears it. A hit returns true and marks dirty;
/// a path absent from the database returns false (describe annotates only recorded entries)
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
