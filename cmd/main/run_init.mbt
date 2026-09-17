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
    "elvish" => @tpl.render_elvish(cmd, iopts.hook, echo, resolve_symlinks)
    "nushell" => @tpl.render_nushell(cmd, iopts.hook, echo, resolve_symlinks)
    "posix" => @tpl.render_posix(cmd, iopts.hook, echo, resolve_symlinks)
    "powershell" =>
      @tpl.render_powershell(cmd, iopts.hook, echo, resolve_symlinks)
    "tcsh" => @tpl.render_tcsh(cmd, iopts.hook, echo, resolve_symlinks)
    "xonsh" => @tpl.render_xonsh(cmd, iopts.hook, echo, resolve_symlinks)
    other => {
      err_line(errs, "init: 不支持的 shell: \{other}")
      return 2
    }
  }
  println(source)
  0
}
