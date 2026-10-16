// Minimal Database tests

///|
test "add: create and accumulate, without updating last_accessed" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 1000L)
  db.add("/foo", 1.0, 5000L)
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.all()[0].path, "/foo")
  @debug.assert_eq(db.all()[0].rank, 2.0)
  @debug.assert_eq(db.all()[0].last_accessed, 1000L)
}

///|
test "add: a negative delta clamps to the 0.01 floor ([#3] import normalization, both the new and existing paths)" {
  let db = @core.Database::new()
  db.add("/a", -5.0, 0L)
  @debug.assert_eq(db.all()[0].rank, 0.01)
  db.add("/b", 1.0, 0L)
  db.add("/b", -5.0, 0L)
  @debug.assert_eq(db.all().length(), 2)
  @debug.assert_eq(db.all()[1].rank, 0.01)
}

///|
test "add_update: accumulate the rank and update last_accessed" {
  let db = @core.Database::new()
  db.add_update("/foo", 1.0, 1000L)
  db.add_update("/foo", 1.0, 5000L)
  @debug.assert_eq(db.all()[0].rank, 2.0)
  @debug.assert_eq(db.all()[0].last_accessed, 5000L)
}

///|
test "dirty flag transitions" {
  let db = @core.Database::new()
  @debug.assert_eq(db.is_dirty(), false)
  db.add("/foo", 1.0, 0L)
  @debug.assert_eq(db.is_dirty(), true)
  db.mark_clean()
  @debug.assert_eq(db.is_dirty(), false)
}

///|
test "sort_by_score: ascending, with the most recent at the tail" {
  let db = @core.Database::new()
  // now is a realistic magnitude: a negative la lands in the x4 bucket under u64 saturation (see dir_test)
  let now = 1788833590L
  db.add("/old", 1.0, now - 60L * @core.DAY) // ×0.25
  db.add("/mid", 1.0, now - 2L * @core.HOUR) // ×2.0
  db.add("/new", 1.0, now) // ×4.0
  db.sort_by_score(now)
  @debug.assert_eq(db.all()[0].path, "/old")
  @debug.assert_eq(db.all()[1].path, "/mid")
  @debug.assert_eq(db.all()[2].path, "/new")
}

///|
test "find_idx: a hit and a miss" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 0L)
  @debug.assert_eq(db.find_idx("/foo"), Some(0))
  @debug.assert_eq(db.find_idx("/bar"), None)
}

///|
test "all() returns a copy: external add/remove cannot touch the internals" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 0L)
  let snapshot = db.all()
  snapshot.push(@core.Dir::{
    path: "/injected",
    rank: 9.0,
    last_accessed: 0L,
    note: None,
  })
  @debug.assert_eq(db.all().length(), 1)
}

///|
test "from_dirs: built at the decode entry point, initially clean" {
  let dirs = [
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let db = @core.Database::from_dirs(dirs)
  @debug.assert_eq(db.is_dirty(), false)
  @debug.assert_eq(db.all().length(), 1)
}

///|
test "age: total <= max_age does not fire" {
  let db = @core.Database::new()
  db.add("/a", 5000.0, 0L)
  db.mark_clean()
  db.age(10000.0)
  @debug.assert_eq(db.all()[0].rank, 5000.0)
  @debug.assert_eq(db.is_dirty(), false)
}

///|
test "age: total == max_age does not fire (strictly >)" {
  let db = @core.Database::new()
  db.add("/a", 10000.0, 0L)
  db.age(10000.0)
  @debug.assert_eq(db.all()[0].rank, 10000.0)
}

///|
test "age: past the threshold everything scales and ranks below 1 are deleted" {
  let db = @core.Database::new()
  db.add("/big", 19999.0, 0L)
  db.add("/small", 1.0, 0L)
  // total = 20000, max = 10000 → factor = 0.45
  db.age(10000.0)
  @debug.assert_eq(db.all().length(), 1)
  // 19999 x 0.45 = 8999.55 (float tail differences are compared with is_close)
  @debug.assert_eq(db.all()[0].path, "/big")
  @debug.assert_eq(db.all()[0].rank.is_close(8999.55), true)
}

///|
test "age: total=0 does not fire (guarding against division by zero)" {
  let db = @core.Database::new()
  // after import normalization rank is always >= 0.01 ([#3]), so total=0 can only be built from a Dir literal
  db.dirs.push({ path: "/a", rank: 0.0, last_accessed: 0L, note: None, })
  db.age(0.0)
  @debug.assert_eq(db.all().length(), 1)
}

///|
test "age: _JB_MAXAGE=0 semantics pinned -- any positive total wipes everything" {
  let db = @core.Database::new()
  db.add("/a", 0.1, 0L)
  db.age(0.0)
  // total 0.1 > 0 -> factor = 0 -> rank 0 < 1 -> everything is deleted
  @debug.assert_eq(db.all().length(), 0)
}

///|
test "age: a rank of exactly 1.0 after scaling is kept (strict <, with the factor built to be exactly 0.5)" {
  // m = 0.9 x 10000; padding makes total == 2m -> factor = m/2m == 0.5 (exact in f64)
  let m = 0.9 * 10000.0
  let db = @core.Database::new()
  db.add_unchecked("/exact", 2.0, 0L)
  db.add_unchecked("/pad", m + m - 2.0, 0L)
  // a rank of 0 becomes 0.01 through import normalization ([#3]), so an exact 0 is built from a Dir literal
  db.dirs.push({ path: "/zero", rank: 0.0, last_accessed: 0L, note: None, })
  db.age(10000.0)
  // 2.0 x 0.5 = 1.0, which does not satisfy < 1.0 -> kept
  @debug.assert_eq(db.find_idx("/exact") is Some(_), true)
  @debug.assert_eq(db.all()[0].rank, 1.0)
  // the rank-0 entry scales below 1 -> deleted
  @debug.assert_eq(db.find_idx("/zero") is Some(_), false)
}

///|
test "dedup: ranks add up, last_accessed takes the maximum" {
  let db = @core.Database::new()
  db.add_unchecked("/a", 1.0, 100L)
  db.add_unchecked("/a", 2.0, 300L)
  db.add_unchecked("/a", 4.0, 200L)
  db.dedup()
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.all()[0].path, "/a")
  @debug.assert_eq(db.all()[0].rank, 7.0)
  @debug.assert_eq(db.all()[0].last_accessed, 300L)
}

///|
test "dedup: different paths leave each other alone" {
  let db = @core.Database::new()
  db.add_unchecked("/a", 1.0, 0L)
  db.add_unchecked("/b", 2.0, 0L)
  db.dedup()
  @debug.assert_eq(db.all().length(), 2)
}

///|
test "add_unchecked: no duplicate check, so one path makes several entries" {
  let db = @core.Database::new()
  db.add_unchecked("/a", 1.0, 0L)
  db.add_unchecked("/a", 1.0, 0L)
  @debug.assert_eq(db.all().length(), 2)
}

///|
test "sort_by_path: lexicographic order" {
  let db = @core.Database::new()
  db.add_unchecked("/c", 1.0, 0L)
  db.add_unchecked("/a", 1.0, 0L)
  db.add_unchecked("/b", 1.0, 0L)
  db.sort_by_path()
  @debug.assert_eq(db.all()[0].path, "/a")
  @debug.assert_eq(db.all()[1].path, "/b")
  @debug.assert_eq(db.all()[2].path, "/c")
}

///|
test "set_note: a hit marks dirty and returns true, a miss returns false" {
  let db = @core.Database::from_dirs([
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: 0L, note: None, },
  ])
  db.mark_clean()
  @debug.assert_eq(db.set_note("/missing", Some("x")), false)
  @debug.assert_eq(db.is_dirty(), false)
  @debug.assert_eq(db.set_note("/a", Some("后端")), true)
  @debug.assert_eq(db.is_dirty(), true)
  @debug.assert_eq(db.all()[0].note, Some("后端"))
  // None clears it
  @debug.assert_eq(db.set_note("/a", None), true)
  @debug.assert_eq(db.all()[0].note, None)
}

///|
test "dedup: a note on either side is kept (no information lost)" {
  let a = @core.Database::from_dirs([
    @core.Dir::{
      path: "/dup",
      rank: 1.0,
      last_accessed: 0L,
      note: Some("保留我"),
    },
    @core.Dir::{ path: "/dup", rank: 1.0, last_accessed: 5L, note: None, },
  ])
  a.dedup()
  @debug.assert_eq(a.all().length(), 1)
  @debug.assert_eq(a.all()[0].note, Some("保留我"))
  let b = @core.Database::from_dirs([
    @core.Dir::{ path: "/dup", rank: 1.0, last_accessed: 0L, note: None, },
    @core.Dir::{
      path: "/dup",
      rank: 1.0,
      last_accessed: 5L,
      note: Some("补上"),
    },
  ])
  b.dedup()
  @debug.assert_eq(b.all().length(), 1)
  @debug.assert_eq(b.all()[0].note, Some("补上"))
}

///|
test "sort_by_score: NaN sorts first under IEEE totalOrder (compared against upstream total_cmp)" {
  let db = @core.Database::from_dirs([
    @core.Dir::{ path: "/normal", rank: 1.0, last_accessed: 100L, note: None, },
    @core.Dir::{
      path: "/nan",
      // parse_double("nan") is used (import\'s real path) rather than 0.0/0.0, which folds at compile time into a negative NaN
      rank: @string.parse_double("nan") catch {
        _ => 1.0
      },
      last_accessed: 100L,
      note: None,
    },
    @core.Dir::{ path: "/low", rank: 0.1, last_accessed: 100L, note: None, },
  ])
  db.sort_by_score(100L)
  // upstream\'s ascending sort_unstable_by(total_cmp) plus a reverse stream traversal = NaN first in the descending output
  @debug.assert_eq(db.all()[db.all().length() - 1].path, "/nan")
  @debug.assert_eq(db.all()[0].path, "/low")
}

///|
test "sort_by_score: a tied input still outputs descending with an unchanged entry set" {
  let now = 1788833590L
  let db = @core.Database::from_dirs([
    @core.Dir::{ path: "/b", rank: 1.0, last_accessed: now, note: None, },
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: now, note: None, },
    @core.Dir::{ path: "/c", rank: 2.0, last_accessed: now, note: None, },
    @core.Dir::{ path: "/d", rank: 1.0, last_accessed: now, note: None, },
  ])
  db.sort_by_score(now)
  // the order of tied entries is not pinned (sort_by is unstable); the descending order and the entry set are
  let all = db.all()
  @debug.assert_eq(all.length(), 4)
  @debug.assert_eq(all[0].score(now) <= all[1].score(now), true)
  @debug.assert_eq(all[1].score(now) <= all[2].score(now), true)
  @debug.assert_eq(all[2].score(now) <= all[3].score(now), true)
  @debug.assert_eq(all[3].path, "/c")
}

///|
test "sort_by_score: an empty database and a single entry" {
  let now = 1788833590L
  let db = @core.Database::new()
  db.sort_by_score(now)
  @debug.assert_eq(db.all().length(), 0)
  db.add("/only", 1.0, now)
  db.sort_by_score(now)
  @debug.assert_eq(db.all()[0].path, "/only")
}

///|
test "sort_by_path: pure lexicographic order (length-first shortlex was the divergence from upstream and is now aligned)" {
  let db = @core.Database::from_dirs([
    @core.Dir::{ path: "/z", rank: 1.0, last_accessed: 100L, note: None, },
    @core.Dir::{ path: "/a/b", rank: 1.0, last_accessed: 100L, note: None, },
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: 100L, note: None, },
  ])
  db.sort_by_path()
  // pure lexicographic: /a < /a/b < /z; shortlex (length first) would give /a, /z, /a/b
  @debug.assert_eq(db.all()[0].path, "/a")
  @debug.assert_eq(db.all()[1].path, "/a/b")
  @debug.assert_eq(db.all()[2].path, "/z")
}

///|
test "format_score: NaN displays as NaN (matching Rust {:.1})" {
  let dir = @core.Dir::{
    path: "/nan",
    rank: 0.0 / 0.0,
    last_accessed: 100L,
    note: None,
  }
  inspect(dir.format_score(100L), content="   NaN")
}

///|
test "dedup: la merging matches upstream\'s u64-domain semantics (a negative epoch wins)" {
  // upstream Epoch = u64: 1969 (-1) is the maximum in the u64 domain and wins dedup\'s max
  let a = @core.Database::from_dirs([
    @core.Dir::{ path: "/dup", rank: 1.0, last_accessed: -1L, note: None, },
    @core.Dir::{
      path: "/dup",
      rank: 1.0,
      last_accessed: 1788829200L,
      note: None,
    },
  ])
  a.dedup()
  @debug.assert_eq(a.all()[0].last_accessed, -1L)
  let b = @core.Database::from_dirs([
    @core.Dir::{
      path: "/dup",
      rank: 1.0,
      last_accessed: 1788829200L,
      note: None,
    },
    @core.Dir::{ path: "/dup", rank: 1.0, last_accessed: -1L, note: None, },
  ])
  b.dedup()
  @debug.assert_eq(b.all()[0].last_accessed, -1L)
}

///|
/// [#3] regression: the entry point normalizes non-finite values -- inf clamps to the ceiling, nan/-inf to the floor;
/// red verification: before the fix inf was poisoned into NaN by age() and landed on 0.01
test "import normalization: inf to the ceiling, nan and -inf to the floor (all three entry points)" {
  let inf = @string.parse_double("inf") catch { _ => 0.0 }
  let nan = @string.parse_double("nan") catch { _ => 0.0 }
  let db = @core.Database::new()
  db.add_update("/a", inf, 0L)
  @debug.assert_eq(db.all()[0].rank, 9999999.99)
  db.add_update("/b", nan, 0L)
  @debug.assert_eq(db.all()[1].rank, 0.01)
  db.add_unchecked("/c", inf, 0L)
  @debug.assert_eq(db.all()[2].rank, 9999999.99)
  db.add_unchecked("/d", 0.0 - inf, 0L)
  @debug.assert_eq(db.all()[3].rank, 0.01)
  // the accumulate path normalizes too: a finite value + inf -> the ceiling (not NaN)
  db.add_update("/a", 1.0, 0L)
  @debug.assert_eq(db.all()[0].rank, 9999999.99)
}

///|
/// [#3] regression: after an inf import, aging is no longer poisoned -- the total stays finite and other entries survive.
/// Before the fix: total=inf -> factor=0 -> ranks multiplied into NaN -> the other entries vanished
test "aging is healthy after import normalization: an inf entry does not poison the total" {
  let inf = @string.parse_double("inf") catch { _ => 0.0 }
  let db = @core.Database::new()
  db.add_update("/hot", inf, 0L)
  // the weight is large enough to survive aging at >= 1 (before the fix factor=0: the normal entry was zeroed and deleted,
  // and the hot entry survived as NaN -- the "poisoned" shape)
  db.add_update("/normal", 20000.0, 0L)
  db.age(10000.0)
  @debug.assert_eq(db.find_idx("/normal") is Some(_), true)
  @debug.assert_eq(db.find_idx("/hot") is Some(_), true)
  let hot = match db.find_idx("/hot") {
    Some(i) => db.all()[i].rank
    None => fail("unreachable")
  }
  // the finite test: NaN compares unequal to itself (MoonBit\'s Double has no is_finite predicate)
  @debug.assert_eq(hot != hot, false)
}
