///|
/// 导入插件的行解析（对齐上游 src/import/ 各模块的 parse_line；纯函数，I/O 在 platform）
/// 三种数据格式：
/// - z 系（z / zsh-z / fasd / z.lua）：`path|rank|last_accessed`
/// - autojump：`rank\tpath`（rank 过 sigmoid 归一）
/// - atuin：`YYYY-MM-DD HH:MM:SS\tpath`（UTC，rank=1.0）
/// 坏行返回 Err(原因) 由调用方按 `<来源>:<行号>: <原因>` 上报，不中止整批导入。

///|
/// z 系格式：从右往左切 3 段（rsplitn 语义），路径可含 `|`；
/// last_accessed 为非负整数（上游 u64，负数拒为坏行），rank 任意浮点（可为负）。
/// 注意：不做 trim——空白属于路径的一部分（上游原样保留）。
pub fn parse_z_line(line : String) -> Result[Dir, String] {
  let bad = Err("invalid entry: \{line}")
  let p1 = match line.rev_find("|") {
    Some(i) => i
    None => return bad
  }
  // 上游按 u64 解析：Int64 溢出（>2^63-1）与负数均拒为坏行
  let last_accessed : Int64 = @strconv.from_str(line[p1 + 1:]) catch {
    _ => return bad
  }
  if last_accessed < 0L {
    return bad
  }
  let head = line[0:p1]
  let p2 = match head.rev_find("|") {
    Some(i) => i
    None => return bad
  }
  let rank : Double = @strconv.from_str(head[p2 + 1:]) catch { _ => return bad }
  Ok({ path: head[0:p2].to_owned(), rank, last_accessed, note: None, })
}

///|
/// autojump 格式：首个 \t 切两段，左 rank 右路径（路径可含 \t）；
/// autojump 打分体系与 zoxide 差异大，rank 过 sigmoid 归一到 (0,1)，last_accessed=0。
pub fn parse_autojump_line(line : String) -> Result[Dir, String] {
  let t = match line.find("\t") {
    Some(i) => i
    None => return Err("invalid entry: \{line}")
  }
  let rank_str = line[0:t].to_owned()
  let rank : Double = @strconv.from_str(rank_str) catch {
    _ => return Err("invalid rank: \{rank_str}")
  }
  Ok({
    path: line[t + 1:].to_owned(),
    rank: sigmoid(rank),
    last_accessed: 0L,
    note: None,
  })
}

///|
/// atuin 格式：首个 \t 切两段，左时间戳右路径；
/// 时间戳为 atuin 渲染的 UTC `YYYY-MM-DD HH:MM:SS`（上游 assume_utc）。
pub fn parse_atuin_line(line : String) -> Result[Dir, String] {
  let t = match line.find("\t") {
    Some(i) => i
    None => return Err("invalid entry: \{line}")
  }
  let ts = line[0:t].to_owned()
  let epoch = match parse_atuin_timestamp(ts) {
    Some(e) => e
    None => return Err("invalid timestamp: \"\{ts}\"")
  }
  Ok({
    path: line[t + 1:].to_owned(),
    rank: 1.0,
    last_accessed: epoch,
    note: None,
  })
}

///|
/// 带定位的解析条目：location 供错误上报拼 `<来源>:<行号>`（atuin 无文件来源时
/// 调用方传 `line <N>`），与条目绑定后可整体过折叠器（上游 ImportError 同构）
pub(all) struct LocatedDir {
  location : String
  result : Result[Dir, String]
} derive(Debug)

///|
/// atuin 导入的连续同路径折叠（对齐上游 src/import/atuin.rs Iter 的 prev_cwd）：
/// shell 历史按命令序排列，连住一个目录的多条记录只算一次转换，连续重复仅保留
/// 首次；Err 原样透传且不更新折叠链（上游错误路径不改 prev_cwd），空记录由调用方
/// 在解析前跳过、同样不影响链
pub fn collapse_consecutive(items : Array[LocatedDir]) -> Array[LocatedDir] {
  let out : Array[LocatedDir] = []
  let mut prev : String? = None
  for item in items {
    match item.result {
      Err(_) => out.push(item)
      Ok(dir) => {
        let dup = match prev {
          Some(p) => p == dir.path
          None => false
        }
        if dup {
          continue
        }
        prev = Some(dir.path)
        out.push(item)
      }
    }
  }
  out
}

///|
/// sigmoid：autojump rank 归一（对齐上游 import/autojump.rs sigmoid）
fn sigmoid(x : Double) -> Double {
  1.0 / (1.0 + @math.exp(-x))
}

///|
/// 解析 `YYYY-MM-DD HH:MM:SS`（严格 19 字符、固定分隔符、纯数字、范围校验，
/// 对齐 time crate 解析行为：day 对当月长度校验、闰年规则、秒 0-59）→ Unix 秒（UTC）
fn parse_atuin_timestamp(ts : String) -> Int64? {
  if ts.length() != 19 {
    return None
  }
  if ts[4] != '-' ||
    ts[7] != '-' ||
    ts[10] != ' ' ||
    ts[13] != ':' ||
    ts[16] != ':' {
    return None
  }
  let year = match parse_digits(ts[0:4]) {
    Some(v) => v
    None => return None
  }
  let month = match parse_digits(ts[5:7]) {
    Some(v) => v
    None => return None
  }
  let day = match parse_digits(ts[8:10]) {
    Some(v) => v
    None => return None
  }
  let hour = match parse_digits(ts[11:13]) {
    Some(v) => v
    None => return None
  }
  let minute = match parse_digits(ts[14:16]) {
    Some(v) => v
    None => return None
  }
  let second = match parse_digits(ts[17:19]) {
    Some(v) => v
    None => return None
  }
  if month < 1 || month > 12 {
    return None
  }
  if day < 1 || day > days_in_month(year, month) {
    return None
  }
  if hour > 23 || minute > 59 || second > 59 {
    return None
  }
  let days = days_from_civil(year, month, day)
  let time_of_day = hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64()
  Some(days * 86400L + time_of_day)
}

///|
/// 纯 ASCII 数字段 → Int（拒绝空串/符号/其他字符；溢出走 from_str 失败）
fn parse_digits(v : StringView) -> Int? {
  if v.length() == 0 {
    return None
  }
  for i in 0..<v.length() {
    let c = v[i]
    if c < '0' || c > '9' {
      return None
    }
  }
  let n : Int = @strconv.from_str(v) catch { _ => return None }
  Some(n)
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// 公历日期 → 自 1970-01-01 起的天数（Howard Hinnant days_from_civil 算法，
/// 除法向零截断与 Int 语义一致；范围仅处理 0000-9999 年，溢出无需 Int64）
fn days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146097L + doe.to_int64() - 719468L
}
