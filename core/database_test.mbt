// Database 最小集测试

///|
test "add：新建与累加，不更新 last_accessed" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 1000L)
  db.add("/foo", 1.0, 5000L)
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.all()[0].path, "/foo")
  @debug.assert_eq(db.all()[0].rank, 2.0)
  @debug.assert_eq(db.all()[0].last_accessed, 1000L)
}

///|
test "add：负增量 clamp 到 0（新建与已有两路）" {
  let db = @core.Database::new()
  db.add("/a", -5.0, 0L)
  @debug.assert_eq(db.all()[0].rank, 0.0)
  db.add("/b", 1.0, 0L)
  db.add("/b", -5.0, 0L)
  @debug.assert_eq(db.all().length(), 2)
  @debug.assert_eq(db.all()[1].rank, 0.0)
}

///|
test "add_update：rank 累加且更新 last_accessed" {
  let db = @core.Database::new()
  db.add_update("/foo", 1.0, 1000L)
  db.add_update("/foo", 1.0, 5000L)
  @debug.assert_eq(db.all()[0].rank, 2.0)
  @debug.assert_eq(db.all()[0].last_accessed, 5000L)
}

///|
test "dirty 标志流转" {
  let db = @core.Database::new()
  @debug.assert_eq(db.is_dirty(), false)
  db.add("/foo", 1.0, 0L)
  @debug.assert_eq(db.is_dirty(), true)
  db.mark_clean()
  @debug.assert_eq(db.is_dirty(), false)
}

///|
test "sort_by_score：升序，最近访问的排尾部" {
  let db = @core.Database::new()
  let now = 100000L
  db.add("/old", 1.0, now - 60L * @core.DAY) // ×0.25
  db.add("/mid", 1.0, now - 2L * @core.HOUR) // ×2.0
  db.add("/new", 1.0, now) // ×4.0
  db.sort_by_score(now)
  @debug.assert_eq(db.all()[0].path, "/old")
  @debug.assert_eq(db.all()[1].path, "/mid")
  @debug.assert_eq(db.all()[2].path, "/new")
}

///|
test "find_idx：命中与未命中" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 0L)
  @debug.assert_eq(db.find_idx("/foo"), Some(0))
  @debug.assert_eq(db.find_idx("/bar"), None)
}

///|
test "all() 返回副本：外部增删不影响库内部" {
  let db = @core.Database::new()
  db.add("/foo", 1.0, 0L)
  let snapshot = db.all()
  snapshot.push(@core.Dir::{ path: "/injected", rank: 9.0, last_accessed: 0L, })
  @debug.assert_eq(db.all().length(), 1)
}

///|
test "from_dirs：解码入口构建，初始未标脏" {
  let dirs = [@core.Dir::{ path: "/a", rank: 1.0, last_accessed: 0L, }]
  let db = @core.Database::from_dirs(dirs)
  @debug.assert_eq(db.is_dirty(), false)
  @debug.assert_eq(db.all().length(), 1)
}
