# jumbit

a MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes.

[![CI](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml/badge.svg)](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/superbigcup325/jumbit/blob/main/LICENSE)
[![written in MoonBit](https://img.shields.io/badge/written%20in-MoonBit-9B7EDE)](https://www.moonbitlang.com/)
[![platform](https://img.shields.io/badge/platform-Linux-lightgrey)](https://github.com/superbigcup325/jumbit#与-zoxide-的差异)
[![rewrite of zoxide](https://img.shields.io/badge/rewrite%20of-zoxide-orange)](https://github.com/ajeetdsouza/zoxide)

jumbit 记录你去过的目录并按 frecency（频次 × 时间衰减）排序，用少量关键词跳转：

```bash
j projects      # 记录过的目录里匹配 projects 的最高分
j backend api   # 多关键词：api 锚定路径末组件，backend 向左消耗
```

## 安装

当前从源码构建（需 [MoonBit 工具链](https://www.moonbitlang.com/)）：

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"   # MoonBit 工具链
moon check && moon test               # 构建前自检（可选）
moon build --release
# 产物：_build/native/release/build/cmd/main/main.exe，拷进 PATH 即可
```

工具链锚定版本：`moon 0.1.20260904`（moonc v0.10.12）——CI 以此钉死可复现构建（`.github/workflows/ci.yml` 的 `MOONBIT_VERSION`），仓库全部闸门在该版本上验证。升级工具链时同步 bump 该常量并重跑全套验证（regression/golden/dataset/chaos/realdata），版本口径以该常量为唯一权威

注：发布到 mooncakes、提供预编译二进制在计划中

## 快速上手

```bash
# 1. shell 集成（以 bash 为例；zsh/fish 见「shell 集成」）
echo 'eval "$(jumbit init bash)"' >> ~/.bashrc && exec bash
# 2. 像平常一样干活——cd 换目录时自动记录
cd ~/projects/backend
# 3. 此后在任意位置按关键词跳回
j backend        # 记录过的目录里匹配 backend 的最高分
ji               # fzf 交互式跳转
```

记录是全自动的：换目录时 shell hook 调用 `jumbit add`；想看见它在记什么，`export _JB_ECHO=1`

## 用法

```bash
jumbit add ~/projects/backend        # 记录目录（hook 自动调用；也可手动）
jumbit add --score 3.5 ~/projects    # 指定本次增量权重
jumbit query backend                 # 输出匹配的最高分目录
jumbit query --list --score          # 全部匹配，按得分降序带分数前缀
jumbit query --interactive           # fzf 交互选择
jumbit query --all --exclude ~/tmp   # 跳过存在性检查 / 排除指定目录
jumbit query --json                  # 单行 JSON 数组输出全部匹配（agent 通道）
jumbit query --tsv                   # Tab 分隔数据行（agent 通道，jumbit 扩展）
jumbit query --list --limit 5        # 只输出前 5 条（列表型输出通用，jumbit 扩展）
jumbit query --fuzzy blog            # 精确零命中时按组件子串兜底（jumbit 扩展）
jumbit describe ~/projects/backend --note "后端服务"   # 人工标注（jumbit 扩展）
jumbit export --agents               # 项目地图 Markdown（jumbit 扩展）
jumbit remove ~/projects/backend     # 从数据库移除
jumbit help
```

## shell 集成

```bash
# bash：加入 ~/.bashrc
eval "$(jumbit init bash)"
# zsh：~/.zshrc；fish：~/.config/fish/config.fish 用 `jumbit init fish | source`
# 另支持 elvish / nushell / posix / powershell / tcsh / xonsh，用法同上

j backend        # 跳转（自动补全）
ji               # fzf 交互式跳转
```

参数：`--cmd C` 自定义命令名（默认 `j`，如 `--cmd=cd`）、`--hook pwd|prompt|none` 选择记录触发方式（默认 `pwd`）、`--no-cmd` 只生成内部函数

## 面向 agent

jumbit 的目录记忆不只喂给 shell，也喂给 coding agent。三条通道：

**机器可读查询**：`query --json` / `--tsv` 供 agent 脚本解析，`--limit N` 截断返回条数、控制上下文开销：

```bash
jumbit query --json backend
```

```json
[{"path":"/home/you/projects/backend-api","score":8,"last_accessed":1789054423,"matched_by":"exact"}]
```

- 键序固定 `path, score, last_accessed, matched_by`，单行数组，字节级稳定
- `last_accessed` 为 epoch 秒；`score` 为最短浮点表示（NaN/±Infinity 出 `null`，JSON 数值域）
- `matched_by` 是证据字段：`exact`（关键词精确匹配）或 `fuzzy`（`--fuzzy` 子串兜底命中），agent 可据此决定是否信任结果
- `--tsv` 出无表头 Tab 分隔行，列序与 JSON 键序一致，适合喂表格类工具：

```
/home/you/projects/backend-api	8	1789054423	exact
```

**项目地图**：`describe` 给常用目录加人工标注（随库持久化），`export --agents` 导出为 Markdown 表格，追加进 AGENTS.md 后，agent 打开工作区即获知项目分布与用途：

```bash
jumbit describe ~/projects/backend-api --note "后端服务"
jumbit export --agents >> AGENTS.md
```

```markdown
<!-- jumbit export --agents：项目地图，按常用度（frecency）降序 -->
| 路径 | 说明 |
|---|---|
| /home/you/projects/backend-api | 后端服务 |
```

## 与其他工具集成

jumbit 的目录记忆经 CLI 面供给其他工具消费，以下配置均经真机验证（sesh 2.29 / yazi 26.9）

### sesh（tmux 会话管理器）

sesh v2.29.0 起提供 `[frecency]` 配置节，可把 frecency 后端从 zoxide 整体换成 jumbit。写入 `~/.config/sesh/sesh.toml`：

```toml
[frecency]
list_command = "jumbit query --list --score"
query_command = "jumbit query {}"
add_command = "jumbit add {}"
remove_command = "jumbit remove {}"
```

`sesh list -z` 列出 jumbit 记录（按得分降序）；`sesh connect <名字或路径>` 创建并连接会话，连接后经 `add_command` 回写使用记录——跳转决策与记忆积累双向打通

### yazi（终端文件管理器）

yazi 26.x 经 `--cwd-file` 支持退出时回传所在目录，社区惯例是 shell 包装函数。加入 `~/.bashrc` 或 `~/.zshrc`：

```sh
yj() {
	local start="$PWD" tmp cwd
	if [ "$#" -gt 0 ]; then
		start="$(jumbit query "$@")" || return 1
	fi
	tmp="$(mktemp)" || return 1
	yazi "$start" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ]; then
		jumbit add -- "$cwd"
		[ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
```

`yj <关键词>` 经 jumbit 解析出目录作为 yazi 起点进入文件管理；退出后自动 `jumbit add` 喂入本次到达的目录并 cd 过去——文件管理器成为目录记忆的采集器

## 导入

如果你在用以下插件，可以把历史目录数据导入 jumbit。数据文件按各插件的标准约定自动探测：

```sh
jumbit import <plugin>
```

| 插件 | 命令 | 数据文件探测 |
|---|---|---|
| atuin | `jumbit import atuin` | 经 `atuin history list` 子进程读取 |
| autojump | `jumbit import autojump` | `$XDG_DATA_HOME/autojump/autojump.txt`，默认 `~/.local/share/autojump/autojump.txt` |
| fasd | `jumbit import fasd` | `$_FASD_DATA`，否则 `~/.fasd` |
| z | `jumbit import z` | `$_Z_DATA`，否则 `~/.z` |
| z.lua | `jumbit import z.lua` | `$_ZL_DATA`，否则 `~/.zlua`；主路径缺失回落 `zlua/zlua.txt` |
| zsh-z | `jumbit import zsh-z` | `$ZSHZ_DATA`，否则同 z |

注：数据库非空时须加 `--merge` 合并导入（如 `jumbit import --merge z`）；坏行逐条上报、不中止导入

## 工作原理

**frecency 排序**。每条记录是 `path / rank / last_accessed` 三字段，得分 = rank（累计访问权重）× 时间衰减系数，系数按 `last_accessed` 距今分档：

| 距上次访问 | 系数 |
|---|---|
| 1 小时内 | ×4.0 |
| 1 天内 | ×2.0 |
| 1 周内 | ×0.5 |
| 其余 | ×0.25 |

**老化**。库内总分**严格超过** `_JB_MAXAGE`（默认 10000）时触发一次全局衰减：全体 rank 乘 `0.9 × max_age / total`，乘后 rank < 1 的条目删除——常去的地方留下，冷门自然淡出

**关键词匹配**（语义对齐上游）：最后一个关键词锚定路径末组件（命中点右侧到路径末尾不得再出现分隔符），其余关键词从右往左逐个消耗、命中区间不重叠；大小写归一仅限 ASCII

```bash
j backend api   # api 落在路径末组件，backend 在其左侧消耗
```

**查询流**：按得分降序 → 关键词过滤 → glob 排除（命中即懒删）→ 存在性检查；不存在的目录超过 3 个月未访问，则在查询时懒删除

## 环境变量

| 变量 | 作用 | 默认 |
|---|---|---|
| `_JB_DATA_DIR` | 数据目录（须绝对路径） | `$HOME/.local/share/jumbit` |
| `_JB_ECHO=1` | add 时回显记录的目录 | 关 |
| `_JB_EXCLUDE_DIRS` | 冒号分隔的 glob，命中的目录不入库 | home 目录本身 |
| `_JB_FZF_OPTS` | 透传给 fzf 的自定义参数 | 内置参数组 |
| `_JB_MAXAGE` | 数据库总分老化阈值 | 10000 |
| `_JB_RESOLVE_SYMLINKS=1` | add 时解析符号链接 | 关 |

## 与 zoxide 的差异

- 持久化格式为自定义二进制（版本号 + 长度前缀条目），与上游 `db.zo` **不互通**；v2 起条目带 note 标注（jumbit 扩展），旧 v1 库免迁移兼容读
- 环境变量前缀 `_ZO_*` → `_JB_*`，两者可共存
- 关键词大小写归一仅限 ASCII（上游为 Unicode 全量）
- glob 排除不支持 `{a,b}` 括号展开；`**` 按两个 `*` 处理、不跨分隔符（上游 glob crate 的 `**` 为递归通配）；`*`/`?`/`[...]` 语义对齐
- 仅支持 Linux；fzf 预览窗口的平台定制未实现（import 的 autojump/z.lua 路径探测同按 Linux 语义）
- fzf 交互通道（`query --interactive`）：选中/`--score` 输出与退出码对齐上游（伪 fzf 探针矩阵逐字节对拍）；文案差异两处——fzf 取消（其退出码 1）jumbit 静默退出 1，上游报 `no match found`；fzf 自身异常的提示为英文原文且无 `zoxide: ` 前缀。另 spawn 失败不区分「未安装」与「无法启动」（上游区分，进程绑定不暴露错误类别），统一报 `could not find fzf, is it installed?`
- 未移植：`edit` 子命令
- 已知问题（与上游 0.10.0 一致）：非 finite rank 毒库——`import` 接受 `inf`/`nan` 字面量与溢出饱和为 inf 的大数作 rank，`add --score` 同样接受；随后老化遇 `total=inf` 因子归零、库内其余条目被清出，遇 `total=NaN` 老化永久停摆，全程退出码 0 无告警。上游修复 [ajeetdsouza/zoxide#1280](https://github.com/ajeetdsouza/zoxide/pull/1280) 未合并，合并后跟进
- 扩展（上游无）：`query --json`（单行 JSON 数组，含 `matched_by` 证据字段）、`query --tsv`（无表头 Tab 分隔行 `path\tscore\tlast_accessed\tmatched_by`，列序与 `--json` 键序一致；path 原样不转义——路径含 tab 时该行列数歧义，属已知限制；score 为最短表示，NaN/±Infinity 出 `NaN`/`Infinity`/`-Infinity` 原文而非 JSON 的 `null`）、`query --limit <n>`（`--list`/`--json`/`--tsv` 输出的前 n 条截断，`--limit 0` 为空输出、退出码 0；重复出现后者覆盖）、`query --fuzzy`（仅精确匹配零命中时启用，各关键词为某路径组件的子串即命中——不限末组件、无序且允许同组件，大小写归一同主路仅 ASCII）、`describe`（条目人工标注，随库持久化）与 `export --agents`（项目地图）

## 许可证

MIT License。基于 [zoxide](https://github.com/ajeetdsouza/zoxide)（MIT）的语义重写，许可证附原始版权声明
