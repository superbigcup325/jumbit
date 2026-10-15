///|
/// edit\'s argument-parsing tests (the exclusivity matrix in spec docs/spec-plaintext-edit.md §1.4)

///|
fn edit_opts(
  rename_old~ : String? = None,
  rename_new~ : String? = None,
  prune~ : Bool = false,
) -> @cli.EditOptions {
  { rename_old, rename_new, prune, }
}

///|
test "parse edit: no flag = interactive; --prune; the equals form" {
  @debug.assert_eq(@cli.parse(["edit"]), @cli.Edit(edit_opts()))
  @debug.assert_eq(
    @cli.parse(["edit", "--prune"]),
    @cli.Edit(edit_opts(prune=true)),
  )
  // the equals form of a boolean or unknown flag still reports the original wording with exit 2 (matching clap\'s global --flag=value semantics)
  @debug.assert_eq(
    @cli.parse(["edit", "--prune=true"]),
    @cli.Invalid("unexpected argument '--prune=true'"),
  )
}

///|
test "parse edit: --rename takes two arguments (space and equals forms)" {
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b"]),
    @cli.Edit(edit_opts(rename_old=Some("/a"), rename_new=Some("/b"))),
  )
  @debug.assert_eq(
    @cli.parse(["edit", "--rename=/a", "/b"]),
    @cli.Edit(edit_opts(rename_old=Some("/a"), rename_new=Some("/b"))),
  )
}

///|
test "parse edit: the missing-argument / repeat / exclusivity matrix" {
  // new is missing
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a"]),
    @cli.Invalid("--rename requires <new>"),
  )
  // both are missing
  @debug.assert_eq(
    @cli.parse(["edit", "--rename"]),
    @cli.Invalid("--rename requires <old> <new>"),
  )
  // repeated
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b", "--rename", "/c", "/d"]),
    @cli.Invalid("the argument '--rename' cannot be used multiple times"),
  )
  // exclusive (a semantic Invalid error, exit 2)
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b", "--prune"]),
    @cli.Invalid("the argument '--prune' cannot be used with '--rename'"),
  )
  // an unknown flag and a surplus positional
  @debug.assert_eq(
    @cli.parse(["edit", "--nope"]),
    @cli.Invalid("unexpected argument '--nope'"),
  )
  @debug.assert_eq(
    @cli.parse(["edit", "/path"]),
    @cli.Invalid("unexpected argument '/path'"),
  )
}
