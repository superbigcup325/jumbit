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
/// 无换行 stdout 输出（对齐上游 print! 语义）；写失败吞掉
/// （对齐 main 对 stderr 写失败的处理）
async fn print_stdout(s : String) -> Unit {
  @stdio.stdout.write(s) catch {
    _ => ()
  }
}

///|
/// query --interactive 的 fzf 结果 → 退出码/文案映射（纯逻辑，wbtest 直测；
/// 进程面由 platform 伪 fzf E2E 与 dataset_check D9 对拍覆盖）。
/// stdout 片段收集进 outs 由调用侧落盘（收集式同 errs：moon test 进程内
/// 直写 stdout 会与 test driver 事件协议串扰）。
/// 输出对齐上游 print!：不追加换行（fzf 自身输出带尾换行）；--score 输出
/// 整行，否则剥掉 7 字符得分前缀（对齐上游 selection.get(7..)，len==7 →
/// 空串原样输出）；len<7 上游走错误路（探针 2026-09-13：exit 1 +
/// "could not read selection from fzf"）。退出码表：0 成功 / 1 无选择
/// （上游报 "no match found"，jumbit 静默——取消语义，README 注明）/
/// 2 与 128..=254 与信号杀死与 3..=127、255 均 exit 1 带对应文案 /
/// 130 静默透传 130
fn finish_interactive(
  selection : Result[String, @platform.FzfError],
  score : Bool,
  errs : Array[String],
  outs : Array[String],
) -> Int {
  match selection {
    Ok(s) => {
      if score {
        outs.push(s)
      } else if s.length() >= 7 {
        outs.push(s[7:].to_owned())
      } else {
        err_line(errs, "could not read selection from fzf")
        return 1
      }
      0
    }
    Err(@platform.NotFound) => {
      err_line(errs, "could not find fzf, is it installed?")
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
/// 配置解析步骤的统一出口：Err 文案写入 errs 后返回 None，调用方以
/// `match { None => return 1 }` 提前退出。各子命令保留各自的解析顺序
/// （对齐上游：add 先读配置再开库，query/import 先开库）
/// 各子命令保留各自的解析顺序（对齐上游：add 先读配置再开库，query/import 先开库）
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
/// 打开数据库：打开失败的文案与配置错误分开（含 Repr 调试格式）
async fn open_store(
  data_dir : String,
  errs : Array[String],
) -> @platform.Store? {
  match @platform.load(data_dir) {
    Ok(s) => Some(s)
    Err(err) => {
      err_line(errs, "打开数据库失败: \{err.message()}")
      None
    }
  }
}

///|
/// 结束统一落盘：保存失败时退出码覆盖为 1，否则透传原退出码
async fn finish(
  store : @platform.Store,
  errs : Array[String],
  code : Int,
) -> Int {
  match store.save() {
    Ok(_) => code
    Err(err) => {
      err_line(errs, "保存数据库失败: \{err.message()}")
      1
    }
  }
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
    @cli.Invalid(msg) => {
      err_line(errs, msg)
      err_line(errs, "运行 jumbit help 查看用法")
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
/// _JB_ECHO 调试回显开关：仅值 "1" 生效（对齐上游 config::echo）
fn echo_enabled(getenv : (String) -> String?) -> Bool {
  match getenv("_JB_ECHO") {
    Some("1") => true
    _ => false
  }
}

///|
/// _JB_EXCLUDE_DIRS glob 命中检测（add 与 import 共用；命中即静默跳过）
fn glob_hit(globs : Array[String], path : String) -> Bool {
  for pattern in globs {
    if @core.glob_match(pattern, path) {
      return true
    }
  }
  false
}

///|
/// 双重尝试（对齐上游 remove.rs 的双重查找语义）：先原串，未中再按 cwd 规范化重试
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
/// 双重查找：try_twice 的查找版（describe 显示路需要下标而非布尔）
fn find_twice(db : @core.Database, path : String, cwd : String) -> Int? {
  match db.find_idx(path) {
    Some(i) => Some(i)
    None => db.find_idx(@core.resolve_path(path, cwd))
  }
}
