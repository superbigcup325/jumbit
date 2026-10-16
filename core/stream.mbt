///|
/// Query-stream options (matching upstream StreamOptions)
pub(all) struct StreamOptions {
  now : Int64
  keywords : Array[String]
  /// glob patterns (already through validate_glob); a hit is lazily deleted
  exclude : Array[String]
  /// Some -> component-level prefix filtering (--base-dir; wired to the CLI in a later version)
  base_dir : String?
  /// false skips the existence check (--all)
  exists : Bool
  /// the injected exists callback uses this to decide whether to follow symlinks (matching upstream\'s inverse logic)
  resolve_symlinks : Bool
  /// missing and last_accessed < ttl -> lazily deleted (default now - 3*MONTH)
  ttl : Int64
  /// Some -> collect the chain\'s through-set (entries that missed the keyword but passed base_dir/exclude/exists),
  /// so --fuzzy\'s fallback can finish in one pass: the lazy-deletion semantics match the old second pass (glob/TTL
  /// hits delete the same way), while ordinary queries pass None to keep the keyword short-circuit free
  fuzzy_superset : Array[Dir]?
}

///|
/// The query stream: the full filter chain runs in descending score order (matching upstream Stream::next):
/// score sort -> keywords -> base_dir -> exclude (glob, a hit lazily deletes) -> exists (last, the slowest)
/// -> a missing entry past its TTL is lazily deleted. Returns every hit, highest score first.
/// The exists callback is injected by the caller (platform passes a filesystem check, unit tests pass a closure).
pub async fn Database::query_all(
  self : Database,
  opts : StreamOptions,
  exists : async (String) -> Bool,
) -> Array[Dir] {
  // the exclude globs are compiled once and reused (the whole database is filtered entry by entry, so re-materializing the patterns is the hot spot)
  let globs : Array[Array[Char]] = []
  for pattern in opts.exclude {
    globs.push(compile_glob(pattern))
  }
  // keywords are pre-normalized once (zero allocation per entry); sorting moved after filtering: score is a deterministic
  // per-entry function and the lazy-delete set is independent of traversal order, so filter-then-sort sorts only the hits (a miss-type query
  // skips the full sort), and a stable sort keeps tied scores in their in-database relative order, matching sort-then-filter
  let kws = keywords_lower(opts.keywords)
  let out : Array[Dir] = []
  // reverse traversal: swap_remove moves the tail element into idx, which must already have been visited, so the index is safe
  let len = self.dirs.length()
  if opts.exists {
    // the exists path (default query): the loop holds an await point, so it keeps its original shape
    for i in len>..0 {
      let dir = self.dirs[i]
      let kw_ok = filter_by_keywords_lower(kws, dir.path)
      // a keyword miss with no fallback set being collected: short-circuit and skip (upstream Stream ordering semantics,
      // so lazy deletion and the existence check do not apply)
      if !kw_ok && opts.fuzzy_superset is None {
        continue
      }
      if !filter_base_dir(opts, dir.path) {
        continue
      }
      if !filter_exclude(globs, dir.path) {
        self.swap_remove(i)
        continue
      }
      if !exists(dir.path) {
        // the TTL comparison is in the u64 domain (matching upstream Epoch=u64): a pre-epoch negative epoch is bitwise the
        // maximum, so it is never lazily deleted (measured in the 0.10.0 chaos comparison)
        if dir.last_accessed.reinterpret_as_uint64() <
          opts.ttl.reinterpret_as_uint64() {
          self.swap_remove(i)
        }
        continue
      }
      push_out_or_superset(opts, out, kw_ok, dir)
    }
  } else {
    // the --all hot path: no await point. Lowering to async costs about 8us per iteration for a loop that holds an
    // await point (measured in a variant experiment on 2026-09-11: with only this branch differing, filtering 267k
    // entries took 6ms vs 2034ms), and a short-circuit boolean cannot prevent the lowering, so a pure synchronous loop must be split out
    for i in len>..0 {
      let dir = self.dirs[i]
      let kw_ok = filter_by_keywords_lower(kws, dir.path)
      if !kw_ok && opts.fuzzy_superset is None {
        continue
      }
      if !filter_base_dir(opts, dir.path) {
        continue
      }
      if !filter_exclude(globs, dir.path) {
        self.swap_remove(i)
        continue
      }
      push_out_or_superset(opts, out, kw_ok, dir)
    }
  }
  // descending output: the original implementation sorted ascending and traversed in reverse; here a reversed comparator sorts descending directly
  out.sort_by(fn(a, b) { total_cmp(b.score(opts.now), a.score(opts.now)) })
  out
}

///|
/// A keyword hit enters the result set; a miss (reachable only in fallback-collection mode) enters the superset,
/// so --fuzzy can filter in place on a zero-hit result instead of re-running the whole filter chain plus a full-database sort
fn push_out_or_superset(
  opts : StreamOptions,
  out : Array[Dir],
  kw_ok : Bool,
  dir : Dir,
) -> Unit {
  if kw_ok {
    out.push(dir)
  } else {
    opts.fuzzy_superset.unwrap().push(dir)
  }
}

///|
fn filter_base_dir(opts : StreamOptions, path : String) -> Bool {
  match opts.base_dir {
    Some(base) => starts_with(path, base)
    None => true
  }
}

///|
fn filter_exclude(globs : Array[Array[Char]], path : String) -> Bool {
  for pattern in globs {
    if glob_match_compiled(pattern, path) {
      return false
    }
  }
  true
}
