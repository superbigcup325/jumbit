///|
test "parse：status 默认与 --json/--check" {
  match @cli.parse(["status"]) {
    @cli.Status(o) => {
      @debug.assert_eq(o.json, false)
      @debug.assert_eq(o.check, false)
    }
    other => fail("\{Repr(other)}")
  }
  match @cli.parse(["status", "--json", "--check"]) {
    @cli.Status(o) => {
      @debug.assert_eq(o.json, true)
      @debug.assert_eq(o.check, true)
    }
    other => fail("\{Repr(other)}")
  }
  // 未知 flag 与位置参数归 Unknown
  match @cli.parse(["status", "--nope"]) {
    @cli.Unknown(msg) => @debug.assert_eq(msg, "--nope")
    other => fail("\{Repr(other)}")
  }
  match @cli.parse(["status", "extra"]) {
    @cli.Unknown(msg) => @debug.assert_eq(msg, "extra")
    other => fail("\{Repr(other)}")
  }
}
