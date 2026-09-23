# jumbit 使用手册

完整用法参考：命令与 flag 全表、shell 集成参数、agent 通道、工具集成、导入、工作原理、环境变量与差异清单。报错排查见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)，性能基准见 [BENCHMARKS.md](BENCHMARKS.md)

## 命令总览

```bash
jumbit add [--score N] <path>...        记录目录（hook 自动调用；也可手动；--score 指定本次增量权重）
jumbit remove <path>...                 从数据库移除目录
jumbit query [kw]...                    输出最高得分匹配目录
  --list                                输出全部匹配（按得分降序）
  --score                               前缀显示得分
  --all                                 跳过存在性检查
  --exclude <path>                      排除指定目录（精确路径，glob 排除走 _JB_EXCLUDE_DIRS）
  --interactive                         fzf 交互式选择
  --json                                单行 JSON 数组输出全部匹配（agent 通道，与 --interactive 互斥）
  --fuzzy                               精确零命中时按组件子串兜底（jumbit 扩展）
  --tsv                                 Tab 分隔输出 path/score/last_accessed/matched_by（jumbit 扩展，与 --json/--interactive 互斥）
  --limit <n>                           只输出前 n 条（与 --list/--json/--tsv 组合，jumbit 扩展）
jumbit init <shell>                     生成 shell 集成脚本（默认定义 j/ji，hook=pwd）
  [--cmd C] [--hook pwd|prompt|none] [--no-cmd]
jumbit import <plugin> [--merge]        从其他工具导入历史数据（plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z）
jumbit describe <path> [--note text]    查看/设置人工标注（--note "" 清除，jumbit 扩展）
jumbit export --agents                  输出项目地图 Markdown（jumbit 扩展）
jumbit status [--json] [--check]        数据库自检：条目/标注/格式/阈值（--check 扫存在性，jumbit 扩展）
jumbit edit                             用 $VISUAL/$EDITOR 编辑数据库（jumbit 扩展）
  [--rename <old> <new>] | [--prune]    改路径（标注跟随）/ 清除不存在条目；三形态互斥
jumbit mcp                              启动 stdio MCP 服务器（agent 通道，jumbit 扩展，见「面向 agent」）
jumbit help                             显示帮助
```

语法与行为速记：

- flag 两形态等价：`--cmd zj` 与 `--cmd=zj`（对齐上游 clap 双形态）
- 带值 flag（`--score` / `--exclude` / `--limit` / `--note`）重复出现时后者覆盖；`--` 之后不再解析 flag
- `query` 无关键词 = 输出最高分条目；`query --list` 空结果静默、退出码 0（对齐上游）
- `describe <path>` 不带 `--note` 为查看模式：打印现有标注，无标注 exit 1
- 单结果路 stdout 是纯路径，可直接 `cd "$(jumbit query kw)"`
- `query` 默认做存在性过滤并懒删陈旧条目；确要绕过用 `--all`

## shell 集成

```bash
# bash：加入 ~/.bashrc
eval "$(jumbit init bash)"
# zsh：~/.zshrc；fish：~/.config/fish/config.fish 用 `jumbit init fish | source`
# 另支持 elvish / nushell / posix / powershell / tcsh / xonsh，用法同上

j backend        # 跳转（自动补全）
ji               # fzf 交互式跳转（需安装 fzf）
```

`init` 参数：

| 参数 | 作用 | 默认 |
|---|---|---|
| `--cmd C` | 自定义命令名（两形态 `--cmd cd` / `--cmd=cd`） | `j`（交互命令 `ji` 同步派生） |
| `--hook pwd\|prompt\|none` | 记录触发方式：换目录时 / 提示符时机 / 不自动记录 | `pwd` |
| `--no-cmd` | 只生成内部函数，不定义公开命令（自行 alias） | 关 |

`j` 的完整行为：

| 调用 | 行为 |
|---|---|
| `j`（无参数） | 回 home |
| `j -` | 回上一个目录（OLDPWD） |
| `j <存在的路径>` | 直达该目录（先于关键词匹配） |
| `j <关键词>...` | frecency 最高分匹配并 cd；跳转目的地随后自动入库（`--hook none` 下不自动记录） |
| `ji [关键词]...` | fzf 交互式选择后 cd |

> 测试覆盖口径：bash / zsh / fish 的 hook 链路在 CI 中真跑（source init 输出、驱动钩子、断言落点与入库）；其余六模板为上游同源转译，仅做语法门禁校验，未做 headless 全链路真测，发现问题请提 issue

## 面向 agent

jumbit 的目录记忆不只喂给 shell，也喂给 coding agent。四条通道：

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

**退出码与报错**：agent 决策面，0 有结果或成功；1 无结果或运行失败（「没查到」不是故障，读 stderr 区分）；2 用法错误；130 fzf 用户中断。全表与 stderr 文案对照见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**注册为 tool**（工具注册型 agent 的 JSON schema 草案；skill 加载型用仓库 `skills/jumbit/SKILL.md`）：

```json
{
  "name": "jumbit_query",
  "description": "Resolve a directory from the user's frecency-ranked directory history. Prefer this over guessing paths or running find. Exit code 1 means no match, not failure.",
  "parameters": {
    "type": "object",
    "properties": {
      "keywords": {
        "type": "array",
        "items": {"type": "string"},
        "description": "One or more keywords; the last anchors the final path component"
      },
      "fuzzy": {
        "type": "boolean",
        "description": "Substring fallback when exact matching misses"
      },
      "limit": {
        "type": "integer",
        "description": "Cap rows returned to control context size"
      }
    },
    "required": ["keywords"]
  }
}
```

命令面映射：`jumbit query --json [--fuzzy] [--limit N] <keywords...>`，解析 stdout 单行 JSON，按 `matched_by` 决定信任级别

**MCP 服务器**：`jumbit mcp` 起 stdio MCP 服务器（Model Context Protocol，stdio transport），上一节的 tool 注册对 MCP 客户端是自动的：客户端从 `tools/list` 拿 schema，无需手工注册。Claude Code 一行接入：

```bash
claude mcp add jumbit -- jumbit mcp
```

其他 MCP 客户端用等价 JSON 配置：

```json
{
  "mcpServers": {
    "jumbit": {
      "command": "jumbit",
      "args": ["mcp"]
    }
  }
}
```

- 两个 tool：`jumbit_query`（`keywords`/`fuzzy`/`limit`，返回与 `query --json` 同源同形的单行 JSON 数组）、`jumbit_export_agents`（无参，返回项目地图 Markdown）
- `initialize` 应答带 server instructions（何时用 jumbit 的短叙事，客户端注入模型 system prompt）；协议版本支持 2024-11-05 / 2025-03-26 / 2025-06-18，协商规则=支持则回显、否则回 2025-06-18
- newline-delimited JSON-RPC 2.0，stdout 只承载协议消息（日志无）；客户端关闭 stdin 即正常退出（exit 0）
- 错误划分对齐同类实现（atuin mcp）：未知工具/参数非法走协议层 -32602；miss 等执行失败走结果内 `isError: true`，文案与 CLI stderr 同源（「没查到」不是故障）
- 协议字节面由 `scripts/mcp_check.sh` 冻结（CI 步骤），真 client 兼容性经官方 TypeScript SDK 实测

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

`sesh list -z` 列出 jumbit 记录（按得分降序）；`sesh connect <名字或路径>` 创建并连接会话，连接后经 `add_command` 回写使用记录，跳转决策与记忆积累双向打通

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

`yj <关键词>` 经 jumbit 解析出目录作为 yazi 起点进入文件管理；退出后自动 `jumbit add` 喂入本次到达的目录并 cd 过去，文件管理器成为目录记忆的采集器

## 导入

如果你在用以下插件，可以把历史目录数据导入 jumbit。数据文件按各插件的标准约定自动探测：

```sh
jumbit import <plugin>
```

| 插件 | 命令 | 数据文件探测 | 数据格式 |
|---|---|---|---|
| atuin | `jumbit import atuin` | 经 `atuin history list` 子进程读取 | `YYYY-MM-DD HH:MM:SS<TAB>path`（子进程输出） |
| autojump | `jumbit import autojump` | `$XDG_DATA_HOME/autojump/autojump.txt`，默认 `~/.local/share/autojump/autojump.txt` | `rank<TAB>path`（rank 过 sigmoid 归一，对齐上游） |
| fasd | `jumbit import fasd` | `$_FASD_DATA`，否则 `~/.fasd` | `path\|rank\|timestamp` |
| z | `jumbit import z` | `$_Z_DATA`，否则 `~/.z` | `path\|rank\|timestamp` |
| z.lua | `jumbit import z.lua` | `$_ZL_DATA`，否则 `~/.zlua`；主路径缺失回落 `zlua/zlua.txt` | `path\|rank\|timestamp`（与 z 同解析器，对齐上游） |
| zsh-z | `jumbit import zsh-z` | `$ZSHZ_DATA`，否则同 z | `path\|rank\|timestamp` |

注：数据库非空时须加 `--merge` 合并导入（如 `jumbit import --merge z`）；坏行逐条上报、不中止导入

注：atuin 经子进程 `atuin history list` 读取，其退出码不检查（对齐上游）：atuin 自身报错时得到空结果且 exit 0，成败以 stderr 为准

## 工作原理

**frecency 排序**。每条记录是 `path / rank / last_accessed` 三字段，得分 = rank（累计访问权重）× 时间衰减系数，系数按 `last_accessed` 距今分档：

| 距上次访问 | 系数 |
|---|---|
| 1 小时内 | ×4.0 |
| 1 天内 | ×2.0 |
| 1 周内 | ×0.5 |
| 其余 | ×0.25 |

**老化**。库内总分**严格超过** `_JB_MAXAGE`（默认 10000）时触发一次全局衰减：全体 rank 乘 `0.9 × max_age / total`，乘后 rank < 1 的条目删除，常去的地方留下，冷门自然淡出

**持久化**。数据存于明文文本 `<数据目录>/db.txt`，每行一条：`timestamp\trank\tpath`（timestamp 为 10 位访问时间，rank 定点两位小数、上限 9999999.99），任意文本工具可直接查看与手改（改坏会整库拒绝加载并按行报错，见 TROUBLESHOOTING）。人工标注存于同目录 `notes.tsv`（`path\tnote`），不进 db.txt；换行/tab 的标注被拒绝。旧版二进制 `db.zo` 首次写库时自动转换为明文，转换后原文件保留，确认无误可手动删除

**关键词匹配**（语义对齐上游）：最后一个关键词锚定路径末组件（命中点右侧到路径末尾不得再出现分隔符），其余关键词从右往左逐个消耗、命中区间不重叠；大小写归一仅限 ASCII

```bash
j backend api   # api 落在路径末组件，backend 在其左侧消耗
```

**查询流**：按得分降序 → 关键词过滤 → glob 排除（`_JB_EXCLUDE_DIRS`，命中即懒删）→ 存在性检查；不存在的目录超过 3 个月未访问，则在查询时懒删除

## 环境变量

| 变量 | 作用 | 默认 |
|---|---|---|
| `_JB_DATA_DIR` | 数据目录（须绝对路径） | `$HOME/.local/share/jumbit` |
| `_JB_ECHO=1` | add 时回显记录的目录 | 关 |
| `_JB_EXCLUDE_DIRS` | 冒号分隔的 glob：add 时拦截写入，查询时命中懒删出库 | home 目录本身 |
| `_JB_FZF_OPTS` | 透传给 fzf 的自定义参数 | 内置参数组 |
| `_JB_MAXAGE` | 数据库总分老化阈值 | 10000 |
| `_JB_RESOLVE_SYMLINKS=1` | add 时解析符号链接 | 关 |
| `_JB_DOCTOR=0` | 关闭 shell 配置诊断提示（仅 bash/zsh/posix 模板有此检查） | 开 |

## 与 zoxide 的差异

- 持久化为明文 `db.txt`（`timestamp\trank\tpath`，对齐上游 [zoxide#1288](https://github.com/ajeetdsouza/zoxide/pull/1288) 的明文方向，该 PR 合并前 jumbit 已先行）；rank 定点两位小数（全精度入、两位出），标注存侧文件 `notes.tsv` 不进主格式（jumbit 扩展）；与上游 0.10.0 的二进制 `db.zo` 不互通，与未来上游明文格式可互换（减 note 列）
- 环境变量前缀 `_ZO_*` → `_JB_*`，两者可共存
- 关键词大小写归一仅限 ASCII（上游为 Unicode 全量）
- `_JB_EXCLUDE_DIRS` 的 glob 排除不支持 `{a,b}` 括号展开；`**` 按两个 `*` 处理、不跨分隔符（上游 glob crate 的 `**` 为递归通配）；`*`/`?`/`[...]` 语义对齐；`query --exclude` 为精确路径过滤、不做 glob（对齐上游）
- 仅支持 Linux；fzf 预览窗口的平台定制未实现（import 的 autojump/z.lua 路径探测同按 Linux 语义）
- fzf 交互通道（`query --interactive`）：选中/`--score` 输出与退出码对齐上游（伪 fzf 探针矩阵逐字节对拍）；文案差异两处：fzf 取消（其退出码 1）jumbit 静默退出 1，上游报 `no match found`；fzf 自身异常的提示为英文原文且无 `zoxide: ` 前缀。另 spawn 失败不区分「未安装」与「无法启动」（上游区分，进程绑定不暴露错误类别），统一报 `could not find fzf, is it installed?`
- `edit` 上游为 fzf 交互调 rank（0.10.0），jumbit 为编辑器/结构化形态（见 `edit` 扩展条）；上游已宣布该形态待砍（#1288 评论区），不跟随
- 非 finite rank：明文格式下入库时 `inf` 钳到上限、`nan` 归最低权重（0.01），读取遇 `nan` 行整库拒绝并按行报错；上游 0.10.0 的「非 finite 毒库」问题（[zoxide#1280](https://github.com/ajeetdsouza/zoxide/pull/1280)）在 jumbit 明文格式下不再成立
- 扩展（上游无）：`query --json`（单行 JSON 数组，含 `matched_by` 证据字段）、`query --tsv`（无表头 Tab 分隔行 `path\tscore\tlast_accessed\tmatched_by`，列序与 `--json` 键序一致；path 原样不转义；路径含 tab 时该行列数歧义，属已知限制；score 为最短表示，NaN/±Infinity 出 `NaN`/`Infinity`/`-Infinity` 原文而非 JSON 的 `null`）、`query --limit <n>`（`--list`/`--json`/`--tsv` 输出的前 n 条截断，`--limit 0` 为空输出、退出码 0；重复出现后者覆盖）、`query --fuzzy`（仅精确匹配零命中时启用，各关键词为某路径组件的子串即命中：不限末组件、无序且允许同组件，大小写归一同主路仅 ASCII）、`describe`（条目人工标注，随库持久化）、`export --agents`（项目地图）、`status`（数据库自检：数据文件/大小/格式/条目数/标注数/老化阈值，`--json` 单行对象，`format` 出 `plaintext`/`binary`/`null`；`--check` 显式触发 O(N) 存在性扫描并报 `存在 K/N`；库损坏退出码 1）与 `edit`（`$VISUAL`/`$EDITOR` 编辑明文库，`--rename` 改路径、`--prune` 清除不存在条目）
