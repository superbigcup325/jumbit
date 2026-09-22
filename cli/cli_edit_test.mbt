///|
/// edit 参数解析测试（规格 docs/spec-plaintext-edit.md §1.4 互斥矩阵）

///|
fn edit_opts(
  rename_old? : String? = None,
  rename_new? : String? = None,
  prune? : Bool = false,
) -> @cli.EditOptions {
  { rename_old, rename_new, prune, }
}

///|
test "parse edit：无 flag = 交互形态；--prune；等号形态" {
  @debug.assert_eq(@cli.parse(["edit"]), @cli.Edit(edit_opts()))
  @debug.assert_eq(
    @cli.parse(["edit", "--prune"]),
    @cli.Edit(edit_opts(prune=true)),
  )
  // 布尔/未知 flag 的等号形式维持报原文 exit 2（对齐 clap，--flag=value 全局语义）
  @debug.assert_eq(
    @cli.parse(["edit", "--prune=true"]),
    @cli.Unknown("--prune=true"),
  )
}

///|
test "parse edit：--rename 双参（空格/等号两形态）" {
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b"]),
    @cli.Edit(edit_opts(rename_old=Some("/a"), rename_new=Some("/b"))),
  )
  @debug.assert_eq(
    @cli.parse(["edit", "--rename=/a", "/b"]),
    @cli.Edit(edit_opts(rename_old=Some("/a"), rename_new=Some("/b"))),
  )
}

///|
test "parse edit：缺参/重复/互斥矩阵" {
  // 缺 new
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a"]),
    @cli.Unknown("--rename 缺少 <new> 参数"),
  )
  // 全缺
  @debug.assert_eq(
    @cli.parse(["edit", "--rename"]),
    @cli.Unknown("--rename 缺少 <old> <new> 两个参数"),
  )
  // 重复
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b", "--rename", "/c", "/d"]),
    @cli.Unknown("--rename 重复出现"),
  )
  // 互斥（Invalid 语义错误，exit 2）
  @debug.assert_eq(
    @cli.parse(["edit", "--rename", "/a", "/b", "--prune"]),
    @cli.Invalid("edit: --rename 与 --prune 互斥"),
  )
  // 未知 flag 与多余位置参数
  @debug.assert_eq(@cli.parse(["edit", "--nope"]), @cli.Unknown("--nope"))
  @debug.assert_eq(@cli.parse(["edit", "/path"]), @cli.Unknown("/path"))
}
