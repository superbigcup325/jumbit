# Changelog

本文件记录 jumbit 所有对外可见的变更，与 git 提交历史保持同步。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本（SemVer）。

## [Unreleased]

### Added

- 项目脚手架：以 `moon new` 铺设，`preferred_target = "native"`，MIT 许可证，包结构按 `core`（纯函数内核）/ `platform`（IO 外壳）/ `config` / `cli` 分层
- 依赖锁定 `moonbitlang/async@0.21.2`：其 `fs` 子包提供带同步落盘的文件读写与 `rename`（原子写的基础），`process` 子包提供子进程调用（交互式选择的基础）
- 命令行入口 `jumbit`：输出版本号与项目简介
- 开发者回归脚本 `scripts/regression.sh`：`moon check --deny-warn`、`moon test`、`moon fmt --check`、`moon info` 接口面冻结四道闸，任一失败即非零退出

[Unreleased]: https://github.com/superbigcup325/jumbit
