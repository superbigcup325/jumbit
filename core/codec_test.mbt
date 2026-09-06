// 编解码测试：roundtrip + 畸形数据拒绝

///|
test "roundtrip：空库只有 4 字节版本头" {
  let bytes = @core.encode([])
  @debug.assert_eq(bytes.length(), 4)
  match @core.decode(bytes) {
    Ok(dirs) => @debug.assert_eq(dirs.length(), 0)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip：单条 ASCII 路径，rank 按 bit 精确保真" {
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
test "roundtrip：Unicode 路径" {
  let dirs = [
    @core.Dir::{
      path: "/home/用户/下载/图片",
      rank: 1.5,
      last_accessed: 42L,
    },
  ]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => @debug.assert_eq(out[0].path, "/home/用户/下载/图片")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "roundtrip：超长路径（10000 字符）" {
  let long = "/" + "a".repeat(9999)
  let dirs = [@core.Dir::{ path: long, rank: 1.0, last_accessed: 0L, }]
  match @core.decode(@core.encode(dirs)) {
    Ok(out) => @debug.assert_eq(out[0].path, long)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "空文件 → CorruptedData" {
  match @core.decode(Bytes::make(0, 0)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "截断于路径长度头 → CorruptedData" {
  let dirs = [@core.Dir::{ path: "/foo/bar", rank: 1.0, last_accessed: 0L, }]
  let bytes = @core.encode(dirs).to_array()[0:6] // 版本 4 字节 + 长度头 2 字节
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "截断于 rank 中间 → CorruptedData" {
  let dirs = [@core.Dir::{ path: "/foo", rank: 1.0, last_accessed: 0L, }]
  let bytes = @core.encode(dirs).to_array()[0:16] // 4 版本 + 4 长度 + 4 路径 + 4 rank 半截
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "版本号不符 → UnsupportedVersion" {
  let dirs = [@core.Dir::{ path: "/foo", rank: 1.0, last_accessed: 0L, }]
  let bytes = @core.encode(dirs).to_array()
  bytes[0] = (999).to_byte() // 小端首字节 = 低 8 位
  match @core.decode(Bytes::from_array(bytes)) {
    Err(@core.UnsupportedVersion(v)) => @debug.assert_eq(v % 256, 999 % 256)
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "伪造超长路径长度 → CorruptedData" {
  let buf : Array[Byte] = []
  buf.push((1).to_byte()) // 版本 1 的 LE 首字节
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
test "超过 32MiB 上限 → TooLarge（长度检查先于版本检查）" {
  let bytes = Bytes::make(@core.MAX_SIZE + 5, 0)
  match @core.decode(bytes) {
    Err(@core.TooLarge) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "非法 UTF-8 路径 → CorruptedData" {
  // 版本 1 + plen=2 + 两个非法续字节（0x80 0x80 无引导字节）
  let buf : Array[Byte] = [1, 0, 0, 0, 2, 0, 0, 0, 128, 128].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "恰好 32MiB：允许通过大小检查，继续走版本校验" {
  let bytes = Bytes::make(@core.MAX_SIZE, 0)
  match @core.decode(bytes) {
    // 全零字节版本号为 0 ≠ 1，说明大小检查放行、版本检查生效
    Err(@core.UnsupportedVersion(0)) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "空路径条目（path_len=0）合法解码" {
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
test "roundtrip：特殊浮点与边界时间戳按 bit 保真" {
  let dirs = [
    // NaN：rank 唯一的 f64 非 bit 自反风险点（NaN != NaN）
    @core.Dir::{ path: "/nan", rank: 0.0 / 0.0, last_accessed: -5L, },
    // ±inf 与 Int64 边界
    @core.Dir::{ path: "/inf", rank: 1.0 / 0.0, last_accessed: -1L, },
    @core.Dir::{
      path: "/ninf",
      rank: -1.0 / 0.0,
      last_accessed: 9223372036854775807L,
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
test "路径含 NUL 字节 → CorruptedData" {
  // 版本 1 + plen=3 + "a\x00b"（NUL 在路径中间）
  let buf : Array[Byte] = [1, 0, 0, 0, 3, 0, 0, 0, 97, 0, 98].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}

///|
test "路径含换行字节 → CorruptedData" {
  // 版本 1 + plen=2 + 0x0A 0x0D
  let buf : Array[Byte] = [1, 0, 0, 0, 2, 0, 0, 0, 10, 13].map(fn(i) {
    i.to_byte()
  })
  match @core.decode(Bytes::from_array(buf)) {
    Err(@core.CorruptedData) => ()
    other => fail("unexpected: \{Repr(other)}")
  }
}
