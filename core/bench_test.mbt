// Function-level benchmarks (moon bench): function-granularity hot-spot observation beyond perf_check.sh\'s end-to-end view,
// with the numbers going into the D9 ledger (docs/test-ledger.md). The dataset is built deterministically (fixed chacha8 seed)
// at 10k entries, the same order as the perf dataset; it.keep guards against dead-code elimination

///|
fn bench_dirs(n : Int32) -> Array[@core.Dir] {
  // the chacha8 seed is a fixed 32 bytes (short input aborts; @alert unsafe)
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
    // a D9 optimization-round hot spot: sorting by score after a load (the inner loop shared by query --all and add).
    // the shallow copy must live inside the closure: from_dirs does not copy, so the first iteration would sort the shared array
    // and later iterations would measure "adaptive sorting of already-sorted input" instead of the real load
    let db = @core.Database::from_dirs(dirs.copy())
    db.sort_by_score(1704067200L)
    it.keep(db)
  })
}

///|
test "bench plaintext codec 10k" (it : @bench.T) {
  let dirs = bench_dirs(10000)
  it.bench(fn() {
    // the encode/decode round trip of saving and loading
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
    // calling the public entry point per entry: each call includes the keyword pre-normalization check (zero-allocation lowercase).
    // The real query hot path is in core/stream: keyword normalization is hoisted to once per query, and per entry only the
    // internal match function runs; for the end-to-end view see perf_check\'s query scenarios
    let mut hits = 0
    for p in paths {
      if @core.filter_by_keywords(["user", "work"], p) {
        hits = hits + 1
      }
    }
    it.keep(hits)
  })
}
