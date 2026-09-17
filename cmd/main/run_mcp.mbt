///|
/// MCP stdio 服务器（jumbit 扩展，上游无）。传输形态对齐 MCP 规范
/// 2025-06-18 的 stdio transport：newline-delimited JSON-RPC 2.0，UTF-8，
/// stdout 只承载 MCP 消息（规范硬性要求，任何日志只能走 stderr）。
/// 零新语义薄适配：工具执行层与 CLI 同源（query_exec 的 --json 形态 /
/// export_exec），进程退出码 0/1 直接映射 isError；协议层新增决策仅限
/// JSON-RPC 信封、错误码与 content 包装（协议必需品）。参考实现
/// atuinsh/atuin crates/atuin-ai/src/mcp.rs（rmcp SDK）的工具面划分。
async fn run_mcp(getenv : (String) -> String?) -> Int {
  while true {
    match @stdio.stdin.read_until("\n") {
      // EOF：客户端关闭 stdin 即规范 shutdown（关流→等进程退出），静默退出 0
      None => break
      Some(raw) => {
        let line = strip_eol(raw)
        if line == "" {
          continue
        }
        match mcp_handle_line(line, getenv) {
          Some(out) => @stdio.stdout.write(out + "\n") catch { _ => () }
          None => ()
        }
      }
    }
  }
  0
}

///|
/// 剥行尾换行（\n 与 \r\n 两形态；行内空白按 JSON 语义本就非法，不碰）
fn strip_eol(s : String) -> String {
  let s = if s.has_suffix("\n") { s[0:s.length() - 1].to_owned() } else { s }
  if s.has_suffix("\r") {
    s[0:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// 单条消息处理：返回响应行（None=不响应）。纯信封层，工具体走执行层。
async fn mcp_handle_line(
  line : String,
  getenv : (String) -> String?,
) -> String? {
  let msg : Json = @json.parse(line) catch {
    _ => return Some(mcp_error(Json::null(), -32700, "Parse error"))
  }
  let entries : Map[String, Json] = match msg {
    Json::Object(map) => map
    // MCP 2025-06-18 已移除 JSON-RPC batch；数组与其余非对象形态一律 Invalid Request
    _ => return Some(mcp_error(Json::null(), -32600, "Invalid Request"))
  }
  let id : Json? = entries.get("id")
  let method_name : String? = match entries.get("method") {
    Some(Json::String(m)) => Some(m)
    _ => None
  }
  // jsonrpc 版本字段：请求缺字段/非 "2.0" → Invalid Request（JSON-RPC 2.0 语义）；
  // 通知形态一律静默忽略（含 notifications/initialized 与无法识别的通知）
  let version_ok = match entries.get("jsonrpc") {
    Some(Json::String("2.0")) => true
    _ => false
  }
  match (method_name, id) {
    (Some(m), Some(id)) => {
      if !version_ok {
        return Some(mcp_error(id, -32600, "Invalid Request"))
      }
      mcp_handle_request(m, id, entries, getenv)
    }
    _ => None
  }
}

///|
/// 已确认「请求」（有 method 有 id、jsonrpc 合法）的方法分发
async fn mcp_handle_request(
  method_name : String,
  id : Json,
  entries : Map[String, Json],
  getenv : (String) -> String?,
) -> String? {
  match method_name {
    "initialize" => Some(mcp_initialize(id, entries))
    "ping" => Some(mcp_ok(id, "{}"))
    "tools/list" =>
      Some(mcp_ok(id, "{\"tools\":[\{mcp_query_tool()},\{mcp_export_tool()}]}"))
    "tools/call" => mcp_tools_call(id, entries, getenv)
    other => Some(mcp_error(id, -32601, "Method not found: \{other}"))
  }
}

///|
/// 版本协商（规范 lifecycle）：支持客户端请求版本则 MUST 回显同版本；
/// 否则回自身支持的最新版本。客户端不支持时会自行断开。
fn mcp_latest_version() -> String {
  "2025-06-18"
}

///|
fn mcp_version_supported(v : String) -> Bool {
  v == "2024-11-05" || v == "2025-03-26" || v == "2025-06-18"
}

///|
fn mcp_initialize(id : Json, entries : Map[String, Json]) -> String {
  let requested : String? = match entries.get("params") {
    Some(Json::Object(p)) =>
      match p.get("protocolVersion") {
        Some(Json::String(v)) => Some(v)
        _ => None
      }
    _ => None
  }
  let negotiated = match requested {
    Some(v) => if mcp_version_supported(v) { v } else { mcp_latest_version() }
    None => mcp_latest_version()
  }
  // serverInfo 只带 name/version（对齐 atuin Implementation::new 两参形态）；
  // capabilities 只声明 tools 且无 listChanged（工具集静态，不发变更通知）
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":{\"protocolVersion\":\"\{negotiated}\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"jumbit\",\"version\":\"\{@jumbit.VERSION}\"},\"instructions\":\"\{json_escape(mcp_instructions())}\"}}"
}

///|
/// server instructions：客户端注入模型 system prompt 的「何时用 jumbit」
/// 叙事（atuin 同杠杆）。保持短小（atuin 以 2000 字符为上限自检）。
fn mcp_instructions() -> String {
  "jumbit is the user's directory memory: a frecency-ranked history of directories they have actually worked in (a MoonBit rewrite of zoxide, own database). " +
  "Use jumbit_query when the user refers to a project by a loose or partial name ('the backend repo', 'that lab dir') instead of guessing paths or running find. " +
  "Results carry matched_by evidence: trust exact hits, verify fuzzy ones before acting. " +
  "Use jumbit_export_agents to read the human-annotated project map before exploring the filesystem; the user's other projects live in this history, and 'not in this repository' is not an answer."
}

///|
fn mcp_query_tool() -> String {
  "{\"name\":\"jumbit_query\"," +
  "\"title\":\"Search directory history\"," +
  "\"description\":\"\{json_escape(mcp_query_description())}\"," +
  "\"inputSchema\":{\"type\":\"object\",\"properties\":{" +
  "\"keywords\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Keywords matched against recorded paths (AND-ed); the last keyword anchors the final path component. Omit to list all entries.\"}," +
  "\"fuzzy\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Fall back to substring matching of any path component when exact matching finds nothing.\"}," +
  "\"limit\":{\"type\":\"integer\",\"minimum\":0,\"description\":\"Maximum number of results. Omit for all.\"}" +
  "}}}"
}

///|
fn mcp_export_tool() -> String {
  "{\"name\":\"jumbit_export_agents\"," +
  "\"title\":\"Export annotated project map\"," +
  "\"description\":\"\{json_escape(mcp_export_description())}\"," +
  "\"inputSchema\":{\"type\":\"object\",\"properties\":{}}}"
}

///|
fn mcp_query_description() -> String {
  "Search the user's frecency-ranked directory history and return matching paths with score, last_accessed and matched_by evidence, as a single-line JSON array (same shape as jumbit query --json). " +
  "Keywords match like zoxide: case-insensitive; the last keyword must land in the final path component, earlier ones are consumed right-to-left. " +
  "With fuzzy=true, keywords fall back to substring matches of any path component when exact matching finds nothing. " +
  "A miss is a normal outcome, reported with isError=true and the reason as text."
}

///|
fn mcp_export_description() -> String {
  "Export the user's annotated project map: a Markdown table (path | description) of directories that carry human-written notes, ordered by frecency descending — the same output as jumbit export --agents. " +
  "Use it to learn what the user's main projects are and what each one is for."
}

///|
/// tools/call：工具名分发 + 参数校验。未知工具/参数形态非法走协议层
/// -32602（对齐 atuin 的 invalid_params 划分）；工具执行失败（miss、
/// 配置/打开库错误）走结果内 isError=true，文案与 CLI stderr 同源。
async fn mcp_tools_call(
  id : Json,
  entries : Map[String, Json],
  getenv : (String) -> String?,
) -> String? {
  let params : Map[String, Json] = match entries.get("params") {
    Some(Json::Object(p)) => p
    _ =>
      return Some(
        mcp_error(id, -32602, "Invalid arguments: missing params object"),
      )
  }
  let name = match params.get("name") {
    Some(Json::String(n)) => n
    _ =>
      return Some(mcp_error(id, -32602, "Invalid arguments: missing tool name"))
  }
  let args : Map[String, Json] = match params.get("arguments") {
    Some(Json::Object(a)) => a
    // arguments 可省略（无参工具的合法调用形态）
    None => {}
    _ =>
      return Some(
        mcp_error(id, -32602, "Invalid arguments: arguments must be an object"),
      )
  }
  match name {
    "jumbit_query" => {
      let qopts = match mcp_query_options(args) {
        Ok(opts) => opts
        Err(msg) => return Some(mcp_error(id, -32602, msg))
      }
      let errs : Array[String] = []
      let outs : Array[String] = []
      let code = query_exec(qopts, getenv, errs, fn(s) { outs.push(s) })
      let text = if code == 0 { join_lines(outs) } else { join_lines(errs) }
      Some(mcp_tool_result(id, text, code != 0))
    }
    "jumbit_export_agents" => {
      let errs : Array[String] = []
      let outs : Array[String] = []
      let code = export_exec({ agents: true, }, getenv, errs, fn(s) {
        outs.push(s)
      })
      let text = if code == 0 { join_lines(outs) } else { join_lines(errs) }
      Some(mcp_tool_result(id, text, code != 0))
    }
    other => Some(mcp_error(id, -32602, "Unknown tool: \{other}"))
  }
}

///|
/// jumbit_query 参数 → QueryOptions（--json 形态；all/interactive/tsv 不外露）。
/// limit 值域对齐 CLI parse_limit_value：非负整数、拒小数、拒超 Int 上限。
fn mcp_query_options(
  args : Map[String, Json],
) -> Result[@cli.QueryOptions, String] {
  let keywords : Array[String] = match args.get("keywords") {
    None => []
    Some(Json::Array(items)) => {
      let kws : Array[String] = []
      for item in items {
        match item {
          Json::String(s) => kws.push(s)
          _ =>
            return Err(
              "Invalid arguments: keywords must be an array of strings",
            )
        }
      }
      kws
    }
    Some(_) =>
      return Err("Invalid arguments: keywords must be an array of strings")
  }
  let fuzzy = match args.get("fuzzy") {
    None => false
    Some(Json::True) => true
    Some(Json::False) => false
    Some(_) => return Err("Invalid arguments: fuzzy must be a boolean")
  }
  let limit : Int? = match args.get("limit") {
    None => None
    Some(Json::Number(n, ..)) => {
      if n < 0.0 || n > 2147483647.0 || n != n.floor() {
        return Err("Invalid arguments: limit must be a non-negative integer")
      }
      Some(n.to_int())
    }
    Some(_) =>
      return Err("Invalid arguments: limit must be a non-negative integer")
  }
  Ok({
    keywords,
    all: false,
    list: false,
    score: false,
    interactive: false,
    exclude: None,
    json: true,
    fuzzy,
    limit,
    tsv: false,
  })
}

///|
fn join_lines(lines : Array[String]) -> String {
  let out : StringBuilder = StringBuilder()
  for i, line in lines {
    if i > 0 {
      out.write_string("\n")
    }
    out.write_string(line)
  }
  out.to_string()
}

///|
/// 信封写出器：键序手工固定（响应字节确定性；Json::Object 的 stringify
/// 走哈希表键序不稳定，不用于信封）。id 经 Json::stringify 原样回显
/// （Number 保留客户端字面量 repr，字符串 id 正确转义）。
fn mcp_ok(id : Json, result : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":\{result}}"
}

///|
fn mcp_error(id : Json, code : Int, message : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"error\":{\"code\":\{code},\"message\":\"\{json_escape(message)}\"}}"
}

///|
fn mcp_tool_result(id : Json, text : String, is_error : Bool) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\{json_escape(text)}\"}],\"isError\":\{is_error}}}"
}
