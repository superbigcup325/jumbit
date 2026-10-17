///|
async test "export --agents: annotated entries make the map, a missing --agents exits 2, an empty database exits 0" {
  let data = make_test_dir("exp-data")
  let target = make_test_dir("exp-target")
  let errs : Array[String] = []
  @debug.assert_eq(run(["add", target], env_with(data), errs), 0)
  @debug.assert_eq(
    run(["describe", target, "--note", "后端服务"], env_with(data), errs),
    0,
  )
  @debug.assert_eq(run(["export", "--agents"], env_with(data), errs), 0)
  // an unannotated entry stays out of the map: another directory is only added, never described
  let plain = make_test_dir("exp-plain")
  @debug.assert_eq(run(["add", plain], env_with(data), errs), 0)
  @debug.assert_eq(run(["export", "--agents"], env_with(data), errs), 0)
  // an argument error
  @debug.assert_eq(run(["export"], env_with(data), errs), 2)
  // an empty database does not error
  let empty = make_test_dir("exp-empty")
  @debug.assert_eq(run(["export", "--agents"], env_with(empty), errs), 0)
  cleanup_test_dir(data)
  cleanup_test_dir(target)
  cleanup_test_dir(plain)
  cleanup_test_dir(empty)
}
