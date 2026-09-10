#!/usr/bin/env python3
"""合成 jumbit/zoxide 对拍数据集。

固定随机种子可复现；stdlib-only。三种格式：
- z 系（z/fasd/zsh-z/z.lua 共用）：`path|rank|last_accessed`
- autojump：`rank\\tpath`
- atuin：`YYYY-MM-DD HH:MM:SS\\tpath` 记录流（NUL 分隔由对拍脚本包装）

分布设计：
- 路径池 = 本机真实目录采样（find ~，限制深度与数量）+ 人工边界路径
- 访问频率按 Zipf 分布（少数目录占绝大多数访问，模拟真实足迹）
- 时间戳 7 成近期（指数分布）、2 成两年内、1 成陈旧（触发 ×0.25 档/懒删除），
  另含衰减档位精确边界（now-1h/-1d/-1w/-30d）
- rank 含常规浮点与边界字面量（nan/inf/+5/007/1e3 等——双方解析语义的对拍面）
- 少量确定性坏行（校验 stderr 坏行上报的逐字节一致）

用法：gen_dataset.py --format z --lines 20000 --out /tmp/ds/z.txt [--seed N]
"""

from __future__ import annotations

import argparse
import itertools
import os
import random
import subprocess
from datetime import datetime, timezone
from pathlib import Path

SEED = 20260908
# 固定基准时间（数据集创建日附近）：时间戳全部相对它生成，保证同种子逐字节可复现。
# 注意：随真实时间流逝，"近期"条目会逐渐陈旧——对对拍无影响（双方看到同一份数据）
NOW = 1788824275

# 人工边界路径：Unicode/空格/竖线/加点/超长/连字符混合（z 系格式允许 path 含 |）
EDGE_PATHS = [
    "/home/用户/博客",
    "/opt/with space/dir name",
    "/opt/pipe|in|path",
    "/data/.hidden/.config",
    "/data/trailing.dots...",
    "/data/" + "l" * 200 + "-long-component",
    "/data/a/b/c/d/e/f/deep-nest",
    "/data/mixed-中文-한국어-عربي",
    "/data/-dash-start",
    "/data/number-123-456",
]


def real_dir_pool(max_depth: int, limit: int) -> list[str]:
    """本机真实目录采样；find 失败或为空则退化为纯边界池。"""
    home = os.path.expanduser("~")
    try:
        out = subprocess.run(
            ["find", home, "-maxdepth", str(max_depth), "-type", "d"],
            capture_output=True,
            text=True,
            timeout=20,
            check=True,
        ).stdout.splitlines()
    except Exception:
        return []
    # 过滤明显噪声：超长路径、含换行不可能出现，find 也不会给出
    pool = [p for p in out if len(p) < 250 and p != home][:limit]
    return pool


def synthetic_pool(n: int) -> list[str]:
    """合成唯一路径池（性能规模集用）：组件词池 + 六位序号保证 n 条互不相同。

    末组件来自 10 词小池，供关键词查询场景按末组件命中约 1/10 条目。
    """
    words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
             "golf", "hotel", "india", "juliet", "kilo", "lima"]
    tails = ["src", "docs", "build", "test", "tools", "bin", "lib", "conf", "data", "log"]
    return [
        f"/opt/{words[i % len(words)]}/{words[(i // len(words)) % len(words)]}-{i:06d}/{tails[i % len(tails)]}"
        for i in range(n)
    ]


def zipf_pick(rng: random.Random, pool: list[str]) -> str:
    """1/rank 幂律采样：少数路径占绝大多数命中。"""
    rank = rng.paretovariate(1.2)  # 重尾
    idx = min(int(rank * 8), len(pool) - 1)
    return pool[idx]


def pick_offset(rng: random.Random) -> int:
    """距 now 的秒数偏移：时间衰减分布 + 精确档位边界。"""
    roll = rng.random()
    if roll < 0.10:
        # 精确档位边界（1h/1d/1w/30d 前）：双方衰减系数切换点
        return rng.choice([3600, 86400, 604800, 2592000])
    if roll < 0.75:
        # 近期：指数分布，均值 7 天
        return int(rng.expovariate(1 / (7 * 86400)))
    if roll < 0.95:
        # 两年内
        return rng.randint(86400, 2 * 365 * 86400)
    # 陈旧长尾（>3 个月，触发 ×0.25 与懒删除边界）
    return rng.randint(90 * 86400, 5 * 365 * 86400)


def unique_offsets(rng: random.Random, n: int) -> list[int]:
    """n 个唯一的秒级偏移：分布采样后排序去重（相邻 +1 保唯一）。
    唯一时间戳保证 score 几乎无平分——不同排序算法对相等 score 的平分顺序
    无法逐字节一致，唯一化是对拍稳定的前提。"""
    offsets = sorted(pick_offset(rng) for _ in range(n))
    for i in range(1, n):
        if offsets[i] <= offsets[i - 1]:
            offsets[i] = offsets[i - 1] + 1
    rng.shuffle(offsets)
    return offsets


RANK_POOL = [
    "1", "2.5", "0.5", "10", "100", "3.14159",
    "-2", "-0.75", "0", "007", "+5", "1e3", "-0",
    "0.1", "0.2", "0.3",  # 浮点精度敏感值
    "123.456", "99999",
]
# nan/inf 族：双方解析后按位型差异（payload/符号）会引入平分顺序分歧，不进
# 逐字节对拍面——其显示/排序语义由单测按上游 total_cmp 源码锁定。
# 1e308 同理：inf 聚合 clamp 后全部平分为 9999.0。
RANK_EDGE = ["nan", "NaN", "inf", "-inf", "infinity", "INF", "1e308"]


def pick_rank(rng: random.Random, allow_edge: bool) -> str:
    if allow_edge and rng.random() < 0.02:
        return rng.choice(RANK_EDGE)
    return rng.choice(RANK_POOL)


BAD_Z_LINES = [
    "nobar",
    "|1.5|100",
    "/a|x|100",
    "/a|1.5|y",
    "/a|1.5|-5",
    "",
    "1.5|100",
]
BAD_AJ_LINES = ["bad-line", "", "\t", "x\t", "1.5|no-tab"]


def gen_z(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
    path_iter=None,
) -> list[str]:
    offsets = unique_offsets(rng, lines)
    out = []
    for i in range(lines):
        if rng.random() < 0.01:
            out.append(rng.choice(BAD_Z_LINES))
            continue
        path = next(path_iter) if path_iter is not None else zipf_pick(rng, pool)
        if path == "":
            continue
        out.append(f"{path}|{pick_rank(rng, allow_edge)}|{now - offsets[i]}")
    return out


def gen_autojump(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
) -> list[str]:
    del now  # autojump 不落时间
    out = []
    for _ in range(lines):
        if rng.random() < 0.01:
            out.append(rng.choice(BAD_AJ_LINES))
            continue
        path = zipf_pick(rng, pool)
        if path == "":
            continue
        # autojump 权重任意浮点，时间不落盘（导入侧 sigmoid 归一 + last_accessed=0）
        out.append(f"{pick_rank(rng, allow_edge)}\t{path}")
    return out


def fmt_atuin_time(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def gen_atuin_records(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
) -> list[str]:
    """atuin 命令序记录：含大量连续重复（触发连续折叠语义）。"""
    del allow_edge  # atuin rank 恒 1.0，无 rank 字面量
    offsets = unique_offsets(rng, lines)
    out = []
    i = 0
    while i < lines:
        path = zipf_pick(rng, pool)
        if path == "":
            i += 1
            continue
        stay = min(rng.randint(1, 20), lines - i)  # 连住一个目录的命令数
        for _ in range(stay):
            if rng.random() < 0.02:
                # 时间戳边界（闰日/纪元前由解析端校验）
                ts = rng.choice([
                    "2024-02-29 00:00:00", "2023-02-29 00:00:00",
                    "1969-12-31 23:59:59",
                ])
            else:
                ts = fmt_atuin_time(now - offsets[i])
            out.append(f"{ts}\t{path}")
            i += 1
            if i >= lines:
                break
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--format", required=True, choices=["z", "autojump", "atuin"])
    ap.add_argument("--lines", type=int, default=20000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--max-depth", type=int, default=4)
    ap.add_argument("--now", type=int, default=NOW, help="时间戳基准 epoch 秒")
    ap.add_argument("--rank-edge", action="store_true",
                    help="掺入 nan/inf/1e308 边界 rank（仅供内容级对拍，逐字节对拍勿用）")
    ap.add_argument("--unique-paths", type=int, default=0,
                    help="改用合成唯一路径池（性能规模集，仅 --format z）：路径逐行轮转，"
                         "每路径约 lines/N 次（触发 dedup），不与本机真实池/Zipf 叠加")
    args = ap.parse_args()

    if args.unique_paths and args.format != "z":
        ap.error("--unique-paths 仅支持 --format z")

    rng = random.Random(args.seed)
    now = args.now

    path_iter = None
    if args.unique_paths:
        order = synthetic_pool(args.unique_paths)
        rng.shuffle(order)
        path_iter = itertools.cycle(order)
        pool = order  # 仅供末尾统计显示
    else:
        pool = real_dir_pool(args.max_depth, 800) + EDGE_PATHS
        if not pool:
            pool = list(EDGE_PATHS)

    if args.format == "z":
        lines_ = gen_z(rng, args.lines, pool, now, args.rank_edge, path_iter)
    elif args.format == "autojump":
        lines_ = gen_autojump(rng, args.lines, pool, now, args.rank_edge)
    else:
        lines_ = gen_atuin_records(rng, args.lines, pool, now, args.rank_edge)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.format == "atuin":
        # atuin --print0 语义：记录间 NUL 分隔、尾部 NUL（不是行文本！）
        out.write_bytes("\x00".join(lines_).encode("utf-8") + b"\x00")
    else:
        out.write_text("\n".join(lines_) + "\n", encoding="utf-8")
    print(f"{args.format}: {len(lines_)} lines -> {out} (seed={args.seed}, pool={len(pool)})")


if __name__ == "__main__":
    main()
