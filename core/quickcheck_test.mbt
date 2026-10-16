// Property tests (core @quickcheck): their division of labour against unit tests and goldens is pinning semantic invariants
// (random input plus failure shrinking), not piling on byte assertions. The seed is fixed so CI can reproduce; A=UInt64 is injected
// into chacha8 as the "data seed" and each property builds its own random input (the landing of the roadmap line item
// "evaluate bringing quickcheck into the test surface")

///|
fn qc_seed_bytes(s : UInt64) -> Bytes {
  // the chacha8 seed is a fixed 32 bytes: the decimal form plus fixed padding out to 32 (ASCII is always 32 bytes;
  // String::to_bytes is deprecated, so @encoding/utf8.encode is used)
  let base = s.to_string()
  let filler = "0123456789abcdefghij0123456789abcdefghij"
  @utf8.encode(base + filler[0:32 - base.length()].to_owned())
}

///|
test "property: the plaintext codec round-trip invariant" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      let dirs : Array[@core.Dir] = []
      for i in 0..<rand.int(limit=20) {
        dirs.push({
          path: "/home/user/\{rand.int(limit=64)}/dir-\{i}",
          // generated inside the two-decimal domain (plaintext ranks come out with two decimals, so an in-domain round trip must be exact)
          rank: rand.int(limit=1000000).to_double() / 100.0,
          last_accessed: rand.int(limit=100000).to_int64(),
          note: None,
        })
      }
      match @core.decode_plaintext(@core.encode_plaintext(dirs)) {
        Ok(out) => {
          let mut ok = out.length() == dirs.length()
          if ok {
            for i in 0..<dirs.length() {
              if out[i].path != dirs[i].path ||
                out[i].rank != dirs[i].rank ||
                out[i].last_accessed != dirs[i].last_accessed {
                ok = false
              }
            }
          }
          ok
        }
        Err(_) => false
      }
    },
    count=200U,
    seed=20260925UL,
  )
}

///|
test "property: a glob star crosses separators (matching the glob crate default require_literal_separator=false)" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      // a separator-free pattern: letters + `*` + `?` (always valid, avoiding an unterminated `[`)
      let alphabet = "abcxy*?".to_array()
      let n = 1 + rand.int(limit=8)
      let buf = StringBuilder()
      let mut has_wild = false
      for _ in 0..<n {
        let ch = alphabet[rand.int(limit=7)]
        if ch == '*' || ch == '?' {
          has_wild = true
        }
        buf.write_char(ch)
      }
      let pattern = buf.to_string()
      // a control: the pattern always matches itself (guarding against a vacuous always-false property)
      @core.glob_match(pattern, pattern) &&
      // with leading and trailing stars, a wildcard pattern must match a multi-component path across separators
      (!has_wild || @core.glob_match("*" + pattern + "*", "/" + pattern + "/x")) &&
      // a pure literal pattern (no wildcards) still cannot match a multi-component path across a separator
      (has_wild || !@core.glob_match(pattern, "/" + pattern + "/x"))
    },
    count=200U,
    seed=20260925UL,
  )
}

///|
test "property: resolve_path is idempotent" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      let segs = ["a", "b", "c", "..", "."]
      let n = rand.int(limit=6)
      let buf = StringBuilder()
      for _ in 0..<n {
        buf.write_string(segs[rand.int(limit=5)])
        buf.write_string("/")
      }
      let mut path = buf.to_string()
      if rand.int(limit=2) == 0 {
        path = "/" + path
      }
      let base = ["/x/y", "/", "/x"][rand.int(limit=3)]
      let once = @core.resolve_path(path, base)
      // a second normalization is the identity (the fixed point after .. past the root and dot segments are removed)
      @core.resolve_path(once, base) == once
    },
    count=200U,
    seed=20260925UL,
  )
}
