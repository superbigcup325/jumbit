///|
/// 原子写：同目录创建 tmp 文件（tmp_ + 16 随机字符，冲突重试 5 次）
/// → 写入 → sync 落盘 → rename 原子替换；失败时 errdefer 清理 tmp 并原样抛错。
/// （对齐上游 src/util.rs util::write；rename 在 UNIX 下原子）
pub async fn write_atomic(path : String, contents : Bytes) -> Unit {
  let dir = match path.rev_find("/") {
    Some(i) => path[0:i + 1].to_owned()
    None => ""
  }
  let pair = for attempts = 0 {
    let tmp = dir + "tmp_" + rand_name()
    let opened = @afs.create(tmp, allow_existing=false) catch {
      e => if attempts >= 4 { raise e } else { continue attempts + 1 }
    }
    break (opened, tmp)
  }
  let (file, tmp) = pair
  errdefer remove_quiet(tmp)
  file.write(contents)
  file.sync()
  file.close()
  @afs.rename(tmp, path, replace=true)
}

///|
/// 删除文件并吞掉错误（errdefer 清理用；tmp 本就不存在时也当成功）
async fn remove_quiet(path : String) -> Unit {
  @afs.remove(path) catch {
    err => ignore(err)
  }
}

///|
/// tmp 随机名：Rand::new() 从系统熵播种（@env.rand），16 位小写字母数字
fn rand_name() -> String {
  let rand = @random.Rand::new()
  let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789".to_array()
  let sb = StringBuilder()
  for _ in 0..<16 {
    sb.write_char(alphabet[rand.int(limit=36)])
  }
  sb.to_string()
}
