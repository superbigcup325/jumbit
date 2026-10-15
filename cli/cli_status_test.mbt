///|
test "parse: status defaults with --json/--check" {
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
  // an unknown flag or a positional goes Invalid (unexpected argument)
  match @cli.parse(["status", "--nope"]) {
    @cli.Invalid(msg) => @debug.assert_eq(msg, "unexpected argument '--nope'")
    other => fail("\{Repr(other)}")
  }
  match @cli.parse(["status", "extra"]) {
    @cli.Invalid(msg) => @debug.assert_eq(msg, "unexpected argument 'extra'")
    other => fail("\{Repr(other)}")
  }
}
