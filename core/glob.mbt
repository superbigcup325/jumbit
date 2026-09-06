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
  match_from(pattern.to_array(), 0, path.to_array(), 0)
}

///|
/// 校验 + 匹配一步到位（exclude 配置入口用）
pub fn glob_matches(pattern : String, path : String) -> Result[Bool, GlobError] {
  match validate_glob(pattern) {
    Some(e) => Err(e)
    None => Ok(glob_match(pattern, path))
  }
}

///|
fn match_from(p : Array[Char], pi : Int, s : Array[Char], si : Int) -> Bool {
  let pn = p.length()
  let sn = s.length()
  if pi == pn {
    return si == sn
  }
  match p[pi] {
    '*' => match_star(p, pi + 1, s, si)
    '?' => si < sn && s[si] != '/' && match_from(p, pi + 1, s, si + 1)
    '[' => {
      if si >= sn || s[si] == '/' {
        return false
      }
      let mut j = pi + 1
      let mut negated = false
      if p[j] == '!' {
        negated = true
        j += 1
      }
      let mut matched = false
      while p[j] != ']' {
        if j + 2 < pn && p[j + 1] == '-' && p[j + 2] != ']' {
          if s[si] >= p[j] && s[si] <= p[j + 2] {
            matched = true
          }
          j += 3
        } else {
          if s[si] == p[j] {
            matched = true
          }
          j += 1
        }
      }
      if matched == negated {
        return false
      }
      match_from(p, j + 1, s, si + 1)
    }
    '\\' => si < sn && s[si] == p[pi + 1] && match_from(p, pi + 2, s, si + 1)
    c => si < sn && s[si] == c && match_from(p, pi + 1, s, si + 1)
  }
}

///|
/// `*` 的展开：从 si 起尝试零/一/多字符消耗，遇到 `/` 停止
fn match_star(p : Array[Char], pi : Int, s : Array[Char], si : Int) -> Bool {
  if match_from(p, pi, s, si) {
    return true
  }
  if si >= s.length() || s[si] == '/' {
    return false
  }
  match_star(p, pi, s, si + 1)
}
