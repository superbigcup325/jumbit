// strip_argv0 单测：argv[0] 各真实形态（PATH 裸名 / 完整路径 / moon run exe 路径）一律剥掉

///|
test "strip_argv0：裸名与完整路径都剥首参" {
  // bash/fish/zsh 经 PATH 裸名调用：argv[0] = "jumbit"（不含 /）
  @debug.assert_eq(strip_argv0(["jumbit", "help"]), ["help"])
  // 全路径 / moon run exe 路径调用
  @debug.assert_eq(strip_argv0(["/usr/local/bin/jumbit", "add", "/tmp"]), ["add", "/tmp"])
  @debug.assert_eq(strip_argv0(["./main.exe"]), [])
}

///|
test "strip_argv0：空 argv 与形似子命令的首参" {
  @debug.assert_eq(strip_argv0([]), [])
  // 首参即使恰好是子命令名也剥（argv[0] 永远不是用户输入）
  @debug.assert_eq(strip_argv0(["query", "--list"]), ["--list"])
}
