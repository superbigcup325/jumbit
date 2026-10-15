///|
/// Database access errors: IO failure, binary codec failure, plaintext line-level failure
pub enum StoreError {
  Io(String)
  Codec(@core.CodecError)
  Plaintext(@core.PlaintextError)
} derive(Debug)

///|
/// CodecError -> a user-readable reason (the single exit shared by status\'s header diagnosis and StoreError, so the
/// Debug enum name never reaches stderr)
pub fn codec_error_message(e : @core.CodecError) -> String {
  match e {
    @core.CorruptedData => "unparseable data"
    @core.UnsupportedVersion(v) => "unsupported format version: \{v}"
    @core.TooLarge => "data file too large"
  }
}

///|
/// StoreError -> a user-readable reason (without a scenario prefix; the caller prefixes "jumbit: corrupted data file: ", "jumbit: could not open
/// database: " and so on); a plaintext line-level error spans lines (one per line, decode already truncated to 8+N)
pub fn StoreError::message(self : StoreError) -> String {
  match self {
    Io(msg) => "io failure: \{msg}"
    Codec(e) => codec_error_message(e)
    Plaintext(e) => e.message()
  }
}

///|
/// Error -> a short single-line message: an OSError expands to a strerror-style phrase plus (os error N), matching
/// std io::Error\'s Display; other errors fall back to Repr (diagnostic text only, never on the normal output path).
/// The phrase comes from OSError\'s public predicates, covering the frequent errnos; the rest keep the numeric suffix
/// (errno_to_string is marked alert_internal and unusable under deny-warn)
pub fn os_error_message(err : Error) -> String {
  match err {
    @os_error.OSError(errno, ..) as ose => {
      let phrase = if ose.is_ENOENT() {
        "No such file or directory"
      } else if ose.is_EACCES() {
        "Permission denied"
      } else if ose.is_ENOTDIR() {
        "Not a directory"
      } else if ose.is_EEXIST() {
        "File exists"
      } else {
        return "(os error \{errno})"
      }
      "\{phrase} (os error \{errno})"
    }
    other => "\{Repr(other)}"
  }
}

///|
/// The access context: the database plus the data-directory location
pub(all) struct Store {
  db : @core.Database
  data_dir : String
} derive(Debug)

///|
pub fn Store::database(self : Store) -> @core.Database {
  self.db
}

///|
/// The note side file\'s path (plaintext db.txt carries no note column; human annotations live in a separate TSV;
/// format `path\tnote`; a path containing a tab is pathological and both read and write split at the first tab --
/// the misalignment is a known limitation, noted in TROUBLESHOOTING)
fn notes_path(data_dir : String) -> String {
  data_dir + "/notes.tsv"
}

///|
/// Read notes.tsv and attach the notes onto dirs by path in place (a missing file means no annotations, a normal state;
/// a line with no matching entry is ignored silently -- an orphan note after a remove or lazy delete follows loosely;
/// an empty note line is a clear marker and is skipped)
async fn attach_notes(data_dir : String, dirs : Array[@core.Dir]) -> Unit {
  let path = notes_path(data_dir)
  if !@afs.exists(path) {
    return
  }
  let data = @afs.read_file(path) catch {
    _ => return // a failed notes read does not block the main load (best-effort annotations)
  }
  let text = data.text()
  // note lines go into a Map first (a later line with the same path overwrites, matching a line-by-line scan), then a
  // single pass attaches them: O(entries + note lines), replacing a per-line whole-database scan\'s O(entries x note lines)
  let notes : Map[String, String] = Map([])
  for line in text.split("\n") {
    let line = line.to_owned()
    if line.is_empty() {
      continue
    }
    match line.find("\t") {
      Some(tab) => notes[line[0:tab].to_owned()] = line[tab + 1:].to_owned()
      None => () // a line with no tab is not a valid entry, so ignore it
    }
  }
  for d in dirs {
    match notes.get(d.path) {
      // an empty line is a clear marker, so skip the attachment
      Some(note) => if note != "" { d.note = Some(note) }
      None => () // a line with no matching entry follows loosely (an orphan note after a remove or lazy delete)
    }
  }
}

///|
/// Open the database (spec docs/spec-plaintext-edit.md §1.3):
/// 1. db.txt exists -> plaintext decode (notes attached from notes.tsv), dirty=false
/// 2. db.txt absent and a legacy db.zo present -> binary decode (not marked dirty: the migration is triggered by the first
///    real data change -- a write command dirtying it, or a query\'s lazy deletion doing so -- and the save then lands as plaintext
///    db.txt with the content preserved; a read-only path never writes, [#2])
/// 3. neither exists -> create the data directory and return an empty database (upstream\'s open semantics)
/// The single meeting point of the on-disk file and the in-memory Database.
pub async fn load(data_dir : String) -> Result[Store, StoreError] {
  let txt_path = data_dir + "/db.txt"
  let zo_path = data_dir + "/db.zo"
  if @afs.exists(txt_path) {
    let data = @afs.read_file(txt_path) catch {
      err => return Err(Io(os_error_message(err)))
    }
    match @core.decode_plaintext(data.binary()) {
      Ok(dirs) => {
        attach_notes(data_dir, dirs)
        Ok({ db: @core.Database::from_dirs(dirs), data_dir, })
      }
      Err(e) => Err(Plaintext(e))
    }
  } else if @afs.exists(zo_path) {
    let data = @afs.read_file(zo_path) catch {
      err => return Err(Io(os_error_message(err)))
    }
    match @core.decode(data.binary()) {
      Ok(dirs) =>
        // legacy state: the read path does not mark dirty (a read-only load never migrates, [#2]); the first real data change
        // (a write command, or a query's lazy deletion) dirties it, and the next save converts to plaintext with the content kept;
        // notes are read with the bincode (v2) and flow into notes.tsv at save time
        Ok({ db: @core.Database::from_dirs(dirs), data_dir, })
      Err(e) => Err(Codec(e))
    }
  } else {
    // allow_exist=true: an existing directory is not an error (mkdir -p semantics, a 0.22-line argument),
    // removing the exists-then-mkdir race; the exists-probe guard from the 0.21.2 era went with it
    @afs.mkdir(data_dir, recursive=true, allow_exist=true) catch {
      err => return Err(Io(os_error_message(err)))
    }
    Ok({ db: @core.Database::new(), data_dir, })
  }
}

///|
/// Save: write only when dirty (tmp + sync + rename, an atomic replacement), clearing dirty on success.
/// The plaintext side: db.txt (the main database) plus notes.tsv (the annotation side file, rewritten wholesale from the
/// in-memory set of annotations as the single source of truth, so orphan lines die off naturally); main database first, then the side file, with no cross-file transaction
/// (annotations are best-effort, so losing the crash window is acceptable, spec §1.2)
pub async fn Store::save(self : Store) -> Result[Unit, StoreError] {
  if !self.db.is_dirty() {
    return Ok(())
  }
  let dirs = self.db.all()
  let bytes = @core.encode_plaintext(dirs)
  write_atomic(self.data_dir + "/db.txt", bytes) catch {
    err => return Err(Io(os_error_message(err)))
  }
  // notes.tsv: every annotated entry is rewritten
  let sb = StringBuilder()
  for d in dirs {
    match d.note {
      Some(note) => {
        sb.write_string(d.path)
        sb.write_char('\t')
        sb.write_string(note)
        sb.write_char('\n')
      }
      None => ()
    }
  }
  let notes_bytes = @utf8.encode(sb.to_string())
  write_atomic(notes_path(self.data_dir), notes_bytes) catch {
    err => return Err(Io(os_error_message(err)))
  }
  self.db.mark_clean()
  Ok(())
}
