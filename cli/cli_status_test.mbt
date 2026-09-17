///|
test "parse：status 默认与 --json/--check" {
  match parse(["status"]) {
    Status(o) => {
      @debug.assert_eq(o.json, false)
      @debug.assert_eq(o.check, false)
    }
    other => fail("\{Repr(other)}")
  }
  match parse(["status", "--json", "--check"]) {
    Status(o) => {
      @debug.assert_eq(o.json, true)
      @debug.assert_eq(o.check, true)
    }
    other => fail("\{Repr(other)}")
  }
  // 未知 flag 与位置参数归 Unknown
  match parse(["status", "--nope"]) {
    Unknown(msg) => @debug.assert_eq(msg, "--nope")
    other => fail("\{Repr(other)}")
  }
  match parse(["status", "extra"]) {
    Unknown(msg) => @debug.assert_eq(msg, "extra")
    other => fail("\{Repr(other)}")
  }
}
