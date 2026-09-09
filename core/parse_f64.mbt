///|
/// Rust `f64::from_str` 兼容的浮点解析（rank/`--score` 等数值面共用）。
/// 语义逐项对齐 Rust std（2026-09-09 rustc + zoxide 0.10.0 探针实测）：
/// - 特殊字面量大小写不敏感：inf / infinity / nan，可带一个前导符号；
///   nan/inf 经 parse_double 运行时构造——MoonBit 会把 0.0/0.0 编译期折叠成
///   负 NaN，位型与 Rust 的 +NaN 不同且会翻转 total_cmp 的排序位置
/// - 语法 `[+-]?( digits [. digits?] | . digits )( [eE] [+-]? digits )?`；
///   不收下划线/前后空白/十六进制（@string.parse_double 放宽了下划线、
///   且溢出报错而非饱和，故不能直接委托）
/// - 溢出饱和为 ±inf：按调整后十进制指数 E（value ∈ [10^E, 10^(E+1))）分流——
///   E ≤ 307 必有限，直接委托 parse_double；E ≥ 309 必溢出取 ±inf；
///   E == 308 交 parse_double 定夺（其报错阈值与舍入溢出阈值同位，
///   仅 f64::MAX 邻域半 ulp 带存在理论偏差）
/// - 下溢同 parse_double 饱和为 ±0；零值保留符号（"-0.0" → -0.0）
pub fn parse_f64(s : StringView) -> Result[Double, Unit] {
  let n = s.length()
  if n == 0 {
    return Err(())
  }
  let neg = s[0] == 45 // '-'
  let mut i = 0
  if s[0] == 43 || s[0] == 45 { // '+' '-'
    i = 1
  }
  // 特殊字面量（大小写不敏感）：infinity / inf / nan
  if i < n && eq_lower_ascii(s, i, "infinity") {
    return Ok(f64_inf(neg))
  }
  if i < n && eq_lower_ascii(s, i, "inf") {
    return Ok(f64_inf(neg))
  }
  if i < n && eq_lower_ascii(s, i, "nan") {
    return Ok(f64_nan())
  }
  // 尾数：整数段 [. 小数段]
  let int_start = i
  while i < n && s[i] >= 48 && s[i] <= 57 {
    i += 1
  }
  let int_digits = i - int_start
  let mut frac_digits = 0
  let mut frac_start = 0
  if i < n && s[i] == 46 { // '.'
    i += 1
    frac_start = i
    while i < n && s[i] >= 48 && s[i] <= 57 {
      i += 1
    }
    frac_digits = i - frac_start
  }
  if int_digits + frac_digits == 0 {
    return Err(()) // "+"/"-"/"."/"e5" 等无数字
  }
  // 指数（悬空指数报错；超长指数饱和累计防 Int 溢出，阈值仅需 309）
  let mut exp = 0
  if i < n && (s[i] == 101 || s[i] == 69) { // e E
    i += 1
    let mut exp_sign = 1
    if i < n && (s[i] == 43 || s[i] == 45) {
      if s[i] == 45 {
        exp_sign = -1
      }
      i += 1
    }
    let exp_start = i
    while i < n && s[i] >= 48 && s[i] <= 57 {
      i += 1
    }
    if i == exp_start {
      return Err(())
    }
    let mut v = 0
    for j in exp_start..<i {
      if v <= 100000 {
        v = v * 10 + (s[j].to_int() - 48)
      }
    }
    exp = exp_sign * v
  }
  if i != n {
    return Err(()) // 尾随杂质（下划线/空格/非法字母）
  }
  // 调整后十进制指数：首个非零位定位（整数段起 / 小数段起）
  let mut found = false
  let mut adj_exp = 0
  for k in 0..<int_digits {
    if s[int_start + k] != 48 {
      adj_exp = int_digits - 1 - k + exp
      found = true
      break
    }
  }
  if !found {
    for j in 0..<frac_digits {
      if s[frac_start + j] != 48 {
        adj_exp = exp - j - 1
        found = true
        break
      }
    }
  }
  if !found {
    // 全零：保留符号（Rust "-0.0".parse() → -0.0）
    return Ok(if neg { -0.0 } else { 0.0 })
  }
  if adj_exp >= 309 {
    return Ok(f64_inf(neg))
  }
  if adj_exp <= 307 {
    let v = @string.parse_double(s) catch { _ => return Err(()) }
    return Ok(v)
  }
  // adj_exp == 308：有限与溢出的分界带
  let v = @string.parse_double(s) catch { _ => return Ok(f64_inf(neg)) }
  Ok(v)
}

///|
/// ±inf 运行时构造（位型对齐 Rust；1.0/0.0 折叠值符号已实测正确，
/// 这里统一走 parse_double 消除对折叠行为的依赖）
fn f64_inf(neg : Bool) -> Double {
  let p = @string.parse_double("inf") catch { _ => 1.0 / 0.0 }
  if neg {
    -p
  } else {
    p
  }
}

///|
/// +NaN 运行时构造：0.0/0.0 会被编译期折叠成负 NaN（totalOrder 最小值，
/// 排序位置翻转），必须走 parse_double 拿 Rust 同款正 NaN
fn f64_nan() -> Double {
  @string.parse_double("nan") catch {
    _ => 0.0 / 0.0
  }
}

///|
/// 剩余串与 ASCII 小写字面量逐码元比较（用于 inf/nan 特殊字面量）
fn eq_lower_ascii(s : StringView, from : Int, lit : String) -> Bool {
  if s.length() - from != lit.length() {
    return false
  }
  for k in 0..<lit.length() {
    let c = s[from + k].to_int()
    let lc = if c >= 65 && c <= 90 { c + 32 } else { c }
    if lc != lit[k].to_int() {
      return false
    }
  }
  true
}
