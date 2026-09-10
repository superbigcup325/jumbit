#!/usr/bin/env python3
"""子进程计时包装器：同一命令跑 N 轮，逐轮输出 wall 秒与子进程峰值 RSS。

输出行格式（TAB 分隔）：`<rep>\\t<wall 秒>\\t<maxrss KB>\\t<退出码>`，供编排脚
本聚合。峰值 RSS 取 resource.getrusage(RUSAGE_CHILDREN).ru_maxrss（Linux 单位
KB），是该进程全部已收子进程的历史峰值——每次调用只应跑一个场景（同一命令
N 轮），峰值即该场景峰值。stdout/stderr 按轮截断落盘（保留最后一轮现场，文
件尺寸即单轮产出规模），避免管道/终端 IO 污染计时。

env 值中的 `{rep}` 占位替换为轮号：import 类场景每轮需独立空库（非 --merge
对非空库拒绝），如 `--env=_JB_DATA_DIR=/tmp/x/jb-{rep}`。

计时含 subprocess.run 的 fork/exec 开销（毫秒级），对秒级场景可忽略。
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
                    help="追加环境变量（值支持 {rep} 占位）；可重复")
    ap.add_argument("--stdout", required=True, help="子进程 stdout 落盘路径（逐轮截断）")
    ap.add_argument("--stderr", required=True, help="子进程 stderr 落盘路径（逐轮截断）")
    ap.add_argument("cmd", nargs="+", help="被计时命令（-- 之后）")
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
