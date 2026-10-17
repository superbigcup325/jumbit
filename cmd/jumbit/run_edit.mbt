///|
/// The edit execution layer (a jumbit extension, spec docs/spec-plaintext-edit.md §1.4):
/// all three forms share one "load -> transform -> validate -> save" pipeline, with a single semantic authority.
/// The default form: $VISUAL/$EDITOR edits a copy of db.txt, which is parsed on read-back; no change is silent and a change
/// replaces the whole database; --rename changes a path (the note follows); --prune drops entries that no longer exist
async fn run_edit(
  eopts : @cli.EditOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(e) => {
      err_line(errs, "jumbit: could not open database: \{e.message()}")
      return 1
    }
  }
  let db = store.database()
  // the structured forms precede the interactive one (exclusivity was settled at the parse layer)
  if eopts.prune {
    return run_edit_prune(db, store, errs)
  }
  match eopts.rename_old {
    Some(old) => {
      let new = match eopts.rename_new {
        Some(n) => n
        None => return 1 // the parse layer guarantees this is unreachable
      }
      return run_edit_rename(db, store, old, new, errs)
    }
    None => ()
  }
  run_edit_interactive(data_dir, db, store, getenv, errs)
}

///|
/// --rename: exact-path matching (remove\'s dual attempt: the original string, then normalized);
/// the note migrates with it; a new path colliding with an existing entry errors rather than merging
async fn run_edit_rename(
  db : @core.Database,
  store : @platform.Store,
  old : String,
  new : String,
  errs : Array[String],
) -> Int32 {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  // the collision pre-check: new is already in the database (the same dual attempt) -> error, no merge (spec §1.4;
  // old==new counts as colliding with itself and is rejected too -- renaming to itself is meaningless and semantically vague)
  let new_norm = @core.resolve_path(new, cwd)
  if db.find_idx(new_norm) is Some(_) {
    err_line(errs, "jumbit: path already in database: \{new}")
    return 1
  }
  let renamed = try_twice(db, old, cwd, fn(db, p) { db.rename(p, new) })
  if !renamed {
    err_line(errs, "jumbit: path not found in database: \{old}")
    return 1
  }
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "jumbit: could not save database: \{e.message()}")
      1
    }
  }
}

///|
/// --prune: a full existence scan (as in status --check) that removes entries that no longer exist and prints the list
/// line by line (stdout); with nothing removed it exits 0 silently
async fn run_edit_prune(
  db : @core.Database,
  store : @platform.Store,
  errs : Array[String],
) -> Int32 {
  let removed : Array[String] = []
  for d in db.all() {
    if !(@afs.exists(d.path) catch { _ => false }) {
      removed.push(d.path)
    }
  }
  if removed.is_empty() {
    return 0
  }
  for p in removed {
    // remove\'s swap_remove semantics (as in lazy deletion); only a confirmed-existence entry reaches the list
    let _ = db.remove(p)
    println(p)
  }
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "jumbit: could not save database: \{e.message()}")
      1
    }
  }
}

///|
/// The default form: db.txt\'s current content goes to a temp file -> $VISUAL/$EDITOR edits it with an inherited terminal ->
/// read back and parse (decode_plaintext\'s full line-level validation) -> compare against the pre-edit state: no change is silent,
/// a change replaces the whole database and saves. Notes do not enter the edit surface (the notes.tsv side file); after editing they
/// are kept by path match (renaming a path loses its annotation, noted in spec §1.4)
async fn run_edit_interactive(
  data_dir : String,
  db : @core.Database,
  store : @platform.Store,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  // the edit surface holds the current main-database serialization (without the note column)
  let before = @core.encode_plaintext(db.all())
  let tmp = data_dir + "/db.txt.edit"
  let opened = @afs.create(tmp) catch {
    err => {
      err_line(
        errs,
        "jumbit: could not write temporary file: \{@platform.os_error_message(err)}",
      )
      return 1
    }
  }
  opened.write(before) catch {
    err => {
      ignore(err)
      let _ = @afs.remove(tmp)
      err_line(errs, "jumbit: could not write temporary file")
      return 1
    }
  }
  opened.sync()
  // spawn the editor (inherited terminal; a non-zero exit means the user cancelled or the editor failed, and nothing is saved)
  match @platform.run_editor(tmp, getenv) {
    Err(NotFound) => {
      err_line(errs, "jumbit: no editor: set $EDITOR or $VISUAL")
      let _ = @afs.remove(tmp)
      return 1
    }
    Err(Failed(code)) => {
      err_line(errs, "jumbit: editor exited with code \{code}")
      let _ = @afs.remove(tmp)
      return 1
    }
    Err(Spawn) => {
      err_line(errs, "could not launch editor")
      let _ = @afs.remove(tmp)
      return 1
    }
    Ok(_) => ()
  }
  // read back and validate line by line (a bad row -> nothing is saved, with the same "corrupted data file" prefix)
  let data = @afs.read_file(tmp) catch {
    err => {
      err_line(
        errs,
        "jumbit: could not read editor output: \{@platform.os_error_message(err)}",
      )
      let _ = @afs.remove(tmp)
      return 1
    }
  }
  let dirs = match @core.decode_plaintext(data.binary()) {
    Ok(dirs) => dirs
    Err(e) => {
      err_line(errs, "jumbit: corrupted data file: \{e.message()}")
      let _ = @afs.remove(tmp)
      return 1
    }
  }
  let _ = @afs.remove(tmp)
  // the no-change test: byte level (a deterministic encoding means equal content)
  if @core.encode_plaintext(dirs) == before {
    return 0
  }
  // notes are kept: a path annotated before the edit inherits its note if it still exists in the new set
  let old_notes : Array[@core.Dir] = db.all()
  for nd in dirs {
    for od in old_notes {
      if od.path == nd.path && nd.note is None {
        nd.note = od.note
      }
    }
  }
  db.replace_all(dirs)
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "jumbit: could not save database: \{e.message()}")
      1
    }
  }
}
