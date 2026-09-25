# jumbit

<a href="README_EN.md">English</a> | 简体中文

a MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes，用少量关键词跳回去过的目录，jump + Moon**bit**

[![CI](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml/badge.svg)](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/superbigcup325/jumbit/blob/main/LICENSE)
[![written in MoonBit](https://img.shields.io/badge/written%20in-MoonBit-9B7EDE)](https://www.moonbitlang.com/)
[![platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)](USAGE.md#与-zoxide-的差异)
[![rewrite of zoxide](https://img.shields.io/badge/rewrite%20of-zoxide-orange)](https://github.com/ajeetdsouza/zoxide)

```bash
cd ~/projects/backend     # 照常干活：cd 换目录时自动记录
cd ~/somewhere/else       # …
j backend                 # 一个词，跳回 ~/projects/backend
ji                        # 或者 fzf 交互式挑
```

## 为什么做

zoxide 用 frecency（频次 × 时间衰减）把「cd 过的地方」变成「一个词就能回去」，是现代 shell 的标配。jumbit 把这套久经验证的语义用 MoonBit 从零重写：不携带上游任何代码，行为逐条对齐 zoxide 0.10.0，包括衰减系数、关键词匹配、老化口径、退出码、fzf 通道并有百万行级数据与上游真二进制的位级对拍背书（[BENCHMARKS.md](BENCHMARKS.md)）

在这个底座上，jumbit 把目录记忆延伸到 shell 之外：coding agent 是新的「重度 cd 用户」，为此 jumbit 准备了机器可读查询、人工标注、项目地图与 MCP 服务器，让 agent 打开工作区，即知目录分布与用途

## 功能

- **关键词跳转**：`j backend`、`j backend api`，使用 frecency 排序，最后一个关键词锚定路径末组件，多关键词从右往左消耗（语义对齐上游）
- **9 shell 集成**：bash / zsh / fish 等九个模板，cd 自动记录，`j`/`ji`（fzf 交互）与补全开箱即用
- **agent 通道**：`--json`/`--tsv` 字节级稳定输出（含 `matched_by` 证据字段）、`describe` 人工标注随库持久化、`export --agents` 生成项目地图 Markdown、`jumbit mcp` 起 stdio MCP 服务器（`jumbit_query`/`jumbit_export_agents` 双工具 + server instructions，官方 SDK 真 client 实测）
- **历史迁移**：从 z / zsh-z / z.lua / autojump / fasd / atuin 一键导入，空库直灌、`--merge` 合并、坏行不中止
- **工具生态**：sesh（tmux 会话管理）可整体切换 frecency 后端；yazi 经包装函数成为目录记忆采集器
- **数据自检与编辑**：`status` 一眼看库（条目/标注/格式/老化阈值），`edit` 用编辑器或 `--rename`/`--prune` 直接改库，`--json` 供脚本消费

## 安装

从源码构建（需 [MoonBit 工具链](https://www.moonbitlang.com/)，锚定 `moon 0.1.20260920`，CI 以此钉死可复现构建）：

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"   # MoonBit 工具链
moon check && moon test               # 构建前自检（可选）
moon build --release
cp _build/native/release/build/cmd/main/main.exe ~/.local/bin/   # 或任意 PATH 目录
```

工具链锚定：CI 以 `.github/workflows/ci.yml` 的 `MOONBIT_VERSION` 常量钉死可复现构建；升级工具链时同步 bump 该常量并重跑全套验证（regression/golden/dataset/chaos/realdata），版本口径以该常量为唯一权威

mooncakes 已发布 `superbigcup325/jumbit 0.1.0`，但滞后于 main（不含近期修复）；预编译二进制在计划中

## 快速上手

```bash
# 1. shell 集成（bash 为例；zsh/fish 等见 USAGE.md）
echo 'eval "$(jumbit init bash)"' >> ~/.bashrc && exec bash
# 2. 像平常一样干活：cd 换目录时自动记录
cd ~/projects/backend
# 3. 此后在任意位置按关键词跳回
j backend        # 记录过的目录里匹配 backend 的最高分
ji               # fzf 交互式跳转（需安装 fzf）
```

记录是全自动的：换目录时 shell hook 调用 `jumbit add`；想看见它在记什么，`export _JB_ECHO=1`

## 最小命令集

```bash
jumbit add ~/projects/backend        # 记录目录（hook 自动调用；也可手动）
jumbit query backend                 # 输出匹配的最高分目录
jumbit query --list --score          # 全部匹配，按得分降序带分数前缀
jumbit describe ~/projects/backend --note "后端服务"   # 人工标注（jumbit 扩展）
jumbit status                        # 数据库自检（jumbit 扩展）
jumbit remove ~/projects/backend     # 从数据库移除
jumbit help                          # 全部命令与 flag
```

## 文档

- [USAGE.md](USAGE.md)：完整用法，含命令与 flag 全表、shell 集成参数与 `j`/`ji` 行为、agent 通道（`--json`/`--tsv`/tool 注册 schema）、sesh/yazi 配置、六插件导入、frecency/老化/匹配语义、环境变量、与 zoxide 的差异
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)：报错与故障，含退出码表、常见症状速查、stderr 文案对照、数据损坏处置
- [BENCHMARKS.md](BENCHMARKS.md)：百万行规模对拍基准（裁判 = 上游真二进制）
- skill 加载型 agent：[skills/jumbit/SKILL.md](skills/jumbit/SKILL.md)

## 许可证

MIT License。基于 [zoxide](https://github.com/ajeetdsouza/zoxide)（MIT）的语义重写，许可证附原始版权声明
