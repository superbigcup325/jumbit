///|
/// MCP envelope-layer wbtest: it proves only that the shell forwards correctly -- the protocol shape, method dispatch, error codes,
/// argument validation, and the execution layer\'s result -> content/isError mapping. Tool semantics (score/matched_by/
/// sorting/lazy deletion) are not re-proved here: the semantic assertions live in the CLI-side tests and goldens, and the protocol bytes
/// are frozen by scripts/mcp_check.sh.

///|
async test "mcp initialize: a supported version echoed back, plus capabilities/server info/instructions" {
  let resp = mcp_handle_line(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"0\"}}}",
    env_map([]),
  )
  let out = match resp {
    Some(out) => out
    None => fail("initialize must respond")
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
async test "mcp initialize: an unsupported version returns this server\'s newest; a non-numeric id is echoed as is" {
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
async test "mcp ping/tools/list: the result shape and the tool directory" {
  let ping = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("ping must respond")
  }
  assert_true(ping.contains("\"result\":{}"))
  let list = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("tools/list must respond")
  }
  assert_true(list.contains("\"tools\":["))
  assert_true(list.contains("\"name\":\"jumbit_query\""))
  assert_true(list.contains("\"name\":\"jumbit_export_agents\""))
  assert_true(list.contains("\"inputSchema\":{\"type\":\"object\""))
}

///|
async test "mcp error paths: Parse error, -32601, an unknown tool, -32600, and notifications getting no reply" {
  // illegal JSON -> -32700 with a null id
  let bad = match mcp_handle_line("not json", env_map([])) {
    Some(out) => out
    None => fail("a Parse error must respond")
  }
  assert_true(bad.contains("\"id\":null"))
  assert_true(bad.contains("\"code\":-32700"))
  // an unknown method -> -32601
  let unknown_method = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"resources/list\"}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("an unknown method must respond")
  }
  assert_true(unknown_method.contains("\"code\":-32601"))
  assert_true(unknown_method.contains("Method not found: resources/list"))
  // an unknown tool -> -32602 (the protocol layer, matching atuin\'s split)
  let unknown_tool = match
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"nope\"}}",
      env_map([]),
    ) {
    Some(out) => out
    None => fail("an unknown tool must respond")
  }
  assert_true(unknown_tool.contains("\"code\":-32602"))
  assert_true(unknown_tool.contains("Unknown tool: nope"))
  // a batch array (removed in 2025-06-18) -> -32600 with a null id
  let batch = match mcp_handle_line("[1,2]", env_map([])) {
    Some(out) => out
    None => fail("a batch must respond")
  }
  assert_true(batch.contains("\"code\":-32600"))
  // a request with no jsonrpc field -> -32600
  let nover = match
    mcp_handle_line("{\"id\":6,\"method\":\"ping\"}", env_map([])) {
    Some(out) => out
    None => fail("a missing version field must respond")
  }
  assert_true(nover.contains("\"code\":-32600"))
  // a notification (no id) gets no reply
  assert_eq(
    mcp_handle_line(
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
      env_map([]),
    ),
    None,
  )
}

///|
async test "mcp tools/call jumbit_query: the hit, miss and argument-validation paths" {
  let data = make_test_dir("mcp-query")
  let zdir = make_test_dir("mcp-query-z")
  let zfile = zdir + "/zdata"
  // The imported path uses a real zdir plus a fresh la: the tool path does not expose --all, so the default chain has the
  // exists check plus the 3-month TTL lazy deletion, and an la=0 entry would be lazily deleted outright;
  // the bytes literal takes no interpolation, so a String is built first and encoded (the same stance as the atuin fold tests)
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
  // a hit: content embeds the single-line JSON array from the same source as query --json
  let hit = match call("{\"keywords\":[\"mcp-query-z\"]}") {
    Some(out) => out
    None => fail("a query hit must respond")
  }
  assert_true(hit.contains("\"isError\":false"))
  assert_true(hit.contains("mcp-query-z"))
  assert_true(hit.contains("matched_by"))
  // a miss: isError=true, with the wording from the same source as the CLI\'s stderr
  let miss = match call("{\"keywords\":[\"zzz\"]}") {
    Some(out) => out
    None => fail("a query miss must respond")
  }
  assert_true(miss.contains("\"isError\":true"))
  assert_true(miss.contains("no match found"))
  // a failed argument validation -> the protocol layer\'s -32602
  let badkw = match call("{\"keywords\":[1]}") {
    Some(out) => out
    None => fail("a wrong keywords type must respond")
  }
  assert_true(badkw.contains("\"code\":-32602"))
  let badlimit = match call("{\"keywords\":[\"x\"],\"limit\":1.5}") {
    Some(out) => out
    None => fail("a decimal limit must respond")
  }
  assert_true(badlimit.contains("\"code\":-32602"))
  // keywords is required (as in the schema): a missing one goes through the protocol layer as -32602,
  // never a silent "no keywords = highest score"
  let nokw = match call("{}") {
    Some(out) => out
    None => fail("a missing keywords must respond")
  }
  assert_true(nokw.contains("\"code\":-32602"))
  assert_true(nokw.contains("missing keywords"))
  cleanup_test_dir(data)
  cleanup_test_dir(zdir)
}

///|
async test "mcp tools/call jumbit_export_agents: the map goes into content" {
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
    None => fail("export must respond")
  }
  assert_true(resp.contains("\"isError\":false"))
  assert_true(resp.contains("jumbit export --agents"))
  assert_true(resp.contains("后端服务"))
  cleanup_test_dir(data)
  cleanup_test_dir(target)
}

///|
test "mcp strip_eol: the LF/CRLF/bare-line arms (\\r\\n is the shape a real Windows client sends)" {
  assert_eq(strip_eol("ping\n"), "ping")
  assert_eq(strip_eol("ping\r\n"), "ping")
  assert_eq(strip_eol("ping"), "ping")
  // 裸 \r 也剥（先 LF 后 CR 的顺序剥离，行内空白不碰）
  assert_eq(strip_eol("ping\r"), "ping")
}

///|
async test "mcp tools/call\'s four guard arms: params not an object, a missing tool name, arguments not an object, a non-boolean fuzzy (-32602)" {
  let data = make_test_dir("mcp-guard")
  let env = env_map([("_JB_DATA_DIR", data)])
  let call = async fn(raw_params : String) -> String {
    match
      mcp_handle_line(
        "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":\{raw_params}}",
        env,
      ) {
      Some(out) => out
      None => fail("tools/call must respond")
    }
  }
  // params is not an object (an array shape)
  assert_true(call("[]").contains("\"code\":-32602"))
  assert_true(call("[]").contains("missing params object"))
  // the tool name is missing
  assert_true(call("{\"arguments\":{}}").contains("missing tool name"))
  // the tool name is not a string
  assert_true(call("{\"name\":1}").contains("missing tool name"))
  // arguments is not an object
  assert_true(
    call("{\"name\":\"jumbit_query\",\"arguments\":1}").contains(
      "arguments must be an object",
    ),
  )
  // fuzzy is not a boolean
  assert_true(
    call(
      "{\"name\":\"jumbit_query\",\"arguments\":{\"keywords\":[\"x\"],\"fuzzy\":\"yes\"}}",
    ).contains("fuzzy must be a boolean"),
  )
  cleanup_test_dir(data)
}
