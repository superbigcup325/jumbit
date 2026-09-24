// 函数级基准（moon bench）：perf_check.sh 端到端口径之外的函数粒度热点观测，
// 数字进 D9 台账（docs/test-ledger.md）。数据集确定性构造（固定种子 chacha8），
// 规模 1 万条与 perf 数据集同量级；it.keep 防死码消除

///|
fn bench_dirs(n : Int) -> Array[@core.Dir] {
  // chacha8 种子定长 32 字节（不足 abort，@alert unsafe）
  let rand = @random.Rand::chacha8(seed=b"jumbit-bench-seed000000000000000")
  let out : Array[@core.Dir] = []
  for i in 0..<n {
    out.push({
      path: "/home/user/\{rand.int(limit=64)}/project-\{i}",
      rank: rand.double(min=0.01, max=100.0),
      last_accessed: rand.int(limit=180).to_int64() * 86400L,
      note: None,
    })
  }
  out
}

///|
test "bench sort_by_score 10k" (it : @bench.T) {
  let dirs = bench_dirs(10000)
  it.bench(fn() {
    // D9 优化轮热点：装载后按得分排序（query --all / add 落库的共同内循环）。
    // 浅拷贝必须放闭包内：from_dirs 不拷贝，首迭代会把共享数组排好序，
    // 后续迭代测的是「有序输入的自适应排序」而非真实负载
    let db = @core.Database::from_dirs(dirs.copy())
    db.sort_by_score(1704067200L)
    it.keep(db)
  })
}

///|
test "bench plaintext codec 10k" (it : @bench.T) {
  let dirs = bench_dirs(10000)
  it.bench(fn() {
    // 落库与加载的编解码往返
    it.keep(@core.decode_plaintext(@core.encode_plaintext(dirs)))
  })
}

///|
test "bench filter_by_keywords 10k" (it : @bench.T) {
  let dirs = bench_dirs(10000)
  let paths : Array[String] = []
  for d in dirs {
    paths.push(d.path)
  }
  it.bench(fn() {
    // 真实查询形态：对全库逐条做末组件锚定过滤
    let mut hits = 0
    for p in paths {
      if @core.filter_by_keywords(["user", "work"], p) {
        hits = hits + 1
      }
    }
    it.keep(hits)
  })
}
