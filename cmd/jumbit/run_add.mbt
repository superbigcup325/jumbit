///|
/// add (matching upstream add.rs):
/// - _JB_RESOLVE_SYMLINKS chooses realpath (canonicalize) or resolve_path
/// - a path containing a newline, or a _JB_EXCLUDE_DIRS glob hit -> skipped silently; not a directory -> errors out immediately
/// - after every add_update(score), if dirty then age(_JB_MAXAGE) runs before the save
async fn run_add(
  aopts : @cli.AddOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let globs = match cfg(@config.exclude_dirs(getenv, getenv("HOME")), errs) {
    Some(globs) => globs
    None => return 1
  }
  let maxage = match cfg(@config.maxage(getenv), errs) {
    Some(maxage) => maxage
    None => return 1
  }
  let resolve_symlinks = @config.resolve_symlinks(getenv)
  let store = match open_store(data_dir, errs) {
    Some(s) => s
    None => return 1
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  let now = current_second()
  for path in aopts.paths {
    let resolved = @core.resolve_path(path, cwd)
    let resolved = if resolve_symlinks {
      @afs.realpath(resolved) catch {
        err => {
          // os_error_message already carries a (os error N) suffix, so a colon joins them to avoid nested parentheses
          err_line(
            errs,
            "jumbit: could not resolve path \{resolved}: \{@platform.os_error_message(err)}",
          )
          return 1
        }
      }
    } else {
      resolved
    }
    // a newline or carriage return cannot be printed cleanly on one line, so it is skipped silently (matching upstream EXCLUDE_CHARS)
    if resolved.find("\n") is Some(_) || resolved.find("\r") is Some(_) {
      continue
    }
    // a _JB_EXCLUDE_DIRS hit -> skipped silently
    if glob_hit(globs, resolved) {
      continue
    }
    let kind = @afs.kind(resolved) catch {
      err => {
        ignore(err)
        @afs.Unknown
      }
    }
    if kind != @afs.Directory {
      err_line(errs, "jumbit: not a directory: \{resolved}")
      return 1
    }
    store.database().add_update(resolved, aopts.score, now)
    if echo_enabled(getenv) {
      println(resolved)
    }
  }
  if store.database().is_dirty() {
    store.database().age(maxage)
  }
  finish(store, errs, 0)
}

///|
/// remove (matching upstream remove.rs): delete by the original string first, then by the normalized path, and error if neither matches
async fn run_remove(
  paths : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let store = match open_store(data_dir, errs) {
    Some(s) => s
    None => return 1
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  for path in paths {
    let removed = try_twice(store.database(), path, cwd, fn(db, p) {
      db.remove(p)
    })
    if !removed {
      err_line(errs, "jumbit: path not found in database: \{path}")
      return 1
    }
  }
  finish(store, errs, 0)
}
