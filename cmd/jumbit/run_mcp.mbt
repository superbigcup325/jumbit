///|
/// The MCP stdio server (a jumbit extension, no upstream equivalent). The transport shape matches the MCP spec\'s
/// 2025-06-18 stdio transport: newline-delimited JSON-RPC 2.0, UTF-8, with
/// stdout carrying MCP messages only (a spec requirement; any logging must go to stderr).
/// A thin adapter with no new semantics: the tool execution layer is the same as the CLI\'s (query_exec\'s --json form /
/// export_exec), and the process exit code 0/1 maps straight onto isError; the only new decisions at the protocol layer are
/// the JSON-RPC envelope, the error codes and the content wrapper (protocol necessities). For the tool surface it follows
/// atuinsh/atuin crates/atuin-ai/src/mcp.rs (the rmcp SDK).
async fn run_mcp(getenv : (String) -> String?) -> Int32 {
  while true {
    match @stdio.stdin.read_until("\n") {
      // EOF: the client closing stdin is the spec\'s shutdown (close the stream, then wait for the process to exit), a silent exit 0
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
/// Strip a trailing newline (\n or \r\n; whitespace inside the line is already illegal JSON, so it is left alone)
fn strip_eol(s : String) -> String {
  let s = if s.has_suffix("\n") { s[0:s.length() - 1].to_owned() } else { s }
  if s.has_suffix("\r") {
    s[0:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// Handle one message: return the response line (None = no response). A pure envelope layer; tool bodies go through the execution layer.
async fn mcp_handle_line(
  line : String,
  getenv : (String) -> String?,
) -> String? {
  let msg : Json = @json.parse(line) catch {
    _ => return Some(mcp_error(Json::null(), -32700, "Parse error"))
  }
  let entries : Map[String, Json] = match msg {
    Json::Object(map) => map
    // MCP 2025-06-18 removed JSON-RPC batch, so an array or any other non-object shape is an Invalid Request
    _ => return Some(mcp_error(Json::null(), -32600, "Invalid Request"))
  }
  let id : Json? = entries.get("id")
  let method_name : String? = match entries.get("method") {
    Some(Json::String(m)) => Some(m)
    _ => None
  }
  // the jsonrpc version field: a missing field or anything but "2.0" -> Invalid Request (JSON-RPC 2.0 semantics);
  // a notification shape is always ignored silently (including notifications/initialized and unrecognised notifications)
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
/// Method dispatch for a confirmed "request" (a method and an id present, jsonrpc legal)
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
/// Version negotiation (the spec lifecycle): if the client\'s requested version is supported it MUST be echoed back;
/// otherwise the newest version this server supports is returned. An unsupporting client disconnects on its own.
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
  // serverInfo carries only name and version (matching atuin\'s two-argument Implementation::new);
  // capabilities declares tools only and no listChanged (the tool set is static and no change notification is sent)
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":{\"protocolVersion\":\"\{negotiated}\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"jumbit\",\"version\":\"\{@root.VERSION}\"},\"instructions\":\"\{json_escape(mcp_instructions())}\"}}"
}

///|
/// Server instructions: the "when to reach for jumbit" narrative a client injects into the model\'s system prompt
/// (the same lever atuin uses). Kept short (atuin self-checks against a 2000-character ceiling).
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
  "\"keywords\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Keywords matched against recorded paths (AND-ed); the last keyword anchors the final path component.\"}," +
  "\"fuzzy\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Fall back to substring matching of any path component when exact matching finds nothing.\"}," +
  "\"limit\":{\"type\":\"integer\",\"minimum\":0,\"description\":\"Maximum number of results. Omit for all.\"}" +
  "},\"required\":[\"keywords\"]}}"
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
/// tools/call: tool-name dispatch plus argument validation. An unknown tool or an illegal argument shape goes through the protocol layer
/// as -32602 (matching atuin\'s invalid_params split); a tool execution failure (a miss, or a
/// config/open error) becomes isError=true in the result, with the same wording as the CLI\'s stderr.
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
    // arguments may be omitted (a legal call shape for an argument-free tool)
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
/// jumbit_query arguments -> QueryOptions (the --json form; all/interactive/tsv are not exposed).
/// The limit domain matches the CLI\'s parse_limit_value: a non-negative integer, rejecting decimals and anything past the Int cap.
fn mcp_query_options(
  args : Map[String, Json],
) -> Result[@cli.QueryOptions, String] {
  // keywords is required (matching the inputSchema required field and USAGE\'s tool-registration draft):
  // a missing one goes through the protocol layer as -32602, never a silent "no keywords = highest score"
  let keywords : Array[String] = match args.get("keywords") {
    None => return Err("Invalid arguments: missing keywords")
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
  let limit : Int32? = match args.get("limit") {
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
/// The envelope writer: the key order is fixed by hand (for deterministic response bytes; Json::Object\'s stringify
/// goes through a hash table whose order is unstable, so it is not used for the envelope). The id is echoed through Json::stringify
/// (a Number keeps the client\'s literal repr, and a string id is escaped correctly).
fn mcp_ok(id : Json, result : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":\{result}}"
}

///|
fn mcp_error(id : Json, code : Int32, message : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"error\":{\"code\":\{code},\"message\":\"\{json_escape(message)}\"}}"
}

///|
fn mcp_tool_result(id : Json, text : String, is_error : Bool) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\{json_escape(text)}\"}],\"isError\":\{is_error}}}"
}
