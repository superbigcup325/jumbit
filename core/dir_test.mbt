// 黑盒测试：通过 @core 访问公共 API

///|
test "score 衰减系数：四档 + 时钟回拨" {
  let base = 1000000L
  let dir = @core.Dir::{
    path: "/foo",
    rank: 10.0,
    last_accessed: base,
    note: None,
  }
  // 30 分钟前 → <1h ×4.0
  @debug.assert_eq(dir.score(base + 30L * @core.MINUTE), 40.0)
  // 2 小时前 → <1d ×2.0
  @debug.assert_eq(dir.score(base + 2L * @core.HOUR), 20.0)
  // 3 天前 → <1w ×0.5
  @debug.assert_eq(dir.score(base + 3L * @core.DAY), 5.0)
  // 2 个月前 → 其余 ×0.25
  @debug.assert_eq(dir.score(base + 60L * @core.DAY), 2.5)
  // 恰好 1 小时 → 落下一档 ×2.0（严格 <）
  @debug.assert_eq(dir.score(base + @core.HOUR), 20.0)
  // 恰好 1 天 → 落 <1w ×0.5（严格 <）
  @debug.assert_eq(dir.score(base + @core.DAY), 5.0)
  // 恰好 1 周 → 落其余 ×0.25（严格 <）
  @debug.assert_eq(dir.score(base + @core.WEEK), 2.5)
  // now == last_accessed → ×4.0
  @debug.assert_eq(dir.score(base), 40.0)
  // now < last_accessed（时钟回拨）→ ×4.0
  @debug.assert_eq(dir.score(base - 100L), 40.0)
}

///|
test "score：rank=0 与极大 rank 的 clamp" {
  let zero = @core.Dir::{
    path: "/a",
    rank: 0.0,
    last_accessed: 0L,
    note: None,
  }
  @debug.assert_eq(zero.score(60L), 0.0)
  // 极大 rank ×4 → inf，显示时被 clamp 到 9999.0
  let huge = @core.Dir::{
    path: "/a",
    rank: 1.0e308,
    last_accessed: 0L,
    note: None,
  }
  @debug.assert_eq(huge.format_score(1L), "9999.0")
}

///|
test "format_score：宽度 6、1 位小数、clamp 边界" {
  let now = 1000L
  let dir = @core.Dir::{
    path: "/foo",
    rank: 10.0,
    last_accessed: now,
    note: None,
  }
  // 40.0 → 右对齐宽 6
  inspect(dir.format_score(now), content="  40.0")
  // 5.0（3 天前，rank 10 ×0.5）
  inspect(dir.format_score(now + 3L * @core.DAY), content="   5.0")
  // 超上限 clamp：rank 3000 ×4 = 12000 → 9999.0
  let big = @core.Dir::{
    path: "/foo",
    rank: 3000.0,
    last_accessed: now,
    note: None,
  }
  inspect(big.format_score(now), content="9999.0")
  // 负 rank clamp 到 0
  let neg = @core.Dir::{
    path: "/foo",
    rank: -1.0,
    last_accessed: now,
    note: None,
  }
  inspect(neg.format_score(now), content="   0.0")
  // 小数进位：rank 123.456 ×4 = 493.824 → 493.8
  let frac = @core.Dir::{
    path: "/foo",
    rank: 123.456,
    last_accessed: now,
    note: None,
  }
  inspect(frac.format_score(now), content=" 493.8")
  // 个位小数：rank 0.1 ×4 = 0.4 → 整数部分补齐 3 空格
  let tiny = @core.Dir::{
    path: "/foo",
    rank: 0.1,
    last_accessed: now,
    note: None,
  }
  inspect(tiny.format_score(now), content="   0.4")
  // round 进位不破坏 clamp：rank 2499.74 ×4 = 9998.96 → ×10 round = 99990 → 9999.0
  let carry = @core.Dir::{
    path: "/foo",
    rank: 2499.74,
    last_accessed: now,
    note: None,
  }
  inspect(carry.format_score(now), content="9999.0")
}

///|
test "format_score：精确半界按 Rust {:.1} 半界取偶（与 zoxide 输出对齐）" {
  // now 取现实量级：now-2*WEEK 需保持正 epoch（负 la 会落 ×4 档，见 score 测试）
  let now = 1788833590L
  // 1.0×0.25 = 0.25 → 0.2（0 向下取偶；.round() 会错给 0.3）
  let a = @core.Dir::{
    path: "/a",
    rank: 1.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(a.format_score(now), content="   0.2")
  // 3.0×0.25 = 0.75 → 0.8（7 奇数向偶进到 8）
  let b = @core.Dir::{
    path: "/b",
    rank: 3.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(b.format_score(now), content="   0.8")
  // 5.0×0.25 = 1.25 → 1.2（2 偶数不动）
  let c = @core.Dir::{
    path: "/c",
    rank: 5.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(c.format_score(now), content="   1.2")
  // 7.0×0.25 = 1.75 → 1.8（7 奇数进到 8）
  let d = @core.Dir::{
    path: "/d",
    rank: 7.0,
    last_accessed: now - 2L * @core.WEEK,
    note: None,
  }
  inspect(d.format_score(now), content="   1.8")
}

///|
test "score：负 last_accessed 走 u64 饱和语义落 ×4 档（上游对拍实测）" {
  // 1969-12-31 23:59:59 = epoch -1：i64 直减得到巨大 age，上游 u64 域下溢饱和为 0
  let dir = @core.Dir::{
    path: "/a",
    rank: 13.0,
    last_accessed: -1L,
    note: None,
  }
  let now = 1788833590L
  inspect(dir.score(now), content="52")
}
