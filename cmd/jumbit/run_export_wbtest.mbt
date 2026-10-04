///|
async test "export --agents：有标注条目出地图，缺 --agents 退出码 2，空库退出码 0" {
  let data = make_test_dir("exp-data")
  let target = make_test_dir("exp-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["describe", target, "--note", "后端服务"], env_with(data), errs),
    0,
  )
  @debug.assert_eq(run(["export", "--agents"], env_with(data), errs), 0)
  // 无标注条目不进地图：另一个目录只 add 不 describe
  let plain = make_test_dir("exp-plain")
  @debug.assert_eq(run(["add", plain], env_with(data), errs), 0)
  @debug.assert_eq(run(["export", "--agents"], env_with(data), errs), 0)
  // 参数错误
  @debug.assert_eq(run(["export"], env_with(data), errs), 2)
  // 空库不报错
  let empty = make_test_dir("exp-empty")
  @debug.assert_eq(run(["export", "--agents"], env_with(empty), errs), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
  cleanup_test_dir(plain)
  cleanup_test_dir(empty)
}
