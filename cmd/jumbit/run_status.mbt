///|
/// status\'s database report (a jumbit extension with no upstream equivalent): computation is separated from rendering (the wbtest can assert the bytes directly).
/// existing is Some only under --check (an O(N) per-path existence scan; the default quick check does not run it);
/// a missing data file counts as an empty database (file_size 0 / entries 0 / format None).
/// format = the identity of the format actually loaded (spec docs/spec-plaintext-edit.md §3.4):
/// "plaintext" (db.txt, the main format) / "binary" (legacy db.zo, read-only with no migration) / None (no database) --
/// the binary\'s internal version number never leaks (the diagnostic value lives on the "corrupted data file" path)
struct DbStatus {
  data_file : String
  file_size : Int32
  format : String?
  entries : Int32
  notes : Int32
  /// the current _JB_MAXAGE (config parses it into a Double)
  maxage : Double
  existing : Int32?
} derive(Debug)

///|
fn render_status_human(r : DbStatus) -> Array[String] {
  let fmt = match r.format {
    Some(v) => v
    None => "-"
  }
  let lines = [
    "data file      \{r.data_file}",
    "file size      \{r.file_size} bytes",
    "format         \{fmt}",
    "entries        \{r.entries}",
    "notes          \{r.notes}",
    "aging threshold \{r.maxage}",
  ]
  match r.existing {
    Some(k) => lines.push("existing        \{k}/\{r.entries}")
    None => ()
  }
  lines
}

///|
/// A single-line JSON object (fixed key order, the same --json discipline as query --json); existing appears only under --check.
/// The format_version key became format in 0.1.2, with the value a format-identifying string (breaking,
/// noted in the CHANGELOG)
fn render_status_json(r : DbStatus) -> String {
  let fmt = match r.format {
    Some(v) => "\"\{v}\""
    None => "null"
  }
  let existing = match r.existing {
    Some(k) => ",\"existing\":\{k}"
    None => ""
  }
  "{\"data_file\":\"\{json_escape(r.data_file)}\",\"file_size\":\{r.file_size},\"format\":\{fmt},\"entries\":\{r.entries},\"notes\":\{r.notes},\"maxage\":\{r.maxage}\{existing}}"
}

///|
/// Load the database and summarize entries and annotations (all through platform.load\'s single load path; a legacy db.zo
/// is marked dirty, but status is read-only and never saves, so no migration fires). None means the load failed
/// (already reported on stderr)
async fn load_status_dirs(
  data_dir : String,
  errs : Array[String],
) -> Array[@core.Dir]? {
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(Io(msg)) => {
      err_line(errs, "jumbit: could not read data file: \{msg}")
      return None
    }
    Err(e) => {
      err_line(errs, "jumbit: corrupted data file: \{e.message()}")
      return None
    }
  }
  Some(store.database().all())
}

///|
async fn run_status(
  sopts : @cli.StatusOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let maxage = match cfg(@config.maxage(getenv), errs) {
    Some(maxage) => maxage
    None => return 1
  }
  let dirs = match load_status_dirs(data_dir, errs) {
    Some(dirs) => dirs
    None => return 1
  }
  // the data-file facts: db.txt (the main format) first, then the legacy db.zo; neither -> the main path with zero values
  let txt_path = data_dir + "/db.txt"
  let zo_path = data_dir + "/db.zo"
  let (data_file, format) = if @afs.exists(txt_path) {
    (txt_path, Some("plaintext"))
  } else if @afs.exists(zo_path) {
    (zo_path, Some("binary"))
  } else {
    (txt_path, None)
  }
  let file_size = if @afs.exists(data_file) {
    let data = @afs.read_file(data_file) catch {
      err => {
        err_line(
          errs,
          "jumbit: could not read data file: \{@platform.os_error_message(err)}",
        )
        return 1
      }
    }
    data.binary().length()
  } else {
    0
  }
  let mut notes = 0
  for d in dirs {
    if d.note is Some(_) {
      notes += 1
    }
  }
  let existing = if sopts.check {
    let mut k = 0
    for d in dirs {
      if @afs.exists(d.path) {
        k += 1
      }
    }
    Some(k)
  } else {
    None
  }
  let report : DbStatus = {
    data_file,
    file_size,
    format,
    entries: dirs.length(),
    notes,
    maxage,
    existing,
  }
  if sopts.json {
    println(render_status_json(report))
  } else {
    for line in render_status_human(report) {
      println(line)
    }
  }
  0
}
