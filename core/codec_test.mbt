// Codec tests: round-trip plus malformed-data rejection

///|
test "roundtrip: an empty database is just the 4-byte version header" {
  let bytes = @core.encode([])
  @debug.assert_eq(bytes.length(), 4)
  match @core.decode(bytes) {
    Ok(dirs) => @debug.assert_eq(dirs.length(), 0)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip: a single ASCII path, with the rank preserved exactly bit for bit" {
  let db = @core.Database::new()
  db.add("/home/user/projects", 3.1400001, 1725561600L)
  match @core.decode(@core.encode(db.all())) {
    Ok(dirs) => {
      @debug.assert_eq(dirs.length(), 1)
      @debug.assert_eq(dirs[0].path, "/home/user/projects")
      @debug.assert_eq(dirs[0].rank, 3.1400001)
      @debug.assert_eq(dirs[0].last_accessed, 1725561600L)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip: a Unicode path" {
  let dirs = [
    @core.Dir::{
      path: "/home/用户/下载/图片",
      rank: 1.5,
      last_accessed: 42L,
      note: None,
    },
  ]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => @debug.assert_eq(out[0].path, "/home/用户/下载/图片")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip: an overlong path (10000 characters)" {
  let long = "/" + "a".repeat(9999)
  let dirs = [
    @core.Dir::{ path: long, rank: 1.0, last_accessed: 0L, note: None, },
  ]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => @debug.assert_eq(out[0].path, long)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "an empty file -> CorruptedData" {
  match @core.decode(Bytes::make(0, 0)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "truncated in the path-length header -> CorruptedData" {
  let dirs = [
    @core.Dir::{ path: "/foo/bar", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let bytes = @core.encode(dirs).to_array()[0:6] // 4 version bytes + 2 length-header bytes
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "truncated in the middle of rank -> CorruptedData" {
  let dirs = [
    @core.Dir::{ path: "/foo", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let bytes = @core.encode(dirs).to_array()[0:16] // 4 version + 4 length + 4 path + half of rank
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "a wrong version number -> UnsupportedVersion" {
  let dirs = [
    @core.Dir::{ path: "/foo", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let bytes = @core.encode(dirs).to_array()
  bytes[0] = (999).to_byte() // the first little-endian byte = the low 8 bits
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.UnsupportedVersion(v)) => @debug.assert_eq(v % 256, 999 % 256)
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "a forged overlong path length -> CorruptedData" {
  let buf : Array[Byte] = []
  buf.push((1).to_byte()) // the first LE byte of version 1
  buf.push(0)
  buf.push(0)
  buf.push(0)
  buf.push((255).to_byte()) // plen = 0xFFFFFFFF
  buf.push((255).to_byte())
  buf.push((255).to_byte())
  buf.push((255).to_byte())
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "past the 32MiB cap -> TooLarge (the length check runs before the version check)" {
  let bytes = Bytes::make(@core.MAX_SIZE + 5, 0)
  match @core.decode(bytes) {
    Err(@core.TooLarge) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "an invalid UTF-8 path -> CorruptedData" {
  // version 1 + plen=2 + two illegal continuation bytes (0x80 0x80 with no lead byte)
  let buf : Array[Byte] = [1, 0, 0, 0, 2, 0, 0, 0, 128, 128].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "exactly 32MiB: the size check passes and the version check runs" {
  let bytes = Bytes::make(@core.MAX_SIZE, 0)
  match @core.decode(bytes) {
    // all-zero bytes give version 0 != 1, showing the size check let it through and the version check fired
    Err(@core.UnsupportedVersion(0)) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "an empty-path entry (path_len=0) decodes legally" {
  let buf : Array[Byte] = [
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ].map(fn(i) { i.to_byte() })
  match @core.decode(Bytes::from_array(buf)) {
    Ok(dirs) => {
      @debug.assert_eq(dirs.length(), 1)
      @debug.assert_eq(dirs[0].path, "")
      @debug.assert_eq(dirs[0].rank, 0.0)
      @debug.assert_eq(dirs[0].last_accessed, 0L)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip: special floats and boundary timestamps stay bit-exact" {
  let dirs = [
    // NaN: the one place a rank f64 is not bit-reflexive (NaN != NaN)
    @core.Dir::{
      path: "/nan",
      rank: 0.0 / 0.0,
      last_accessed: -5L,
      note: None,
    },
    // ±inf and the Int64 boundaries
    @core.Dir::{
      path: "/inf",
      rank: 1.0 / 0.0,
      last_accessed: -1L,
      note: None,
    },
    @core.Dir::{
      path: "/ninf",
      rank: -1.0 / 0.0,
      last_accessed: 9223372036854775807L,
      note: None,
    },
  ]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => {
      @debug.assert_eq(out[0].rank != out[0].rank, true) // NaN
      @debug.assert_eq(out[0].last_accessed, -5L)
      @debug.assert_eq(out[1].rank, 1.0 / 0.0)
      @debug.assert_eq(out[1].last_accessed, -1L)
      @debug.assert_eq(out[2].rank, -1.0 / 0.0)
      @debug.assert_eq(out[2].last_accessed, 9223372036854775807L)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "a path containing a NUL byte -> CorruptedData" {
  // version 1 + plen=3 + "a\x00b" (a NUL inside the path)
  let buf : Array[Byte] = [1, 0, 0, 0, 3, 0, 0, 0, 97, 0, 98].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "a path containing a newline byte -> CorruptedData" {
  // version 1 + plen=2 + 0x0A 0x0D
  let buf : Array[Byte] = [1, 0, 0, 0, 2, 0, 0, 0, 10, 13].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "v2 round-trip: both note Some and None survive" {
  let dirs = [
    @core.Dir::{
      path: "/a",
      rank: 1.0,
      last_accessed: 5L,
      note: Some("后端项目"),
    },
    @core.Dir::{ path: "/b", rank: 2.0, last_accessed: 6L, note: None, },
  ]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => {
      @debug.assert_eq(out.length(), 2)
      @debug.assert_eq(out[0].note, Some("后端项目"))
      @debug.assert_eq(out[1].note, None)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "v1 compatible read: an old-format entry reads its note as None" {
  // a v2 entry is a v1 entry plus a 4-byte note header; lowering the version and cutting the note header gives legal v1 bytes
  let dirs = [
    @core.Dir::{ path: "/legacy", rank: 1.5, last_accessed: 42L, note: None, },
  ]
  let bytes = @core.encode(dirs).to_array()
  bytes[0] = (1).to_byte()
  let v1 = Bytes::from_array(bytes[:bytes.length() - 4])
  match @core.decode(v1) {
    Ok(out) => {
      @debug.assert_eq(out.length(), 1)
      @debug.assert_eq(out[0].path, "/legacy")
      @debug.assert_eq(out[0].rank, 1.5)
      @debug.assert_eq(out[0].last_accessed, 42L)
      @debug.assert_eq(out[0].note, None)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "an illegal v2 note length -> CorruptedData (negative / out of range)" {
  let dirs = [
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  // the last 4 bytes are the note length: 0xFFFFFFFF (read as a negative signed value) -> rejected
  let neg = @core.encode(dirs).to_array()
  for i in (neg.length() - 4)..<neg.length() {
    neg[i] = (255).to_byte()
  }
  match @core.decode(Bytes::from_array(neg)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
  // a length past the remaining bytes -> rejected
  let over = @core.encode(dirs).to_array()
  over[over.length() - 1] = (100).to_byte()
  match @core.decode(Bytes::from_array(over)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "bad UTF-8 in a v2 note -> CorruptedData" {
  let dirs = [
    @core.Dir::{ path: "/a", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  // the note length set to 1 with content 0xFF (an illegal UTF-8 start)
  let bad = @core.encode(dirs).to_array()
  bad[bad.length() - 4] = (1).to_byte()
  bad[bad.length() - 1] = (255).to_byte()
  match @core.decode(Bytes::from_array(bad)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}
