# BENCHMARKS

jumbit 与上游 zoxide 的百万行规模对拍基准。裁判是上游真二进制（zoxide 0.10.0），数据集固定种子可复现，一致性看护随表给出。本表记录于 2026-10-05（明文库解码快路径落地后的主线 release 构建）

> **English summary.** jumbit vs upstream zoxide 0.10.0 on a 1M-line synthetic z-format dataset (300k unique paths, fixed seed). Judge = the real upstream binary. jumbit is 5.5x slower in wall time on import (dedup sort dominated) and 1.5-3.2x on queries (plaintext db decode dominated; keyword matching went zero-alloc and sorting now happens after filtering); peak memory ~2.5x on import, ~1.3x on query. Entry counts legitimately diverge ~2% under the stress aging regime (jumbit clamps rank at entry per its documented policy, upstream does not); semantic parity is guarded by the boundary-row suite (dataset_check, 19/19) and perf_check carries a 5% tolerance band. Real-world directories hold hundreds to thousands of entries, two to three orders of magnitude below this stress dataset

## 方法学

| 项 | 值 |
|---|---|
| 记录日期 | 2026-10-05 |
| 硬件 | Intel i5-12500H（12th Gen，16 线程）/ 15 GiB / x86_64 |
| 系统 | CachyOS，kernel 7.2.8-2-cachyos |
| jumbit | release 构建（2026-10-05 主线，query 热路径两轮优化后），工具链 moon 0.1.20260920（记录时的 ci.yml 锚定版本；2026-10-15 升 0.1.20261012 后 perf_check 复核同量级） |
| 裁判 | zoxide 0.10.0（PATH 真二进制，非 mock） |
| 数据集 | z 格式 1,000,000 行 / 300,000 唯一路径 / 43,822,540 字节（`scripts/gen_dataset.py`，seed=20260908，Zipf 访问分布 + 时间衰减 + 边界行 + 确定性坏行） |
| 环境压脚 | `_JB_MAXAGE`/`_ZO_MAXAGE` = u32::MAX（压住老化削库；1M 行 rank 累计远超默认阈值，不压则两侧同样清库） |
| 计时 | 每场景 3 轮取最优 wall；RSS = 子进程 getrusage 峰值（`scripts/perf_run.py`） |
| 判定 | 不求快过上游，只求数字健康（同量级）；看护 = 条目数容差带（5%）/ import stderr 逐字节 / dataset_check 语义套件 |

## 结果

数据集 1M 行，入库约 27 万唯一条目（老化削边后）：

| 场景 | jumbit | zoxide | 时间比 |
|---|---|---|---|
| import z（1M 行全量导入） | 2.025s / 249.8 MB | 0.370s / 101.5 MB | 5.47x |
| query --list --score --all（全量输出） | 0.210s / 55.5 MB | 0.140s / 41.8 MB | 1.50x |
| query 关键词（单结果） | 0.060s / 55.4 MB | 0.019s / 41.9 MB | 3.16x |
| query --tsv --all（jumbit 扩展，上游无对应） | 0.214s / 55.4 MB | 无 | 无 |
| query --fuzzy 兜底 miss（jumbit 扩展，上游无对应） | 0.114s / 55.4 MB | 无 | 无 |

一致性看护（每轮 perf_check 校验）：

- 库条目数：jumbit 272133 vs zoxide 266618（差 ~2%）。这是 [#3] 的口径分歧非缺陷：jumbit 入库口钳位 rank（文档口径），上游不钳，u32::MAX 压脚域下边缘条目去留判定不同；语义一致性由 dataset_check 边界行套件把关（19/19 绿），perf_check 以 5% 容差带防灾难偏差
- import stderr（坏行上报）：423845 = 423845 字节，逐字节
- 库文件：jumbit 明文 db.txt 13,869,258 字节 vs 上游二进制 db.zo 13,854,856 字节（条目多集有上述 ~2% 差异，文件不再逐字节可比）

## 边际由什么决定（What decides the margin）

**query 的大头是明文库解码**。0.1.2 起库格式为明文 db.txt（对齐上游 #1288 分支，换取 `edit` 人工编辑与 human-readable），代价是每次载入把 13.8MB 文本逐行解析（时间戳整数 + 定点 rank + 路径串）。本轮两轮热路径改造后，解码是 qkw 0.060s 的主要构成。第一轮解码快路径：命中 encode 产物形态（纯数字时间戳 + 整数/恰两位定点 rank、值 ≤ 2^53）时免整行 UTF-8 解码与 parse_f64，函数级解码约 5x。第二轮过滤链：关键词匹配零归一化分配（ASCII 大写预扫 + 关键词归一提升到每查询一次）+ 排序后置（先过滤后排序，miss 型查询免全量排序 ~34ms），qkw 0.135 → 0.060s。剩余差距来自 27 万条 path 串物化与文本行结构本身；上游二进制格式解码 ~15ms 量级，该差距是格式特性的固有代价

**--fuzzy 兜底 miss（0.114s）单趟化**：原形态在精确路零命中后以空关键词重跑一整趟过滤链并对全库排序（~0.22s）；现改为趟内收集链路通过集（StreamOptions.fuzzy_superset，仅 --fuzzy 门控，普通查询零成本），零命中时就地模糊过滤 + 小集排序。glob/TTL 懒删集合与原二趟逐条核对一致

**import 的 2.1s 由 dedup 前置排序主导**：对 1M 条 `add_unchecked` 产物做 `sort_by_path`（`path_lex_cmp` 纯字典序比较器，MoonBit 层逐码元，2000 万+ 次比较）+ 1M 次 swap_remove，外加明文编码。读取段是单趟流式（对齐上游 import.rs::run 惰性迭代结构）。哈希聚合替代排序有 f64 求和顺序的字节级对拍代价，不做

**内存构成**：import 251MB = pre-dedup 全量条目物化（~170MB，上游结构相同、Rust 对象更紧凑）+ MoonBit String 为 UTF-16（每字符 2 字节，相对 Rust UTF-8 有 ×~1.8 的字符串带宽差）；历史优化链已把 import 峰值从 499MB 压到 200MB 量级。query 55MB = 解码产物物化（[#2] 去掉无条件落盘后不再持有 13.8MB 编码缓冲，从 85MB 降下来）vs 上游 42MB

**规模感**：这是压力测试集。真实目录库是几百到几千条，比数据集小 2-3 个数量级，全场景都在毫秒级，选型不应以本表为依据，表的价值在可复现与一致性看护证明

**jumbit 的差异面不在速度**：`--json`/`--tsv`/`--limit`/`--fuzzy`/`describe`/`export --agents`/`status` 是上游没有的通道（agent/脚本消费面），本表仅确认这些通道在大库下同量级健康

## 复现

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"
moon build --release
bash scripts/perf_check.sh          # 数据集生成 + 计时 + 一致性看护，全程自动
```
