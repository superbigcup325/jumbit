///|
/// export --agents (a jumbit extension): annotated entries are printed in frecency-descending order as a Markdown
/// "project map" to append to AGENTS.md so a coding agent can learn the workspace.
/// No existence check (an offline view); a `|` in a path or annotation is escaped to keep the table intact
async fn run_export(
  eopts : @cli.ExportOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  export_exec(eopts, getenv, errs, fn(s) { println(s) })
}

///|
/// The export execution core: output lines go out through an emit callback (the CLI prints directly; the MCP tool path
/// collects byte-identical lines into content)
async fn export_exec(
  _eopts : @cli.ExportOptions,
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
  let noted : Array[@core.Dir] = []
  for d in store.database().all() {
    if d.note is Some(_) {
      noted.push(d)
    }
  }
  // sorted through a temporary Database, reusing core\'s sort_by_score (including its NaN total_cmp semantics);
  // sort_by_score is ascending (Stream takes descending by traversing in reverse), so this traverses in reverse to deliver the
  // declared frecency-descending order
  let ranked = @core.Database::from_dirs(noted)
  ranked.sort_by_score(current_second())
  emit("<!-- jumbit export --agents: project map, ordered by frecency -->")
  emit("| Path | Description |")
  emit("|---|---|")
  let dirs = ranked.all()
  for i in dirs.length()>..0 {
    let d = dirs[i]
    let note = match d.note {
      Some(t) => t
      None => ""
    }
    emit("| \{md_cell(d.path)} | \{md_cell(note)} |")
  }
  finish(store, errs, 0)
}

///|
/// Markdown table-cell escaping: a pipe becomes `\|` to keep the table intact (newlines are already rejected by describe)
fn md_cell(text : String) -> String {
  let out : StringBuilder = StringBuilder()
  for ch in text {
    if ch == '|' {
      out.write_string("\\|")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
