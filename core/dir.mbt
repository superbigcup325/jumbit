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
/// 单条目录记录：path/rank/last_accessed 三字段对齐上游 src/db/dir.rs；
/// note 为 jumbit 扩展（describe 的人工标注，v2 格式起持久化，None 编码为空）
pub(all) struct Dir {
  mut path : String
  mut rank : Double
  mut last_accessed : Int64
  mut note : String?
} derive(Debug)

///|
/// frecency 得分 = rank × 时间衰减系数（Epoch 单位：秒）
/// 衰减档位：<1h ×4.0 / <1d ×2.0 / <1w ×0.5 / 其余 ×0.25
pub fn Dir::score(self : Dir, now : Int64) -> Double {
  // 衰减间隔对齐上游的 u64 saturating_sub 语义（zoxide 0.10.0 对拍实测）：
  // last_accessed 为负（1969 边界：i64 域 -1 = u64 域极大值）或未来时间戳时，
  // u64 域比较下溢饱和为 0 → 落 <1h ×4.0 档，而非 i64 直减得到的大数
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
/// 得分显示：clamp 到 0..9999，总宽 6、1 位小数（对齐上游 `{score:>6.1}`）
/// 例：40.0 → "  40.0"，9999.95 → "9999.0"（clamp），-1.0 → "   0.0"
pub fn Dir::format_score(self : Dir, now : Int64) -> String {
  let s = self.score(now).clamp(min=0.0, max=9999.0)
  // Rust {:.1} 对 NaN 显示 "NaN"（:>6.1 即右对齐 6 宽）；NaN 可经 import 的
  // nan/inf 字面量或 inf+(-inf) 聚合进入库
  if s.is_nan() {
    return "   NaN"
  }
  // 舍入对齐 Rust {:.1}（半界取偶，round-half-to-even）：
  // 精确半界（如陈旧条目 1.0×0.25=0.25）→ 0.2 而非 0.3
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
