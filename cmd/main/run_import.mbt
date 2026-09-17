///|
/// import（对齐上游 cmd/import.rs + import/run）：
/// 空库直灌 / --merge 合并进非空库；坏行按 `<来源>:<行号>: <原因>` 上报不中止；

///|
/// 坏行定位前缀（`<来源>:<行号>`；atuin 无文件来源时为 `line N`）。
/// 只对坏行调用——成功行不构造定位串
fn make_location(source : String?, line_num : Int) -> String {
  match source {
    Some(path) => "\{path}:\{line_num}"
    None => "line \{line_num}"
  }
}

///|
/// 结束后 dedup + age(maxage) 再落盘。atuin 走子进程，其余插件读数据文件。
async fn run_import(
  iopts : @cli.ImportOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }

  let store = match open_store(data_dir, errs) {
    Some(s) => s
    None => return 1
  }
  if !iopts.merge && !store.database().is_empty() {
    err_line(
      errs, "current database is not empty, specify --merge to continue anyway",
    )
    return 1
  }

  let globs = match cfg(@config.exclude_dirs(getenv, getenv("HOME")), errs) {
    Some(globs) => globs
    None => return 1
  }
  // 单趟流式处理（对齐上游 import.rs::run 的惰性迭代结构）：逐行
  // 「Err 行/解析失败 → <定位>: <原因> 上报不中止；Ok → exclude 命中静默跳过、
  // 直接入库」。atuin 折叠语义需要完整记录序列（六插件唯一带状态者），保持物化
  let parse : (String) -> Result[@core.Dir, String] = match iopts.plugin {
    "autojump" => @core.parse_autojump_line
    "atuin" => @core.parse_atuin_line
    // z / zsh-z / fasd / z.lua 与 z 同格式，共用解析（对齐上游复用 z::Iter）
    _ => @core.parse_z_line
  }
  // 单行处理内核：空行静默跳过（上游迭代器 continue）；
  // location 串只对坏行构造（成功行下游不读它；百万行级每行拼串是可测开销）
  let process_line = fn(
    source : String?,
    line_num : Int,
    line : Result[String, String],
  ) -> Unit {
    match line {
      Err(reason) =>
        err_line(errs, "\{make_location(source, line_num)}: \{reason}")
      Ok(l) =>
        if l != "" {
          match parse(l) {
            Ok(dir) =>
              // _JB_EXCLUDE_DIRS 命中 → 静默跳过（对齐上游 exclude_dirs 过滤）
              if !glob_hit(globs, dir.path) {
                store
                .database()
                .add_unchecked(dir.path, dir.rank, dir.last_accessed)
              }
            Err(reason) =>
              err_line(errs, "\{make_location(source, line_num)}: \{reason}")
          }
        }
    }
  }
  if iopts.plugin == "atuin" {
    let (records, _) = match @platform.atuin_history_records() {
      Ok((records, stderr_text)) => {
        forward_atuin_stderr(errs, stderr_text)
        let source : String? = None
        (records, source)
      }
      Err(msg) => {
        err_line(errs, msg)
        return 1
      }
    }
    let parsed : Array[@core.LocatedDir] = []
    for record in records {
      match record.result {
        Err(reason) =>
          parsed.push({
            location: make_location(None, record.line_num),
            result: Err(reason),
          })
        Ok(line) =>
          if line != "" {
            match parse(line) {
              Ok(dir) => parsed.push({ location: "", result: Ok(dir), })
              Err(reason) =>
                parsed.push({
                  location: make_location(None, record.line_num),
                  result: Err(reason),
                })
            }
          }
      }
    }
    for entry in @core.collapse_consecutive(parsed) {
      match entry.result {
        Err(reason) => err_line(errs, "\{entry.location}: \{reason}")
        Ok(dir) =>
          if !glob_hit(globs, dir.path) {
            store
            .database()
            .add_unchecked(dir.path, dir.rank, dir.last_accessed)
          }
      }
    }
  } else {
    // 文件源：逐行回调，行串即抛不物化记录数组；z.lua 主路径缺失回落
    // fish 变体、双双缺失报主路径（对齐上游 z_lua.rs）
    let stream_file = async fn(
      path_res : Result[String, String],
    ) -> Result[Unit, String] {
      match path_res {
        Ok(path) =>
          @platform.for_each_import_line(path, fn(line_num, line) {
            process_line(Some(path), line_num, line)
          })
        Err(msg) => Err(msg)
      }
    }
    let done = match iopts.plugin {
      "z" => stream_file(@config.z_data_path(getenv))
      "fasd" => stream_file(@config.fasd_data_path(getenv))
      "zsh-z" => stream_file(@config.zsh_z_data_path(getenv))
      "autojump" => stream_file(@config.autojump_data_path(getenv))
      "z.lua" =>
        match stream_file(@config.zlua_data_path(getenv)) {
          Ok(_) => Ok(())
          Err(_) =>
            match @config.zlua_fish_path(getenv) {
              Ok(fish_path) =>
                if @afs.exists(fish_path) {
                  stream_file(Ok(fish_path))
                } else {
                  stream_file(@config.zlua_data_path(getenv))
                }
              Err(msg) => Err(msg)
            }
        }
      other => Err("import: 不支持的插件: \{other}")
    }
    match done {
      Ok(_) => ()
      Err(msg) => {
        err_line(errs, msg)
        return 1
      }
    }
  }

  if store.database().is_dirty() {
    store.database().dedup()
    let maxage = match cfg(@config.maxage(getenv), errs) {
      Some(maxage) => maxage
      None => return 1
    }
    store.database().age(maxage)
  }

  finish(store, errs, 0)
}

///|
/// atuin stderr 透传（对齐上游继承 stderr 的字节原样）：err_line 会补尾换行，
/// 原文自带的尾换行须先剥掉，否则多出一个空行（v18 真机回放实测的真分歧）
fn forward_atuin_stderr(errs : Array[String], text : String) -> Unit {
  if text == "" {
    return
  }
  let t = if text.has_suffix("\n") {
    text[0:text.length() - 1].to_owned()
  } else {
    text
  }
  err_line(errs, t)
}
