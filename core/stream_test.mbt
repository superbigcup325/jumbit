// Stream 过滤链测试（exists 回调注入，不碰真实 FS）

///|
/// 构造测试选项：now 固定，其余给默认
fn opts(
  now : Int64,
  keywords? : Array[String] = [],
  exclude? : Array[String] = [],
  base_dir? : String? = None,
  exists? : Bool = false,
  resolve_symlinks? : Bool = false,
) -> @core.StreamOptions {
  {
    now,
    keywords,
    exclude,
    base_dir,
    exists,
    resolve_symlinks,
    ttl: now - 3L * @core.MONTH,
  }
}

///|
/// exists 回调桩：固定返回 should_exist 并计数。
/// 体内探测真实 async fs（结果丢弃）以满足 async 语义（无 async 调用的 async fn 是警告）。
fn counting_exists(should_exist : Bool) -> (async (String) -> Bool, Array[Int]) {
  let counter = [0]
  let f : async (String) -> Bool = async fn(_path : String) -> Bool {
    counter[0] = counter[0] + 1
    let _probe = @afs.exists("/tmp")
    should_exist
  }
  (f, counter)
}

///|
/// 不关心计数时的固定 exists 桩
fn fixed_exists(should_exist : Bool) -> async (String) -> Bool {
  counting_exists(should_exist).0
}

///|
async test "exclude glob 命中即懒删除（复查库状态与 dirty）" {
  let db = @core.Database::new()
  db.add("/a/x", 1.0, 0L)
  db.add("/b/y", 1.0, 0L)
  db.mark_clean()
  let o = opts(1000L, exclude=["/a/*"])
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 1)
  @debug.assert_eq(hits[0].path, "/b/y")
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.is_dirty(), true)
}

///|
async test "exists=false 且超 TTL → 懒删除" {
  let db = @core.Database::new()
  db.add("/stale", 1.0, 0L)
  let (exists_fn, _) = counting_exists(false)
  // now = 4 个月 → ttl = now - 3 个月 = 1 个月 > last_accessed(0)
  let o = opts(4L * @core.MONTH, exists=true)
  let hits = db.query_all(o, exists_fn)
  @debug.assert_eq(hits.length(), 0)
  @debug.assert_eq(db.all().length(), 0)
}

///|
async test "exists=false 但近期访问 → 保留不删" {
  let db = @core.Database::new()
  db.add("/recent", 1.0, 3L * @core.MONTH + 1L)
  let (exists_fn, _) = counting_exists(false)
  let o = opts(4L * @core.MONTH, exists=true)
  let hits = db.query_all(o, exists_fn)
  // last_accessed(3 个月+1 秒) ≥ ttl(1 个月) → 不删但也不返回
  @debug.assert_eq(hits.length(), 0)
  @debug.assert_eq(db.all().length(), 1)
}

///|
async test "exists 回调在所有前置过滤之后才调用（exists 最慢放最后）" {
  let db = @core.Database::new()
  db.add("/miss", 1.0, 0L) // 关键词不命中
  db.add("/hit", 1.0, 0L)
  let (exists_fn, counter) = counting_exists(true)
  let o = opts(1000L, keywords=["hit"], exists=true)
  let hits = db.query_all(o, exists_fn)
  @debug.assert_eq(hits.length(), 1)
  @debug.assert_eq(counter[0], 1)
}

///|
async test "关键词不命中时 exclude 不执行（不懒删）" {
  let db = @core.Database::new()
  db.add("/a/x", 1.0, 0L)
  let o = opts(1000L, keywords=["zzz"], exclude=["/a/*"])
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 0)
  // 关键词先行短路，exclude 未触碰条目
  @debug.assert_eq(db.all().length(), 1)
}

///|
async test "base_dir：组件级前缀（字符串前缀陷阱被排除）" {
  let db = @core.Database::new()
  db.add("/foo/bar/x", 1.0, 0L)
  db.add("/foo/baz/y", 1.0, 0L)
  // 字符串前缀会误中 /foo/baz，组件前缀不会
  let o = opts(1000L, base_dir=Some("/foo/ba"))
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 0)
  let o2 = opts(1000L, base_dir=Some("/foo/bar"))
  let hits2 = db.query_all(o2, fixed_exists(true))
  @debug.assert_eq(hits2.length(), 1)
  @debug.assert_eq(hits2[0].path, "/foo/bar/x")
}

///|
async test "query_all 顺序：得分从高到低" {
  let db = @core.Database::new()
  let now = 100000L
  db.add("/old", 1.0, now - 60L * @core.DAY)
  db.add("/new", 1.0, now)
  db.add("/mid", 1.0, now - 2L * @core.HOUR)
  let hits = db.query_all(opts(now), fixed_exists(true))
  @debug.assert_eq(hits[0].path, "/new")
  @debug.assert_eq(hits[1].path, "/mid")
  @debug.assert_eq(hits[2].path, "/old")
}

///|
test "remove：删返回 true，重复删返回 false" {
  let db = @core.Database::new()
  db.add("/a", 1.0, 0L)
  db.add("/b", 1.0, 0L)
  @debug.assert_eq(db.remove("/a"), true)
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.all()[0].path, "/b")
  @debug.assert_eq(db.remove("/a"), false)
  @debug.assert_eq(db.is_dirty(), true)
}

///|
test "starts_with：组件级前缀语义" {
  @debug.assert_eq(@core.starts_with("/foo/bar/x", "/foo/bar"), true)
  @debug.assert_eq(@core.starts_with("/foo/bar/x", "/foo/ba"), false)
  @debug.assert_eq(@core.starts_with("/foo/bar", "/"), true)
  @debug.assert_eq(@core.starts_with("/foo/bar", ""), true)
  @debug.assert_eq(@core.starts_with("/foo", "/foo/bar"), false)
}
