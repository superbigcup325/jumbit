///|
pub(all) enum GlobError {
  UnclosedBracket
  EmptyClass
  InvalidRange
  TrailingEscape
} derive(Debug, Eq)

///|
/// 校验 glob 合法性（对齐 Rust glob crate 的构造期错误）：
/// 未闭合 `[`、空类 `[]`/`[!]`、倒序区间 `[z-a]`、以 `\` 结尾均为非法。
pub fn validate_glob(pattern : String) -> GlobError? {
  let chars = pattern.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    match chars[i] {
      '[' => {
        let mut j = i + 1
        if j < n && chars[j] == '!' {
          j += 1
        }
        if j >= n {
          return Some(UnclosedBracket)
        }
        if chars[j] == ']' {
          return Some(EmptyClass)
        }
        let mut closed = false
        while j < n {
          if chars[j] == ']' {
            closed = true
            break
          } else if j + 2 < n && chars[j + 1] == '-' && chars[j + 2] != ']' {
            if chars[j] > chars[j + 2] {
              return Some(InvalidRange)
            }
            j += 3
          } else {
            j += 1
          }
        }
        if !closed {
          return Some(UnclosedBracket)
        }
        i = j + 1
      }
      '\\' => {
        if i + 1 >= n {
          return Some(TrailingEscape)
        }
        i += 2
      }
      _ => i += 1
    }
  }
  None
}

///|
/// glob 匹配（pattern 须先过 validate_glob）。
/// 语义对齐 Rust glob Pattern：`*` 匹配零或多字符、`?` 匹配单字符，但二者与
/// `[...]` 均不匹配分隔符 `/`；`\` 转义下一字符按字面量匹配；`{a,b}` 不支持，
/// 视为字面量（与上游差异，README 注明）。
pub fn glob_match(pattern : String, path : String) -> Bool {
  glob_match_compiled(pattern.to_array(), path)
}

///|
/// pattern 编译：字符序列只做一次 to_array，供同一 pattern 反复匹配时复用
/// （查询流对全库条目逐个过 exclude glob，分配是主要开销）。
fn compile_glob(pattern : String) -> Array[Char] {
  pattern.to_array()
}

///|
/// 编译后的 glob 匹配：迭代式双指针 + 单星回溯点，布尔语义与逐字符递归的
/// 完全回溯搜索等价——星号区不吞 `/` 的约束对任意星号一致，贪心最右星
/// 回溯可探索全部可行分解。无递归、无分配（path 走 codeunit 索引）。
fn glob_match_compiled(p : Array[Char], s : String) -> Bool {
  let pn = p.length()
  let sn = s.length()
  let slash = 47 // '/'
  let mut pi = 0
  let mut si = 0
  let mut star_pi = -1
  let mut star_si = 0
  while si < sn {
    if pi < pn {
      let c = p[pi].to_int()
      if c == 42 {
        // '*'：记录回溯点，先按零消耗续配
        star_pi = pi
        star_si = si
        pi += 1
        continue
      }
      let sc = s.at(si).to_int()
      let consumed = match_single(p, pi, sc, slash)
      match consumed {
        Some(next_pi) => {
          // 单字符 token：字面量与转义可匹配 '/'，'?' 与 [...] 不匹配
          if sc == slash && c != 63 && c != 92 && !(c >= 91 && c <= 93) {
            // '/' 只被字面量/转义匹配——但单字符 token 的排除规则在
            // match_single 内已按 token 类别处理，这里无需再排除
            ()
          }
          pi = next_pi
          si += 1
          continue
        }
        None => ()
      }
    }
    if star_pi >= 0 {
      // 回溯：最近一个 `*` 多吞一个字符；`*` 不吞 `/`
      if s.at(star_si).to_int() == slash {
        return false
      }
      star_si += 1
      si = star_si
      pi = star_pi + 1
      continue
    }
    return false
  }
  while pi < pn && p[pi].to_int() == 42 {
    pi += 1
  }
  pi == pn
}

///|
/// 单字符 token 匹配（`*` 之外）：sc 为 s[si] 的 codeunit 值，返回 pattern
/// 侧推进位置；不匹配返回 None。token 语义与原递归版逐条对应：`?` 与
/// `[...]` 不匹配 `/`（由 slash 参数判定），`\x` 按字面量（含 '/'）。
fn match_single(p : Array[Char], pi : Int, sc : Int, slash : Int) -> Int? {
  let pn = p.length()
  let c = p[pi].to_int()
  if c == 63 {
    // '?'
    if sc != slash {
      Some(pi + 1)
    } else {
      None
    }
  } else if c == 91 {
    // '['
    if sc == slash {
      return None
    }
    let mut j = pi + 1
    let mut negated = false
    if j < pn && p[j].to_int() == 33 {
      // '!'
      negated = true
      j += 1
    }
    let mut matched = false
    while j < pn && p[j].to_int() != 93 {
      // ']'
      if j + 2 < pn && p[j + 1].to_int() == 45 && p[j + 2].to_int() != 93 {
        // '-'
        if sc >= p[j].to_int() && sc <= p[j + 2].to_int() {
          matched = true
        }
        j += 3
      } else {
        if sc == p[j].to_int() {
          matched = true
        }
        j += 1
      }
    }
    if matched == negated {
      None
    } else {
      Some(j + 1)
    }
  } else if c == 92 {
    // '\\'
    if pi + 1 < pn && sc == p[pi + 1].to_int() {
      Some(pi + 2)
    } else {
      None
    }
  } else if sc == c {
    Some(pi + 1)
  } else {
    None
  }
}

///|
/// 校验 + 匹配一步到位（exclude 配置入口用）
pub fn glob_matches(pattern : String, path : String) -> Result[Bool, GlobError] {
  match validate_glob(pattern) {
    Some(e) => Err(e)
    None => Ok(glob_match(pattern, path))
  }
}
