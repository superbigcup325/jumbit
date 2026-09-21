// 导入插件数据文件路径解析测试（get 注入，不读真实环境；fake_env 复用 config_test）

///|
fn expect_path(r : Result[String, String], want : String) -> Unit raise {
  match r {
    Ok(p) => @debug.assert_eq(p, want)
    Err(e) => fail("unexpected err: \{e}")
  }
}

///|
test "z_data_path：_Z_DATA 优先，否则 $HOME/.z" {
  expect_path(
    @config.z_data_path(fake_env([("_Z_DATA", "/custom/z")])),
    "/custom/z",
  )
  expect_path(
    @config.z_data_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.z",
  )
  // 空串不滤（对齐上游 var_os 原样采用）
  expect_path(@config.z_data_path(fake_env([("_Z_DATA", "")])), "")
}

///|
test "z_data_path：无 HOME 报错" {
  match @config.z_data_path(fake_env([])) {
    Err(e) => @debug.assert_eq(e, "could not find home directory")
    Ok(p) => fail("expected error, got \{p}")
  }
}

///|
test "zsh_z_data_path：ZSHZ_DATA > _Z_DATA > $HOME/.z（上游 Some(\"\") 也命中首位）" {
  expect_path(
    @config.zsh_z_data_path(fake_env([("ZSHZ_DATA", "/a"), ("_Z_DATA", "/b")])),
    "/a",
  )
  expect_path(
    @config.zsh_z_data_path(fake_env([("_Z_DATA", "/b"), ("HOME", "/home/u")])),
    "/b",
  )
  expect_path(
    @config.zsh_z_data_path(fake_env([("ZSHZ_DATA", ""), ("_Z_DATA", "/b")])),
    "",
  )
  expect_path(
    @config.zsh_z_data_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.z",
  )
}

///|
test "fasd_data_path：_FASD_DATA 优先，否则 $HOME/.fasd" {
  expect_path(
    @config.fasd_data_path(fake_env([("_FASD_DATA", "/custom/fasd")])),
    "/custom/fasd",
  )
  expect_path(
    @config.fasd_data_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.fasd",
  )
}

///|
test "autojump_data_path：XDG_DATA_HOME 优先，否则 $HOME/.local/share" {
  expect_path(
    @config.autojump_data_path(fake_env([("XDG_DATA_HOME", "/xdg")])),
    "/xdg/autojump/autojump.txt",
  )
  expect_path(
    @config.autojump_data_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.local/share/autojump/autojump.txt",
  )
}

///|
test "zlua_data_path：_ZL_DATA 滤空值与 Windows 风格值（非 Windows）" {
  expect_path(
    @config.zlua_data_path(fake_env([("_ZL_DATA", "/custom/zlua")])),
    "/custom/zlua",
  )
  // 空串 → 回落默认
  expect_path(
    @config.zlua_data_path(fake_env([("_ZL_DATA", ""), ("HOME", "/home/u")])),
    "/home/u/.zlua",
  )
  // Windows 风格（防 Cygwin/MSYS 泄漏）→ 回落默认
  expect_path(
    @config.zlua_data_path(
      fake_env([("_ZL_DATA", "C:\\Users\\x"), ("HOME", "/home/u")]),
    ),
    "/home/u/.zlua",
  )
  expect_path(
    @config.zlua_data_path(
      fake_env([("_ZL_DATA", "z:/rel"), ("HOME", "/home/u")]),
    ),
    "/home/u/.zlua",
  )
  // 长度不足 3 / 首段非字母冒号 → 视为普通路径原样采用
  expect_path(@config.zlua_data_path(fake_env([("_ZL_DATA", "C:")])), "C:")
  expect_path(@config.zlua_data_path(fake_env([("_ZL_DATA", "1:/x")])), "1:/x")
}

///|
test "zlua_fish_path：XDG_DATA_HOME 优先，否则 $HOME/.local/share" {
  expect_path(
    @config.zlua_fish_path(fake_env([("XDG_DATA_HOME", "/xdg")])),
    "/xdg/zlua/zlua.txt",
  )
  expect_path(
    @config.zlua_fish_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.local/share/zlua/zlua.txt",
  )
}
