// 黑盒测试：通过 @core 访问公共 API

///|
test "score 衰减系数：四档 + 时钟回拨" {
  let base = 1000000L
  let dir = @core.Dir::{ path: "/foo", rank: 10.0, last_accessed: base, }
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
  let zero = @core.Dir::{ path: "/a", rank: 0.0, last_accessed: 0L, }
  @debug.assert_eq(zero.score(60L), 0.0)
  // 极大 rank ×4 → inf，显示时被 clamp 到 9999.0
  let huge = @core.Dir::{ path: "/a", rank: 1.0e308, last_accessed: 0L, }
  @debug.assert_eq(huge.format_score(1L), "9999.0")
}

///|
test "format_score：宽度 6、1 位小数、clamp 边界" {
  let now = 1000L
  let dir = @core.Dir::{ path: "/foo", rank: 10.0, last_accessed: now, }
  // 40.0 → 右对齐宽 6
  inspect(dir.format_score(now), content="  40.0")
  // 5.0（3 天前，rank 10 ×0.5）
  inspect(dir.format_score(now + 3L * @core.DAY), content="   5.0")
  // 超上限 clamp：rank 3000 ×4 = 12000 → 9999.0
  let big = @core.Dir::{ path: "/foo", rank: 3000.0, last_accessed: now, }
  inspect(big.format_score(now), content="9999.0")
  // 负 rank clamp 到 0
  let neg = @core.Dir::{ path: "/foo", rank: -1.0, last_accessed: now, }
  inspect(neg.format_score(now), content="   0.0")
  // 小数进位：rank 123.456 ×4 = 493.824 → 493.8
  let frac = @core.Dir::{ path: "/foo", rank: 123.456, last_accessed: now, }
  inspect(frac.format_score(now), content=" 493.8")
  // 个位小数：rank 0.1 ×4 = 0.4 → 整数部分补齐 3 空格
  let tiny = @core.Dir::{ path: "/foo", rank: 0.1, last_accessed: now, }
  inspect(tiny.format_score(now), content="   0.4")
  // round 进位不破坏 clamp：rank 2499.74 ×4 = 9998.96 → ×10 round = 99990 → 9999.0
  let carry = @core.Dir::{ path: "/foo", rank: 2499.74, last_accessed: now, }
  inspect(carry.format_score(now), content="9999.0")
}
