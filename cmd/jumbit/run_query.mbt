///|
/// query: the full filter chain (core/stream) plus --exclude exact-path filtering and output-mode selection.
/// Sorting and lazy deletion mark dirty, so the final unified flush saves to disk (matching upstream\'s save after a query).
async fn run_query(
  qopts : @cli.QueryOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  query_exec(qopts, getenv, errs, fn(s) { println(s) })
}

///|
/// The query execution core: stdout lines go out through an emit callback (the CLI prints directly; the MCP tool path
/// collects byte-identical lines into content). The interactive path writes fzf straight out (print_stdout), bypassing emit
async fn query_exec(
  qopts : @cli.QueryOptions,
  getenv : (String) -> String?,
  errs : Array[String],
  emit : (String) -> Unit,
) -> Int32 {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let store = match open_store(data_dir, errs) {
    Some(s) => s
    None => return 1
  }
  let globs = match cfg(@config.exclude_dirs(getenv, getenv("HOME")), errs) {
    Some(globs) => globs
    None => return 1
  }
  let resolve_symlinks = @config.resolve_symlinks(getenv)
  let now = current_second()
  // the exists callback: a kind check; with resolve_symlinks=true symlinks are not followed (upstream\'s inverse logic)
  let exists = async fn(path : String) { dir_exists(path, resolve_symlinks) }
  // --fuzzy\'s fallback finishes in one pass: with superset collection on, entries that missed the keyword but passed the
  // filter chain are kept in place, and on an exact zero-hit result the fuzzy filter runs over them directly -- replacing the old
  // "re-run query_all with an empty keyword" (no second chain scan, no full-database sort, and half the exists calls)
  let superset : Array[@core.Dir] = []
  let collect = qopts.fuzzy && !qopts.keywords.is_empty()
  let hits = store
    .database()
    .query_all(
      make_stream_opts(
        now,
        globs,
        resolve_symlinks,
        qopts.keywords,
        qopts.all,
        if collect {
          Some(superset)
        } else {
          None
        },
      ),
      exists,
    )
  // --exclude is exact-path filtering (matching the skip loop in upstream query_first/list)
  let mut matched_by = "exact"
  let mut remaining = apply_exclude(hits, qopts.exclude)
  if hits.is_empty() && collect {
    let fuzzy_hits : Array[@core.Dir] = []
    for d in superset {
      if @core.filter_by_keywords_fuzzy(qopts.keywords, d.path) {
        fuzzy_hits.push(d)
      }
    }
    // the superset follows the database traversal order (unordered): the hit set is explicitly sorted descending, reusing a temporary
    // Database\'s sort_by_score (as in export, including its NaN total_cmp semantics)
    @core.Database::from_dirs(fuzzy_hits).sort_by_score(now)
    remaining = apply_exclude(
      @core.Database::from_dirs(fuzzy_hits).all(),
      qopts.exclude,
    )
    if !remaining.is_empty() {
      matched_by = "fuzzy"
    }
  }
  let code = if qopts.list {
    // --list is silent on an empty result with exit code 0 (matching upstream query_list: it never takes the no-match error path)
    let shown = take_limit(remaining, qopts.limit)
    for d in shown {
      emit(render(d, now, qopts.score, " "))
    }
    0
  } else if remaining.is_empty() {
    if hits.length() > 0 {
      // there were hits but --exclude removed them all (the same wording as upstream query.rs)
      err_line(errs, "jumbit: you are already in the only match")
    } else {
      // both a query miss and an empty database use upstream\'s wording (the probe measured no match found for both)
      err_line(errs, "jumbit: no match found")
    }
    1
  } else if qopts.json {
    // the agent channel: a single-line JSON array (every match plus the matched_by evidence field).
    // fully materialized: the single-line contract\'s newline-free write conflicts with moon test\'s stdout protocol, so only tsv streams
    emit(render_json(take_limit(remaining, qopts.limit), now, matched_by))
    0
  } else if qopts.tsv {
    // the agent channel: headerless tab-separated lines (--limit 0 -> no lines at all, head -0 semantics).
    // written line by line: the bytes equal the lines joined with \n plus a trailing newline, matching the old materialized version
    let shown = take_limit(remaining, qopts.limit)
    for d in shown {
      emit(tsv_row(d, now, matched_by))
    }
    0
  } else if qopts.interactive {
    let outs : Array[String] = []
    let code = finish_interactive(
      @platform.fzf_select(remaining, now, @config.fzf_opts(getenv), getenv),
      qopts.score,
      errs,
      outs,
    )
    for s in outs {
      print_stdout(s)
    }
    code
  } else {
    emit(render(remaining[0], now, qopts.score, " "))
    0
  }
  finish(store, errs, code)
}

///|
/// --limit truncation: None means no truncation; it takes the first n of the sorted (already descending) remaining rows without re-sorting.
/// Truncation lives inside each output branch -- truncating remaining up front would make limit 0 hit upstream\'s empty-check error path
fn take_limit(dirs : Array[@core.Dir], limit : Int32?) -> Array[@core.Dir] {
  match limit {
    None => dirs
    Some(n) => {
      let out : Array[@core.Dir] = []
      let bound = if n < dirs.length() { n } else { dirs.length() }
      for i in 0..<bound {
        out.push(dirs[i])
      }
      out
    }
  }
}

///|
/// StreamOptions assembly: the exact and fuzzy fallback paths share one set of filter-chain parameters
fn make_stream_opts(
  now : Int64,
  globs : Array[String],
  resolve_symlinks : Bool,
  keywords : Array[String],
  all : Bool,
  fuzzy_superset : Array[@core.Dir]?,
) -> @core.StreamOptions {
  {
    now,
    keywords,
    exclude: globs,
    base_dir: None,
    exists: !all,
    resolve_symlinks,
    ttl: now - 3L * @core.MONTH,
    fuzzy_superset,
  }
}

///|
/// The exists callback: a kind check; with resolve_symlinks=true symlinks are not followed (upstream\'s inverse logic).
/// Shared by the exact and fuzzy fallback paths
async fn dir_exists(path : String, resolve_symlinks : Bool) -> Bool {
  let kind = @afs.kind(path, follow_symlink=!resolve_symlinks) catch {
    err => {
      ignore(err)
      @afs.Unknown
    }
  }
  kind == @afs.Directory
}

///|
/// --exclude exact-path filtering (matching the skip loop in upstream query_first/list)
fn apply_exclude(
  dirs : Array[@core.Dir],
  exclude : String?,
) -> Array[@core.Dir] {
  match exclude {
    Some(exclude_path) => {
      let out : Array[@core.Dir] = []
      for d in dirs {
        if d.path != exclude_path {
          out.push(d)
        }
      }
      out
    }
    None => dirs
  }
}

///|
/// An output line: with --score it is prefixed by a 6.1f score plus a separator (which becomes \t for the fzf case)
fn render(
  dir : @core.Dir,
  now : Int64,
  with_score : Bool,
  separator : String,
) -> String {
  if with_score {
    dir.format_score(now) + separator + dir.path
  } else {
    dir.path
  }
}
