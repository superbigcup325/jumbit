///|
/// A millisecond timestamp -> a second-level Epoch (upstream Epoch is seconds; @async.now() proved to be milliseconds)
fn current_second() -> Int64 {
  @async.now() / 1000L
}

///|
/// stderr message collection: nothing writes to the fd directly; main flushes it all at the end.
/// (writing to stderr inside a moon test process panics, and the collecting design also lets tests assert on the wording)
fn err_line(errs : Array[String], msg : String) -> Unit {
  errs.push(msg)
}

///|
/// stdout output with no newline (matching upstream print! semantics); a failed write is swallowed
/// (matching how main handles a failed stderr write)
async fn print_stdout(s : String) -> Unit {
  @stdio.stdout.write(s) catch {
    _ => ()
  }
}

///|
/// Map query --interactive\'s fzf result to an exit code and wording (pure logic, tested directly by the wbtest;
/// the process surface is covered by platform\'s fake-fzf E2E and dataset_check\'s D9 comparison).
/// stdout fragments are collected into outs and flushed by the caller (collected like errs: writing to stdout inside
/// a moon test process would crosstalk with the test driver\'s event protocol).
/// The output matches upstream print!: no newline is appended (fzf\'s own output carries one); with --score the whole
/// line is printed, otherwise the 7-character score prefix is stripped (matching upstream selection.get(7..); len==7 ->
/// an empty string is printed as is); len<7 takes upstream\'s error path (probed 2026-09-13: exit 1 with
/// "could not read selection from fzf"). The exit-code table: 0 success / 1 no selection
/// (upstream reports "no match found", jumbit is silent -- cancel semantics, noted in the README) /
/// 2, 128..=254, a signal kill, and 3..=127/255 all exit 1 with the matching wording /
/// 130 passes 130 through silently
fn finish_interactive(
  selection : Result[String, @platform.FzfError],
  score : Bool,
  errs : Array[String],
  outs : Array[String],
) -> Int32 {
  match selection {
    Ok(s) => {
      if score {
        outs.push(s)
      } else if s.length() >= 7 {
        outs.push(s[7:].to_owned())
      } else {
        err_line(errs, "jumbit: could not read selection from fzf")
        return 1
      }
      0
    }
    Err(@platform.NotFound) => {
      err_line(errs, "jumbit: could not find fzf, is it installed?")
      1
    }
    Err(@platform.NoMatch) => 1
    Err(@platform.ReturnedAnError) => {
      err_line(errs, "fzf returned an error")
      1
    }
    Err(@platform.Interrupted) => 130
    Err(@platform.Terminated) => {
      err_line(errs, "fzf was terminated")
      1
    }
    Err(@platform.UnknownExit(_)) => {
      err_line(errs, "fzf returned an unknown error")
      1
    }
  }
}

///|
/// The single exit for the config-parsing step: on Err the wording goes into errs and None is returned, which the caller
/// turns into an early `match { None => return 1 }`. Each subcommand keeps its own parsing order
/// (matching upstream: add reads the config before opening the database; query/import open it first)
/// Each subcommand keeps its own parsing order (matching upstream: add reads the config before opening the database; query/import open it first)
fn[T] cfg(r : Result[T, String], errs : Array[String]) -> T? {
  match r {
    Ok(v) => Some(v)
    Err(msg) => {
      err_line(errs, msg)
      None
    }
  }
}

///|
/// Open the database: a failed open gets its own wording, separate from config errors (including the Repr debug format)
async fn open_store(
  data_dir : String,
  errs : Array[String],
) -> @platform.Store? {
  match @platform.load(data_dir) {
    Ok(s) => Some(s)
    Err(err) => {
      err_line(errs, "jumbit: could not open database: \{err.message()}")
      None
    }
  }
}

///|
/// The unified flush at the end: a failed save overrides the exit code to 1, otherwise the original code passes through
async fn finish(
  store : @platform.Store,
  errs : Array[String],
  code : Int32,
) -> Int32 {
  match store.save() {
    Ok(_) => code
    Err(err) => {
      err_line(errs, "jumbit: could not save database: \{err.message()}")
      1
    }
  }
}

///|
/// The execution entry point for every subcommand.
/// Returns the process exit code: 0 success / 1 runtime failure (config errors included, matching upstream ExitCode::FAILURE)
/// / 2 a usage error (matching clap\'s argument-parsing error). stderr messages go into errs.
pub async fn run(
  args : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int32 {
  match @cli.parse(args) {
    @cli.Help => {
      println(@cli.usage())
      0
    }
    @cli.Version => {
      println(@cli.version())
      0
    }
    @cli.Usage => {
      // the full help goes to stderr with exit code 2 (matching upstream clap with no subcommand)
      err_line(errs, @cli.usage())
      2
    }
    @cli.Unknown(cmd) => {
      // the clap idiom (upstream probe: error: unrecognized subcommand 'x' plus a try line)
      err_line(errs, "error: unrecognized subcommand '\{cmd}'")
      err_line(errs, "For more information, try 'jumbit help'.")
      2
    }
    @cli.Add(aopts) => run_add(aopts, getenv, errs)
    @cli.Invalid(msg) => {
      err_line(errs, "error: \{msg}")
      err_line(errs, "For more information, try 'jumbit help'.")
      2
    }
    @cli.Query(qopts) => run_query(qopts, getenv, errs)
    @cli.Remove(paths) => run_remove(paths, getenv, errs)
    @cli.Init(iopts) => run_init(iopts, getenv, errs)
    @cli.Import(iopts) => run_import(iopts, getenv, errs)
    @cli.Describe(dopts) => run_describe(dopts, getenv, errs)
    @cli.Export(eopts) => run_export(eopts, getenv, errs)
    @cli.Status(sopts) => run_status(sopts, getenv, errs)
    @cli.Edit(eopts) => run_edit(eopts, getenv, errs)
    @cli.Mcp => run_mcp(getenv)
  }
}

///|
/// The _JB_ECHO debug switch: only the value "1" takes effect (matching upstream config::echo)
fn echo_enabled(getenv : (String) -> String?) -> Bool {
  match getenv("_JB_ECHO") {
    Some("1") => true
    _ => false
  }
}

///|
/// The _JB_EXCLUDE_DIRS glob hit test (shared by add and import; a hit skips silently)
fn glob_hit(globs : Array[String], path : String) -> Bool {
  for pattern in globs {
    if @core.glob_match(pattern, path) {
      return true
    }
  }
  false
}

///|
/// The dual attempt (matching the dual lookup in upstream remove.rs): the original string first, then a retry normalized against the cwd
fn try_twice(
  db : @core.Database,
  path : String,
  cwd : String,
  op : (@core.Database, String) -> Bool,
) -> Bool {
  if op(db, path) {
    return true
  }
  op(db, @core.resolve_path(path, cwd))
}

///|
/// The dual lookup\'s find version (describe\'s view path needs the index, not a boolean)
fn find_twice(db : @core.Database, path : String, cwd : String) -> Int32? {
  match db.find_idx(path) {
    Some(i) => Some(i)
    None => db.find_idx(@core.resolve_path(path, cwd))
  }
}
