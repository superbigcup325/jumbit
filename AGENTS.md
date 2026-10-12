# jumbit — AGENTS.md

jumbit is a MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide):
a frecency-ranked directory jumper for the shell. It is an independent
implementation written from scratch — not a fork, and no code is carried over
from upstream.

The name: zoxide describes itself as "jump to directories in a few keystrokes";
jump + Moon**bit**.

## Repository layout

```
core/        database model, frecency scoring, keyword matching, codec
cli/         command parsing, subcommand implementations, and their tests
config/      data-directory resolution (_JB_DATA_DIR, else $HOME/.local/share/jumbit)
             and shell-import path handling
platform/    OS-facing pieces: atomic write, fzf integration, editor, import
templates/   generated shell integration (bash/zsh/fish/elvish/nushell/powershell)
cmd/         the native binary entry point
scripts/     dataset generators, golden checks, integration test drivers
```

- MoonBit packages are organized per directory, one `moon.pkg` each; `moon.mod`
  at the top level
- Blackbox tests are `*_test.mbt`, whitebox tests `*_wbtest.mbt`
- `templates/` is **generated** (upstream's shell templates through a one-shot
  transpiler) — do not hand-edit; regenerate instead
- `.agents/skills/jumbit/SKILL.md` tells an agent how to call jumbit, for both
  the CLI and the MCP server

## Build and test

```bash
export PATH="$HOME/.moon/bin:$PATH"   # the toolchain is not on PATH by default

moon check --deny-warn
moon test
moon fmt --check
moon info        # regenerates the .mbti interfaces, which are committed
```

- `moon check --deny-warn`, `moon test` and `moon fmt --check` must all be green
- `.mbti` interface files are version-controlled: run `moon info` and stage the
  result whenever a public signature changes
- Tests must cover the core path **and** the failure paths
- The docstring tests in `README.mbt.md` are a plus signal

## Coding conventions

- Block style, blocks separated by `///|`
- Public `derive(Debug, Eq)` method-lift suppression lives in each package's
  `extends.mbt` (`#deprecated` + `#doc(hidden)` `pub extend`)
- Blackbox tests refer to the package under test as `@pkg.fn`
- Prefer fixing the root cause over layering a workaround. If the cause is
  structural, straighten the structure out first (single source of truth,
  de-duplication), then fix — the bar is that the same class of problem cannot
  recur
- When the semantics are ambiguous, the upstream implementation decides: read the
  Rust source or probe it. Where jumbit deliberately differs, the difference must
  be listed in the README
- Isolated and parallel tests must use the underscore-prefixed `_JB_*` variables;
  upstream ignores the unprefixed names, so a typo silently touches the real
  database

## Documentation style

- Chinese prose carries no trailing period on a paragraph or list item; English
  keeps normal punctuation
- No em-dashes in Chinese prose — use commas, colons or parentheses
- README badges may only state verifiable facts (static shields; never claim a
  platform or a version that is not actually built and tested)

## Toolchain

- The pinned toolchain version in `ci.yml` is the source of truth
- Install and upgrade from `cli.moonbitlang.com`

## Known pitfalls

(Add a row as each one is hit: symptom → root cause → the fix to reuse)
