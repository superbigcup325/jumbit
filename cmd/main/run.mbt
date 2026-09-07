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
/// 返回进程退出码：0 成功 / 1 运行失败（含配置错误，对齐上游 ExitCode::FAILURE）
/// / 2 用法错误（对齐 clap 参数解析错误）。stderr 消息写入 errs。
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
    @cli.Add(aopts) => run_add(aopts, getenv, errs)
    @cli.Query(qopts) => run_query(qopts, getenv, errs)
    @cli.Remove(paths) => run_remove(paths, getenv, errs)
    @cli.Init(iopts) => run_init(iopts, getenv, errs)
    @cli.Import(iopts) => run_import(iopts, getenv, errs)
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
/// add（对齐上游 add.rs）：
/// - 按 _JB_RESOLVE_SYMLINKS 选择 realpath（canonicalize）或 resolve_path
/// - 换行路径 / _JB_EXCLUDE_DIRS glob 命中 → 静默跳过；非目录 → 立即报错中止
/// - 全部 add_update(score) 后，若 dirty 则 age(_JB_MAXAGE) 再 save
async fn run_add(
  aopts : @cli.AddOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  if aopts.paths.is_empty() {
    err_line(errs, "add: 缺少路径参数")
    return 2
  }
  let data_dir = match @config.data_dir(getenv) {
    Ok(d) => d
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  let globs = match @config.exclude_dirs(getenv, getenv("HOME")) {
    Ok(g) => g
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  let maxage = match @config.maxage(getenv) {
    Ok(m) => m
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  let resolve_symlinks = @config.resolve_symlinks(getenv)
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
  for path in aopts.paths {
    let resolved = @core.resolve_path(path, cwd)
    let resolved = if resolve_symlinks {
      @afs.realpath(resolved) catch {
        err => {
          err_line(errs, "解析路径失败: \{resolved} (\{Repr(err)})")
          return 1
        }
      }
    } else {
      resolved
    }
    // 换行/回车无法整洁地打印在单行，静默跳过（对齐上游 EXCLUDE_CHARS）
    if resolved.find("\n") is Some(_) || resolved.find("\r") is Some(_) {
      continue
    }
    // _JB_EXCLUDE_DIRS 命中 → 静默跳过
    let mut excluded = false
    for pattern in globs {
      if @core.glob_match(pattern, resolved) {
        excluded = true
        break
      }
    }
    if excluded {
      continue
    }
    let kind = @afs.kind(resolved) catch {
      err => {
        ignore(err)
        @afs.Unknown
      }
    }
    if kind != @afs.Directory {
      err_line(errs, "not a directory: \{resolved}")
      return 1
    }
    store.database().add_update(resolved, aopts.score, now)
    if echo_enabled(getenv) {
      println(resolved)
    }
  }
  if store.database().is_dirty() {
    store.database().age(maxage)
  }
  match store.save() {
    Ok(_) => 0
    Err(err) => {
      err_line(errs, "保存数据库失败: \{Repr(err)}")
      1
    }
  }
}

///|
/// remove（对齐上游 remove.rs）：先按原始串删，未中再按规范化路径删，仍未中报错
async fn run_remove(
  paths : Array[String],
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  if paths.is_empty() {
    err_line(errs, "remove: 缺少路径参数")
    return 2
  }
  let data_dir = match @config.data_dir(getenv) {
    Ok(d) => d
    Err(msg) => {
      err_line(errs, msg)
      return 1
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
  for path in paths {
    let mut removed = store.database().remove(path)
    if !removed {
      let resolved = @core.resolve_path(path, cwd)
      removed = store.database().remove(resolved)
    }
    if !removed {
      err_line(errs, "path not found in database: \{path}")
      return 1
    }
  }
  match store.save() {
    Ok(_) => 0
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
      return 1
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
      return 1
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
  } else if qopts.interactive {
    match @platform.fzf_select(remaining, now, @config.fzf_opts(getenv)) {
      Ok(selection) => {
        // --score 输出整行（得分\t路径）；否则剥掉 7 字符得分前缀（对齐上游）
        if qopts.score {
          println(selection)
        } else if selection.length() > 7 {
          println(selection[7:].to_owned())
        } else {
          println("")
        }
        0
      }
      Err(@platform.NotFound) => {
        err_line(errs, "could not find fzf, is it installed?")
        1
      }
      Err(@platform.NoMatch) => 1
      Err(@platform.Exit(c)) => c
    }
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

///|
/// init：按 shell 渲染集成脚本（echo/resolve_symlinks 取自运行时配置，对齐上游 init.rs）
fn run_init(
  iopts : @cli.InitOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let echo = echo_enabled(getenv)
  let resolve_symlinks = @config.resolve_symlinks(getenv)
  let cmd : String? = if iopts.no_cmd { None } else { iopts.cmd }
  let source = match iopts.shell {
    "bash" => @tpl.render_bash(cmd, iopts.hook, echo, resolve_symlinks)
    "zsh" => @tpl.render_zsh(cmd, iopts.hook, echo, resolve_symlinks)
    "fish" => @tpl.render_fish(cmd, iopts.hook, echo, resolve_symlinks)
    other => {
      err_line(errs, "init: 不支持的 shell: \{other}")
      return 2
    }
  }
  println(source)
  0
}

///|
/// import（对齐上游 cmd/import.rs + import/run）：
/// 空库直灌 / --merge 合并进非空库；坏行按 `<来源>:<行号>: <原因>` 上报不中止；
/// 结束后 dedup + age(maxage) 再落盘。atuin 走子进程，其余插件读数据文件。
async fn run_import(
  iopts : @cli.ImportOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match @config.data_dir(getenv) {
    Ok(d) => d
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(err) => {
      err_line(errs, "打开数据库失败: \{Repr(err)}")
      return 1
    }
  }
  if !iopts.merge && !store.database().is_empty() {
    err_line(
      errs, "current database is not empty, specify --merge to continue anyway",
    )
    return 1
  }
  let globs = match @config.exclude_dirs(getenv, getenv("HOME")) {
    Ok(g) => g
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  // 读数据源：source 为 None 表示无文件来源（atuin），上报定位用 `line N`
  let loaded : Result[(Array[@platform.ImportRecord], String?), String] = match
    iopts.plugin {
    "atuin" =>
      match @platform.atuin_history_records() {
        Ok((records, stderr_text)) => {
          if stderr_text != "" {
            err_line(errs, stderr_text)
          }
          Ok((records, None))
        }
        Err(msg) => Err(msg)
      }
    "z" => read_import_file(@config.z_data_path(getenv))
    "fasd" => read_import_file(@config.fasd_data_path(getenv))
    "zsh-z" => read_import_file(@config.zsh_z_data_path(getenv))
    "autojump" => read_import_file(@config.autojump_data_path(getenv))
    // z.lua：主路径缺失回落 fish 变体；双双缺失报主路径（对齐上游 z_lua.rs）
    "z.lua" =>
      match read_import_file(@config.zlua_data_path(getenv)) {
        Ok(found) => Ok(found)
        Err(_) =>
          match @config.zlua_fish_path(getenv) {
            Ok(fish_path) =>
              if @afs.exists(fish_path) {
                read_import_file(Ok(fish_path))
              } else {
                read_import_file(@config.zlua_data_path(getenv))
              }
            Err(msg) => Err(msg)
          }
      }
    other => Err("import: 不支持的插件: \{other}")
  }
  let (records, source) = match loaded {
    Ok((records, source)) => (records, source)
    Err(msg) => {
      err_line(errs, msg)
      return 1
    }
  }
  let parse : (String) -> Result[@core.Dir, String] = match iopts.plugin {
    "autojump" => @core.parse_autojump_line
    "atuin" => @core.parse_atuin_line
    // z / zsh-z / fasd / z.lua 与 z 同格式，共用解析（对齐上游复用 z::Iter）
    _ => @core.parse_z_line
  }
  // 折叠开关与解析器同源派生（仅 atuin 有连续折叠，六插件中唯一）
  let collapse = iopts.plugin == "atuin"
  // 解析 pass：记录流转为带定位条目（空行静默跳过，上游迭代器 continue；
  // 行号占位保留，坏解码行折为 Err 后续按位上报）
  let parsed : Array[@core.LocatedDir] = []
  for record in records {
    let location = match source {
      Some(path) => "\{path}:\{record.line_num}"
      None => "line \{record.line_num}"
    }
    match record.result {
      Err(reason) => parsed.push({ location, result: Err(reason), })
      Ok(line) =>
        if line != "" {
          parsed.push({ location, result: parse(line), })
        }
    }
  }
  let entries = if collapse {
    @core.collapse_consecutive(parsed)
  } else {
    parsed
  }
  // 入库 pass：坏行按 <定位>: <原因> 上报不中止；exclude 命中静默跳过
  for entry in entries {
    match entry.result {
      Err(reason) => err_line(errs, "\{entry.location}: \{reason}")
      Ok(dir) => {
        // _JB_EXCLUDE_DIRS 命中 → 静默跳过（对齐上游 exclude_dirs 过滤）
        let mut excluded = false
        for pattern in globs {
          if @core.glob_match(pattern, dir.path) {
            excluded = true
            break
          }
        }
        if !excluded {
          store.database().add_unchecked(dir.path, dir.rank, dir.last_accessed)
        }
      }
    }
  }
  if store.database().is_dirty() {
    store.database().dedup()
    let maxage = match @config.maxage(getenv) {
      Ok(m) => m
      Err(msg) => {
        err_line(errs, msg)
        return 1
      }
    }
    store.database().age(maxage)
  }
  match store.save() {
    Ok(_) => 0
    Err(err) => {
      err_line(errs, "保存数据库失败: \{Repr(err)}")
      1
    }
  }
}

///|
/// 读单个插件数据文件（路径解析失败一并折算为 Err 文案）
async fn read_import_file(
  path : Result[String, String],
) -> Result[(Array[@platform.ImportRecord], String?), String] {
  let path = match path {
    Ok(p) => p
    Err(msg) => return Err(msg)
  }
  match @platform.read_import_lines(path) {
    Ok(records) => Ok((records, Some(path)))
    Err(msg) => Err(msg)
  }
}
