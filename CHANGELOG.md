# Changelog

本文件记录 jumbit 所有对外可见的变更，与 git 提交历史保持同步。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本（SemVer）。

## [Unreleased]

### Added

- glob 匹配器：`*`/`?`/`[...]`/`[!...]` 均不跨路径分隔符，`\` 转义，非法 pattern（未闭合/空类/倒序区间/尾转义）报错；`{a,b}` 不支持（与上游差异）
- 数据层：`Dir` 三字段模型（path/rank/last_accessed）与 frecency score 衰减（<1h ×4.0 / <1d ×2.0 / <1w ×0.5 / 其余 ×0.25）
- 数据库操作：权重累加（add/add_update，负增量 clamp 到 0）、按得分排序、dirty 标志
- 自有二进制持久化格式（4 字节版本号 + 长度前缀条目），32MiB 上限，畸形数据（截断/版本不符/非法 UTF-8/超限）明确报错
- 原子写：tmp 文件（系统熵随机名，冲突重试 5 次）+ sync 落盘 + rename 替换，失败自动清理
- 数据目录解析：`_JB_DATA_DIR`（须绝对路径）优先，回落 `$HOME/.local/share/jumbit`
- 项目脚手架：以 `moon new` 铺设，`preferred_target = "native"`，MIT 许可证，包结构按 `core`（纯函数内核）/ `platform`（IO 外壳）/ `config` / `cli` 分层
- 依赖锁定 `moonbitlang/async@0.21.2`：其 `fs` 子包提供带同步落盘的文件读写与 `rename`（原子写的基础），`process` 子包提供子进程调用（交互式选择的基础）
- 关键词查询：最后一个关键词锚定路径末组件、其余从右往左消耗不许重叠（对齐 zoxide 匹配语义，大小写归一仅 ASCII）
- 查询流过滤链：score 排序 → 关键词 → base_dir（组件级前缀）→ exclude glob（命中懒删除）→ exists 检查（最后执行）→ 不存在且超 3 个月 TTL 懒删除；exists 回调注入使过滤链可纯测试
- 数据库删除：按路径 remove 与 O(1) swap_remove（懒删除落库）
- 命令行入口 `jumbit`：`add <path>...` 记录目录（路径规范化、换行/非目录校验）、`query [kw]...` 按关键词过滤后输出最高得分目录、`help`
- 调试回显 `_JB_ECHO=1`：add 时回显记录的目录
- 端到端冒烟脚本 `scripts/smoke.sh`：真实二进制验证 add→query 回显与错误退出码
- 开发者回归脚本 `scripts/regression.sh`：`moon check --deny-warn`、`moon test`、`moon fmt --check`、`moon info` 接口面冻结四道闸，任一失败即非零退出

### Fixed

- 持久化解码拒绝路径字节含 NUL/换行的库文件（此前仅 add 入口拦截，手工构造的库文件可绕过）

### Internal

- Database 封装收敛：字段改为外部不可构造/原地修改，`all()` 返回数组副本，保证 dirty 标志一致性

[Unreleased]: https://github.com/superbigcup325/jumbit
