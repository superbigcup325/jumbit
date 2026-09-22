///|
/// editor 解析序（UNIX 惯例；上游无此物——现行 zoxide edit 为 fzf 交互调
/// rank，无 EDITOR/VISUAL 解析，本形态为 jumbit 自有语义面，规格 §1.4）：
/// $VISUAL → $EDITOR → "vi"；全空 → None（调用方报 no editor）
async fn resolve_editor(get : (String) -> String?) -> String? {
  match get("VISUAL") {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  match get("EDITOR") {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  // vi 兜底仍须存在性解析（spawn 前裁定，与 fzf 同款纪律）
  resolve_program("vi", get)
}

///|
/// editor 错误（jumbit 自有语义面，文案风格对齐既有 stderr 短语）
pub enum EditorError {
  /// $VISUAL/$EDITOR 未设且 PATH 无 vi
  NotFound
  /// editor 退出码非 0（用户取消编辑/编辑器自身故障）
  Failed(Int)
  /// spawn 失败（解析通过但 exec 失败等；@process 绑定不暴露错误类别）
  Spawn
} derive(Debug)

///|
/// 交互式编辑：以继承终端的 stdio 起编辑器编辑指定文件（等退出，不收集
/// 输出）。解析（resolve_editor）与执行分离——wbtest 注入假 editor 绝对
/// 路径直测执行面，解析面单测。
///
/// $VISUAL/$EDITOR 含空格时按 shell 命令行处理（sh -c '<值> "$@"' <值>
/// <file>，git EDITOR 惯用法同款：值可带参数如 "code -w"）；不含空格按
/// 单程序名 PATH 解析 + 直 spawn。参数转义由用户自负（TROUBLESHOOTING 注记）
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
