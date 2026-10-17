// strip_argv0 unit tests: every real argv[0] shape (a bare PATH name / a full path / moon run\'s exe path) is stripped

///|
test "strip_argv0: both a bare name and a full path lose the first argument" {
  // bash/fish/zsh calling by bare name through PATH: argv[0] = "jumbit" (no /)
  @debug.assert_eq(strip_argv0(["jumbit", "help"]), ["help"])
  // a full-path call and a moon run exe-path call
  @debug.assert_eq(strip_argv0(["/usr/local/bin/jumbit", "add", "/tmp"]), [
    "add", "/tmp",
  ])
  @debug.assert_eq(strip_argv0(["./main.exe"]), [])
}

///|
test "strip_argv0: an empty argv, and a first argument that looks like a subcommand" {
  @debug.assert_eq(strip_argv0([]), [])
  // a first argument that happens to be a subcommand name is stripped too (argv[0] is never user input)
  @debug.assert_eq(strip_argv0(["query", "--list"]), ["--list"])
}
