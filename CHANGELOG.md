# Changelog

本文件记录 jumbit 所有对外可见的变更，与 git 提交历史保持同步。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本（SemVer）。

## [Unreleased]

### Added

- 数据层：`Dir` 三字段模型（path/rank/last_accessed）与 frecency score 衰减（<1h ×4.0 / <1d ×2.0 / <1w ×0.5 / 其余 ×0.25）
- 数据库操作：权重累加（add/add_update，负增量 clamp 到 0）、按得分排序、dirty 标志
- 自有二进制持久化格式（4 字节版本号 + 长度前缀条目），32MiB 上限，畸形数据（截断/版本不符/非法 UTF-8/超限）明确报错
- 原子写：tmp 文件（系统熵随机名，冲突重试 5 次）+ sync 落盘 + rename 替换，失败自动清理
- 数据目录解析：`_JB_DATA_DIR`（须绝对路径）优先，回落 `$HOME/.local/share/jumbit`
- 项目脚手架：以 `moon new` 铺设，`preferred_target = "native"`，MIT 许可证，包结构按 `core`（纯函数内核）/ `platform`（IO 外壳）/ `config` / `cli` 分层
- 依赖锁定 `moonbitlang/async@0.21.2`：其 `fs` 子包提供带同步落盘的文件读写与 `rename`（原子写的基础），`process` 子包提供子进程调用（交互式选择的基础）
- 命令行入口 `jumbit`：输出版本号与项目简介
- 开发者回归脚本 `scripts/regression.sh`：`moon check --deny-warn`、`moon test`、`moon fmt --check`、`moon info` 接口面冻结四道闸，任一失败即非零退出

[Unreleased]: https://github.com/superbigcup325/jumbit
