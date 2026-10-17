///|
/// import (matching upstream cmd/import.rs + import/run):
/// a direct pour into an empty database / --merge into a non-empty one; bad rows are reported as `<source>:<line>: <reason>` without aborting;

///|
/// the bad-row location prefix (`<source>:<line>`; `line N` when there is no file source, as with atuin).
/// Called only for bad rows -- a successful row never builds a location string
fn make_location(source : String?, line_num : Int32) -> String {
  match source {
    Some(path) => "\{path}:\{line_num}"
    None => "line \{line_num}"
  }
}

///|
/// When it finishes, dedup + age(maxage) run before the save. atuin goes through a subprocess; the other plugins read data files.
async fn run_import(
  iopts : @cli.ImportOptions,
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
  if !iopts.merge && !store.database().is_empty() {
    err_line(
      errs, "jumbit: current database is not empty, specify --merge to continue anyway",
    )
    return 1
  }

  let globs = match cfg(@config.exclude_dirs(getenv, getenv("HOME")), errs) {
    Some(globs) => globs
    None => return 1
  }
  // A single streaming pass (matching the lazy iterator structure of upstream import.rs::run): line by line,
  // "an Err row or a parse failure -> report <location>: <reason> without aborting; Ok -> skip silently on an exclude
  // hit, otherwise import". atuin\'s folding needs the whole record sequence (it is the only one of the six with state), so it stays materialized
  let parse : (String) -> Result[@core.Dir, String] = match iopts.plugin {
    "autojump" => @core.parse_autojump_line
    "atuin" => @core.parse_atuin_line
    // z / zsh-z / fasd / z.lua share z\'s format and its parser (matching upstream\'s reuse of z::Iter)
    _ => @core.parse_z_line
  }
  // The single-line processing core: a blank line is skipped silently (upstream\'s iterator continues);
  // the location string is built only for bad rows (nothing downstream reads it for a success; concatenating one per line at a million lines is measurable)
  let process_line = fn(
    source : String?,
    line_num : Int32,
    line : Result[String, String],
  ) -> Unit {
    match line {
      Err(reason) =>
        err_line(errs, "\{make_location(source, line_num)}: \{reason}")
      Ok(l) =>
        if l != "" {
          match parse(l) {
            Ok(dir) =>
              // a _JB_EXCLUDE_DIRS hit -> skipped silently (matching upstream\'s exclude_dirs filter)
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
    // a file source: a per-line callback that drops each line string without materializing a record array; z.lua falls back to the
    // fish variant when the main path is missing, and reports the main path when both are (matching upstream z_lua.rs)
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
      other => Err("invalid value '\{other}' for '<PLUGIN>'")
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
/// atuin stderr passthrough (matching upstream\'s byte-verbatim stderr inheritance): err_line appends a newline, so the
/// source\'s own trailing newline must be stripped first, otherwise a blank line appears (a real divergence the v18 replay measured)
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
