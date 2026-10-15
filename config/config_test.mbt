// Environment-parsing tests (get is injected; the real environment is never read)

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
test "_JB_DATA_DIR absolute path: used as is" {
  match
    @config.data_dir(
      fake_env([("_JB_DATA_DIR", "/tmp/data"), ("HOME", "/home/u")]),
    ) {
    Ok(d) => @debug.assert_eq(d, "/tmp/data")
    Err(e) => fail(e)
  }
}

///|
test "_JB_DATA_DIR relative path: errors" {
  match
    @config.data_dir(
      fake_env([("_JB_DATA_DIR", "rel/path"), ("HOME", "/home/u")]),
    ) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "_JB_DATA_DIR empty string: errors" {
  match
    @config.data_dir(fake_env([("_JB_DATA_DIR", ""), ("HOME", "/home/u")])) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "_JB_DATA_DIR unset: falls back to $HOME/.local/share/jumbit" {
  match @config.data_dir(fake_env([("HOME", "/home/u")])) {
    Ok(d) => @debug.assert_eq(d, "/home/u/.local/share/jumbit")
    Err(e) => fail(e)
  }
}

///|
test "neither _JB_DATA_DIR nor HOME set: errors" {
  match @config.data_dir(fake_env([])) {
    Err(_) => ()
    Ok(d) => fail("expected error, got \{d}")
  }
}

///|
test "HOME unset but _JB_DATA_DIR valid: unaffected" {
  match @config.data_dir(fake_env([("_JB_DATA_DIR", "/data/jumbit")])) {
    Ok(d) => @debug.assert_eq(d, "/data/jumbit")
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs: colon split, empty segments ignored" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "/mnt/*::/tmp/*")])
  match @config.exclude_dirs(get, Some("/home/u")) {
    Ok(globs) => @debug.assert_eq(globs, ["/mnt/*", "/tmp/*"])
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs: an invalid glob errors" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "[unclosed")])
  match @config.exclude_dirs(get, Some("/home/u")) {
    Err(_) => ()
    Ok(globs) => fail("expected error, got \{Repr(globs)}")
  }
}

///|
test "exclude_dirs: unset falls back to an escaped literal glob for home" {
  let get = fake_env([])
  match @config.exclude_dirs(get, Some("/home/u [x]")) {
    Ok(globs) => @debug.assert_eq(globs, ["/home/u \\[x\\]"])
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs: unset with no home -> an empty list" {
  match @config.exclude_dirs(fake_env([]), None) {
    Ok(globs) => @debug.assert_eq(globs.length(), 0)
    Err(e) => fail(e)
  }
}

///|
test "exclude_dirs: an explicit list wins over the home fallback" {
  let get = fake_env([("_JB_EXCLUDE_DIRS", "/a*")])
  match @config.exclude_dirs(get, Some("/home/u")) {
    Ok(globs) => @debug.assert_eq(globs, ["/a*"])
    Err(e) => fail(e)
  }
}

///|
test "resolve_symlinks: only the value 1 takes effect" {
  @debug.assert_eq(
    @config.resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "1")])),
    true,
  )
  @debug.assert_eq(
    @config.resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "0")])),
    false,
  )
  @debug.assert_eq(
    @config.resolve_symlinks(fake_env([("_JB_RESOLVE_SYMLINKS", "")])),
    false,
  )
  @debug.assert_eq(@config.resolve_symlinks(fake_env([])), false)
}

///|
test "maxage: leading plus and leading zeros (matching upstream parse::<u32> semantics)" {
  // Rust\'s "+5".parse::<u32>() accepts a leading +
  match @config.maxage(fake_env([("_JB_MAXAGE", "+5")])) {
    Ok(v) => @debug.assert_eq(v, 5.0)
    Err(e) => fail(e)
  }
  match @config.maxage(fake_env([("_JB_MAXAGE", "007")])) {
    Ok(v) => @debug.assert_eq(v, 7.0)
    Err(e) => fail(e)
  }
  // u32::MAX is accepted, u32::MAX+1 rejected (probed against 0.10.0)
  match @config.maxage(fake_env([("_JB_MAXAGE", "4294967295")])) {
    Ok(v) => @debug.assert_eq(v, 4294967295.0)
    Err(e) => fail(e)
  }
  @debug.assert_eq(
    @config.maxage(fake_env([("_JB_MAXAGE", "4294967296")])) is Err(_),
    true,
  )
}

///|
test "maxage: empty / whitespace / overflow all rejected" {
  @debug.assert_eq(
    @config.maxage(fake_env([("_JB_MAXAGE", "")])) is Err(_),
    true,
  )
  // Rust\'s parse tolerates no whitespace
  @debug.assert_eq(
    @config.maxage(fake_env([("_JB_MAXAGE", " 5")])) is Err(_),
    true,
  )
  @debug.assert_eq(
    @config.maxage(fake_env([("_JB_MAXAGE", "5 ")])) is Err(_),
    true,
  )
  // beyond the integer range
  @debug.assert_eq(
    @config.maxage(fake_env([("_JB_MAXAGE", "99999999999999")])) is Err(_),
    true,
  )
}

///|
test "escape_glob: every special character gets a leading backslash" {
  @debug.assert_eq(@config.escape_glob("a*b"), "a\\*b")
  @debug.assert_eq(@config.escape_glob("x?y[1]"), "x\\?y\\[1\\]")
  @debug.assert_eq(@config.escape_glob("c\\d"), "c\\\\d")
  @debug.assert_eq(@config.escape_glob("/plain/path"), "/plain/path")
  // the escaped result matches itself back as a literal through the glob engine
  @debug.assert_eq(
    @core.glob_match(@config.escape_glob("/home/u [x]"), "/home/u [x]"),
    true,
  )
}
