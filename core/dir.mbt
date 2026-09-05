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
/// 单条目录记录：三字段模型（对齐上游 src/db/dir.rs）
pub(all) struct Dir {
  path : String
  rank : Double
  last_accessed : Int64
}

///|
/// frecency 得分 = rank × 时间衰减系数（Epoch 单位：秒）
/// 衰减档位：<1h ×4.0 / <1d ×2.0 / <1w ×0.5 / 其余 ×0.25
pub fn Dir::score(self : Dir, now : Int64) -> Double {
  // now < last_accessed（时钟回拨）按 0 间隔处理，落 <1h 档
  let duration = if now > self.last_accessed {
    now - self.last_accessed
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
/// 得分显示：clamp 到 0..9999，总宽 6、1 位小数（对齐上游 `{score:>6.1}`）
/// 例：40.0 → "  40.0"，9999.95 → "9999.0"（clamp），-1.0 → "   0.0"
pub fn Dir::format_score(self : Dir, now : Int64) -> String {
  let s = self.score(now).clamp(min=0.0, max=9999.0)
  let scaled = (s * 10.0).round().to_int64()
  let int_part = (scaled / 10L).to_string().pad_start(4, ' ')
  let dec_part = (scaled % 10L).to_string()
  int_part + "." + dec_part
}
