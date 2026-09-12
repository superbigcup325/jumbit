// query --tsv 写出层字节级测试（jumbit 扩展语义；now 取 10_000_000L ≈ 115 天，
// la=0 落 ×0.25 档、la=2^40 未来落 ×4 档，均不随时间漂移）

///|
/// 构造条目辅助
fn tsv_dir(p : String, r : Double, la : Int64) -> @core.Dir {
  @core.Dir::{ path: p, rank: r, last_accessed: la, note: None, }
}

///|
/// 整体拼装（末行不带换行，空数组出空串）——生产路已改 tsv_row 流式，
/// 此包装保留作多行形状的字节级冻结器
fn render_tsv(
  dirs : Array[@core.Dir],
  now : Int64,
  matched_by : String,
) -> String {
  let out : StringBuilder = StringBuilder()
  for i, d in dirs {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string(tsv_row(d, now, matched_by))
  }
  out.to_string()
}

///|
test "render_tsv：空数组出空串" {
  @debug.assert_eq(render_tsv([], 10000000L, "exact"), "")
}

///|
test "render_tsv：列序与 tab 分隔（path/score/last_accessed/matched_by）" {
  let dirs = [tsv_dir("/a", 2.0, 1099511627776), tsv_dir("/b", 1.5, 0)]
  // score：2.0×4=8 → "8"；1.5×0.25=0.375 → "0.375"（与 --json 数字形态一致）
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/a\t8\t1099511627776\texact\n/b\t0.375\t0\texact",
  )
}

///|
test "render_tsv：score 短表示与 NaN/Inf 原文 token（JSON 侧为 null，此处不 null 化）" {
  let dirs = [
    tsv_dir("/int", 4.0, 0),
    tsv_dir("/frac", 0.75, 0),
    tsv_dir("/neg", -0.75, 0),
    tsv_dir("/nan", @string.parse_double("nan") catch { _ => 1.0 }, 0),
    tsv_dir("/inf", @string.parse_double("inf") catch { _ => 1.0 }, 0),
    tsv_dir("/ninf", @string.parse_double("-inf") catch { _ => 1.0 }, 0),
  ]
  // ×0.25：1 / 0.1875 / -0.1875 / NaN / Infinity / -Infinity
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/int\t1\t0\texact\n/frac\t0.1875\t0\texact\n/neg\t-0.1875\t0\texact\n/nan\tNaN\t0\texact\n/inf\tInfinity\t0\texact\n/ninf\t-Infinity\t0\texact",
  )
}

///|
test "render_tsv：path 原样透传不做任何转义（tab/引号/中文）" {
  let dirs = [
    tsv_dir("/a\tb", 1.0, 0),
    tsv_dir("c\"d|e", 1.0, 0),
    tsv_dir("/中文", 1.0, 0),
  ]
  // tab 路径使该行列数歧义——已知限制（README 注记），行为在此冻结
  @debug.assert_eq(
    render_tsv(dirs, 10000000L, "exact"),
    "/a\tb\t0.25\t0\texact\nc\"d|e\t0.25\t0\texact\n/中文\t0.25\t0\texact",
  )
}

///|
test "render_tsv：matched_by 值透传" {
  let dirs = [tsv_dir("/x", 1.0, 0)]
  @debug.assert_eq(render_tsv(dirs, 10000000L, "fuzzy"), "/x\t0.25\t0\tfuzzy")
}
