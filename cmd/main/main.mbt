///|
/// 所有启动路径下 argv[0] 都是程序名/路径（OS 直跑传裸名或完整路径，
/// moon run native/wasm 传 exe/wasm 路径），无条件剥掉——对齐上游 clap
/// 「首参即 bin_name、解析从 argv[1] 开始」的约定。
fn strip_argv0(argv : Array[String]) -> Array[String] {
  let args : Array[String] = []
  for i in 1..<argv.length() {
    args.push(argv[i])
  }
  args
}

///|
async fn main {
  let errs : Array[String] = []
  let args = strip_argv0(@env.args())
  let code = run(args, @env.get_env_var, errs)
  // 批量一次写（import 大数据集坏行上万，逐条写是纯 syscall 开销）；
  // 字节面与逐条版一致（每条 + 换行），写失败吞掉语义不变
  if errs.length() > 0 {
    let out : StringBuilder = StringBuilder()
    for msg in errs {
      out.write_string(msg)
      out.write_string("\n")
    }
    @stdio.stderr.write(out.to_string()) catch {
      err => ignore(err)
    }
  }
  @sys.exit(code)
}
