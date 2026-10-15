///|
/// The editor resolution order (a UNIX convention; upstream has no such thing -- current zoxide edit is fzf-driven rank
/// adjustment with no EDITOR/VISUAL resolution, so this shape is jumbit\'s own semantic surface, spec §1.4):
/// $VISUAL -> $EDITOR -> "vi"; all empty -> None (the caller reports no editor)
async fn resolve_editor(get : (String) -> String?) -> String? {
  match get("VISUAL") {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  match get("EDITOR") {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  // the vi fallback still needs an existence check (decided before spawning, the same discipline as fzf)
  resolve_program("vi", get)
}

///|
/// Editor errors (jumbit\'s own semantic surface, worded in the style of the existing stderr phrases)
pub enum EditorError {
  /// $VISUAL/$EDITOR unset and no vi on PATH
  NotFound
  /// the editor exited non-zero (the user cancelled, or the editor itself failed)
  Failed(Int32)
  /// a spawn failure (resolution succeeded but exec failed, and so on; the @process binding exposes no error class)
  Spawn
} derive(Debug)

///|
/// Interactive editing: spawn the editor on the given file with inherited terminal stdio (wait for exit, collecting no
/// output). Resolution (resolve_editor) is separated from execution, so the wbtest injects a fake editor\'s absolute
/// path to test the execution surface directly, while resolution is unit-tested.
///
/// A $VISUAL/$EDITOR containing spaces is treated as a shell command line (sh -c '<value> "$@"' <value>
/// <file>, the same idiom git uses for EDITOR: the value may carry arguments such as "code -w"); without spaces it is
/// resolved on PATH as a single program name and spawned directly. Argument escaping is the user\'s responsibility (noted in TROUBLESHOOTING)
pub async fn run_editor(
  file : String,
  get : (String) -> String?,
) -> Result[Unit, EditorError] {
  let editor = match resolve_editor(get) {
    Some(e) => e
    None => return Err(NotFound)
  }
  let code = if editor.contains(" ") {
    @process.run("sh", ["-c", "\{editor} \"$@\"", editor, file]) catch {
      _ => return Err(Spawn)
    }
  } else {
    @process.run(editor, [file]) catch {
      _ => return Err(Spawn)
    }
  }
  if code != 0 {
    return Err(Failed(code))
  }
  Ok(())
}
