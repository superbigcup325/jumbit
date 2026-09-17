///|
/// describe（jumbit 扩展）：为已记录条目设置/清除/显示人工标注。
/// 路径对齐 remove 的双重尝试：先原串，未中再按 cwd 规范化
async fn run_describe(
  dopts : @cli.DescribeOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let store = match open_store(data_dir, errs) {
    Some(s) => s
    None => return 1
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  let db = store.database()
  match dopts.note {
    Some(text) => {
      // 空串即清除
      let note = if text == "" { None } else { Some(text) }
      let ok = try_twice(db, dopts.path, cwd, fn(db, p) { db.set_note(p, note) })
      if !ok {
        err_line(errs, "path not found in database: \{dopts.path}")
        return 1
      }
    }
    None => {
      let i = match find_twice(db, dopts.path, cwd) {
        Some(i) => i
        None => {
          err_line(errs, "path not found in database: \{dopts.path}")
          return 1
        }
      }
      match db.all()[i].note {
        Some(text) => println(text)
        None => {
          err_line(errs, "describe: \{dopts.path} 无标注")
          return 1
        }
      }
    }
  }
  finish(store, errs, 0)
}
