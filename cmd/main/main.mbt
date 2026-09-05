///|
async fn main {
  let errs : Array[String] = []
  // OS 直跑时 argv[0] = 程序路径（含 /）；moon run 不传程序名。
  // 以「含路径分隔符」区分，剥掉程序名后交给 run。
  let argv = @env.args()
  let args : Array[String] = []
  if argv.length() > 0 && argv[0].find("/") is Some(_) {
    for i in 1..<argv.length() {
      args.push(argv[i])
    }
  } else {
    for a in argv {
      args.push(a)
    }
  }
  let code = run(args, @env.get_env_var, errs)
  for msg in errs {
    @stdio.stderr.write(msg + "\n") catch {
      err => ignore(err)
    }
  }
  @sys.exit(code)
}
