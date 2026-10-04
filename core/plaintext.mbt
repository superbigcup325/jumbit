///|
/// 明文数据库格式（对齐上游 ajeetdsouza/zoxide#1288 分支 src/db/mod.rs，
/// 2026-09-22 逐行核对源码；规格见 docs/spec-plaintext-edit.md §1.1）：
/// 每行 `<timestamp>\t<rank>\t<path>`，timestamp 10 位 0 填充 epoch 秒，
/// rank 定点两位小数 0 填充、序列化时 clamp [MIN_RANK, MAX_RANK]，path 为
/// 行内剩余全部（仅剥前导空白——上游 deserialize 同款，前导空白路径
/// round-trip 后丢失，属上游语义；README 差异清单注记）

///|
/// 列宽（timestamp 与 rank 的 0 填充宽度；上游 COL_WIDTH=10）
const PLAINTEXT_COL_WIDTH : Int = 10

///|
/// 行级错误聚合上限：最多列出 8 行，超出折叠为 "... and N more"
/// （对齐上游 deserialize 的 MAX_ERRORS=8）
const PLAINTEXT_MAX_ERRORS : Int = 8

///|
/// 明文解码行级错误（聚合在解码末尾，整库拒绝；对齐上游 errors 收集语义）。
/// lines 为展示面：decode_plaintext 内已按 PLAINTEXT_MAX_ERRORS 截断
pub(all) struct PlaintextError {
  lines : Array[String]
} derive(Debug)

///|
/// 聚合文案：逐行换行拼接（对齐上游 errors.join("\n") 的多行 stderr 形态）
pub fn PlaintextError::message(self : PlaintextError) -> String {
  let sb = StringBuilder()
  for i, line in self.lines {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(line)
  }
  sb.to_string()
}

///|
/// rank 两位小数的精确十进制格式化（Rust `{:.2}` 语义：按 double 的精确
/// 二进制值做十进制舍入、半界取偶）。
///
/// 实现：x = mant × 2^(unbiased-52)（53 位隐含首一 mantissa），
/// x × 100 的整数/分数部分经 UInt64 纯整数移位获得（rank 值域 clamp 后
/// shift ≤ 59、M × 100 < 2^60，全程无浮点舍入），分数与半界比较进位、
/// 恰半界取偶。
///
/// ⚠️ 不可用 `x * 100.0` 二进制乘法缩放：乘积自身舍入在半界邻域翻转
/// （探针实证：2.675 → ×100 恰落 267.5 → 误进位 2.68，正确为 2.67；
/// 999.995 精确值略大于半界 → 正确进位 1000.00）。半界专项与 20000 随机
/// 值对拍（Python f"{:.2f}" = Rust {:.2} 同为正确舍入）2026-09-22 全绿
fn plaintext_fmt_rank(rank : Double) -> String {
  let bits = rank.reinterpret_as_uint64()
  let biased = (bits >> 52).to_int() & 0x7FF
  let frac52 = bits & 0x000FFFFFFFFFFFFFUL
  let unbiased = biased - 1023
  let mant = frac52 + 0x0010000000000000UL // 53 位隐含首一
  let pair : (UInt64, UInt64, UInt64) = if unbiased >= 52 {
    // rank clamp 后 < 2^24,此支不达;防御:整数直乘无分数
    ((mant * 100UL) << (unbiased - 52), 0UL, 1UL)
  } else {
    let shift = 52 - unbiased
    let m100 = mant * 100UL
    (m100 >> shift, m100 & ((1UL << shift) - 1UL), (1UL << shift) - 1UL)
  }
  let q = pair.0
  let rem = pair.1
  let mask = pair.2
  // 半界点 = (mask+1)/2：rem×2 与 mask+1 比较；恰半界（rem×2 == mask+1）取偶
  let twice = rem * 2UL
  let carry = if twice > mask + 1UL {
    true
  } else if twice == mask + 1UL {
    q % 2UL == 1UL
  } else {
    false
  }
  let scaled = q + (if carry { 1UL } else { 0UL })
  let int_part = (scaled / 100UL).to_string()
  let dec = (scaled % 100UL).to_string()
  int_part + "." + (if dec.length() == 1 { "0" + dec } else { dec })
}

///|
/// 数字 0 填充到指定宽度（上游 `{:0COL_WIDTH$}`；超宽原样——epoch 2286 年
/// 起 11 位，上游 {:010} 同样不截断，行为一致）
fn plaintext_pad10(n : Int64) -> String {
  // 负数对齐 Rust `{:010}`：符号在前、0 填充其后（"-1" → "-000000001"）；
  // i64::MIN 取绝对值溢出，直接原样（超宽不填充，Rust 同款）
  if n < 0 {
    let s = n.to_string()
    let digits = s[1:].to_owned()
    if digits.length() >= PLAINTEXT_COL_WIDTH {
      s
    } else {
      "-" + plaintext_pad_str(digits)
    }
  } else {
    plaintext_pad_str(n.to_string())
  }
}

///|
/// 字符串 0 填充到列宽（超宽原样）
fn plaintext_pad_str(s : String) -> String {
  if s.length() >= PLAINTEXT_COL_WIDTH {
    s
  } else {
    String::make(PLAINTEXT_COL_WIDTH - s.length(), '0') + s
  }
}

///|
/// 明文序列化：每行 `timestamp\trank\tpath\n`（上游 serialize 同款结构；
/// 预分配省略——StringBuilder 单趟拼接已是线性）。
///
/// rank NaN 归 RANK_MIN：上游经 deserialize_line 已拒 NaN 不会有
/// 此态；jumbit legacy bincode 解码不拒，明文迁移时兜底为最低权重（救库语义，
/// 规格文档 §1.3）——即 CHANGELOG 已知问题（非 finite 毒库）的销账路径
pub fn encode_plaintext(dirs : Array[Dir]) -> Bytes {
  let sb = StringBuilder()
  for dir in dirs {
    // 空 path 条目跳过：明文行格式无法表达（空 path 行 decode 即拒，写出行
    // 会让库永久不可读——上游 #1288 未处理此自锁），迁移救库语义与 NaN 归
    // 下限同族（规格 §1.3）。空 path 仅混沌数据可产生（add 拒空路径）
    if dir.path.is_empty() {
      continue
    }
    let rank = if dir.rank.is_nan() {
      RANK_MIN
    } else {
      dir.rank.clamp(min=RANK_MIN, max=RANK_MAX)
    }
    sb.write_string(plaintext_pad10(dir.last_accessed))
    sb.write_char('\t')
    sb.write_string(plaintext_pad_str(plaintext_fmt_rank(rank)))
    sb.write_char('\t')
    sb.write_string(dir.path)
    sb.write_char('\n')
  }
  @utf8.encode(sb.to_string())
}

///|
/// i64 十进制文本解析（Rust i64::from_str 语义子集）：可选单个 +/-、
/// 剩余全数字（前导 0 合法）、值域 [i64::MIN, i64::MAX]；空串/垃圾/溢出拒
fn plaintext_parse_i64(s : String) -> Result[Int64, Unit] {
  let n = s.length()
  if n == 0 {
    return Err(())
  }
  let mut i = 0
  let neg = s[0] == 45 // '-'
  if s[0] == 43 || s[0] == 45 { // '+' '-'
    i += 1
  }
  if i >= n {
    return Err(())
  }
  // 位数上限：i64 十进制最长 20 位（含符号另计）；超长必溢出，早拒
  if n - i > 20 {
    return Err(())
  }
  let mut v : UInt64 = 0
  while i < n {
    let c = s[i]
    if c < 48 || c > 57 {
      return Err(())
    }
    v = v * 10UL + (c - 48).to_uint64()
    i += 1
  }
  let limit : UInt64 = if neg {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  if v > limit {
    return Err(())
  }
  if neg {
    // -0 → 0;两补码取负安全（v ≤ 2^63）
    Ok(if v == 0UL { 0L } else { (0UL - v).reinterpret_as_int64() })
  } else {
    Ok(v.reinterpret_as_int64())
  }
}

///|
/// 行内 ASCII 空白判定（对齐 Rust char::is_whitespace 的 ASCII 子集：
/// 0x09 tab、0x0A LF（行切割已消费）、0x0B、0x0C、0x0D CR、0x20 space；
/// Unicode 空白类不认——路径含 U+00A0 等属病态，README 差异注记）

///|
/// 缺列错误的统一文案（上游 deserialize_line 的 EXPECTED）
const PLAINTEXT_EXPECTED : String = "expected: <timestamp> <rank> <path>"

///|
fn plaintext_is_ws(b : UInt16) -> Bool {
  b == 32 || b == 9 || (b >= 11 && b <= 13)
}

///|
/// 单行解码（上游 deserialize_line 同构）：UTF-8 校验 → 剥行尾 CR → 空行
/// 跳过（Ok(None)）→ trim_start 后按首个空白切两刀得 timestamp/rank/path →
/// 数值解析 + NaN 拒收 + clamp。path 段再剥前导空白（上游 path.trim_start()）。
/// 错误文案与上游逐字对齐（"could not parse timestamp/rank: X"、
/// "expected: <timestamp> <rank> <path>"、"invalid UTF-8"）
fn decode_plaintext_line(
  bytes : Bytes,
  start : Int,
  end : Int,
) -> Result[Dir?, String] {
  // UTF-8 校验与解码（非法字节 → 行级错误，上游 str::from_utf8 context）
  let line : String = @utf8.decode(bytes[start:end]) catch {
    _ => return Err("invalid UTF-8")
  }
  // 剥行尾 CR（CRLF 容忍；上游 strip_suffix('\r')）
  let line = if line.has_suffix("\r") {
    line[0:line.length() - 1].to_owned()
  } else {
    line
  }
  // 空行跳过（上游 line.trim().is_empty() → Ok(None)）
  if line.trim().is_empty() {
    return Ok(None)
  }
  // trim_start（上游 line.trim_start()）后切首个空白
  let n = line.length()
  let mut i = 0
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // 第一段：timestamp
  let ts_start = i
  while i < n && !plaintext_is_ws(line[i]) {
    i += 1
  }
  if i >= n {
    return Err(PLAINTEXT_EXPECTED)
  }
  let ts_str = line[ts_start:i].to_owned()
  // 跳过分隔符
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // 第二段：rank
  let rank_start = i
  while i < n && !plaintext_is_ws(line[i]) {
    i += 1
  }
  if i >= n {
    return Err(PLAINTEXT_EXPECTED)
  }
  let rank_str = line[rank_start:i].to_owned()
  // 跳过分隔符
  while i < n && plaintext_is_ws(line[i]) {
    i += 1
  }
  // 第三段：path（上游 path.trim_start()；前导空白由上面跳分隔符覆盖）
  let path = line[i:n].to_owned()
  if path.is_empty() {
    return Err(PLAINTEXT_EXPECTED)
  }
  // timestamp：Rust i64::from_str 语义（可选 +/-、前导 0 合法、溢出拒——
  // 上游 parse::<Epoch>，atuin 数据集含 epoch=-1 边界行，必须 round-trip）
  let last_accessed = match plaintext_parse_i64(ts_str) {
    Ok(v) => v
    Err(_) => return Err("could not parse timestamp: \{ts_str}")
  }
  // rank：Rust f64::from_str 语义（inf/nan 字面量可解析）→ NaN 拒收
  // （上游 clamp 返 NaN 后 isnan bail 同效）→ clamp 值域
  let rank = match parse_f64(rank_str) {
    Ok(v) => v
    Err(_) => return Err("could not parse rank: \{rank_str}")
  }
  if rank.is_nan() {
    return Err("could not parse rank: \{rank_str}")
  }
  let rank = rank.clamp(min=RANK_MIN, max=RANK_MAX)
  Ok(Some({ path, rank, last_accessed, note: None, }))
}

///|
/// 行内字节空白判定（plaintext_is_ws 同一集合作用于字节：全 ASCII，字节即码元）
fn plaintext_is_ws_byte(b : Byte) -> Bool {
  let c = b.to_int()
  c == 32 || c == 9 || (c >= 11 && c <= 13)
}

///|
/// 行级快路径：encode_plaintext 产物形态（timestamp 纯数字 ≤18 位、rank
/// 纯数字或「数字.恰 2 位」定点）直接字节解析，免整行 UTF-8 解码与
/// parse_f64（query 每次全量载入的热段）。返回 None = 形态不适用（符号/
/// 指数/inf/nan/其他空白/坏结构），调用方回落 decode_plaintext_line，
/// 错误文案与优先级（整行 UTF-8 先于字段解析）由慢路径原样保证。空行判定
/// 只对空格/tab 直接判空（trim 必剥的交集），其余空白形态交慢路径。
/// 数值位级等价依据：k ≤ 2^53 时 Int64→Double 精确，N/100.0 为单次 IEEE
/// 除法（正确舍入），与 parse_f64 对同一定点小数的最近偶舍入一致
fn decode_plaintext_line_fast(
  bytes : Bytes,
  start : Int,
  end : Int,
) -> Result[Dir?, String]? {
  // 行尾 CR 剥离（慢路径同款，先于空行判定）
  let e = if end > start && bytes[end - 1] == 0x0D { end - 1 } else { end }
  // 跳前导空白；耗尽整行时空行判定只认空格/tab（其余空白形态回落）
  let mut i = start
  let mut only_std_ws = true
  while i < e {
    let b = bytes[i]
    if b == 32 || b == 9 {
      i += 1
    } else if plaintext_is_ws_byte(b) {
      only_std_ws = false
      i += 1
    } else {
      break
    }
  }
  if i >= e {
    if only_std_ws {
      return Some(Ok(None))
    }
    return None
  }
  // timestamp：纯数字段（≤18 位 Int64 无溢出，前导 0 合法同 from_str）
  let ts_start = i
  let mut ts : Int64 = 0L
  while i < e {
    let c = bytes[i].to_int()
    if c >= 48 && c <= 57 {
      ts = ts * 10L + (c - 48).to_int64()
      i += 1
    } else {
      break
    }
  }
  let ts_len = i - ts_start
  if ts_len == 0 || ts_len > 18 || i >= e || !plaintext_is_ws_byte(bytes[i]) {
    return None
  }
  while i < e && plaintext_is_ws_byte(bytes[i]) {
    i += 1
  }
  // rank：整数或「整数.恰 2 位小数」定点；整数段 >16 位（×100 溢出防护）
  // 或值超 2^53 回落
  let r_start = i
  let mut k : Int64 = 0L
  while i < e && i - r_start < 16 {
    let c = bytes[i].to_int()
    if c >= 48 && c <= 57 {
      k = k * 10L + (c - 48).to_int64()
      i += 1
    } else {
      break
    }
  }
  if i == r_start ||
    (i < e && bytes[i].to_int() >= 48 && bytes[i].to_int() <= 57) {
    return None // 段空或整数段超 16 位被截断
  }
  // N = 整数段×100 + 两位小数（k ≤ 16 位 → k×100 ≤ ~1e18，Int64 安全）
  let mut n : Int64 = k * 100L
  if i < e && bytes[i] == 46 {
    // '.'：恰 2 位小数才走快路径
    i += 1
    let mut f : Int64 = 0L
    let mut fd = 0
    while fd < 2 && i < e {
      let c = bytes[i].to_int()
      if c >= 48 && c <= 57 {
        f = f * 10L + (c - 48).to_int64()
        i += 1
        fd += 1
      } else {
        break
      }
    }
    if fd != 2 {
      return None
    }
    n = n + f
  }
  if i < e && !plaintext_is_ws_byte(bytes[i]) {
    return None
  }
  if n > 9007199254740992L {
    return None
  }
  while i < e && plaintext_is_ws_byte(bytes[i]) {
    i += 1
  }
  if i >= e {
    return Some(Err(PLAINTEXT_EXPECTED)) // 空 path（慢路径同文案）
  }
  // UTF-8 校验只对 path 段：ts/rank 已限定 ASCII 数字，整行校验的其余
  // 部分与慢路径无分歧（非 ASCII 必落 path 段或触发回落）
  let path : String = @utf8.decode(bytes[i:e]) catch {
    _ => return Some(Err("invalid UTF-8"))
  }
  let rank = (n.to_double() / 100.0).clamp(min=RANK_MIN, max=RANK_MAX)
  Some(Ok(Some({ path, rank, last_accessed: ts, note: None, })))
}

///|
/// 明文反序列化：按 0x0A 切行逐行解码，行号从 1 起；行级错误全部收集后
/// 若非空则整库拒绝，最多列 PLAINTEXT_MAX_ERRORS 条、超出折叠为
/// "... and N more"（对齐上游 deserialize）
pub fn decode_plaintext(bytes : Bytes) -> Result[Array[Dir], PlaintextError] {
  let dirs : Array[Dir] = []
  let errors : Array[String] = []
  let n = bytes.length()
  let mut start = 0
  let mut line_no = 0
  while start <= n {
    let mut end = start
    while end < n && bytes[end] != 0x0A {
      end += 1
    }
    line_no += 1
    // 快路径优先（encode 产物形态），形态不适用回落慢路径
    let line = match decode_plaintext_line_fast(bytes, start, end) {
      Some(res) => res
      None => decode_plaintext_line(bytes, start, end)
    }
    match line {
      Ok(Some(dir)) => dirs.push(dir)
      Ok(None) => ()
      Err(msg) => errors.push("line \{line_no}: \{msg}")
    }
    if end >= n {
      break
    }
    start = end + 1
  }
  if errors.is_empty() {
    Ok(dirs)
  } else {
    let shown = if errors.length() > PLAINTEXT_MAX_ERRORS {
      let rest = errors.length() - PLAINTEXT_MAX_ERRORS
      let head = errors[0:PLAINTEXT_MAX_ERRORS].to_owned()
      head.push("... and \{rest} more")
      head
    } else {
      errors
    }
    Err({ lines: shown, })
  }
}
