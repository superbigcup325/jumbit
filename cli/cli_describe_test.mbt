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
    @cli.Unknown("describe: 缺少路径参数"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "--note"]),
    @cli.Unknown("--note 缺少标注文本"),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note", "多\n行"]),
    @cli.Invalid("describe: 标注不能包含换行"),
  )
  @debug.assert_eq(@cli.parse(["describe", "/a", "/b"]), @cli.Unknown("/b"))
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--bogus"]),
    @cli.Unknown("--bogus"),
  )
}
