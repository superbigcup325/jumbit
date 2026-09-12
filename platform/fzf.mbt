///|
pub(all) enum FzfError {
  /// fzf 不可用（spawn 失败统一归此；上游另区分 "could not launch fzf"，
  /// @process 绑定不暴露 spawn 错误类别，无法拆分——README 注明）
  NotFound
  /// fzf 退出码 1：用户未选择（取消语义）。上游报 "no match found"，
  /// jumbit 静默 exit 1（shell 钩子下行为一致），README 注明
  NoMatch
  /// fzf 退出码 2：fzf 自身错误（上游文案 "fzf returned an error"）
  ReturnedAnError
  /// fzf 退出码 130：用户中断，静默透传退出码（上游 SilentExit）
  Interrupted
  /// fzf 退出码 128..=254 或被信号杀死（wait 返回负值；上游文案
  /// "fzf was terminated"）
  Terminated
  /// 其余退出码：3..=127 与 255（上游文案 "fzf returned an unknown error"）
  UnknownExit(Int)
} derive(Debug, Eq)

///|
/// fzf 退出码映射（对齐上游 FzfChild::wait，zoxide 0.10.0 伪 fzf 探针矩阵
/// 2026-09-13 实测：0 成功 / 1 无选择 / 2 自身错误 / 130 中断静默 /
/// 128..=254 与信号杀死视为被终止 / 3..=127 与 255 未知错误，均 exit 1）
fn map_fzf_exit(code : Int) -> FzfError? {
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
/// fzf 交互选择：候选按 "6.1f 得分\t路径\0" 写入 stdin，返回 fzf 打印的选中行。
/// fzf_opts 非 None 时经 FZF_DEFAULT_OPTS 透传（对齐上游 _ZO_FZF_OPTS）。
pub async fn fzf_select(
  hits : Array[@core.Dir],
  now : Int64,
  fzf_opts : String?,
) -> Result[String, FzfError] {
  fzf_select_with("fzf", hits, now, fzf_opts)
}

///|
/// 指定可执行文件的交互选择核心（fzf_select 的注入点：单测传绝对路径，
/// 规避 moon test 并行下全局 PATH 注入的同名串扰）
async fn fzf_select_with(
  program : String,
  hits : Array[@core.Dir],
  now : Int64,
  fzf_opts : String?,
) -> Result[String, FzfError] {
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
      program,
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
        // fzf 提前退出（已选定/出错）时管道断裂：对齐上游 write 的
        // BrokenPipe → wait 路径，静默停止投喂（结果已由 fzf 决定）
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
