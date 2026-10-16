///|
/// Plaintext-format tests: round-trip, the byte surface, the line-level error matrix (spec docs/spec-plaintext-edit.md §3.2)

///|
test "plaintext round-trip: multiple fields survive encode/decode entry by entry (note always None)" {
  let dirs : Array[@core.Dir] = [
    {
      path: "/home/user/projects",
      rank: 3.14,
      last_accessed: 1789054423L,
      note: None,
    },
    {
      path: "/tmp/α β/中文目录",
      rank: 0.01,
      last_accessed: 1L,
      note: Some("标注"),
    },
  ]
  match @core.decode_plaintext(@core.encode_plaintext(dirs)) {
    Ok(out) => {
      @debug.assert_eq(out.length(), 2)
      @debug.assert_eq(out[0].path, "/home/user/projects")
      // the rank through the two-decimal plaintext: 3.14 stays exactly
      @debug.assert_eq(out[0].rank, 3.14)
      @debug.assert_eq(out[0].last_accessed, 1789054423L)
      @debug.assert_eq(out[1].path, "/tmp/α β/中文目录")
      @debug.assert_eq(out[1].rank, 0.01)
      @debug.assert_eq(out[1].last_accessed, 1L)
      // the note does not enter the plaintext main format (the notes.tsv side file carries it, wired at the store layer)
      @debug.assert_eq(out[1].note, None)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "the plaintext byte surface: zero padding and column order, byte for byte (matching upstream {:010}\\t{:010.2}\\t{path})" {
  let bytes = @core.encode_plaintext([
    { path: "/a/b", rank: 1.0, last_accessed: 1789054423L, note: None, },
  ])
  @debug.assert_eq(@utf8.decode(bytes), "1789054423\t0000001.00\t/a/b\n")
}

///|
test "plaintext rank clamp: 0.005 rises to the floor, 1e10 is cut to the ceiling, NaN falls back to the floor" {
  let bytes = @core.encode_plaintext([
    { path: "/lo", rank: 0.005, last_accessed: 1L, note: None, },
    { path: "/hi", rank: 10000000000.0, last_accessed: 1L, note: None, },
    {
      path: "/nan",
      rank: @core.parse_f64("nan").unwrap_or(0.0),
      last_accessed: 1L,
      note: None,
    },
  ])
  @debug.assert_eq(
    @utf8.decode(bytes),
    "0000000001\t0000000.01\t/lo\n0000000001\t9999999.99\t/hi\n0000000001\t0000000.01\t/nan\n",
  )
}

///|
/// Plaintext rank formatting: half-to-even and the correct rounding boundary (the probe was promoted 2026-09-22;
/// each double\'s exact value decides the rounding direction, so decimal intuition cannot predict it)
fn fmt_one(x : Double) -> String raise {
  let bytes = @core.encode_plaintext([
    { path: "/p", rank: x, last_accessed: 0L, note: None, },
  ])
  let s = @utf8.decode(bytes)
  let cols : Array[String] = s.split("\t").map(fn(v) { v.to_owned() }).collect()
  cols[1]
}

///|
test "plaintext rank formatting: a binary-inexact half boundary rounds by its exact value" {
  // 2.675\'s exact value is 2.6749999...8 -> rounds down to 2.67 (the classic trap: a x100 binary multiply flips it)
  @debug.assert_eq(fmt_one(2.675), "0000002.67")
  // 999.995\'s exact value is 999.995000...00104 -> rounds up to 1000.00 (the opposite direction from 2.675)
  @debug.assert_eq(fmt_one(999.995), "0001000.00")
  // 0.005\'s exact value is slightly above the half boundary -> 0.01
  @debug.assert_eq(fmt_one(0.005), "0000000.01")
}

///|
test "plaintext rank formatting: a binary-exact half boundary rounds to even" {
  @debug.assert_eq(fmt_one(1.125), "0000001.12") // 112 is even -> round down
  @debug.assert_eq(fmt_one(1.375), "0000001.38") // 137 is odd -> round up
  @debug.assert_eq(fmt_one(0.125), "0000000.12")
  @debug.assert_eq(fmt_one(0.375), "0000000.38")
}

///|
test "plaintext decode: an empty file and pure newlines both give an empty database" {
  match @core.decode_plaintext(@utf8.encode("")) {
    Ok(dirs) => @debug.assert_eq(dirs.length(), 0)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  match @core.decode_plaintext(@utf8.encode("\n\n")) {
    Ok(dirs) => @debug.assert_eq(dirs.length(), 0)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "plaintext decode: CRLF tolerated, mid-line whitespace as multiple separators, a path\'s leading whitespace stripped (upstream semantics)" {
  // CRLF: a trailing \r is stripped
  match
    @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t/a\r\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // multiple whitespace separators (upstream split_once(char::is_whitespace) semantics)
  match
    @core.decode_plaintext(@utf8.encode("1789054423  \t00000001.00\t/a b\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a b")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // the path\'s leading whitespace is stripped (upstream path.trim_start(); a round trip loses leading whitespace)
  match
    @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t  /a\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "plaintext decode: the line-level error matrix (wording matching upstream)" {
  // a missing column
  match @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\n")) {
    Err(e) =>
      @debug.assert_eq(e.lines, ["line 1: expected: <timestamp> <rank> <path>"])
    Ok(_) => fail("expected error")
  }
  // a garbage timestamp / a garbage rank / a NaN rank
  match @core.decode_plaintext(@utf8.encode("xx\t00000001.00\t/a\n")) {
    Err(e) =>
      @debug.assert_eq(e.lines, ["line 1: could not parse timestamp: xx"])
    Ok(_) => fail("expected error")
  }
  match @core.decode_plaintext(@utf8.encode("1789054423\txx\t/a\n")) {
    Err(e) => @debug.assert_eq(e.lines, ["line 1: could not parse rank: xx"])
    Ok(_) => fail("expected error")
  }
  match @core.decode_plaintext(@utf8.encode("1789054423\tnan\t/a\n")) {
    Err(e) => @debug.assert_eq(e.lines, ["line 1: could not parse rank: nan"])
    Ok(_) => fail("expected error")
  }
  // inf is accepted and clamped to the ceiling (upstream parse::<Rank> accepts the inf literal too)
  match @core.decode_plaintext(@utf8.encode("1789054423\tinf\t/a\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].rank, 9999999.99)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // an empty path (three fields, but the third is whitespace)
  match @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t  \n")) {
    Err(e) =>
      @debug.assert_eq(e.lines, ["line 1: expected: <timestamp> <rank> <path>"])
    Ok(_) => fail("expected error")
  }
}

///|
test "plaintext decode: invalid UTF-8 reports its line number; beyond 8 errors the aggregate folds to ... and N more" {
  // an invalid UTF-8 byte, 0xFF
  let bad = b"1789054423\t00000001.00\t/\xff\n"
  match @core.decode_plaintext(bad) {
    Err(e) => @debug.assert_eq(e.lines, ["line 1: invalid UTF-8"])
    Ok(_) => fail("expected error")
  }
  // 10 bad rows -> the first 8 plus "... and 2 more"
  let sb = StringBuilder()
  for i in 0..<10 {
    sb.write_string("badline\{i}\n")
  }
  match @core.decode_plaintext(@utf8.encode(sb.to_string())) {
    Err(e) => {
      @debug.assert_eq(e.lines.length(), 9)
      @debug.assert_eq(
        e.lines[0],
        "line 1: expected: <timestamp> <rank> <path>",
      )
      @debug.assert_eq(
        e.lines[7],
        "line 8: expected: <timestamp> <rank> <path>",
      )
      @debug.assert_eq(e.lines[8], "... and 2 more")
    }
    Ok(_) => fail("expected error")
  }
}

///|
/// Boundary catch-up (the blind spots coverage listed on 2026-09-25): the pad10 negative path, empty-path skipping,
/// the parse_i64 branch matrix, multi-line error aggregation, and leading whitespace
test "plaintext encode: pad10 for a negative last_accessed (-1 zero-padded, i64::MIN left over-wide)" {
  let dirs : Array[@core.Dir] = [
    { path: "/a", rank: 1.0, last_accessed: -1L, note: None, },
    { path: "/b", rank: 1.0, last_accessed: -9223372036854775808L, note: None, },
  ]
  let text = @core.encode_plaintext(dirs)
  // -1 -> "-000000001" (the sign first, zero padding after); MIN\'s 20 digits stay over-wide and are not truncated
  inspect(
    @utf8.decode(text).contains("-0000000001\t0000001.00\t/a"),
    content="true",
  )
  inspect(
    @utf8.decode(text).contains("-9223372036854775808\t0000001.00\t/b"),
    content="true",
  )
  // a round trip on a negative epoch (the other half of the atuin dataset\'s epoch=-1 boundary row)
  match @core.decode_plaintext(text) {
    Ok(out) => {
      @debug.assert_eq(out[0].last_accessed, -1L)
      @debug.assert_eq(out[1].last_accessed, -9223372036854775808L)
    }
    Err(e) => fail("\{e.message()}")
  }
}

///|
test "plaintext encode: an empty-path entry is skipped (the plaintext line format cannot express it; the migration\'s rescue semantics)" {
  let dirs : Array[@core.Dir] = [
    { path: "", rank: 1.0, last_accessed: 0L, note: None, },
    { path: "/kept", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let text = @utf8.decode(@core.encode_plaintext(dirs))
  inspect(text.contains("/kept"), content="true")
  // an empty-path line is not written (writing one would make the database permanently unreadable)
  inspect(text.split("\n").count(), content="2")
}

///|
test "plaintext decode: the timestamp parsing branch matrix (i64::from_str semantics)" {
  // a lone sign ("+" / "-") -> could not parse timestamp
  // more than 20 digits (certain overflow) is rejected early; 2^63 past i64::MAX is rejected; -0 becomes 0; i64::MIN is accepted
  let cases : Array[(String, Result[Int64, Unit])] = [
    ("+ 00000001.00 /x", Err(())),
    ("- 00000001.00 /x", Err(())),
    ("0000000000000000000001 00000001.00 /x", Err(())),
    ("9223372036854775807 00000001.00 /x", Ok(9223372036854775807L)),
    ("9223372036854775808 00000001.00 /x", Err(())),
    ("-9223372036854775808 00000001.00 /x", Ok(-9223372036854775808L)),
    ("-0 00000001.00 /x", Ok(0L)),
    ("007 00000001.00 /x", Ok(7L)),
  ]
  for case in cases {
    let line = case.0
    let want = case.1
    match @core.decode_plaintext(@utf8.encode(line + "\n")) {
      Ok(out) =>
        match want {
          Ok(v) => @debug.assert_eq(out[0].last_accessed, v)
          Err(_) => fail("should reject: \{line}")
        }
      Err(_) =>
        match want {
          Ok(_) => fail("should accept: \{line}")
          Err(_) => ()
        }
    }
  }
}

///|
test "plaintext decode: multi-line error aggregation, newline joining and line numbers" {
  let bad = "garbage\nalso bad\n1789054423\t00000001.00\t/ok\n"
  match @core.decode_plaintext(@utf8.encode(bad)) {
    Ok(_) => fail("a bad row should make the whole database refuse to load")
    Err(e) => {
      let msg = e.message()
      // joined line by line with newlines (matching upstream errors.join("\n"))
      inspect(msg.contains("\n"), content="true")
      inspect(msg.contains("line 1:"), content="true")
      inspect(msg.contains("line 2:"), content="true")
    }
  }
}

///|
test "plaintext decode: trim_start on leading whitespace, and a trailing CR tolerated" {
  let text = "  \t1789054423\t00000001.00\t/x\r\n"
  match @core.decode_plaintext(@utf8.encode(text)) {
    Ok(out) => {
      @debug.assert_eq(out.length(), 1)
      @debug.assert_eq(out[0].path, "/x")
      @debug.assert_eq(out[0].last_accessed, 1789054423L)
    }
    Err(e) => fail("\{e.message()}")
  }
}
