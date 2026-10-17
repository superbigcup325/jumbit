///|
/// On every startup path argv[0] is the program name or path (running from the OS passes a bare name or a full path,
/// and moon run passes the exe/wasm path for native and wasm), so it is stripped unconditionally -- matching upstream clap\'s
/// convention that the first argument is the bin name and parsing starts at argv[1].
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
  // written in one batch (a large import can produce tens of thousands of bad rows, and per-row writes would be pure syscall cost);
  // the bytes match a per-row version (each row plus a newline), and swallowing a failed write is unchanged
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
