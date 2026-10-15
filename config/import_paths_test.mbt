// Data-file path resolution tests for the import plugins (get injected, the real environment never read; fake_env is reused from config_test)

///|
fn expect_path(r : Result[String, String], want : String) -> Unit raise {
  match r {
    Ok(p) => @debug.assert_eq(p, want)
    Err(e) => fail("unexpected err: \{e}")
  }
}

///|
test "z_data_path: _Z_DATA first, otherwise $HOME/.z" {
  expect_path(
    @config.z_data_path(fake_env([("_Z_DATA", "/custom/z")])),
    "/custom/z",
  )
  expect_path(
    @config.z_data_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.z",
  )
  // empty strings are not filtered (upstream\'s var_os takes them as is)
  expect_path(@config.z_data_path(fake_env([("_Z_DATA", "")])), "")
}

///|
test "z_data_path: no HOME errors" {
  match @config.z_data_path(fake_env([])) {
    Err(e) => @debug.assert_eq(e, "jumbit: could not find home directory")
    Ok(p) => fail("expected error, got \{p}")
  }
}

///|
test "zsh_z_data_path: ZSHZ_DATA > _Z_DATA > $HOME/.z (upstream's Some(\"\") takes the first too)" {
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
test "fasd_data_path: _FASD_DATA first, otherwise $HOME/.fasd" {
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
test "autojump_data_path: XDG_DATA_HOME first, otherwise $HOME/.local/share" {
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
test "zlua_data_path: _ZL_DATA filters empty and Windows-style values (non-Windows)" {
  expect_path(
    @config.zlua_data_path(fake_env([("_ZL_DATA", "/custom/zlua")])),
    "/custom/zlua",
  )
  // an empty string -> fall back to the default
  expect_path(
    @config.zlua_data_path(fake_env([("_ZL_DATA", ""), ("HOME", "/home/u")])),
    "/home/u/.zlua",
  )
  // a Windows-style value (guarding against Cygwin/MSYS leaks) -> fall back to the default
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
  // shorter than 3, or the first segment is not a letter+colon -> treated as an ordinary path and used as is
  expect_path(@config.zlua_data_path(fake_env([("_ZL_DATA", "C:")])), "C:")
  expect_path(@config.zlua_data_path(fake_env([("_ZL_DATA", "1:/x")])), "1:/x")
}

///|
test "zlua_fish_path: XDG_DATA_HOME first, otherwise $HOME/.local/share" {
  expect_path(
    @config.zlua_fish_path(fake_env([("XDG_DATA_HOME", "/xdg")])),
    "/xdg/zlua/zlua.txt",
  )
  expect_path(
    @config.zlua_fish_path(fake_env([("HOME", "/home/u")])),
    "/home/u/.local/share/zlua/zlua.txt",
  )
}
