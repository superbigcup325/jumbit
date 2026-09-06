///|
/// 毫秒时间戳 → 秒级 Epoch（上游 Epoch 为秒；@async.now() 实测毫秒）
fn current_second() -> Int64 {
  @async.now() / 1000L
}

///|
/// stderr 消息收集：不直接写 fd，由 main 统一落盘。
/// （moon test 进程里写 stderr 会 panic，收集式设计同时让错误文案可被测试断言）
fn err_line(errs : Array[String], msg : String) -> Unit {
  errs.push(msg)
}

///|
/// 全部子命令的执行入口。
/// 返回进程退出码（0 成功 / 1 运行失败 / 2 用法错误）；stderr 消息写入 errs。
pub async fn run(
  args : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  match @cli.parse(args) {
    @cli.Help => {
      println(@cli.usage())
      0
    }
    @cli.Unknown(cmd) => {
      err_line(errs, "未知命令: \{cmd}")
      err_line(errs, "运行 jumbit help 查看用法")
      2
    }
    @cli.Add(paths) => run_add(paths, getenv, errs)
    @cli.Query(qopts) => run_query(qopts, getenv, errs)
  }
}

///|
/// _JB_ECHO 调试回显开关：仅值 "1" 生效（对齐上游 config::echo）
fn echo_enabled(getenv : (String) -> String?) -> Bool {
  match getenv("_JB_ECHO") {
    Some("1") => true
    _ => false
  }
}

///|
/// add：路径规范化 → 换行/目录校验 → add_update → save（_JB_MAXAGE 老化在后续版本接入）
async fn run_add(
  paths : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  if paths.is_empty() {
    err_line(errs, "add: 缺少路径参数")
    return 2
  }
  let data_dir = match @config.data_dir(getenv) {
    Ok(d) => d
    Err(msg) => {
      err_line(errs, msg)
      return 2
    }
  }
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(err) => {
      err_line(errs, "打开数据库失败: \{Repr(err)}")
      return 1
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  let now = current_second()
  let echo = echo_enabled(getenv)
  let mut failed = false
  for path in paths {
    if path.find("\n") is Some(_) || path.find("\r") is Some(_) {
      err_line(errs, "路径包含换行，已跳过: \{path}")
      failed = true
      continue
    }
    let resolved = @core.resolve_path(path, cwd)
    let kind = @afs.kind(resolved) catch {
      err => {
        ignore(err)
        @afs.Unknown
      }
    }
    if kind != @afs.Directory {
      err_line(errs, "不是目录: \{resolved}")
      failed = true
      continue
    }
    store.database().add_update(resolved, 1.0, now)
    if echo {
      println(resolved)
    }
  }
  match store.save() {
    Ok(_) => if failed { 1 } else { 0 }
    Err(err) => {
      err_line(errs, "保存数据库失败: \{Repr(err)}")
      1
    }
  }
}

///|
/// query：完整过滤链（core/stream）+ --exclude 精确路径过滤 + 三种输出模式。
/// 排序与懒删除会标脏，结束统一 save 落盘（对齐上游 query 后 save）。
async fn run_query(
  qopts : @cli.QueryOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match @config.data_dir(getenv) {
    Ok(d) => d
    Err(msg) => {
      err_line(errs, msg)
      return 2
    }
  }
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(err) => {
      err_line(errs, "打开数据库失败: \{Repr(err)}")
      return 1
    }
  }
  let globs = match @config.exclude_dirs(getenv, getenv("HOME")) {
    Ok(g) => g
    Err(msg) => {
      err_line(errs, msg)
      return 2
    }
  }
  let resolve_symlinks = @config.resolve_symlinks(getenv)
  let now = current_second()
  let stream_opts : @core.StreamOptions = {
    now,
    keywords: qopts.keywords,
    exclude: globs,
    base_dir: None,
    exists: !qopts.all,
    resolve_symlinks,
    ttl: now - 3L * @core.MONTH,
  }
  // exists 回调：kind 检查；resolve_symlinks=true 时不跟随符号链接（上游反向逻辑）
  let hits = store
    .database()
    .query_all(stream_opts, async fn(path) {
      let kind = @afs.kind(path, follow_symlink=!resolve_symlinks) catch {
        err => {
          ignore(err)
          @afs.Unknown
        }
      }
      kind == @afs.Directory
    })
  // --exclude 为精确路径过滤（对齐上游 query_first/list 的跳过循环）
  let remaining = match qopts.exclude {
    Some(exclude_path) => {
      let out : Array[@core.Dir] = []
      for d in hits {
        if d.path != exclude_path {
          out.push(d)
        }
      }
      out
    }
    None => hits
  }
  let code = if remaining.is_empty() {
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
  } else if qopts.list {
    for d in remaining {
      println(render(d, now, qopts.score, " "))
    }
    0
  } else {
    println(render(remaining[0], now, qopts.score, " "))
    0
  }
  match store.save() {
    Ok(_) => code
    Err(err) => {
      err_line(errs, "保存数据库失败: \{Repr(err)}")
      1
    }
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
