// 环境变量解析测试（get 注入，不读真实环境）

///|
fn fake_env(pairs : Array[(String, String)]) -> (String) -> String? {
  fn(key : String) -> String? {
    for pair in pairs {
      if pair.0 == key {
        return Some(pair.1)
      }
    }
    None
  }
}

///|
test "_JB_DATA_DIR 绝对路径：直接采用" {
  match
    data_dir(fake_env([("_JB_DATA_DIR", "/tmp/data"), ("HOME", "/home/u")])) {
    Ok(d) => @debug.assert_eq(d, "/tmp/data")
    Err(e) => fail(e)
  }
}

///|
test "_JB_DATA_DIR 相对路径：报错" {
  match
    data_dir(fake_env([("_JB_DATA_DIR", "rel/path"), ("HOME", "/home/u")])) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "_JB_DATA_DIR 空串：报错" {
  match data_dir(fake_env([("_JB_DATA_DIR", ""), ("HOME", "/home/u")])) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "未设 _JB_DATA_DIR：回落 $HOME/.local/share/jumbit" {
  match data_dir(fake_env([("HOME", "/home/u")])) {
    Ok(d) => @debug.assert_eq(d, "/home/u/.local/share/jumbit")
    Err(e) => fail(e)
  }
}

///|
test "_JB_DATA_DIR 与 HOME 都未设：报错" {
  match data_dir(fake_env([])) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "HOME 未设但 _JB_DATA_DIR 合法：不受影响" {
  match data_dir(fake_env([("_JB_DATA_DIR", "/data/jumbit")])) {
    Ok(d) => @debug.assert_eq(d, "/data/jumbit")
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs：冒号切分并忽略空段" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "/mnt/*::/tmp/*")])
  match exclude_dirs(get, Some("/home/u")) {
    Ok(globs) => @debug.assert_eq(globs, ["/mnt/*", "/tmp/*"])
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs：非法 glob 报错" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "[unclosed")])
  match exclude_dirs(get, Some("/home/u")) {
    Err(_) => ()
    Ok(globs) => fail("expected error, got \{Repr(globs)}")
  }
}

///|
test "exclude_dirs：未设置回落 home 的转义字面 glob" {
  let get = fake_env([])
  match exclude_dirs(get, Some("/home/u [x]")) {
    Ok(globs) => @debug.assert_eq(globs, ["/home/u \\[x\\]"])
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs：未设置且无 home → 空列表" {
  match exclude_dirs(fake_env([]), None) {
    Ok(globs) => @debug.assert_eq(globs.length(), 0)
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs：显式列表优先于 home 回落" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "/a*")])
  match exclude_dirs(get, Some("/home/u")) {
    Ok(globs) => @debug.assert_eq(globs, ["/a*"])
    Err(e) => fail(e)
  }
}

///|
test "resolve_symlinks：仅值 1 生效" {
  @debug.assert_eq(
    resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "1")])),
    true,
  )
  @debug.assert_eq(
    resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "0")])),
    false,
  )
  @debug.assert_eq(
    resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "")])),
    false,
  )
  @debug.assert_eq(resolve_symlinks(fake_env([])), false)
}

///|
test "maxage：前导正号与前导零（对齐上游 parse::<u32> 语义）" {
  // Rust "+5".parse::<u32>() 接受前导 +
  match maxage(fake_env([("_JB_MAXAGE", "+5")])) {
    Ok(v) => @debug.assert_eq(v, 5.0)
    Err(e) => fail(e)
  }
  match maxage(fake_env([("_JB_MAXAGE", "007")])) {
    Ok(v) => @debug.assert_eq(v, 7.0)
    Err(e) => fail(e)
  }
  // u32::MAX 接受、u32::MAX+1 拒绝（0.10.0 探针实测）
  match maxage(fake_env([("_JB_MAXAGE", "4294967295")])) {
    Ok(v) => @debug.assert_eq(v, 4294967295.0)
    Err(e) => fail(e)
  }
  @debug.assert_eq(
    maxage(fake_env([("_JB_MAXAGE", "4294967296")])) is Err(_),
    true,
  )
}

///|
test "maxage：空串 / 空白 / 溢出均拒绝" {
  @debug.assert_eq(maxage(fake_env([("_JB_MAXAGE", "")])) is Err(_), true)
  // Rust parse 不容忍空白
  @debug.assert_eq(maxage(fake_env([("_JB_MAXAGE", " 5")])) is Err(_), true)
  @debug.assert_eq(maxage(fake_env([("_JB_MAXAGE", "5 ")])) is Err(_), true)
  // 超出整数范围
  @debug.assert_eq(
    maxage(fake_env([("_JB_MAXAGE", "99999999999999")])) is Err(_),
    true,
  )
}

///|
test "escape_glob：特殊字符逐一前置反斜杠" {
  @debug.assert_eq(escape_glob("a*b"), "a\\*b")
  @debug.assert_eq(escape_glob("x?y[1]"), "x\\?y\\[1\\]")
  @debug.assert_eq(escape_glob("c\\d"), "c\\\\d")
  @debug.assert_eq(escape_glob("/plain/path"), "/plain/path")
  // 转义结果可被 glob 引擎按字面量匹配回来
  @debug.assert_eq(
    @core.glob_match(escape_glob("/home/u [x]"), "/home/u [x]"),
    true,
  )
}
