///|
/// An ASCII uppercase pre-scan: to_lower normalizes ASCII only (see the note on filter_by_keywords), so
/// a path with no ASCII uppercase skips the lowercase allocation. Non-ASCII bytes are untouched either way, so the outcome is strictly equivalent
fn has_ascii_upper(s : String) -> Bool {
  for i in 0..<s.length() {
    let c = s[i]
    if c >= 65 && c <= 90 {
      return true
    }
  }
  false
}

///|
/// Lowercase normalization of a path (equivalent to normalize_separators(path.to_lower()); with no ASCII uppercase
/// it allocates nothing): the main allocation source on query's per-entry hot path; the '\\' normalization is counted separately
/// (normalize_separators decides internally, and a path with no backslash also avoids the allocation)
fn path_lower(path : String) -> String {
  if has_ascii_upper(path) {
    normalize_separators(path.to_lower())
  } else {
    normalize_separators(path)
  }
}

///|
/// Pre-lowercase the keywords (once): the caller (stream, once per query) normalizes the keyword array first, so
/// per-entry matching never allocates again
fn keywords_lower(keywords : Array[String]) -> Array[String] {
  // all-lowercase (the most common shape) returns the original array with zero allocation: to_lower normalizes ASCII only,
  // so with no ASCII uppercase the keywords need no change, and non-ASCII uppercase is left alone either way
  for kw in keywords {
    if has_ascii_upper(kw) {
      let out : Array[String] = []
      for kw in keywords {
        out.push(kw.to_lower())
      }
      return out
    }
  }
  keywords
}

///|
/// Keyword matching (matching upstream src/db/stream.rs filter_by_keywords):
/// 1. the keywords and the path are case-normalized first (`to_lower` is ASCII only; upstream folds the full Unicode
///    range, so full-width and Cyrillic are not folded here -- a known difference, noted in the README)
/// 2. the last keyword takes its **rightmost** hit, and no separator may appear between that hit and the end of the path
///    (final-component anchoring)
/// 3. the earlier keywords are consumed right-to-left, one by one, without overlapping hit ranges
/// An empty keyword array is always true.
pub fn filter_by_keywords(keywords : Array[String], path : String) -> Bool {
  if keywords.is_empty() {
    return true
  }
  filter_by_keywords_lower(keywords_lower(keywords), path_lower(path))
}

///|
/// The matching core: keywords and path are already lowercase-normalized. The per-entry hot path is called by the stream
/// layer after pre-normalizing the keywords, and this body allocates nothing
fn filter_by_keywords_lower(keywords : Array[String], path : String) -> Bool {
  if keywords.is_empty() {
    return true
  }
  let last = keywords[keywords.length() - 1]
  let mut limit = match path.rev_find(last) {
    Some(idx) => {
      if path[idx + last.length():].find("/") is Some(_) {
        return false
      }
      idx
    }
    None => return false
  }
  for i in (keywords.length() - 1)>..0 {
    match path[0:limit].rev_find(keywords[i]) {
      Some(idx) => limit = idx
      None => return false
    }
  }
  true
}

///|
/// Fuzzy keyword matching (a jumbit extension with no upstream equivalent; noted in the README):
/// every keyword (ASCII-lowercase normalized, as in filter_by_keywords) must hit at least one
/// path component as a substring to pass -- no final-component anchoring, order-free, and the same component may be reused.
/// Only the exact-miss fallback for `query --fuzzy`, never default semantics; an empty array is always true.
pub fn filter_by_keywords_fuzzy(
  keywords : Array[String],
  path : String,
) -> Bool {
  if keywords.is_empty() {
    return true
  }
  let lower = path_lower(path)
  for kw in keywords_lower(keywords) {
    let mut hit = false
    for comp in lower.split("/") {
      if comp.find(kw) is Some(_) {
        hit = true
        break
      }
    }
    if !hit {
      return false
    }
  }
  true
}
