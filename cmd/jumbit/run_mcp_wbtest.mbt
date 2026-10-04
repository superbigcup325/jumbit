///|
/// MCP 信封层 wbtest：只证「壳转发正确」——协议形状、方法分发、错误码、
/// 参数校验、执行层结果 → content/isError 映射。工具语义（score/matched_by/
/// 排序/懒删除）不在此重证：语义断言由 CLI 侧测试与 golden 承载，协议字节
/// 冻结由 scripts/mcp_check.sh 承载。

///|
async test "mcp initialize：支持版本回显 + 能力/服务器信息/instructions" {
  let resp = mcp_handle_line(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"0\"}}}",
    env_map([]),
  )
  let out = match resp {
    Some(out) => out
    None => fail("initialize 必须响应")
  }
  assert_true(out.contains("\"id\":1"))
  assert_true(out.contains("\"protocolVersion\":\"2025-03-26\""))
  assert_true(out.contains("\"capabilities\":{\"tools\":{}}"))
  assert_true(
    out.contains("\"serverInfo\":{\"name\":\"jumbit\",\"version\":\""),
  )
  assert_true(out.contains("\"instructions\":"))
}

///|
async test "mcp initialize：不支持版本回自身最新；id 非数字原样回显" {
  let resp = mcp_handle_line(
    "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"1.0\"}}",
    env_map([]),
  )
  let out = match resp {
    Some(out) => out
    None => fail("initialize 必须响应")
  }
  assert_true(out.contains("\"id\":\"abc\""))
  assert_true(out.contains("\"protocolVersion\":\"\{mcp_latest_version()}\""))
}

///|
async test "mcp ping/tools/list：result 形状与工具目录" {
  let ping = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("ping 必须响应")
  }
  assert_true(ping.contains("\"result\":{}"))
  let list = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("tools/list 必须响应")
  }
  assert_true(list.contains("\"tools\":["))
  assert_true(list.contains("\"name\":\"jumbit_query\""))
  assert_true(list.contains("\"name\":\"jumbit_export_agents\""))
  assert_true(list.contains("\"inputSchema\":{\"type\":\"object\""))
}

///|
async test "mcp 错误路：Parse error/-32601/未知工具/-32600/通知不响应" {
  // 非法 JSON → -32700 id null
  let bad = match mcp_handle_line("not json", env_map([])) {
    Some(out) => out
    None => fail("Parse error 必须响应")
  }
  assert_true(bad.contains("\"id\":null"))
  assert_true(bad.contains("\"code\":-32700"))
  // 未知方法 → -32601
  let unknown_method = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"resources/list\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("未知方法必须响应")
  }
  assert_true(unknown_method.contains("\"code\":-32601"))
  assert_true(unknown_method.contains("Method not found: resources/list"))
  // 未知工具 → -32602（协议层，对齐 atuin 划分）
  let unknown_tool = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"nope\"}}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("未知工具必须响应")
  }
  assert_true(unknown_tool.contains("\"code\":-32602"))
  assert_true(unknown_tool.contains("Unknown tool: nope"))
  // batch 数组（2025-06-18 已移除）→ -32600 id null
  let batch = match mcp_handle_line("[1,2]", env_map([])) {
    Some(out) => out
    None => fail("batch 必须响应")
  }
  assert_true(batch.contains("\"code\":-32600"))
  // jsonrpc 字段缺失的请求 → -32600
  let nover = match
    mcp_handle_line("{\"id\":6,\"method\":\"ping\"}", env_map([])) {
    Some(out) => out
    None => fail("缺版本字段必须响应")
  }
  assert_true(nover.contains("\"code\":-32600"))
  // 通知（无 id）不响应
  assert_eq(
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
      env_map([]),
    ),
    None,
  )
}

///|
async test "mcp tools/call jumbit_query：命中/miss/参数校验三路" {
  let data = make_test_dir("mcp-query")
  let zdir = make_test_dir("mcp-query-z")
  let zfile = zdir + "/zdata"
  // 入库路径用真实存在的 zdir + 新鲜 la：工具路不外露 --all，默认链路有
  // exists 检查 + 3 个月 TTL 懒删除，la=0 的条目会被直接懒删掉；
  // bytes 字面量不插值，先构 String 再 encode（atuin 折叠测试同款姿势）
  let zline = "\{zdir}|1.0|\{current_second()}\n"
  @platform.write_atomic(zfile, @utf8.encode(zline))
  let env = env_map([("_JB_DATA_DIR", data), ("_Z_DATA", zfile)])
  let errs : Array[String] = []
  assert_eq(run(["import", "z"], env, errs), 0)
  assert_eq(errs.length(), 0)
  let call = async fn(args : String) {
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"jumbit_query\",\"arguments\":\{args}}}",
      env,
    )
  }
  // 命中：content 内嵌与 query --json 同源的单行 JSON 数组
  let hit = match call("{\"keywords\":[\"mcp-query-z\"]}") {
    Some(out) => out
    None => fail("query 命中必须响应")
  }
  assert_true(hit.contains("\"isError\":false"))
  assert_true(hit.contains("mcp-query-z"))
  assert_true(hit.contains("matched_by"))
  // miss：isError=true，文案与 CLI stderr 同源
  let miss = match call("{\"keywords\":[\"zzz\"]}") {
    Some(out) => out
    None => fail("query miss 必须响应")
  }
  assert_true(miss.contains("\"isError\":true"))
  assert_true(miss.contains("no match found"))
  // 参数校验失败 → 协议层 -32602
  let badkw = match call("{\"keywords\":[1]}") {
    Some(out) => out
    None => fail("keywords 类型错必须响应")
  }
  assert_true(badkw.contains("\"code\":-32602"))
  let badlimit = match call("{\"keywords\":[\"x\"],\"limit\":1.5}") {
    Some(out) => out
    None => fail("limit 小数必须响应")
  }
  assert_true(badlimit.contains("\"code\":-32602"))
  // keywords 必填（schema required 同款）：缺失走协议层 -32602，
  // 不静默按「无关键词查最高分」执行
  let nokw = match call("{}") {
    Some(out) => out
    None => fail("缺 keywords 必须响应")
  }
  assert_true(nokw.contains("\"code\":-32602"))
  assert_true(nokw.contains("missing keywords"))
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "mcp tools/call jumbit_export_agents：地图进 content" {
  let data = make_test_dir("mcp-export")
  let target = make_test_dir("mcp-export-t")
  let errs : Array[String] = []
  assert_eq(run(["add", target], env_with(data), errs), 0)
  assert_eq(
    run(["describe", target, "--note", "后端服务"], env_with(data), errs),
    0,
  )
  let resp = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"jumbit_export_agents\"}}",
      env_with(data),
    ) {
    Some(out) => out
    None => fail("export 必须响应")
  }
  assert_true(resp.contains("\"isError\":false"))
  assert_true(resp.contains("jumbit export --agents"))
  assert_true(resp.contains("后端服务"))
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
test "mcp strip_eol：LF/CRLF/裸行三臂（\\r\\n 为 Windows 客户端真实发送形态）" {
  assert_eq(strip_eol("ping\n"), "ping")
  assert_eq(strip_eol("ping\r\n"), "ping")
  assert_eq(strip_eol("ping"), "ping")
  // 裸 \r 也剥（先 LF 后 CR 的顺序剥离，行内空白不碰）
  assert_eq(strip_eol("ping\r"), "ping")
}

///|
async test "mcp tools/call 卫士四臂：params 非对象/缺 tool name/arguments 非对象/fuzzy 非布尔（-32602）" {
  let data = make_test_dir("mcp-guard")
  let env = env_map([("_JB_DATA_DIR", data)])
  let call = async fn(raw_params : String) -> String {
    match
      mcp_handle_line(
        "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":\{raw_params}}",
        env,
      ) {
      Some(out) => out
      None => fail("tools/call 必须响应")
    }
  }
  // params 非对象（数组形态）
  assert_true(call("[]").contains("\"code\":-32602"))
  assert_true(call("[]").contains("missing params object"))
  // 缺 tool name
  assert_true(call("{\"arguments\":{}}").contains("missing tool name"))
  // tool name 非字符串
  assert_true(call("{\"name\":1}").contains("missing tool name"))
  // arguments 非对象
  assert_true(
    call("{\"name\":\"jumbit_query\",\"arguments\":1}").contains(
      "arguments must be an object",
    ),
  )
  // fuzzy 非布尔
  assert_true(
    call(
      "{\"name\":\"jumbit_query\",\"arguments\":{\"keywords\":[\"x\"],\"fuzzy\":\"yes\"}}",
    ).contains("fuzzy must be a boolean"),
  )
  cleanup_test_dir(data)
}
