///|
test "parse：describe 基本/显示模式/清除" {
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "后端项目"]),
    @cli.Describe({ path: "/a", note: Some("后端项目"), }),
  )
  // 无 --note 为显示模式
  @debug.assert_eq(
    @cli.parse(["describe", "/a"]),
    @cli.Describe({ path: "/a", note: None, }),
  )
  // 空串即清除
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", ""]),
    @cli.Describe({ path: "/a", note: Some(""), }),
  )
}

///|
test "parse：describe 坏参族" {
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
