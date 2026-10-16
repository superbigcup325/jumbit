///|
pub const SECOND : Int64 = 1L

///|
pub const MINUTE : Int64 = 60L * SECOND

///|
pub const HOUR : Int64 = 60L * MINUTE

///|
pub const DAY : Int64 = 24L * HOUR

///|
pub const WEEK : Int64 = 7L * DAY

///|
pub const MONTH : Int64 = 30L * DAY

///|
/// One directory record: the three fields path/rank/last_accessed match upstream src/db/dir.rs;
/// note is a jumbit extension (the describe annotation, persisted from the v2 format on, encoded as empty for None)
pub(all) struct Dir {
  mut path : String
  mut rank : Double
  mut last_accessed : Int64
  mut note : String?
} derive(Debug)

///|
/// Frecency score = rank x the time-decay factor (epoch units: seconds)
/// Decay buckets: <1h x4.0 / <1d x2.0 / <1w x0.5 / otherwise x0.25
pub fn Dir::score(self : Dir, now : Int64) -> Double {
  // the decay interval matches upstream\'s u64 saturating_sub semantics (measured against zoxide 0.10.0):
  // when last_accessed is negative (the 1969 boundary: -1 in the i64 domain is the maximum in the u64 domain) or in the future,
  // a u64-domain comparison underflows and saturates to 0 -> the <1h x4.0 bucket, not the large number a straight i64 subtraction would give
  let now_u = now.reinterpret_as_uint64()
  let la_u = self.last_accessed.reinterpret_as_uint64()
  let duration = if now_u >= la_u {
    (now_u - la_u).reinterpret_as_int64()
  } else {
    0L
  }
  if duration < HOUR {
    self.rank * 4.0
  } else if duration < DAY {
    self.rank * 2.0
  } else if duration < WEEK {
    self.rank * 0.5
  } else {
    self.rank * 0.25
  }
}

///|
/// Score display: clamped to 0..9999, total width 6 with one decimal (matching upstream `{score:>6.1}`)
/// Examples: 40.0 -> "  40.0", 9999.95 -> "9999.0" (clamped), -1.0 -> "   0.0"
pub fn Dir::format_score(self : Dir, now : Int64) -> String {
  let s = self.score(now).clamp(min=0.0, max=9999.0)
  // Rust\'s {:.1} shows NaN as "NaN" (:>6.1 being right-aligned width 6); a NaN can enter the database through import\'s
  // nan/inf literals or an inf+(-inf) aggregation
  if s.is_nan() {
    return "   NaN"
  }
  // rounding matches Rust\'s {:.1} (round-half-to-even):
  // an exact half boundary (e.g. a stale entry at 1.0x0.25=0.25) -> 0.2, not 0.3
  let m = s * 10.0
  let fl = m.floor()
  let frac = m - fl
  let scaled = if frac > 0.5 {
    fl.to_int64() + 1L
  } else if frac < 0.5 {
    fl.to_int64()
  } else if fl % 2.0 == 0.0 {
    fl.to_int64()
  } else {
    fl.to_int64() + 1L
  }
  let int_part = (scaled / 10L).to_string().pad_start(4, ' ')
  let dec_part = (scaled % 10L).to_string()
  int_part + "." + dec_part
}
