#!/usr/bin/env python3
"""Child-process timing wrapper: run the same command N rounds, printing wall seconds and the child\'s peak RSS each round.

Output line format (TAB separated): `<rep>\\t<wall seconds>\\t<maxrss KB>\\t<exit code>`, which the
orchestrating script aggregates. Peak RSS comes from resource.getrusage(RUSAGE_CHILDREN).ru_maxrss
(in KB on Linux), the historic peak over every child this process has reaped — so each invocation
should run exactly one scenario (N rounds of one command), making that peak the scenario\'s peak.
stdout/stderr are truncated to disk per round (keeping the last round\'s evidence; the file size then

reflects one round\'s output), which keeps pipe/terminal IO from polluting the timing.
The `{rep}` placeholder in an env value is replaced by the round number: import-type scenarios need a

fresh empty database each round (a non-`--merge` import refuses a non-empty one), e.g. `--env=_JB_DATA_DIR=/tmp/x/jb-{rep}`.
"""

from __future__ import annotations

import argparse
import os
import resource
import subprocess
import time


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--env", action="append", default=[], metavar="KEY=V",
                    help="extra environment variable (its value supports the {rep} placeholder); repeatable")
    ap.add_argument("--stdout", required=True, help="where to write the child\'s stdout (truncated per round)")
    ap.add_argument("--stderr", required=True, help="where to write the child\'s stderr (truncated per round)")
    ap.add_argument("cmd", nargs="+", help="the command to time (after --)")
    args = ap.parse_args()

    env = dict(os.environ)
    for kv in args.env:
        key, _, value = kv.partition("=")
        env[key] = value

    for rep in range(args.reps):
        cmd = [part.replace("{rep}", str(rep)) for part in args.cmd]
        renv = {k: v.replace("{rep}", str(rep)) for k, v in env.items()}
        with open(args.stdout, "wb") as fo, open(args.stderr, "wb") as fe:
            t0 = time.monotonic()
            proc = subprocess.run(cmd, env=renv, stdout=fo, stderr=fe)
            wall = time.monotonic() - t0
        rss_kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        print(f"{rep}\t{wall:.3f}\t{rss_kb}\t{proc.returncode}", flush=True)


if __name__ == "__main__":
    main()
