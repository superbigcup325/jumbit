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
    @cli.Query(keywords) => run_query(keywords, getenv, errs)
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
/// query：按得分降序找首个命中关键词的目录（过滤语义见 core/keyword）
async fn run_query(
  keywords : Array[String],
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
  let db = store.database()
  let now = current_second()
  db.sort_by_score(now)
  let dirs = db.all()
  // sort_by_score 为升序，倒序即从最高分向低分找首个命中
  for i in dirs.length()>..0 {
    if @core.filter_by_keywords(keywords, dirs[i].path) {
      println(dirs[i].path)
      return 0
    }
  }
  if keywords.is_empty() {
    err_line(errs, "数据库为空，没有可跳转的目录")
  } else {
    let kw = keywords.join(" ")
    err_line(errs, "无匹配: \{kw}")
  }
  1
}
