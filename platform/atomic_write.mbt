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
/// 进程级随机源（[#11]）：Rand::new() 无参为固定种子（deprecated API，默认
/// "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"），函数内每次新建会产出同一序列——
/// 并发下 write_atomic 的 5 次重试反复撞同一 tmp 名、make_tmp_dir 的目录名
/// 只剩毫秒时间戳兜底。全局单例让每次调用推进序列，进程内唯一性成立
let global_rand : @random.Rand = @random.Rand::new()

///|
/// tmp 随机名：进程级生成器推进，16 位小写字母数字
fn rand_name() -> String {
  let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789".to_array()
  let sb = StringBuilder()
  for _ in 0..<16 {
    sb.write_char(alphabet[global_rand.int(limit=36)])
  }
  sb.to_string()
}
