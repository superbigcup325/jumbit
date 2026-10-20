# BENCHMARKS

jumbit vs upstream zoxide at the one-million-line scale. The judge is the real
upstream binary (zoxide 0.10.0), the dataset is fixed-seed and reproducible, and
the consistency guard is given alongside the table. Measured 2026-10-05, on a
main-line release build after the plaintext-database decode fast path landed.

> **English summary.** jumbit vs upstream zoxide 0.10.0 on a 1M-line synthetic z-format dataset (300k unique paths, fixed seed). Judge = the real upstream binary. jumbit is 5.5x slower in wall time on import (dedup sort dominated) and 1.5-3.2x on queries (plaintext db decode dominated; keyword matching went zero-alloc and sorting now happens after filtering); peak memory ~2.5x on import, ~1.3x on query. Entry counts legitimately diverge ~2% under the stress aging regime (jumbit clamps rank at entry per its documented policy, upstream does not); semantic parity is guarded by the boundary-row suite (dataset_check, 19/19) and perf_check carries a 5% tolerance band. Real-world directories hold hundreds to thousands of entries, two to three orders of magnitude below this stress dataset

## Methodology

| Item | Value |
|---|---|
| Measured | 2026-10-05 |
| Hardware | Intel i5-12500H (12th gen, 16 threads) / 15 GiB / x86_64 |
| System | CachyOS, kernel 7.2.x |
| jumbit | release build (main line 2026-10-05, after two rounds of query hot-path work), toolchain moon 0.1.20260920 (the version ci.yml anchored at the time; after the 2026-10-15 bump to 0.1.20261012 and the 2026-10-20 bump to 0.1.20261016, perf_check re-checked both times and found the same order of magnitude) |
| Judge | zoxide 0.10.0 (the real binary from PATH, not a mock) |
| Dataset | z format, 1,000,000 lines / 300,000 unique paths / 43,822,540 bytes (`scripts/gen_dataset.py`, seed=20260908, Zipf visit distribution + time decay + boundary rows + deterministic bad rows) |
| Environment pin | `_JB_MAXAGE`/`_ZO_MAXAGE` = u32::MAX (suppresses aging-driven pruning; 1M rows accumulate far past the default threshold, and without this both sides would prune identically) |
| Timing | best of 3 rounds per scenario by wall clock; RSS = peak from the child process's `getrusage` (`scripts/perf_run.py`) |
| Verdict | not "faster than upstream", only "healthy numbers" (same order of magnitude); the guard = the entry-count tolerance band (5%) / import stderr byte for byte / the dataset_check semantics suite |

## Results

Dataset 1M lines, about 270k unique entries after aging trims the edges:

| Scenario | jumbit | zoxide | Time ratio |
|---|---|---|---|
| import z (full 1M-line import) | 2.025s / 249.8 MB | 0.370s / 101.5 MB | 5.47x |
| query --list --score --all (full output) | 0.210s / 55.5 MB | 0.140s / 41.8 MB | 1.50x |
| query keyword (single result) | 0.060s / 55.4 MB | 0.019s / 41.9 MB | 3.16x |
| query --tsv --all (jumbit extension, no upstream counterpart) | 0.214s / 55.4 MB | — | — |
| query --fuzzy fallback miss (jumbit extension, no upstream counterpart) | 0.114s / 55.4 MB | — | — |

Consistency guards (checked on every perf_check run):

- Database entry count: jumbit 272133 vs zoxide 266618 (~2% apart). This is the documented divergence from [#3], not a defect: jumbit's import entry point clamps the rank (its documented policy) while upstream does not, so edge entries survive differently under the u32::MAX pin. Semantic consistency is guarded by the dataset_check boundary-row suite (19/19 green), and perf_check's 5% tolerance band prevents a catastrophic drift
- import stderr (bad-row reporting): 423845 = 423845 bytes, byte for byte
- Database file: jumbit's plaintext db.txt 13,869,258 bytes vs upstream's binary db.zo 13,854,856 bytes (given the ~2% entry-multiset difference above, the files are no longer byte-comparable)

## What decides the margin

**Queries are dominated by decoding the plaintext database.** Since 0.1.2 the
database format is plaintext db.txt (aligning with upstream's #1288 branch, in
exchange for `edit` being hand-editable and human-readable), at the cost of
parsing 13.8 MB of text line by line on every load (integer timestamp + fixed-point
rank + path string). After the two hot-path rounds in this cycle, that decode is
the bulk of qkw's 0.060s. Round one, the decode fast path: when a line matches the
shape the encoder produces (a plain-digit timestamp plus an integer or
exactly-two-decimal fixed-point rank, values ≤ 2^53), the whole-line UTF-8 decode
and `parse_f64` are skipped — about 5x at the function level. Round two, the
filter chain: keyword matching allocates nothing for normalization (an ASCII
pre-scan decides whether folding is needed, and folding is hoisted to once per
query) and sorting moved after filtering (filter first, sort after, so miss-type
queries skip the full sort, ~34ms), taking qkw from 0.135 to 0.060s. The remaining
gap comes from materializing 270k path strings and from the text line structure
itself; upstream's binary format decodes in ~15ms, and this gap is the inherent
price of the format.

**The --fuzzy fallback miss (0.114s) is now a single pass.** The old shape re-ran
the whole filter chain with an empty keyword after an exact-path miss and then
sorted the entire database (~0.22s); now the pass collects its own through-set
(StreamOptions.fuzzy_superset, gated on --fuzzy only, so ordinary queries pay
nothing) and, on a zero-hit result, filters fuzzily in place and sorts the small
set. The glob/TTL lazy-delete set matches the old two-pass result row for row.

**import's 2.1s is dominated by the pre-dedup sort**: a `sort_by_path` over 1M
`add_unchecked` products (the `path_lex_cmp` pure lexicographic comparator,
code-unit by code-unit in MoonBit, 20M+ comparisons) plus 1M `swap_remove` calls,
on top of the plaintext encoding. The read side is a single streaming pass
(matching upstream's lazy iterator structure in import.rs::run). Replacing the
sort with a hash aggregation would cost a byte-level diff on f64 summation order —
not worth it.

**Where the memory goes**: import's 251MB = the pre-dedup materialization of every
entry (~170MB; upstream's structure is the same but Rust objects are more compact)
plus MoonBit String being UTF-16 (2 bytes per char, roughly ×1.8 the string
bandwidth of Rust's UTF-8). The historical optimization chain already took
import's peak from 499MB down to the 200MB range. Query's 55MB = the materialized
decode products ([#2] stopped holding the 13.8MB encoded buffer once the
unconditional save was removed: down from 85MB) vs upstream's 42MB.

**Sense of scale**: this is a stress dataset. Real directory databases hold a few
hundred to a few thousand entries, two to three orders of magnitude less, and
every scenario sits in the millisecond range. Do not pick tools off this table;
its value is reproducibility and a demonstrated consistency guard.

**jumbit's differentiator is not speed**: `--json` / `--tsv` / `--limit` /
`--fuzzy` / `describe` / `export --agents` / `status` are channels upstream does
not have (the agent and script consumption surface). The table only confirms that
those channels stay healthy at the same order of magnitude on a large database.

## Reproduce

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"
moon build --release
bash scripts/perf_check.sh          # dataset generation + timing + consistency guards, fully automatic
```
