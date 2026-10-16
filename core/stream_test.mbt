// Stream filter-chain tests (the exists callback is injected, so the real filesystem is never touched)

///|
/// Build test options: now is fixed, the rest take defaults
fn opts(
  now : Int64,
  keywords~ : Array[String] = [],
  exclude~ : Array[String] = [],
  base_dir~ : String? = None,
  exists~ : Bool = false,
  resolve_symlinks~ : Bool = false,
) -> @core.StreamOptions {
  {
    now,
    keywords,
    exclude,
    base_dir,
    exists,
    resolve_symlinks,
    ttl: now - 3L * @core.MONTH,
    fuzzy_superset: None,
  }
}

///|
/// The exists callback stub: always returns should_exist and counts calls.
/// The body probes the real async fs (discarding the result) to satisfy async semantics (an async fn with no async call is a warning).
fn counting_exists(
  should_exist : Bool,
) -> (async (String) -> Bool, Array[Int32]) {
  let counter = [0]
  let f : async (String) -> Bool = async fn(_path : String) -> Bool {
    counter[0] = counter[0] + 1
    let _probe = @afs.exists("/tmp")
    should_exist
  }
  (f, counter)
}

///|
/// A fixed exists stub for when the count does not matter
fn fixed_exists(should_exist : Bool) -> async (String) -> Bool {
  counting_exists(should_exist).0
}

///|
async test "an exclude glob hit is lazily deleted (re-checking the database state and dirty)" {
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
async test "exists=false and past the TTL -> lazily deleted" {
  let db = @core.Database::new()
  db.add("/stale", 1.0, 0L)
  let (exists_fn, _) = counting_exists(false)
  // now = 4 months -> ttl = now - 3 months = 1 month > last_accessed(0)
  let o = opts(4L * @core.MONTH, exists=true)
  let hits = db.query_all(o, exists_fn)
  @debug.assert_eq(hits.length(), 0)
  @debug.assert_eq(db.all().length(), 0)
}

///|
async test "exists=false but visited recently -> kept, not deleted" {
  let db = @core.Database::new()
  db.add("/recent", 1.0, 3L * @core.MONTH + 1L)
  let (exists_fn, _) = counting_exists(false)
  let o = opts(4L * @core.MONTH, exists=true)
  let hits = db.query_all(o, exists_fn)
  // last_accessed (3 months + 1 second) >= ttl (1 month) -> not deleted, but not returned either
  @debug.assert_eq(hits.length(), 0)
  @debug.assert_eq(db.all().length(), 1)
}

///|
async test "several lazy deletions in one pass: exclude removes several, the survivors are intact and output descending" {
  let db = @core.Database::new()
  db.add("/a/x", 1.0, 0L)
  db.add("/b/y", 1.0, 0L)
  db.add("/c/z", 1.0, 0L)
  db.add("/keep", 1.0, 0L)
  db.mark_clean()
  let o = opts(1000L, exclude=["/a/*", "/c/*"])
  let hits = db.query_all(o, fixed_exists(true))
  // reverse traversal interleaved with swap_remove: /keep and /b/y survive, and hits come highest first
  @debug.assert_eq(hits.length(), 2)
  @debug.assert_eq(hits[0].path, "/keep")
  @debug.assert_eq(hits[1].path, "/b/y")
  @debug.assert_eq(db.all().length(), 2)
  @debug.assert_eq(db.find_idx("/a/x") is Some(_), false)
  @debug.assert_eq(db.find_idx("/c/z") is Some(_), false)
  @debug.assert_eq(db.find_idx("/b/y") is Some(_), true)
}

///|
async test "exists=false with several past the TTL -> all deleted in one pass, recent entries surviving" {
  let db = @core.Database::new()
  db.add("/s1", 1.0, 0L)
  db.add("/s2", 1.0, 0L)
  db.add("/fresh", 1.0, 3L * @core.MONTH + 1L)
  let (exists_fn, _) = counting_exists(false)
  let o = opts(4L * @core.MONTH, exists=true)
  let hits = db.query_all(o, exists_fn)
  @debug.assert_eq(hits.length(), 0)
  @debug.assert_eq(db.all().length(), 1)
  @debug.assert_eq(db.find_idx("/fresh") is Some(_), true)
}

///|
async test "the exists callback runs only after every earlier filter (the slowest, so it goes last)" {
  let db = @core.Database::new()
  db.add("/miss", 1.0, 0L) // the keyword does not hit
  db.add("/hit", 1.0, 0L)
  let (exists_fn, counter) = counting_exists(true)
  let o = opts(1000L, keywords=["hit"], exists=true)
  let hits = db.query_all(o, exists_fn)
  @debug.assert_eq(hits.length(), 1)
  @debug.assert_eq(counter[0], 1)
}

///|
async test "exclude does not run on a keyword miss (no lazy deletion)" {
  let db = @core.Database::new()
  db.add("/a/x", 1.0, 0L)
  let o = opts(1000L, keywords=["zzz"], exclude=["/a/*"])
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 0)
  // the keyword short-circuits first, so exclude never touches the entry
  @debug.assert_eq(db.all().length(), 1)
}

///|
async test "base_dir: component-level prefix (the string-prefix trap is excluded)" {
  let db = @core.Database::new()
  db.add("/foo/bar/x", 1.0, 0L)
  db.add("/foo/baz/y", 1.0, 0L)
  // a string prefix would wrongly hit /foo/baz; a component prefix does not
  let o = opts(1000L, base_dir=Some("/foo/ba"))
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 0)
  let o2 = opts(1000L, base_dir=Some("/foo/bar"))
  let hits2 = db.query_all(o2, fixed_exists(true))
  @debug.assert_eq(hits2.length(), 1)
  @debug.assert_eq(hits2[0].path, "/foo/bar/x")
}

///|
async test "query_all order: highest score first" {
  let db = @core.Database::new()
  let now = 1788833590L
  db.add("/old", 1.0, now - 60L * @core.DAY)
  db.add("/new", 1.0, now)
  db.add("/mid", 1.0, now - 2L * @core.HOUR)
  let hits = db.query_all(opts(now), fixed_exists(true))
  @debug.assert_eq(hits[0].path, "/new")
  @debug.assert_eq(hits[1].path, "/mid")
  @debug.assert_eq(hits[2].path, "/old")
}

///|
test "remove: a deletion returns true, a repeat returns false" {
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
test "starts_with: component-level prefix semantics" {
  @debug.assert_eq(@core.starts_with("/foo/bar/x", "/foo/bar"), true)
  @debug.assert_eq(@core.starts_with("/foo/bar/x", "/foo/ba"), false)
  @debug.assert_eq(@core.starts_with("/foo/bar", "/"), true)
  @debug.assert_eq(@core.starts_with("/foo/bar", ""), true)
  @debug.assert_eq(@core.starts_with("/foo", "/foo/bar"), false)
}

///|
/// --fuzzy\'s single-pass fallback collection: with no keyword hit, out is empty and the chain\'s through-set enters the superset;
/// glob lazy deletion applies to non-hit entries too (matching the old second pass)
async test "fuzzy_superset collection: a keyword miss keeps the chain\'s through-set, and glob lazy deletion still applies" {
  let db = @core.Database::new()
  db.add("/a/hit", 2.0, 0L)
  db.add("/b/two", 1.0, 0L)
  db.add("/c/three", 1.0, 0L)
  db.mark_clean()
  let superset : Array[@core.Dir] = []
  let o = {
    ..opts(1000L, keywords=["hit"], exclude=["/c/*"]),
    fuzzy_superset: Some(superset),
  }
  // the keyword "hit" hits /hit/one and the other two enter the superset (/del/three is lazily deleted by the glob first)
  let hits = db.query_all(o, fixed_exists(true))
  @debug.assert_eq(hits.length(), 1)
  @debug.assert_eq(hits[0].path, "/a/hit")
  @debug.assert_eq(superset.length(), 1)
  @debug.assert_eq(superset[0].path, "/b/two")
  @debug.assert_eq(db.all().length(), 2)
  @debug.assert_eq(db.is_dirty(), true)
  // with collection on, the lazy deletion on the exact-hit path is unchanged
  let superset2 : Array[@core.Dir] = []
  let o2 = { ..opts(1000L), fuzzy_superset: Some(superset2), }
  let hits2 = db.query_all(o2, fixed_exists(true))
  @debug.assert_eq(hits2.length(), 2)
  @debug.assert_eq(superset2.length(), 0)
}
