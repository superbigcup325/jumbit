///|
pub enum FzfError {
  /// fzf 未安装
  NotFound
  /// 用户未选择（退出码 1）
  NoMatch
  /// fzf 以异常码退出（130=中断）
  Exit(Int)
} derive(Debug)

///|
/// fzf 退出码映射（对齐上游 FzfChild::wait：0 成功 / 1 无选择 / 130 中断）
fn map_fzf_exit(code : Int) -> FzfError? {
  match code {
    0 => None
    1 => Some(NoMatch)
    130 => Some(Exit(130))
    c => Some(Exit(c))
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
      "fzf",
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
        stdin_w.write(line)
      }
    }
    let out = stdout_r.read_all().text()
    match map_fzf_exit(proc.wait()) {
      Some(e) => Err(e)
      None => Ok(out)
    }
  }
}
