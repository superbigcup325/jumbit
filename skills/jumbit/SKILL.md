---
name: jumbit
description: Use when finding a project directory by a partial or fuzzy name ("the backend repo", "where is that lab"), listing recently worked-on directories, or mapping what a workspace contains before starting work there. Resolves names against the user's real directory history (frecency-ranked) via the jumbit CLI, and exports an annotated project map for AGENTS.md.
---

# Directory recall with jumbit

jumbit keeps a frecency-ranked history of the user's directories (a MoonBit rewrite of
zoxide, independent database). When the user refers to a project loosely, ask jumbit —
do not guess paths or shell out to `find`.

If `jumbit` is not on `PATH`, fall back to asking the user for the path.

## Resolve a directory

```bash
jumbit query backend          # prints the single best-matching path; exit 1 on no match
jumbit query proj api         # multiple keywords: last one anchors the path's final component
```

Keywords are matched like zoxide: case-insensitive, the last keyword must land in the
final path component, earlier ones are consumed right-to-left. When exact matching finds
nothing, retry with `--fuzzy` (substring of any path component):

```bash
jumbit query --fuzzy back
```

## Machine-readable output (prefer this in scripts)

```bash
jumbit query --json --limit 5 backend
```

```json
[{"path":"/home/you/projects/backend-api","score":8,"last_accessed":1789054423,"matched_by":"exact"}]
```

- Single-line JSON array, key order fixed: `path, score, last_accessed, matched_by`
- `matched_by` is evidence: `exact` (keyword match) or `fuzzy` (`--fuzzy` fallback) —
  trust `exact` hits, double-check `fuzzy` ones before acting
- `jumbit query --tsv` emits headerless tab-separated rows, same column order; paths are
  written verbatim (a path containing a tab is ambiguous — treat TSV as best-effort)
- `jumbit query --list` lists all entries, `--score` prefixes each line with the score

## Exit codes & troubleshooting

Exit codes are the decision surface, identical across subcommands: `0` = result/success
(note: `query --list` exits 0 on empty output too), `1` = no match or runtime failure
(**"not found" is not a malfunction** — read stderr), `2` = usage error (stderr points
to `jumbit help`), `130` = fzf user interrupt (`--interactive` only).

| Symptom | Cause | Fix |
|---|---|---|
| A new directory is not found | Hook not installed, or never `cd`ed into | `jumbit add <dir>`; check the `init` eval line in the rc file |
| Result path no longer exists | Default queries filter nonexistent paths and lazily delete stale ones | `--all` to bypass |
| Fuzzy hit trustworthiness | — | `matched_by` in `--json`: `exact` = act, `fuzzy` = verify first |
| import refuses to run | Database non-empty | `--merge` |
| `could not find fzf` | fzf not installed | Install fzf or use non-interactive query |
| Where is the data | Default `$HOME/.local/share/jumbit/db.zo` | `_JB_DATA_DIR` (absolute path) |

## Record directories

```bash
jumbit add ~/projects/backend-api     # insert or bump frecency
```

The shell integration (`jumbit init bash`) records automatically on `cd`; when working
outside the user's shell, `add` keeps the history useful.

## Workspace map for AGENTS.md

```bash
jumbit describe ~/projects/backend-api --note "backend service"
jumbit export --agents >> AGENTS.md
```

`describe` attaches a human note to an entry (persisted in the database); `export
--agents` renders annotated entries as a Markdown table sorted by usage, ready to append
to AGENTS.md so agents know what lives where.

## Notes

- The database is jumbit's own format — it does not read zoxide's db. Check availability
  with `command -v jumbit`, and never try to parse zoxide's `db.zo`.
- Isolate runs (tests, sandboxes) with `_JB_DATA_DIR=/some/dir`.
- See `jumbit help` for the full command surface.
