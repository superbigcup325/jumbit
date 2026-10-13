# jumbit errors and troubleshooting

Exit codes, a stderr message reference, and what to do about common symptoms. The
full command and flag reference is in [USAGE.md](USAGE.md).

## Exit codes (common to every command)

| Code | Meaning |
|---|---|
| 0 | A result was produced, or the command succeeded. Note that `query --list` exits 0 on empty output too (silent, matching upstream) |
| 1 | No result, or a runtime failure (**"not found" is not a malfunction** — read stderr to tell the two apart) |
| 2 | Usage error (unknown command / mutually exclusive flags / missing required argument); stderr points at `jumbit help`. The wording is clap-style English (`error: ...` plus `For more information, try ...`) |
| 130 | The user interrupted fzf (`--interactive` only), passed through silently |

## Symptom lookup

| Symptom | Cause | What to do |
|---|---|---|
| A new directory cannot be found | The hook is not installed, or the directory was never cd-ed into | `jumbit add <dir>`; check that `eval "$(jumbit init bash)"` is in the rc file |
| The result path no longer exists | Default queries filter on existence and lazily delete stale entries | Use `--all` to bypass |
| Can a fuzzy hit be trusted? | Check `matched_by` in `--json`/`--tsv` | `exact` can be acted on; verify a `fuzzy` hit before acting |
| import refuses to run | The database is not empty | Add `--merge` |
| `could not find fzf` | fzf is not installed | Install fzf, or use a non-interactive query |
| Where is the data file? | Default `$HOME/.local/share/jumbit/db.txt` (an old db.zo is converted to plaintext on the first write; the original file is kept and can be deleted) | Redirect with `_JB_DATA_DIR` (an absolute path is required) |
| The shell prints "possible configuration issue" | The init line is not last in the rc file, or a later setting overrides it | Move `eval "$(jumbit init bash)"` to the end of the rc file; if you are sure it is fine, `export _JB_DOCTOR=0` silences the hint |

## stderr message reference

**Usage errors (exit 2)** — fix the command line:

| Message | Meaning |
|---|---|
| `error: unrecognized subcommand '<X>'` | The subcommand is misspelled (the following line says `For more information, try 'jumbit help'.`) |
| `error: add: missing required argument '<PATHS>'` | `add` was given no directory |
| `error: invalid value '<X>' for '--score <N>'` / `error: a value is required for '--score <N>' ...` | The weight is invalid or missing |
| `error: invalid value '<X>' for '--limit <n>'` / `error: a value is required for '--limit <n>' ...` | The truncation value is invalid |
| `error: the argument '--tsv' cannot be used with '--json'` and similar | The output channels are mutually exclusive; drop one |
| `error: '--limit' requires '--list', '--json' or '--tsv'` | `--limit` needs a list-shaped output |
| `error: missing required argument '<SHELL>'` / `error: invalid value '<X>' for '<SHELL>'` (with a `[possible values: ...]` line) | `init` was given no shell, or a misspelled one |
| `error: invalid value '<X>' for '--hook <HOOK>'` | The hook value is invalid |

**No result / runtime failure (exit 1)**:

| Message | Meaning and what to do |
|---|---|
| `jumbit: no match found` | Nothing matched — not a malfunction. Check that the keyword can anchor the final component (`projects` matches a directory whose last component contains `projects`), or run `query --list --score` first to see what the database holds |
| `jumbit: not a directory: <path>` | The `add` target does not exist or is not a directory |
| `jumbit: path not found in database: <path>` | The path given to `remove`/`describe` is not in the database (it may have been lazily deleted by a `_JB_EXCLUDE_DIRS` query, or by the TTL sweep after 3 months without a visit; `--exclude` only filters the output, it never deletes) |
| `jumbit: you are already in the only match` | The single match was excluded by `--exclude` (same wording as upstream) |
| `jumbit: no note found for <path>` | That entry has no human annotation (viewing mode still returns normally) |
| `error: note cannot contain newline or tab` plus exit code 2 | The `describe --note` text contains a newline or a tab (rejected at the parsing layer) |
| `jumbit: could not find fzf, is it installed?` | fzf is not installed or not executable; install fzf, or use a non-interactive query |
| `fzf returned an error` / `fzf was terminated` / `fzf returned an unknown error` | fzf itself exited abnormally; its stderr is printed verbatim, so debug on the fzf side (the usual cause: no usable terminal) |
| `jumbit: could not read <path>: <errno phrase> (os error N)` | import could not read the plugin's data file (e.g. `No such file or directory`); check the probed path such as `$_Z_DATA` |
| `jumbit: failed to run `atuin`; is it installed and on PATH?` | `import atuin` cannot find the atuin executable; install atuin, or import from another plugin instead |
| `jumbit: could not resolve path <path>: <errno phrase> (os error N)` | With `_JB_RESOLVE_SYMLINKS=1` the target cannot be realpath-ed (a symlink loop, for instance); fix the link or drop that variable |
| `jumbit: could not save database: io failure: <errno phrase> (os error N)` | The database file cannot be written (disk full / read-only directory / permissions); clear that up and retry |
| `jumbit: current database is not empty, specify --merge to continue anyway` | The import target database is not empty; add `--merge` once you are sure |
| `<file>:<line>: invalid entry: <line>` | import reports a bad row row by row (it does not abort the import); the row does not match the plugin's standard format |
| `jumbit: corrupted data file: <reason>` / `jumbit: could not open database: <reason>` | The database file cannot be parsed — see the next section |
| `jumbit: _JB_DATA_DIR must be an absolute path: <path>` | `_JB_DATA_DIR` was given a relative path; use an absolute one |
| `jumbit: cannot determine the data directory: set _JB_DATA_DIR` | HOME is unset and no `_JB_DATA_DIR` was given; set one of them |
| `jumbit: invalid glob in _JB_EXCLUDE_DIRS: <pattern>` | `_JB_EXCLUDE_DIRS` holds an invalid glob (an unterminated `[`, a reversed range, …); fix the pattern |
| `jumbit: _JB_MAXAGE must be a non-negative integer: <value>` | `_JB_MAXAGE` is not a non-negative integer; fix the value (validated when a write command runs; query does not consume it) |
| `jumbit: no editor: set $EDITOR or $VISUAL` | `jumbit edit` found no editor; set `VISUAL` or `EDITOR` |
| `jumbit: editor exited with code N` | The editor exited non-zero (the database was not changed); fix things on the editor side and retry |
| `jumbit: path already in database: <path>` | The `edit --rename` target is already in the database (rejected, not merged) |

## Recovering a corrupted database

The database file (`<data dir>/db.txt`) is plaintext, one
`timestamp<TAB>rank<TAB>path` per line. Light damage (a few bad lines) **can be
fixed by hand** — `jumbit status` reports the line number and the reason — and
then re-running `jumbit status` confirms it is clean:

```bash
jumbit status                                    # see where the bad lines are and why
$EDITOR ~/.local/share/jumbit/db.txt             # fix by hand (or use jumbit edit)
jumbit status                                    # confirm
```

Heavy damage (not worth fixing):

```bash
mv ~/.local/share/jumbit/db.txt ~/.local/share/jumbit/db.txt.bak   # keep a copy
jumbit status                                                      # from here it rebuilds as an empty database
```

The directory history then re-accumulates naturally, and existing plugin data can
be poured back with `jumbit import --merge z` and friends. Move the database
elsewhere with `_JB_DATA_DIR` (an absolute path is required).

Notes:

- An old binary `db.zo` is converted to `db.txt` on the first database write, and
  the **original file is kept**; once the new database looks right you can delete
  `db.zo` by hand
- `notes.tsv` (the annotation side file) can be edited alongside `db.txt`, one
  `path<TAB>note` per line. Annotations are keyed on the path, so renaming a path
  by hand does not move its note — edit both places, or use `edit --rename`, which
  carries the note along
