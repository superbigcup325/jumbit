# BENCHMARKS

jumbit 与上游 zoxide 的百万行规模对拍基准。裁判是上游真二进制（zoxide 0.10.0），数据集固定种子可复现，所有场景位级一致性随表给出

> **English summary.** jumbit vs upstream zoxide 0.10.0 on a 1M-line synthetic z-format dataset (300k unique paths, fixed seed). Judge = the real upstream binary; byte-level parity is verified per run (entry count, import stderr, database file). jumbit is 2.5–4.6x slower in wall time and ~2x in peak memory at this scale; the margin analysis below explains where the time goes and why. Real-world directories hold hundreds to thousands of entries, two to three orders of magnitude below this stress dataset

## 方法学

| 项 | 值 |
|---|---|
| 硬件 | Intel i5-12500H（12th Gen，16 线程）/ 15 GiB / x86_64 |
| 系统 | CachyOS，kernel 7.2.4-3-cachyos |
| jumbit | release 构建，工具链 moon 0.1.20260904（数据采集时点的 ci.yml 锚定版本） |
| 裁判 | zoxide 0.10.0（PATH 真二进制，非 mock） |
| 数据集 | z 格式 1,000,000 行 / 300,000 唯一路径 / 43,822,540 字节（`scripts/gen_dataset.py`，seed=20260908，Zipf 访问分布 + 时间衰减 + 边界行 + 确定性坏行） |
| 环境压脚 | `_JB_MAXAGE`/`_ZO_MAXAGE` = u32::MAX（压住老化削库；1M 行 rank 累计远超默认阈值，不压则两侧同样清库） |
| 计时 | 每场景 3 轮取最优 wall；RSS = 子进程 getrusage 峰值（`scripts/perf_run.py`） |
| 判定 | 不求快过上游，只求数字健康（同量级）；位级看护 = 条目数 / import stderr / db 文件字节逐字节 |

## 结果

数据集 1M 行，入库约 26.7 万唯一条目（老化削边后，两侧一致）：

| 场景 | jumbit | zoxide | 时间比 |
|---|---|---|---|
| import z（1M 行全量导入） | 1.654s / 203.0 MB | 0.357s / 101.2 MB | 4.63x |
| query --list --score --all（全量输出） | 0.344s / 85.2 MB | 0.136s / 41.8 MB | 2.53x |
| query 关键词（单结果） | 0.075s / 85.2 MB | 0.024s / 41.8 MB | 3.12x |
| query --tsv --all（jumbit 扩展，上游无对应） | 0.151s / 85.1 MB | 无 | 无 |

位级一致性（每轮 perf_check 校验）：

- 库条目数：jumbit 266618 = zoxide 266618
- import stderr（坏行上报）：423845 = 423845 字节，逐字节
- 数据库文件：13,854,848 vs 13,854,856 字节（8 字节差异 = 上游头部多一个条目计数字段，内容条目一一对应）

## 边际由什么决定（What decides the margin）

**时间大头在 dedup 的前置排序，不在读取或写盘**。import 的 1.65s 里约 1s 是对 1M 条
`add_unchecked` 产物做 `sort_by_path`（2000 万+ 次 UTF-16 字符串比较）+ 1M 次
swap_remove。读取段已是单趟流式（对齐上游 import.rs::run 的惰性迭代结构），写盘段
（预分配编码 + 原子替换）占 ~0.25s。1M 行是一次性导入场景，秒级足够，进一步压缩
（哈希聚合替代排序）有 f64 求和顺序的字节级对拍代价，不做

**内存 2x 的构成**：pre-dedup 全量条目物化（~170MB，上游结构相同、Rust 对象更紧凑）
+ MoonBit String 为 UTF-16（每字符 2 字节，相对 Rust 的 UTF-8 有 ×~1.8 的字符串带宽
差）。优化链（单趟流式 / 惰性错误串 / 位置串按需构造 / 预分配编码）已把 import 峰值
从 499MB 压到 203MB（-59%）；query 侧 85MB 与上游 42MB 的差距同源

**规模感**：这是压力测试集。真实目录库是几百到几千条，比数据集小 2-3 个数量级，
全场景都在毫秒级，选型不应以本表为依据，表的价值在可复现与位级一致性证明

**jumbit 的差异面不在速度**：`--json`/`--tsv`/`--limit`/`--fuzzy`/`describe`/
`export --agents`/`status` 是上游没有的通道（agent/脚本消费面），本表仅确认这些
通道在大库下同量级健康

## 复现

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"
moon build --release
bash scripts/perf_check.sh          # 数据集生成 + 计时 + 位级看护，全程自动
```
