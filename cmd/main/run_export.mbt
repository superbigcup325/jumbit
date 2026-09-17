///|
/// export --agents（jumbit 扩展）：有标注条目按 frecency 降序输出 Markdown
/// 「项目地图」，可直接追加进 AGENTS.md 供 coding agent 认识工作区。
/// 不做存在性检查（离线视图）；路径/标注中的 `|` 转义保表格完整
async fn run_export(
  eopts : @cli.ExportOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  export_exec(eopts, getenv, errs, fn(s) { println(s) })
}

///|
/// export 执行内核：输出行经 emit 回调写出（CLI 直连 println；MCP 工具路
/// 收集进 content，同字节的行串）
async fn export_exec(
  _eopts : @cli.ExportOptions,
  getenv : (String) -> String?,
  errs : Array[String],
  emit : (String) -> Unit,
) -> Int {
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
  // 经临时 Database 排序：复用 core 的 sort_by_score（含 NaN total_cmp 语义）；
  // sort_by_score 为升序（Stream 靠倒序遍历取降序），此处倒序遍历实现声明的
  // frecency 降序
  let ranked = @core.Database::from_dirs(noted)
  ranked.sort_by_score(current_second())
  emit(
    "<!-- jumbit export --agents：项目地图，按常用度（frecency）降序 -->",
  )
  emit("| 路径 | 说明 |")
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
/// Markdown 表格单元格转义：竖线转 `\|` 防破表（换行已在 describe 拒绝）
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
