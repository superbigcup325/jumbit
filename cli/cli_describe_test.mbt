///|
test "parse: describe basic / view mode / clear" {
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "后端项目"]),
    @cli.Describe({ path: "/a", note: Some("后端项目"), }),
  )
  // without --note it is view mode
  @debug.assert_eq(
    @cli.parse(["describe", "/a"]),
    @cli.Describe({ path: "/a", note: None, }),
  )
  // an empty string clears
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", ""]),
    @cli.Describe({ path: "/a", note: Some(""), }),
  )
}

///|
test "parse: describe\'s bad-argument family" {
  @debug.assert_eq(
    @cli.parse(["describe"]),
    @cli.Invalid("describe: missing required argument '<PATH>'"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "--note"]),
    @cli.Invalid(
      "a value is required for '--note <text>' but none was supplied",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "多\n行"]),
    @cli.Invalid("note cannot contain newline or tab"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "/b"]),
    @cli.Invalid("unexpected argument '/b'"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--bogus"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
}
