// Blackbox tests: reaching the public API through @core

///|
test "score decay factors: four buckets + a clock rollback" {
  let base = 1000000L
  let dir = @core.Dir::{
    path: "/foo",
    rank: 10.0,
    last_accessed: base,
    note: None,
  }
  // 30 minutes ago -> <1h x4.0
  @debug.assert_eq(dir.score(base + 30L * @core.MINUTE), 40.0)
  // 2 hours ago -> <1d x2.0
  @debug.assert_eq(dir.score(base + 2L * @core.HOUR), 20.0)
  // 3 days ago -> <1w x0.5
  @debug.assert_eq(dir.score(base + 3L * @core.DAY), 5.0)
  // 2 months ago -> otherwise x0.25
  @debug.assert_eq(dir.score(base + 60L * @core.DAY), 2.5)
  // exactly 1 hour -> the next bucket down, x2.0 (strictly <)
  @debug.assert_eq(dir.score(base + @core.HOUR), 20.0)
  // exactly 1 day -> <1w x0.5 (strictly <)
  @debug.assert_eq(dir.score(base + @core.DAY), 5.0)
  // exactly 1 week -> otherwise x0.25 (strictly <)
  @debug.assert_eq(dir.score(base + @core.WEEK), 2.5)
  // now == last_accessed → ×4.0
  @debug.assert_eq(dir.score(base), 40.0)
  // now < last_accessed (a clock rollback) -> x4.0
  @debug.assert_eq(dir.score(base - 100L), 40.0)
}

///|
test "score: the clamp for rank=0 and a huge rank" {
  let zero = @core.Dir::{
    path: "/a",
    rank: 0.0,
    last_accessed: 0L,
    note: None,
  }
  @debug.assert_eq(zero.score(60L), 0.0)
  // a huge rank x4 -> inf, clamped to 9999.0 for display
  let huge = @core.Dir::{
    path: "/a",
    rank: 1.0e308,
    last_accessed: 0L,
    note: None,
  }
  @debug.assert_eq(huge.format_score(1L), "9999.0")
}

///|
test "format_score: width 6, one decimal, the clamp boundaries" {
  let now = 1000L
  let dir = @core.Dir::{
    path: "/foo",
    rank: 10.0,
    last_accessed: now,
    note: None,
  }
  // 40.0 -> right-aligned width 6
  inspect(dir.format_score(now), content="  40.0")
  // 5.0 (3 days ago, rank 10 x0.5)
  inspect(dir.format_score(now + 3L * @core.DAY), content="   5.0")
  // above the ceiling it clamps: rank 3000 x4 = 12000 -> 9999.0
  let big = @core.Dir::{
    path: "/foo",
    rank: 3000.0,
    last_accessed: now,
    note: None,
  }
  inspect(big.format_score(now), content="9999.0")
  // a negative rank clamps to 0
  let neg = @core.Dir::{
    path: "/foo",
    rank: -1.0,
    last_accessed: now,
    note: None,
  }
  inspect(neg.format_score(now), content="   0.0")
  // decimal rounding: rank 123.456 x4 = 493.824 -> 493.8
  let frac = @core.Dir::{
    path: "/foo",
    rank: 123.456,
    last_accessed: now,
    note: None,
  }
  inspect(frac.format_score(now), content=" 493.8")
  // a single-digit decimal: rank 0.1 x4 = 0.4 -> the integer part is padded with 3 spaces
  let tiny = @core.Dir::{
    path: "/foo",
    rank: 0.1,
    last_accessed: now,
    note: None,
  }
  inspect(tiny.format_score(now), content="   0.4")
  // rounding carries without breaking the clamp: rank 2499.74 x4 = 9998.96 -> x10 round = 99990 -> 9999.0
  let carry = @core.Dir::{
    path: "/foo",
    rank: 2499.74,
    last_accessed: now,
    note: None,
  }
  inspect(carry.format_score(now), content="9999.0")
}

///|
test "format_score: an exact half boundary rounds half-to-even as Rust {:.1} does (matching zoxide\'s output)" {
  // now is a realistic magnitude: now-2*WEEK must stay a positive epoch (a negative la lands in the x4 bucket; see the score tests)
  let now = 1788833590L
  // 1.0x0.25 = 0.25 -> 0.2 (the 0 rounds down to even; .round() would wrongly give 0.3)
  let a = @core.Dir::{
    path: "/a",
    rank: 1.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(a.format_score(now), content="   0.2")
  // 3.0x0.25 = 0.75 -> 0.8 (the odd 7 rounds up to the even 8)
  let b = @core.Dir::{
    path: "/b",
    rank: 3.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(b.format_score(now), content="   0.8")
  // 5.0x0.25 = 1.25 -> 1.2 (the even 2 stays)
  let c = @core.Dir::{
    path: "/c",
    rank: 5.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(c.format_score(now), content="   1.2")
  // 7.0x0.25 = 1.75 -> 1.8 (the odd 7 goes to 8)
  let d = @core.Dir::{
    path: "/d",
    rank: 7.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(d.format_score(now), content="   1.8")
}

///|
test "score: a negative last_accessed saturates in the u64 domain into the x4 bucket (measured against upstream)" {
  // 1969-12-31 23:59:59 = epoch -1: a straight i64 subtraction gives a huge age, while upstream\'s u64 domain underflows and saturates to 0
  let dir = @core.Dir::{
    path: "/a",
    rank: 13.0,
    last_accessed: -1L,
    note: None,
  }
  let now = 1788833590L
  inspect(dir.score(now), content="52")
}
