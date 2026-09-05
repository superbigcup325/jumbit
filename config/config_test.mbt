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
