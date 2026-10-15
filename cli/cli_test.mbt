// Subcommand parsing tests

///|
fn query_opts(
  keywords~ : Array[String] = [],
  all~ : Bool = false,
  list~ : Bool = false,
  score~ : Bool = false,
  exclude~ : String? = None,
  json~ : Bool = false,
  fuzzy~ : Bool = false,
  limit~ : Int32? = None,
  tsv~ : Bool = false,
) -> @cli.QueryOptions {
  {
    keywords,
    all,
    list,
    score,
    interactive: false,
    exclude,
    json,
    fuzzy,
    limit,
    tsv,
  }
}

///|
fn add_opts(paths~ : Array[String], score~ : Double = 1.0) -> @cli.AddOptions {
  { paths, score, }
}

///|
test "parse: add/query collect arguments" {
  @debug.assert_eq(
    @cli.parse(["add", "/a", "/b"]),
    @cli.Add(add_opts(paths=["/a", "/b"])),
  )
  @debug.assert_eq(@cli.parse(["query"]), @cli.Query(query_opts()))
  @debug.assert_eq(
    @cli.parse(["query", "foo", "bar"]),
    @cli.Query(query_opts(keywords=["foo", "bar"])),
  )
}

///|
test "parse: add/remove missing a required positional goes Invalid (the error: prefix is added by the run layer)" {
  @debug.assert_eq(
    @cli.parse(["add"]),
    @cli.Invalid("add: missing required argument '<PATHS>'"),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--"]),
    @cli.Invalid("add: missing required argument '<PATHS>'"),
  )
  @debug.assert_eq(
    @cli.parse(["remove"]),
    @cli.Invalid("remove: missing required argument '<PATHS>'"),
  )
  @debug.assert_eq(
    @cli.parse(["remove", "--"]),
    @cli.Invalid("remove: missing required argument '<PATHS>'"),
  )
}

///|
test "parse: the three help spellings" {
  @debug.assert_eq(@cli.parse(["help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["--help"]), @cli.Help)
  @debug.assert_eq(@cli.parse(["-h"]), @cli.Help)
}

///|
test "parse: --version/-V and the no-argument usage error (matching upstream clap\'s top level)" {
  @debug.assert_eq(@cli.parse(["--version"]), @cli.Version)
  @debug.assert_eq(@cli.parse(["-V"]), @cli.Version)
  // a version flag followed by extra arguments -> a usage error (clap unexpected argument)
  @debug.assert_eq(
    @cli.parse(["--version", "x"]),
    @cli.Invalid("unexpected argument 'x'"),
  )
  @debug.assert_eq(
    @cli.parse(["-V", "x"]),
    @cli.Invalid("unexpected argument 'x'"),
  )
  // no arguments = a usage error (the full help to stderr, exit code 2, matching upstream)
  @debug.assert_eq(@cli.parse([]), @cli.Usage)
  // a version flag does not hijack the subcommand namespace: as a subcommand argument it goes through subcommand parsing
  @debug.assert_eq(
    @cli.parse(["query", "--version"]),
    @cli.Invalid("unexpected argument '--version'"),
  )
}

///|
test "parse: an unknown command echoes the original name" {
  @debug.assert_eq(@cli.parse(["frobnicate"]), @cli.Unknown("frobnicate"))
  @debug.assert_eq(
    @cli.parse(["--bogus"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
}

///|
test "parse: remove collects paths" {
  @debug.assert_eq(
    @cli.parse(["remove", "/a", "/b"]),
    @cli.Remove(["/a", "/b"]),
  )
  // an empty set is a usage error (the missing-argument wording goes Invalid; see the add/remove case above)
}

///|
test "parse: the --flag=value equals form (matching upstream clap\'s two forms)" {
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd=zj"]),
    @cli.Init({
      shell: "bash",
      cmd: Some("zj"),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["init", "zsh", "--hook=none"]),
    @cli.Init({
      shell: "zsh",
      cmd: Some("j"),
      hook: @tpl.HookNone,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=/tmp/x", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some("/tmp/x"))),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit=3"]),
    @cli.Query(query_opts(list=true, limit=Some(3))),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--score=2.5", "/a"]),
    @cli.Add(add_opts(paths=["/a"], score=2.5)),
  )
  // a negative value (split_once cuts only the first =)
  @debug.assert_eq(
    @cli.parse(["add", "--score=-1", "/a"]),
    @cli.Add(add_opts(paths=["/a"], score=-1.0)),
  )
  @debug.assert_eq(
    @cli.parse(["describe", "/a", "--note=后端服务"]),
    @cli.Describe({ path: "/a", note: Some("后端服务"), }),
  )
  // the value itself contains =
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=/a=b"]),
    @cli.Query(query_opts(exclude=Some("/a=b"))),
  )
}

///|
test "parse: equals-form edges, and no regression in the existing behaviour" {
  // the equals form of a boolean flag is not a value-taking flag, so the original wording goes Unknown (matching clap\'s rejection)
  @debug.assert_eq(
    @cli.parse(["query", "--list=x"]),
    @cli.Invalid("unexpected argument '--list=x'"),
  )
  // the equals form of an unknown flag reports the original wording
  @debug.assert_eq(
    @cli.parse(["query", "--bogus=1"]),
    @cli.Invalid("unexpected argument '--bogus=1'"),
  )
  // empty values: --exclude= takes an empty path; --cmd= takes an empty string; --limit= is an invalid value, so Invalid
  @debug.assert_eq(
    @cli.parse(["query", "--exclude=", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some(""))),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--cmd="]),
    @cli.Init({
      shell: "bash",
      cmd: Some(""),
      hook: @tpl.HookPwd,
      no_cmd: false,
    }),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--limit="]),
    @cli.Invalid(
      "invalid value '' for '--limit <n>': must be a non-negative integer",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["init", "bash", "--hook="]),
    @cli.Invalid(
      "invalid value '' for '--hook <HOOK>'\n  [possible values: pwd, prompt, none]",
    ),
  )
  // --= does not conflict with --: it goes Invalid as an unexpected argument
  @debug.assert_eq(
    @cli.parse(["add", "--=1"]),
    @cli.Invalid("unexpected argument '--=1'"),
  )
  // nothing after -- is split, so an equals string is taken as a positional
  @debug.assert_eq(
    @cli.parse(["query", "--", "--limit=3"]),
    @cli.Query(query_opts(keywords=["--limit=3"])),
  )
  @debug.assert_eq(
    @cli.parse(["add", "--", "--score=1", "/a"]),
    @cli.Add(add_opts(paths=["--score=1", "/a"])),
  )
}

///|
test "parse: mcp takes no arguments; extra arguments or flags go Unknown" {
  @debug.assert_eq(@cli.parse(["mcp"]), @cli.Mcp)
  @debug.assert_eq(
    @cli.parse(["mcp", "extra"]),
    @cli.Invalid("unexpected argument 'extra'"),
  )
  @debug.assert_eq(
    @cli.parse(["mcp", "--json"]),
    @cli.Invalid("unexpected argument '--json'"),
  )
}
