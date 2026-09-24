///|
/// 明文格式测试：round-trip、字节面、行级错误矩阵（规格 docs/spec-plaintext-edit.md §3.2）

///|
test "明文 roundtrip：多字段经 encode/decode 逐条目相等（note 恒 None）" {
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
      // rank 经两位小数明文：3.14 精确保真
      @debug.assert_eq(out[0].rank, 3.14)
      @debug.assert_eq(out[0].last_accessed, 1789054423L)
      @debug.assert_eq(out[1].path, "/tmp/α β/中文目录")
      @debug.assert_eq(out[1].rank, 0.01)
      @debug.assert_eq(out[1].last_accessed, 1L)
      // note 不进明文主格式（notes.tsv 侧文件承载，store 层接线）
      @debug.assert_eq(out[1].note, None)
    }
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "明文字节面：0 填充与列序逐字节（对齐上游 {:010}\\t{:010.2}\\t{path}）" {
  let bytes = @core.encode_plaintext([
    { path: "/a/b", rank: 1.0, last_accessed: 1789054423L, note: None, },
  ])
  @debug.assert_eq(@utf8.decode(bytes), "1789054423\t0000001.00\t/a/b\n")
}

///|
test "明文 rank clamp：0.005 下界进、1e10 上界截、NaN 兜底为下限" {
  let bytes = @core.encode_plaintext([
    { path: "/lo", rank: 0.005, last_accessed: 1L, note: None, },
    { path: "/hi", rank: 10000000000.0, last_accessed: 1L, note: None, },
    {
      path: "/nan",
      rank: @core.parse_f64("nan").or(0.0),
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
/// 明文 rank 格式化：半界取偶与正确舍入边界（探针 2026-09-22 转正；
/// 每个 double 的精确值决定舍入方向，不可凭十进制直觉预测）
fn fmt_one(x : Double) -> String raise {
  let bytes = @core.encode_plaintext([
    { path: "/p", rank: x, last_accessed: 0L, note: None, },
  ])
  let s = @utf8.decode(bytes)
  let cols : Array[String] = s.split("\t").map(fn(v) { v.to_owned() }).collect()
  cols[1]
}

///|
test "明文 rank 格式化：二进制不精确半界按精确值舍入" {
  // 2.675 精确值 2.6749999…8 → 舍到 2.67（经典坑：×100 二进制乘法会翻转）
  @debug.assert_eq(fmt_one(2.675), "0000002.67")
  // 999.995 精确值 999.995000…00104 → 进到 1000.00（方向与 2.675 相反）
  @debug.assert_eq(fmt_one(999.995), "0001000.00")
  // 0.005 精确值略大于半界 → 0.01
  @debug.assert_eq(fmt_one(0.005), "0000000.01")
}

///|
test "明文 rank 格式化：二进制精确半界取偶" {
  @debug.assert_eq(fmt_one(1.125), "0000001.12") // 112 偶 → 舍
  @debug.assert_eq(fmt_one(1.375), "0000001.38") // 137 奇 → 进
  @debug.assert_eq(fmt_one(0.125), "0000000.12")
  @debug.assert_eq(fmt_one(0.375), "0000000.38")
}

///|
test "明文 decode：空文件与纯换行均得空库" {
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
test "明文 decode：CRLF 容忍、行中空白多分隔符、path 前导空白被剥（上游语义）" {
  // CRLF：行尾 \r 剥除
  match
    @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t/a\r\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // 多空白分隔（上游 split_once(char::is_whitespace) 语义）
  match
    @core.decode_plaintext(@utf8.encode("1789054423  \t00000001.00\t/a b\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a b")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // path 前导空白剥除（上游 path.trim_start()；round-trip 丢前导空白）
  match
    @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t  /a\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].path, "/a")
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
}

///|
test "明文 decode：行级错误矩阵（文案对齐上游）" {
  // 缺列
  match @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\n")) {
    Err(e) =>
      @debug.assert_eq(e.lines, ["line 1: expected: <timestamp> <rank> <path>"])
    Ok(_) => fail("expected error")
  }
  // 垃圾 timestamp / 垃圾 rank / NaN rank
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
  // inf 接受并 clamp 到上限（上游 parse::<Rank> 接受 inf 字面量同款）
  match @core.decode_plaintext(@utf8.encode("1789054423\tinf\t/a\n")) {
    Ok(dirs) => @debug.assert_eq(dirs[0].rank, 9999999.99)
    Err(e) => fail("unexpected: \{Repr(e)}")
  }
  // 空 path（三段但第三段空白）
  match @core.decode_plaintext(@utf8.encode("1789054423\t00000001.00\t  \n")) {
    Err(e) =>
      @debug.assert_eq(e.lines, ["line 1: expected: <timestamp> <rank> <path>"])
    Ok(_) => fail("expected error")
  }
}

///|
test "明文 decode：非法 UTF-8 报行号；错误聚合超 8 条折叠为 ... and N more" {
  // 非法 UTF-8 字节 0xFF
  let bad = b"1789054423\t00000001.00\t/\xff\n"
  match @core.decode_plaintext(bad) {
    Err(e) => @debug.assert_eq(e.lines, ["line 1: invalid UTF-8"])
    Ok(_) => fail("expected error")
  }
  // 10 条坏行 → 前 8 条 + "... and 2 more"
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
/// 边界补课（coverage 2026-09-25 盲区明细）：pad10 负数路、空 path 跳过、
/// parse_i64 分支矩阵、多行错误聚合、行首空白
test "明文 encode：负数 last_accessed 的 pad10（-1 补零、i64::MIN 超宽原样）" {
  let dirs : Array[@core.Dir] = [
    { path: "/a", rank: 1.0, last_accessed: -1L, note: None, },
    { path: "/b", rank: 1.0, last_accessed: -9223372036854775808L, note: None, },
  ]
  let text = @core.encode_plaintext(dirs)
  // -1 → "-000000001"（符号在前 0 填充其后）；MIN 20 位超宽原样不截断
  inspect(
    @utf8.decode(text).contains("-0000000001\t0000001.00\t/a"),
    content="true",
  )
  inspect(
    @utf8.decode(text).contains("-9223372036854775808\t0000001.00\t/b"),
    content="true",
  )
  // 负数 epoch roundtrip（atuin 数据集 epoch=-1 边界行的另一半）
  match @core.decode_plaintext(text) {
    Ok(out) => {
      @debug.assert_eq(out[0].last_accessed, -1L)
      @debug.assert_eq(out[1].last_accessed, -9223372036854775808L)
    }
    Err(e) => fail("\{e.message()}")
  }
}

///|
test "明文 encode：空 path 条目跳过（明文行格式无法表达，迁移救库语义）" {
  let dirs : Array[@core.Dir] = [
    { path: "", rank: 1.0, last_accessed: 0L, note: None, },
    { path: "/kept", rank: 1.0, last_accessed: 0L, note: None, },
  ]
  let text = @utf8.decode(@core.encode_plaintext(dirs))
  inspect(text.contains("/kept"), content="true")
  // 空 path 行不落盘（写出让库永久不可读的自锁预防）
  inspect(text.split("\n").length(), content="2")
}

///|
test "明文 decode：timestamp 解析分支矩阵（i64::from_str 语义）" {
  // 符号位单独出现（"+" / "-"）→ could not parse timestamp
  // 超过 20 位（必溢出）早拒；2^63 超 i64::MAX 拒；-0 归 0；i64::MIN 接受
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
          Err(_) => fail("应拒: \{line}")
        }
      Err(_) =>
        match want {
          Ok(_) => fail("应收: \{line}")
          Err(_) => ()
        }
    }
  }
}

///|
test "明文 decode：多坏行错误聚合换行拼接与行号" {
  let bad = "garbage\nalso bad\n1789054423\t00000001.00\t/ok\n"
  match @core.decode_plaintext(@utf8.encode(bad)) {
    Ok(_) => fail("坏行应整库拒绝")
    Err(e) => {
      let msg = e.message()
      // 逐行换行拼接（对齐上游 errors.join("\n")）
      inspect(msg.contains("\n"), content="true")
      inspect(msg.contains("line 1:"), content="true")
      inspect(msg.contains("line 2:"), content="true")
    }
  }
}

///|
test "明文 decode：行首空白 trim_start 与 CR 行尾容忍" {
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
