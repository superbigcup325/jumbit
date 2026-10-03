# jumbit 报错与故障排查

退出码、stderr 文案对照与常见症状处置。命令与 flag 的完整说明见 [USAGE.md](USAGE.md)

## 退出码（全部命令通用）

| 退出码 | 含义 |
|---|---|
| 0 | 有结果或成功；注意 `query --list` 空结果也是 0（静默，对齐上游） |
| 1 | 无结果或运行失败（**是「没查到」不是故障**，读 stderr 区分） |
| 2 | 用法错误（未知命令 / flag 互斥 / 缺必选参数），stderr 提示 `jumbit help`；文案为英文 clap 风格（`error: ...` + `For more information, try ...`） |
| 130 | fzf 用户中断（仅 `--interactive`），静默透传 |

## 常见症状速查

| 症状 | 原因 | 处置 |
|---|---|---|
| 新目录查不到 | hook 未装，或该目录从未 cd 过 | `jumbit add <目录>`；检查 `eval "$(jumbit init bash)"` 是否在 rc 文件 |
| 结果路径已不存在 | 默认查询做存在性过滤并懒删陈旧条目 | 确要绕过用 `--all` |
| fuzzy 命中能不能信 | 看 `--json`/`--tsv` 的 `matched_by` | `exact` 可直接行动，`fuzzy` 先核对再动 |
| import 拒绝执行 | 库非空 | 加 `--merge` |
| `could not find fzf` | fzf 未安装 | 安装 fzf 或改用非交互查询 |
| 数据文件在哪 | 默认 `$HOME/.local/share/jumbit/db.txt`（旧版 db.zo 首次写库时自动转明文，原文件保留可删） | `_JB_DATA_DIR` 重定向（须绝对路径） |
| shell 报「possible configuration issue」 | init 没放在 rc 文件末尾，或被后续配置覆盖 | 把 `eval "$(jumbit init bash)"` 移到 rc 文件末尾；确认无误可 `export _JB_DOCTOR=0` 关闭提示 |

## stderr 文案对照

**用法错误（exit 2）**，改命令行即可：

| 文案 | 含义 |
|---|---|
| `error: unrecognized subcommand '<X>'` | 子命令拼写错误（后续行 `For more information, try 'jumbit help'.`） |
| `error: add: missing required argument '<PATHS>'` | `add` 后没给目录 |
| `error: invalid value '<X>' for '--score <N>'` / `error: a value is required for '--score <N>' ...` | 权重值非法或缺失 |
| `error: invalid value '<X>' for '--limit <n>'` / `error: a value is required for '--limit <n>' ...` | 截断值非法 |
| `error: the argument '--tsv' cannot be used with '--json'` 等 | 输出通道互斥，去掉其一 |
| `error: '--limit' requires '--list', '--json' or '--tsv'` | `--limit` 需与列表型输出组合 |
| `error: missing required argument '<SHELL>'` / `error: invalid value '<X>' for '<SHELL>'`（附 `[possible values: ...]` 行） | `init` 后缺失或拼错 shell 名 |
| `error: invalid value '<X>' for '--hook <HOOK>'` | hook 取值非法 |

**无结果 / 运行失败（exit 1）**：

| 文案 | 含义与处置 |
|---|---|
| `jumbit: no match found` | 没查到，不是故障；确认关键词能锚定末组件（如 `projects` 匹配的是末组件含 projects 的目录），或先 `query --list --score` 看库里有什么 |
| `jumbit: not a directory: <path>` | `add` 的目标不存在或不是目录 |
| `jumbit: path not found in database: <path>` | `remove`/`describe` 的路径不在库里（可能已被 `_JB_EXCLUDE_DIRS` 查询懒删、或超 3 个月未访问的 TTL 懒删清出；`--exclude` 只过滤输出、不删库） |
| `jumbit: you are already in the only match` | 唯一命中被 `--exclude` 排除（对齐上游同文案） |
| `jumbit: no note found for <path>` | 该条目没有人工标注（查看模式正常返回） |
| `error: note cannot contain newline or tab` + 退出码 2 | `describe --note` 的标注含换行或 tab（解析层拒绝） |
| `jumbit: could not find fzf, is it installed?` | fzf 未安装或不可执行；装 fzf 或改用非交互查询 |
| `fzf returned an error` / `fzf was terminated` / `fzf returned an unknown error` | fzf 自身异常退出；其 stderr 原文会一并打印，按 fzf 侧排查（常见：无可用终端） |
| `jumbit: could not read <path>: <errno 短语> (os error N)` | import 读不到插件数据文件（如 `No such file or directory`）；核对 `$_Z_DATA` 等探测路径 |
| `jumbit: failed to run `atuin`; is it installed and on PATH?` | `import atuin` 找不到 atuin 可执行文件；安装 atuin 或改导入其他插件 |
| `jumbit: could not resolve path <path>: <errno 短语> (os error N)` | `_JB_RESOLVE_SYMLINKS=1` 时目标无法 realpath（如符号链接自环）；修链接或去掉该环境变量 |
| `jumbit: could not save database: io failure: <errno 短语> (os error N)` | 库文件写不进去（磁盘满/目录只读/权限）；解除后重试 |
| `jumbit: current database is not empty, specify --merge to continue anyway` | 导入目标库非空，确认后加 `--merge` |
| `<file>:<行号>: invalid entry: <行>` | import 坏行逐条上报（不中止导入）；该行不符合插件标准格式 |
| `jumbit: corrupted data file: <原因>` / `jumbit: could not open database: <原因>` | 库文件无法解析，见下节处置 |
| `jumbit: _JB_DATA_DIR must be an absolute path: <path>` | `_JB_DATA_DIR` 给了相对路径；改用绝对路径 |
| `jumbit: cannot determine the data directory: set _JB_DATA_DIR` | HOME 未设置且未给 `_JB_DATA_DIR`；设置其一 |
| `jumbit: invalid glob in _JB_EXCLUDE_DIRS: <pattern>` | `_JB_EXCLUDE_DIRS` 含非法 glob（未闭合 `[`、倒序区间等）；修正 pattern |
| `jumbit: _JB_MAXAGE must be a non-negative integer: <value>` | `_JB_MAXAGE` 不是非负整数；修正取值（写命令运行时校验，query 不消费该变量） |
| `jumbit: no editor: set $EDITOR or $VISUAL` | `jumbit edit` 找不到编辑器；设置 `VISUAL` 或 `EDITOR` |
| `jumbit: editor exited with code N` | 编辑器退出非零（未改库）；修编辑器侧后重试 |
| `jumbit: path already in database: <path>` | `edit --rename` 的目标路径已在库中（拒绝，不合并） |

## 数据损坏处置

库文件（`<数据目录>/db.txt`）为明文，每行 `timestamp<TAB>rank<TAB>path`。轻微损坏（个别坏行）**可直接手编修复**，`jumbit status` 会给出坏行行号与原因；修好再跑 `jumbit status` 确认不再报错

```bash
jumbit status                                    # 查看坏行位置与原因
$EDITOR ~/.local/share/jumbit/db.txt             # 手编修复（或 jumbit edit）
jumbit status                                    # 复核
```

大面积损坏（不想修）：

```bash
mv ~/.local/share/jumbit/db.txt ~/.local/share/jumbit/db.txt.bak   # 留档
jumbit status                                                      # 自此按空库重建
```

历史目录随后自然重新积累；已有插件数据可 `jumbit import --merge z` 等回灌。换库位置用 `_JB_DATA_DIR`（须绝对路径）

附注：

- 旧版二进制 `db.zo` 在首次写库时自动转换为 `db.txt`，转换后**原文件保留**；确认新库正常后可手动删除 `db.zo`
- `notes.tsv`（标注侧文件）可随 `db.txt` 一起手编，行格式 `path<TAB>note`；path 被改名时标注不会自动跟随（note 按 path 关联），改名请同步编辑两处，或用 `edit --rename`（标注自动跟随）
