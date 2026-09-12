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
  // 坏行消息惰性构造：成功路（绝大多数行）不再为每行预分配错误串
  fn bad() -> Result[Dir, String] {
    Err("invalid entry: \{line}")
  }
  let p1 = match line.rev_find("|") {
    Some(i) => i
    None => return bad()
  }
  // 上游按 u64 解析（0..=2^64-1，前导 + 合法，溢出/负数拒为坏行）；位模式
  // 经 i64 字段原样保存（u64::MAX 即 i64 的 -1），下游 score/dedup 已按
  // u64 域比较（0.10.0 对拍实测：u64::MAX 接受且落 ×4 档）
  let la_str = line[p1 + 1:]
  let la_body = if la_str.has_prefix("+") { la_str[1:] } else { la_str }
  let last_accessed : UInt64 = @string.parse_uint64(la_body) catch {
    _ => return bad()
  }
  let head = line[0:p1]
  let p2 = match head.rev_find("|") {
    Some(i) => i
    None => return bad()
  }
  let rank = match parse_f64(head[p2 + 1:]) {
    Ok(v) => v
    Err(_) => return bad()
  }
  Ok({
    path: head[0:p2].to_owned(),
    rank,
    last_accessed: last_accessed.reinterpret_as_int64(),
    note: None,
  })
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
  let rank = match parse_f64(rank_str) {
    Ok(v) => v
    Err(_) => {
      // 对齐上游 anyhow 消息的 Rust ParseFloatError Display 后缀
      let reason = if rank_str == "" {
        "cannot parse float from empty string"
      } else {
        "invalid float literal"
      }
      return Err("invalid rank: \{rank_str}: \{reason}")
    }
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
    Ok(e) => e
    Err(reason) => return Err(atuin_ts_message(ts, reason))
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
/// 时间戳错误原因（对齐上游 time crate 解析 + anyhow {:#} 链式 Display；
/// 每类消息的真值经与 zoxide 0.10.0 对拍实测）：
/// - 组件非数字/超出字面范围 → "the 'X' component could not be parsed"（链两层）
/// - day 符合 1..=31 但超出当月长度（闰日）→ "day was not in range"（链三层）
/// - 固定布局分隔符错 → "a character literal was not valid"（链两层）
/// - 前 19 位合法但尾部有多余字符 → "unexpected trailing characters; ..."（链两层）
pub(all) enum AtuinTsError {
  Component(String)
  CharLiteral
  Trailing
  DayRange
} derive(Debug, Eq)

///|
fn atuin_ts_message(ts : String, reason : AtuinTsError) -> String {
  let base = "invalid timestamp: \"\{ts}\""
  match reason {
    Component(name) =>
      "\{base}: the '\{name}' component could not be parsed: the '\{name}' component could not be parsed"
    CharLiteral =>
      "\{base}: a character literal was not valid: a character literal was not valid"
    Trailing =>
      "\{base}: unexpected trailing characters; the end of input was expected: unexpected trailing characters; the end of input was expected"
    DayRange =>
      "\{base}: day was not in range: day was not in range: day was not in range"
  }
}

///|
/// 解析 `YYYY-MM-DD HH:MM:SS`（19 字符固定布局、UTC）→ Unix 秒。
/// 逐位置状态机复刻上游 time crate 的解析顺序：位置靠前的组件先报错；
/// 数字段即时做字面范围校验，全部通过后再做当月长度/闰年校验（DayRange）。
fn parse_atuin_timestamp(ts : String) -> Result[Int64, AtuinTsError] {
  let names = ["year", "month", "day", "hour", "minute", "second"]
  let widths = [4, 2, 2, 2, 2, 2]
  // 分隔符 UTF-16 码元：'-','=45、' '=32、':'=58（String 索引返回码元）
  let seps : Array[UInt16] = [45, 45, 32, 58, 58, 58]
  let vals : Array[Int] = []
  let mut pos = 0
  let n = ts.length()
  for seg in 0..<6 {
    let mut v = 0
    for _ in 0..<widths[seg] {
      if pos >= n {
        return Err(Component(names[seg]))
      }
      let c = ts[pos]
      if c < 48 || c > 57 {
        return Err(Component(names[seg]))
      }
      v = v * 10 + (c.to_int() - 48)
      pos += 1
    }
    // 字面范围（组件级）：解析完本段立即校验（上游按组件顺序即时失败）
    match seg {
      1 => if v < 1 || v > 12 { return Err(Component(names[seg])) }
      3 => if v > 23 { return Err(Component(names[seg])) }
      4 | 5 => if v > 59 { return Err(Component(names[seg])) }
      _ => ()
    }
    vals.push(v)
    if seg < 5 {
      if pos >= n || ts[pos] != seps[seg] {
        return Err(CharLiteral)
      }
      pos += 1
    }
  }
  if pos < n {
    return Err(Trailing)
  }
  let year = vals[0]
  let month = vals[1]
  let day = vals[2]
  if day < 1 || day > days_in_month(year, month) {
    return Err(DayRange)
  }
  let days = days_from_civil(year, month, day)
  let time_of_day = vals[3].to_int64() * 3600L +
    vals[4].to_int64() * 60L +
    vals[5].to_int64()
  Ok(days * 86400L + time_of_day)
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
