# `core`

jumbit's pure-function core: path resolution, glob matching, keyword filtering,
float parsing, and database encoding. This file is also the docstring-test
carrier: the ` ```mbt check ` blocks are compiled into the test suite
(`moon test`), so the examples are the cases.

## Path resolution

`resolve_path` makes a relative path absolute against a base (the current
directory) and resolves `.` and `..`; it does not resolve symlinks (matching
upstream zoxide's `util::resolve_path`). Separator semantics are dispatched at
compile time per target platform (POSIX uses `/`; Windows uses the win32
drive-letter and double-separator component model).

```mbt check
///|
// POSIX-shape assertions (the win32 implementation emits backslashes and differs
// on base semantics, so each platform is tested separately)
#cfg(not(platform="windows"))
test "resolve_path absolutises and normalises dot segments" {
  // a relative path is joined onto the base
  inspect(@core.resolve_path("a/b", "/x/y"), content="/x/y/a/b")
  // `..` and `.` are eliminated while normalising
  inspect(@core.resolve_path("../a", "/x/y"), content="/x/a")
  inspect(@core.resolve_path("/a/./b", "/"), content="/a/b")
  // `..` past the root stops at the root
  inspect(@core.resolve_path("/../../a", "/"), content="/a")
}
```

`starts_with` is a component-level prefix test (matching
`std::path::Path::starts_with`): a string prefix does not count, components are
compared one by one.

```mbt check
///|
test "starts_with is component-level" {
  inspect(@core.starts_with("/foo/bar/baz", "/foo/bar"), content="true")
  // a string prefix is not a component prefix
  inspect(@core.starts_with("/foo/ba", "/foo/bar"), content="false")
}
```

## Glob matching

`*` / `**` cross path separators; `?` / `[...]` / `[!...]` match any single
character (separators included), matching the upstream glob crate's default
MatchOptions (require_literal_separator=false). `\` escapes. Brace expansion
`{a,b}` is not supported (a settled difference from the upstream glob crate).
Validate an untrusted pattern up front with `validate_glob`; `glob_matches`
returns a `Result`, while `glob_match` is the fast path for already-validated
patterns.

```mbt check
///|
test "glob crosses separators; invalid pattern" {
  // `*` crosses components (the glob crate's default: `*` matches any sequence,
  // separators included)
  inspect(@core.glob_match("/usr/*", "/usr/local"), content="true")
  inspect(@core.glob_match("/usr/*", "/usr/local/bin"), content="true")
  // an unterminated character class is an error (`{a,b}` is a valid pattern,
  // treated literally and not expanded)
  inspect(@core.validate_glob("/usr/[ab") is Some(_), content="true")
  // validate and match in one step
  inspect(
    @core.glob_matches("/usr/lo*al", "/usr/local") is Ok(true),
    content="true",
  )
}
```

## Keyword filtering

`filter_by_keywords` implements upstream zoxide's keyword semantics: the last
keyword must land in the path's final component, and the earlier ones are
consumed right-to-left without overlapping. Case folding is ASCII-only (a settled
difference from upstream). `filter_by_keywords_fuzzy` is the fallback when an
exact pass finds nothing: a row matches when each keyword is a substring of some
path component.

```mbt check
///|
test "keyword anchoring on the final component, and the fuzzy fallback" {
  // the last keyword anchors the final component; the rest are consumed right-to-left
  inspect(
    @core.filter_by_keywords(["user", "work"], "/home/user/work"),
    content="true",
  )
  // reversed order misses (work is not in the final component)
  inspect(
    @core.filter_by_keywords(["work", "user"], "/home/user/work"),
    content="false",
  )
  // fuzzy: `ork` is a substring of `work` so it matches, with no anchoring on the
  // final component (substring matching, not abbreviation)
  inspect(
    @core.filter_by_keywords_fuzzy(["ork"], "/home/user/work"),
    content="true",
  )
}
```

## Float parsing

`parse_f64` matches Rust's `f64::from_str` semantics (the foundation of jumbit's
byte-for-byte alignment with upstream): scientific notation and the `inf`/`nan`
literals are accepted, overflow saturates to infinity, and invalid strings are
rejected.

```mbt check
///|
test "parse_f64 matches Rust from_str" {
  match @core.parse_f64("3.5") {
    Ok(v) => inspect(v, content="3.5")
    Err(_) => fail("3.5 should parse")
  }
  // overflow saturates to infinity (Rust semantics)
  match @core.parse_f64("1e309") {
    Ok(v) => inspect(v.is_inf(), content="true")
    Err(_) => fail("1e309 should saturate to inf")
  }
  // invalid strings are rejected
  inspect(@core.parse_f64("abc") is Err(_), content="true")
}
```

## Database encoding

Line encoding and decoding for the plaintext `db.txt` format: each line is
`timestamp\trank\tpath`; human annotations live in the side file `notes.tsv` and
never enter the main format. A bad line makes the whole database decode fail with
a line number (see `PlaintextError`).

```mbt check
///|
test "plaintext encode/decode round-trip" {
  let dirs = [
    @core.Dir::{
      path: "/home/user/work",
      rank: 3.0,
      last_accessed: 0L,
      note: None,
    },
  ]
  let bytes = @core.encode_plaintext(dirs)
  match @core.decode_plaintext(bytes) {
    Ok(decoded) => {
      inspect(decoded[0].path, content="/home/user/work")
      inspect(decoded[0].rank == 3.0, content="true")
    }
    Err(_) => fail("decode_plaintext should not fail")
  }
}
```
