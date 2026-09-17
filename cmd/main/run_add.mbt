///|
/// add（对齐上游 add.rs）：
/// - 按 _JB_RESOLVE_SYMLINKS 选择 realpath（canonicalize）或 resolve_path
/// - 换行路径 / _JB_EXCLUDE_DIRS glob 命中 → 静默跳过；非目录 → 立即报错中止
/// - 全部 add_update(score) 后，若 dirty 则 age(_JB_MAXAGE) 再 save
async fn run_add(
  aopts : @cli.AddOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  if aopts.paths.is_empty() {
    err_line(errs, "add: 缺少路径参数")
    return 2
  }
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
          // os_error_message 自带 (os error N) 后缀，用冒号拼接避免括号嵌套
          err_line(
            errs,
            "解析路径失败: \{resolved}: \{@platform.os_error_message(err)}",
          )
          return 1
        }
      }
    } else {
      resolved
    }
    // 换行/回车无法整洁地打印在单行，静默跳过（对齐上游 EXCLUDE_CHARS）
    if resolved.find("\n") is Some(_) || resolved.find("\r") is Some(_) {
      continue
    }
    // _JB_EXCLUDE_DIRS 命中 → 静默跳过
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
      err_line(errs, "not a directory: \{resolved}")
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
/// remove（对齐上游 remove.rs）：先按原始串删，未中再按规范化路径删，仍未中报错
async fn run_remove(
  paths : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  if paths.is_empty() {
    err_line(errs, "remove: 缺少路径参数")
    return 2
  }
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
      err_line(errs, "path not found in database: \{path}")
      return 1
    }
  }
  finish(store, errs, 0)
}
