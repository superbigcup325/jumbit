///|
/// 数据目录：_JB_DATA_DIR 优先（必须绝对路径），否则回落 $HOME/.local/share/jumbit
/// get 注入环境变量读取（cmd/main 传 @env.get_env_var，测试传闭包）
pub fn data_dir(get : (String) -> String?) -> Result[String, String] {
  match get("_JB_DATA_DIR") {
    Some(dir) =>
      if is_absolute(dir) {
        Ok(dir)
      } else {
        Err("_JB_DATA_DIR 必须是绝对路径: \{dir}")
      }
    None =>
      match get("HOME") {
        Some(home) => Ok(home + "/.local/share/jumbit")
        None => Err("无法确定数据目录：请设置 _JB_DATA_DIR")
      }
  }
}

///|
/// 绝对路径判定（Linux：以 / 开头）
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}
