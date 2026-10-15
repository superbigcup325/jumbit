///|
/// query\'s options and keywords (--exclude is an exact path, matching upstream; glob exclusion goes through _JB_EXCLUDE_DIRS;
/// --json/--fuzzy/--limit/--tsv are jumbit extensions upstream has no equivalent for)
pub(all) struct QueryOptions {
  keywords : Array[String]
  mut all : Bool
  mut list : Bool
  mut score : Bool
  mut interactive : Bool
  mut exclude : String?
  mut json : Bool
  mut fuzzy : Bool
  /// --limit <n>: truncate the list-shaped outputs (--list/--json/--tsv) to the first n; None = unset
  mut limit : Int32?
  /// --tsv: the headerless tab-separated data channel (a jumbit extension)
  mut tsv : Bool
} derive(Debug, Eq)

///|
/// Subcommands (add / query / remove / init / import / describe / export / help)
pub(all) struct AddOptions {
  paths : Array[String]
  mut score : Double
} derive(Debug, Eq)

///|
pub(all) struct InitOptions {
  shell : String
  mut cmd : String?
  mut hook : @tpl.Hook
  mut no_cmd : Bool
} derive(Debug, Eq)

///|
/// import\'s options: plugin in {atuin, autojump, fasd, z, z.lua, zsh-z};
/// --merge matches upstream\'s global flag and may appear anywhere before or after the plugin name
pub(all) struct ImportOptions {
  plugin : String
  mut merge : Bool
} derive(Debug, Eq)

///|
/// describe\'s options (a jumbit extension): note None means view mode, Some("") means clear
pub(all) struct DescribeOptions {
  path : String
  mut note : String?
} derive(Debug, Eq)

///|
/// export\'s options (a jumbit extension): --agents prints the project-map Markdown
pub(all) struct ExportOptions {
  mut agents : Bool
} derive(Debug, Eq)

///|
/// status\'s options (a jumbit extension): --json is a single-line JSON object; --check explicitly runs
/// the O(N) existence scan (the default quick check walks no filesystem)
pub(all) struct StatusOptions {
  mut json : Bool
  mut check : Bool
} derive(Debug, Eq)

///|

///|
/// edit\'s argument parsing (a jumbit extension, spec docs/spec-plaintext-edit.md §1.4):
/// no flag = interactive editing with $EDITOR; --rename <old> <new> changes a path (the note follows);
/// --prune drops entries that no longer exist. The three forms are mutually exclusive
pub(all) struct EditOptions {
  mut rename_old : String?
  mut rename_new : String?
  mut prune : Bool
} derive(Debug, Eq)

///|
/// Subcommands (add / query / remove / init / import / describe / export / help)
pub(all) enum Command {
  Add(AddOptions)
  Query(QueryOptions)
  Remove(Array[String])
  Init(InitOptions)
  Import(ImportOptions)
  Describe(DescribeOptions)
  Export(ExportOptions)
  Status(StatusOptions)
  /// Edit the database (a jumbit extension, no upstream equivalent; spec §1.4)
  Edit(EditOptions)
  /// The stdio MCP server (a jumbit extension, no upstream equivalent)
  Mcp
  Help
  /// Version output (--version/-V, matching upstream clap\'s top level)
  Version
  /// Called with no arguments: the full help goes to stderr with exit code 2 (matching upstream clap with no subcommand);
  /// distinct from Help (an explicit help/--help/-h, stdout + 0)
  Usage
  Unknown(String)
  /// A semantic argument error (conflicting flags / invalid value): the wording is reported as is, with no unknown-command prefix
  Invalid(String)
} derive(Debug, Eq)

///|
/// Subcommand parsing (args excludes the program name; verified for @env.args())
pub fn parse(args : Array[String]) -> Command {
  if args.is_empty() {
    return Usage
  }
  // top-level --version/-V (matching upstream clap): used alone it prints the version and exits 0;
  // followed by extra arguments it is a usage error with exit 2 (clap unexpected argument)
  if args[0] == "--version" || args[0] == "-V" {
    if args.length() == 1 {
      return Version
    }
    return Invalid("unexpected argument '\{args[1]}'")
  }
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(args[i])
  }
  match args[0] {
    "add" => parse_add(rest)
    "query" => parse_query(rest)
    "remove" => parse_remove(rest)
    "init" => parse_init(rest)
    "import" => parse_import(rest)
    "describe" => parse_describe(rest)
    "export" => parse_export(rest)
    "status" => parse_status(rest)
    "edit" => parse_edit(rest)
    "mcp" => parse_mcp(rest)
    "help" | "--help" | "-h" => Help
    // an unknown token in top-level flag form: clap reports unexpected argument (upstream
    // zoxide --bogus shows the same wording); only a bare token is an unrecognized subcommand
    other if other.has_prefix("-") => Invalid("unexpected argument '\{other}'")
    other => Unknown(other)
  }
}

///|
/// Float parsing (raise -> Option): for call sites that need a branch rather than an abort;
/// semantics match Rust f64::from_str (the same as clap: overflow saturates to ±inf, underscores rejected)
fn parse_double_opt(s : String) -> Double? {
  match @core.parse_f64(s) {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
/// Splitting the `--flag=value` form (matching upstream clap\'s two forms): a token with a `--` prefix whose
/// name part is not `--` is split at the first `=`, returning (name part, value part); anything else returns None.
/// The value part may contain `=` or be empty; `--=x` is not a flag and goes back down the bad-argument path
fn split_eq_flag(token : String) -> (String, String)? {
  if !token.has_prefix("--") {
    return None
  }
  match token.split_once("=") {
    Some((name, value)) => {
      let name = name.to_owned()
      if name == "--" {
        None
      } else {
        Some((name, value.to_owned()))
      }
    }
    None => None
  }
}

///|
/// Flag matching: a space-form token equal to the name, or an equals-form name part equal to it
fn eq_flag_match(raw : String, pair : (String, String)?, name : String) -> Bool {
  if raw == name {
    return true
  }
  match pair {
    Some((flag, _)) => flag == name
    None => false
  }
}

///|
/// --hook value -> the Hook enum (the value check shared by the space and equals forms)
fn parse_hook(v : String) -> @tpl.Hook? {
  match v {
    "pwd" => Some(@tpl.HookPwd)
    "prompt" => Some(@tpl.HookPrompt)
    "none" => Some(@tpl.HookNone)
    _ => None
  }
}

///|
/// add\'s `--` separator: only the first bare `--` is stripped; what follows is kept as is (including later `--`)
fn strip_double_dash(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut dropped = false
  for a in args {
    if !dropped && a == "--" {
      dropped = true
    } else {
      out.push(a)
    }
  }
  out
}

///|
/// The version line (the --version/-V output, from the same source as usage\'s first line)
pub fn version() -> String {
  "jumbit \{@jumbit.VERSION}"
}

///|
pub fn usage() -> String {
  "jumbit \{@jumbit.VERSION} — a MoonBit rewrite of zoxide\n\n" +
  "Usage:\n" +
  "  jumbit add [--score N] <path>...        record directories (--score sets this visit's weight)\n" +
  "  jumbit remove <path>...                 remove directories from the database\n" +
  "  jumbit query [kw]...                    print the highest-scoring match\n" +
  "    --list                                print all matches (by score, descending)\n" +
  "    --score                               prefix each line with its score\n" +
  "    --all                                 skip the existence check\n" +
  "    --exclude <path>                      exclude a path (exact match)\n" +
  "    --interactive                         select interactively with fzf\n" +
  "    --json                                print all matches as a single-line JSON array (agent channel, mutually exclusive with --interactive)\n" +
  "    --fuzzy                               fall back to component substrings when exact matching finds nothing (jumbit extension)\n" +
  "    --tsv                                 print Tab-separated path/score/last_accessed/matched_by (jumbit extension, mutually exclusive with --json/--interactive)\n" +
  "    --limit <n>                           print only the first n entries (with --list/--json/--tsv, jumbit extension)\n" +
  "  jumbit init <shell>                     generate shell integration code (defines j/ji by default, hook=pwd)\n" +
  "    [--cmd C] [--hook pwd|prompt|none] [--no-cmd]\n" +
  "  jumbit import <plugin> [--merge]        import history data from other tools (empty database imports directly, --merge merges into a non-empty one)\n" +
  "  jumbit describe <path> [--note text]    show or set a human note (--note \"\" clears, jumbit extension)\n" +
  "  jumbit export --agents                  print the project map as Markdown (paste into AGENTS.md, jumbit extension)\n" +
  "    plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z (bad lines are reported one by one, never aborting)\n" +
  "  jumbit status [--json] [--check]        database self-check: entries/notes/format/threshold (--check scans existence, --json for agents, jumbit extension)\n" +
  "  jumbit mcp                              start the stdio MCP server (agent channel, tools: jumbit_query / jumbit_export_agents, jumbit extension)\n" +
  "  jumbit edit                             edit the database with $VISUAL/$EDITOR (jumbit extension)\n" +
  "    [--rename <old> <new>] | [--prune]    rename a path (notes follow) / drop nonexistent entries; mutually exclusive\n" +
  "  jumbit help                             print this help\n" +
  "  jumbit --version                        print version (-V works too)\n\n" +
  "Environment variables:\n" +
  "  _JB_DATA_DIR                            data directory (default $HOME/.local/share/jumbit, must be absolute)\n" +
  "  _JB_ECHO=1                              echo directories as they are recorded\n" +
  "  _JB_EXCLUDE_DIRS                        colon-separated glob list, matched paths are kept out of the database\n" +
  "  _JB_FZF_OPTS                            extra arguments passed through to fzf\n" +
  "  _JB_RESOLVE_SYMLINKS=1                  resolve symlinks when recording (queries do not follow them)\n" +
  "  _JB_MAXAGE=N                            aging threshold for the database total score (default 10000)\n" +
  "  _JB_DOCTOR=0                            disable the shell configuration diagnostic hint (bash/zsh/posix only)\n" +
  "import reads each plugin's standard data file, located via _Z_DATA/_FASD_DATA/ZSHZ_DATA/_ZL_DATA/XDG_DATA_HOME"
}
