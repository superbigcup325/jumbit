///|
test "parse: query\'s four flags" {
  @debug.assert_eq(
    @cli.parse(["query", "--list"]),
    @cli.Query(query_opts(list=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--score", "--all"]),
    @cli.Query(query_opts(score=true, all=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--exclude", "/tmp/x", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], exclude=Some("/tmp/x"))),
  )
  // flags and keywords interleaved
  @debug.assert_eq(
    @cli.parse(["query", "kw", "--list"]),
    @cli.Query(query_opts(keywords=["kw"], list=true)),
  )
}

///|
test "parse: an unknown flag or a missing value goes Unknown" {
  @debug.assert_eq(
    @cli.parse(["query", "--bogus"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--exclude"]),
    @cli.Invalid(
      "a value is required for '--exclude <path>' but none was supplied",
    ),
  )
}

///|
test "parse: query --json and --interactive are mutually exclusive" {
  @debug.assert_eq(
    @cli.parse(["query", "--json", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], json=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--interactive"]),
    @cli.Invalid("the argument '--json' cannot be used with '--interactive'"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--interactive", "--json"]),
    @cli.Invalid("the argument '--json' cannot be used with '--interactive'"),
  )
}

///|
test "parse: query\'s -- ends flag parsing" {
  // the --list after -- is a keyword, not a flag
  @debug.assert_eq(
    @cli.parse(["query", "--", "--list"]),
    @cli.Query(query_opts(keywords=["--list"])),
  )
  @debug.assert_eq(
    @cli.parse(["query", "kw", "--", "-dash"]),
    @cli.Query(query_opts(keywords=["kw", "-dash"])),
  )
}

///|
test "parse：query --fuzzy" {
  @debug.assert_eq(
    @cli.parse(["query", "--fuzzy", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], fuzzy=true)),
  )
  // combines with --json (agent channel: a fuzzy result carries matched_by=fuzzy)
  @debug.assert_eq(
    @cli.parse(["query", "--fuzzy", "--json", "kw"]),
    @cli.Query(query_opts(keywords=["kw"], fuzzy=true, json=true)),
  )
}

///|
test "parse: query --limit valid values and the overwrite semantics" {
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "3"]),
    @cli.Query(query_opts(list=true, limit=Some(3))),
  )
  // a repeat lets the last one win
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit", "1", "--limit", "2"]),
    @cli.Query(query_opts(json=true, limit=Some(2))),
  )
  // limit is valid alongside --list --json; 0 is valid
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--json", "--limit", "0"]),
    @cli.Query(query_opts(list=true, json=true, limit=Some(0))),
  )
}

///|
test "parse: query --limit invalid values and a missing value -> Invalid" {
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit", "abc"]),
    @cli.Invalid(
      "invalid value 'abc' for '--limit <n>': must be a non-negative integer",
    ),
  )
  // negative / float / leading + (parse_uint64 rejects +, same source as import la) / beyond the Int cap
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "-1"]),
    @cli.Invalid(
      "invalid value '-1' for '--limit <n>': must be a non-negative integer",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "1.5"]),
    @cli.Invalid(
      "invalid value '1.5' for '--limit <n>': must be a non-negative integer",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "+2"]),
    @cli.Invalid(
      "invalid value '+2' for '--limit <n>': must be a non-negative integer",
    ),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--limit", "9999999999"]),
    @cli.Invalid(
      "invalid value '9999999999' for '--limit <n>': must be a non-negative integer",
    ),
  )
  // a missing value
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--limit"]),
    @cli.Invalid("a value is required for '--limit <n>' but none was supplied"),
  )
}

///|
test "parse: query --limit combination limits and error precedence" {
  // a bare query (the single-result path) or --interactive combined with limit -> Invalid
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "2"]),
    @cli.Invalid("'--limit' requires '--list', '--json' or '--tsv'"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--interactive", "--limit", "2"]),
    @cli.Invalid("'--limit' requires '--list', '--json' or '--tsv'"),
  )
  // an unknown flag outranks the combination check (the bad-first convention)
  @debug.assert_eq(
    @cli.parse(["query", "--bogus", "--limit", "2"]),
    @cli.Invalid("unexpected argument '--bogus'"),
  )
  // an invalid value outranks the combination check (invalid returns before it)
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "abc"]),
    @cli.Invalid(
      "invalid value 'abc' for '--limit <n>': must be a non-negative integer",
    ),
  )
}

///|
test "parse: query --tsv exclusivity and the --list-wins precedent" {
  // pairwise exclusive with --json/--interactive (order-independent)
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--json"]),
    @cli.Invalid("the argument '--tsv' cannot be used with '--json'"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--json", "--tsv"]),
    @cli.Invalid("the argument '--tsv' cannot be used with '--json'"),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--interactive"]),
    @cli.Invalid("the argument '--tsv' cannot be used with '--interactive'"),
  )
  // --list --tsv: --list wins and --tsv is ignored (following the --list --json precedent, unchecked)
  @debug.assert_eq(
    @cli.parse(["query", "--list", "--tsv"]),
    @cli.Query(query_opts(list=true, tsv=true)),
  )
  // --tsv alone is valid; --limit with --tsv is valid
  @debug.assert_eq(
    @cli.parse(["query", "--tsv"]),
    @cli.Query(query_opts(tsv=true)),
  )
  @debug.assert_eq(
    @cli.parse(["query", "--tsv", "--limit", "1"]),
    @cli.Query(query_opts(tsv=true, limit=Some(1))),
  )
  // the valid-set message for limit grows with --tsv
  @debug.assert_eq(
    @cli.parse(["query", "--limit", "2"]),
    @cli.Invalid("'--limit' requires '--list', '--json' or '--tsv'"),
  )
}
