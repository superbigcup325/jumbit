///|
/// query：完整过滤链（core/stream）+ --exclude 精确路径过滤 + 输出模式选择。
/// 排序与懒删除会标脏，结束统一 save 落盘（对齐上游 query 后 save）。
async fn run_query(
  qopts : @cli.QueryOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  query_exec(qopts, getenv, errs, fn(s) { println(s) })
}

///|
/// query 执行内核：stdout 行经 emit 回调写出（CLI 直连 println；MCP 工具路
/// 收集进 content，同字节的行串）。交互路的 fzf 直写（print_stdout）不经 emit
async fn query_exec(
  qopts : @cli.QueryOptions,
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
  let globs = match cfg(@config.exclude_dirs(getenv, getenv("HOME")), errs) {
    Some(globs) => globs
    None => return 1
  }
  let resolve_symlinks = @config.resolve_symlinks(getenv)
  let now = current_second()
  // exists 回调：kind 检查；resolve_symlinks=true 时不跟随符号链接（上游反向逻辑）
  let exists = async fn(path : String) { dir_exists(path, resolve_symlinks) }
  let hits = store
    .database()
    .query_all(
      make_stream_opts(now, globs, resolve_symlinks, qopts.keywords, qopts.all),
      exists,
    )
  // --exclude 为精确路径过滤（对齐上游 query_first/list 的跳过循环）
  let mut matched_by = "exact"
  let mut remaining = apply_exclude(hits, qopts.exclude)
  if hits.is_empty() && qopts.fuzzy && !qopts.keywords.is_empty() {
    // 模糊兜底路（jumbit 扩展）：仅精确路零命中时启用；同一过滤链
    // （exclude glob 命中懒删 / exists / TTL 懒删）照常生效
    let candidates = store
      .database()
      .query_all(
        make_stream_opts(now, globs, resolve_symlinks, [], qopts.all),
        exists,
      )
    let fuzzy_hits : Array[@core.Dir] = []
    for d in candidates {
      if @core.filter_by_keywords_fuzzy(qopts.keywords, d.path) {
        fuzzy_hits.push(d)
      }
    }
    remaining = apply_exclude(fuzzy_hits, qopts.exclude)
    if !remaining.is_empty() {
      matched_by = "fuzzy"
    }
  }
  let code = if qopts.list {
    // --list 空结果静默、退出码 0（对齐上游 query_list：不进 no match 错误路）
    let shown = take_limit(remaining, qopts.limit)
    for d in shown {
      emit(render(d, now, qopts.score, " "))
    }
    0
  } else if remaining.is_empty() {
    if hits.length() > 0 {
      // 有命中但全被 --exclude 排除
      err_line(errs, "you are already in the only match")
    } else if qopts.keywords.is_empty() {
      err_line(errs, "数据库为空，没有可跳转的目录")
    } else {
      let kw = qopts.keywords.join(" ")
      err_line(errs, "无匹配: \{kw}")
    }
    1
  } else if qopts.json {
    // agent 通道：单行 JSON 数组（含全部匹配与 matched_by 证据字段）。
    // 整体物化：单行契约的无换行写与 moon test stdout 协议冲突，tsv 才流式
    emit(render_json(take_limit(remaining, qopts.limit), now, matched_by))
    0
  } else if qopts.tsv {
    // agent 通道：无表头 Tab 分隔行（--limit 0 → 不输出任何行，head -0 语义）。
    // 逐行写：字节面 = 各行 \n 连接 + 末尾换行，与原整体物化版一致
    let shown = take_limit(remaining, qopts.limit)
    for d in shown {
      emit(tsv_row(d, now, matched_by))
    }
    0
  } else if qopts.interactive {
    let outs : Array[String] = []
    let code = finish_interactive(
      @platform.fzf_select(remaining, now, @config.fzf_opts(getenv), getenv),
      qopts.score,
      errs,
      outs,
    )
    for s in outs {
      print_stdout(s)
    }
    code
  } else {
    emit(render(remaining[0], now, qopts.score, " "))
    0
  }
  finish(store, errs, code)
}

///|
/// --limit 截断：None=不截断；取排序后（remaining 已降序）的前 n 条，不重排。
/// 截断收在各输出分支内——提前统一截 remaining 会让 limit 0 撞上游空检查错误路
fn take_limit(dirs : Array[@core.Dir], limit : Int?) -> Array[@core.Dir] {
  match limit {
    None => dirs
    Some(n) => {
      let out : Array[@core.Dir] = []
      let bound = if n < dirs.length() { n } else { dirs.length() }
      for i in 0..<bound {
        out.push(dirs[i])
      }
      out
    }
  }
}

///|
/// StreamOptions 组装：精确路与模糊兜底路共用同一过滤链参数
fn make_stream_opts(
  now : Int64,
  globs : Array[String],
  resolve_symlinks : Bool,
  keywords : Array[String],
  all : Bool,
) -> @core.StreamOptions {
  {
    now,
    keywords,
    exclude: globs,
    base_dir: None,
    exists: !all,
    resolve_symlinks,
    ttl: now - 3L * @core.MONTH,
  }
}

///|
/// exists 回调：kind 检查；resolve_symlinks=true 时不跟随符号链接（上游反向逻辑）。
/// 精确路与模糊兜底路共用
async fn dir_exists(path : String, resolve_symlinks : Bool) -> Bool {
  let kind = @afs.kind(path, follow_symlink=!resolve_symlinks) catch {
    err => {
      ignore(err)
      @afs.Unknown
    }
  }
  kind == @afs.Directory
}

///|
/// --exclude 精确路径过滤（对齐上游 query_first/list 的跳过循环）
fn apply_exclude(
  dirs : Array[@core.Dir],
  exclude : String?,
) -> Array[@core.Dir] {
  match exclude {
    Some(exclude_path) => {
      let out : Array[@core.Dir] = []
      for d in dirs {
        if d.path != exclude_path {
          out.push(d)
        }
      }
      out
    }
    None => dirs
  }
}

///|
/// 输出行：--score 时前缀 6.1f 得分 + 分隔符（fzf 场景后续换 \t）
fn render(
  dir : @core.Dir,
  now : Int64,
  with_score : Bool,
  separator : String,
) -> String {
  if with_score {
    dir.format_score(now) + separator + dir.path
  } else {
    dir.path
  }
}
