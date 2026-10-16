///|
pub(all) enum GlobError {
  UnclosedBracket
  EmptyClass
  InvalidRange
  TrailingEscape
} derive(Debug, Eq)

///|
/// Validate a glob (matching the Rust glob crate\'s construction-time errors):
/// an unterminated `[`, an empty class `[]`/`[!]`, a reversed range `[z-a]` and a trailing `\` are all illegal.
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
/// Glob matching (the pattern must have passed validate_glob first).
/// Semantics match the Rust glob crate\'s default MatchOptions (require_literal_separator=false, which is what
/// upstream _ZO_EXCLUDE_DIRS uses): `*` and `**` cross separators matching any sequence,
/// `?` matches any single character including separators, as does `[...]`; `\` escapes the next character into a literal match;
/// `{a,b}` is unsupported and treated literally (a difference from upstream, noted in the README).
pub fn glob_match(pattern : String, path : String) -> Bool {
  glob_match_compiled(pattern.to_array(), path)
}

///|
/// Pattern compilation: the character sequence is turned into an array once, reused across repeated matches of the same pattern
/// (the query flow runs every entry in the database through the exclude globs, so allocation is the main cost).
fn compile_glob(pattern : String) -> Array[Char] {
  pattern.to_array()
}

///|
/// Matching a compiled glob: an iterative two-pointer walk with a single-star backtrack point, whose boolean semantics equal a
/// per-character full-backtracking search -- a star may swallow any character (separators included, the glob crate\'s default), and
/// greedy backtracking to the rightmost star explores every feasible split. No recursion, no allocation (the path is indexed by code unit).
fn glob_match_compiled(p : Array[Char], s : String) -> Bool {
  let pn = p.length()
  let sn = s.length()
  let mut pi = 0
  let mut si = 0
  let mut star_pi = -1
  let mut star_si = 0
  while si < sn {
    if pi < pn {
      let c = p[pi].to_int()
      if c == 42 {
        // '*': record the backtrack point, then continue matching with zero consumption
        star_pi = pi
        star_si = si
        pi += 1
        continue
      }
      let sc = s.at(si).to_int()
      let consumed = match_single(p, pi, sc)
      if consumed is Some(next_pi) {
        pi = next_pi
        si += 1
        continue
      }
    }
    if star_pi >= 0 {
      // backtrack: the most recent `*` swallows one more character (any character, separators included)
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
/// Single-character token matching (everything but `*`): sc is the code-unit value of s[si]; returns the pattern\'s
/// advance position, or None on no match. Token semantics match the glob crate\'s default options:
/// `?` and `[...]` match any single character including separators; `\x` is the literal (separators included);
/// a literal token matches equivalent separators on the path side under Windows
fn match_single(p : Array[Char], pi : Int32, sc : Int32) -> Int32? {
  let pn = p.length()
  let c = p[pi].to_int()
  if c == 63 {
    // '?'
    Some(pi + 1)
  } else if c == 91 {
    // '['
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
  } else if sc == c || literal_sep_equiv(sc, c) {
    Some(pi + 1)
  } else {
    None
  }
}

///|
/// Validate and match in one step (for the exclude-config entry point)
pub fn glob_matches(pattern : String, path : String) -> Result[Bool, GlobError] {
  match validate_glob(pattern) {
    Some(e) => Err(e)
    None => Ok(glob_match(pattern, path))
  }
}
