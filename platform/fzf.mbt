///|
pub(all) enum FzfError {
  /// fzf unavailable (every spawn failure lands here; upstream also distinguishes "could not launch fzf",
  /// but the @process binding exposes no spawn error class, so it cannot be split out -- noted in the README)
  NotFound
  /// fzf exit code 1: the user selected nothing (cancel semantics). Upstream reports "no match found";
  /// jumbit exits 1 silently (the same behaviour under the shell hook), noted in the README
  NoMatch
  /// fzf exit code 2: an fzf-side error (upstream\'s wording "fzf returned an error")
  ReturnedAnError
  /// fzf exit code 130: a user interrupt, passed through silently (upstream\'s SilentExit)
  Interrupted
  /// fzf exit codes 128..=254, or killed by a signal (wait returns a negative value; upstream\'s wording
  /// "fzf was terminated"）
  Terminated
  /// every other exit code: 3..=127 and 255 (upstream\'s wording "fzf returned an unknown error")
  UnknownExit(Int32)
} derive(Debug, Eq)

///|
/// The fzf exit-code mapping (matching upstream FzfChild::wait, measured with a fake-fzf probe matrix against
/// zoxide 0.10.0 on 2026-09-13: 0 success / 1 no selection / 2 an fzf-side error / 130 a silent interrupt /
/// 128..=254 and a signal kill treated as terminated / 3..=127 and 255 an unknown error, all with exit 1)
fn map_fzf_exit(code : Int32) -> FzfError? {
  if code == 0 {
    None
  } else if code == 1 {
    Some(NoMatch)
  } else if code == 2 {
    Some(ReturnedAnError)
  } else if code == 130 {
    Some(Interrupted)
  } else if code < 0 || (code >= 128 && code <= 254) {
    Some(Terminated)
  } else {
    Some(UnknownExit(code))
  }
}

///|
/// Interactive fzf selection: candidates are written to stdin as "6.1f score\tpath\0", and the line fzf prints is returned.
/// A non-None fzf_opts passes through via FZF_DEFAULT_OPTS (matching upstream _ZO_FZF_OPTS).
/// `get` is the environment read entry point (used when pre-resolving a bare name on PATH)
pub async fn fzf_select(
  hits : Array[@core.Dir],
  now : Int64,
  fzf_opts : String?,
  get : (String) -> String?,
) -> Result[String, FzfError] {
  fzf_select_with("fzf", hits, now, fzf_opts, get)
}

///|
/// Pre-spawn resolution: a path with a `/` is checked directly; a bare name walks PATH for the first executable regular file.
/// This must be decided before spawning: the @process binding only turns "failed at resolution" (an absolute path that does
/// not exist / is not executable) into NotFound, while an exec failure under PATH-search semantics goes down the wait exit-code
/// path (measured in a blackbox as "fzf returned an error", reproduced 2026-09-15) and cannot be classified afterwards
async fn resolve_program(
  program : String,
  get : (String) -> String?,
) -> String? {
  if program.contains("/") {
    return if is_executable_file(program) { Some(program) } else { None }
  }
  let path_env = match get("PATH") {
    Some(p) => p
    // a missing PATH is treated as an empty table -> NotFound (found nothing to execute)
    None => return None
  }
  for dir in path_env.split(":") {
    let dir = dir.to_owned()
    // an empty entry\'s historical "current directory" meaning takes no part in resolution
    if dir == "" {
      continue
    }
    let candidate = dir + "/" + program
    if is_executable_file(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
/// The executable-regular-file test: kind must be Regular -- a directory\'s own x bit is a traversal bit,
/// and can_execute lets directories through too, so the file type must be excluded first; an error from the kind
/// lookup itself (missing / permissions) counts as not executable
async fn is_executable_file(path : String) -> Bool {
  (@afs.kind(path) catch { _ => Unknown }) is Regular &&
  (@afs.can_execute(path) catch { _ => false })
}

///|
/// The interactive-selection core for a given executable (fzf_select\'s injection point: unit tests pass an absolute path
/// to avoid same-name crosstalk from global PATH injection under parallel moon test)
async fn fzf_select_with(
  program : String,
  hits : Array[@core.Dir],
  now : Int64,
  fzf_opts : String?,
  get : (String) -> String?,
) -> Result[String, FzfError] {
  let resolved = match resolve_program(program, get) {
    Some(p) => p
    None => return Err(NotFound)
  }
  let args = [
    "--delimiter=\t", "--nth=2", "--read0", "--exact", "--no-sort", "--cycle", "--keep-right",
    "--border=sharp", "--height=45%", "--info=inline", "--layout=reverse", "--tabstop=1",
    "--exit-0",
  ]
  @async.with_task_group() <| group => {
    let (stdin_r, stdin_w) = @process.write_to_process()
    let (stdout_r, stdout_w) = @process.read_from_process()
    let extra_env : Map[String, String] = match fzf_opts {
      Some(o) => {
        let m = Map([])
        m["FZF_DEFAULT_OPTS"] = o
        m
      }
      None => Map([])
    }
    let proc = @process.spawn(
      group,
      resolved,
      args,
      stdin=stdin_r,
      stdout=stdout_w,
      extra_env~,
    ) catch {
      _ => return Err(NotFound)
    }
    group.spawn_bg() <| () => {
      defer stdin_w.close()
      for d in hits {
        let line = d.format_score(now) + "\t" + d.path + "\u{0000}"
        // a broken pipe when fzf exits early (selected or errored): matching upstream\'s write handling
        // (BrokenPipe -> wait), the feeding stops silently since fzf has already decided
        stdin_w.write(line) catch {
          _ => break
        }
      }
    }
    let out = stdout_r.read_all().text()
    match map_fzf_exit(proc.wait()) {
      Some(e) => Err(e)
      None => Ok(out)
    }
  }
}
