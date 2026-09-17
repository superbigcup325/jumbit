# jumbit 报错与故障排查

退出码、stderr 文案对照与常见症状处置。命令与 flag 的完整说明见 [USAGE.md](USAGE.md)

## 退出码（全部命令通用）

| 退出码 | 含义 |
|---|---|
| 0 | 有结果或成功；注意 `query --list` 空结果也是 0（静默，对齐上游） |
| 1 | 无结果或运行失败——**是「没查到」不是故障**，读 stderr 区分 |
| 2 | 用法错误（未知命令 / flag 互斥 / 缺必选参数），stderr 提示 `jumbit help` |
| 130 | fzf 用户中断（仅 `--interactive`），静默透传 |

## 常见症状速查

| 症状 | 原因 | 处置 |
|---|---|---|
| 新目录查不到 | hook 未装，或该目录从未 cd 过 | `jumbit add <目录>`；检查 `eval "$(jumbit init bash)"` 是否在 rc 文件 |
| 结果路径已不存在 | 默认查询做存在性过滤并懒删陈旧条目 | 确要绕过用 `--all` |
| fuzzy 命中能不能信 | 看 `--json`/`--tsv` 的 `matched_by` | `exact` 可直接行动，`fuzzy` 先核对再动 |
| import 拒绝执行 | 库非空 | 加 `--merge` |
| `could not find fzf` | fzf 未安装 | 安装 fzf 或改用非交互查询 |
| 数据文件在哪 | 默认 `$HOME/.local/share/jumbit/db.zo` | `_JB_DATA_DIR` 重定向（须绝对路径） |
| shell 报「possible configuration issue」 | init 没放在 rc 文件末尾，或被后续配置覆盖 | 把 `eval "$(jumbit init bash)"` 移到 rc 文件末尾；确认无误可 `export _JB_DOCTOR=0` 关闭提示 |

## stderr 文案对照

**用法错误（exit 2）**——改命令行即可：

| 文案 | 含义 |
|---|---|
| `未知命令: <X>` / `运行 jumbit help 查看用法` | 子命令或 flag 拼写错误 |
| `add: 缺少路径参数` | `add` 后没给目录 |
| `--score 必须是数字: <X>` / `--score 缺少数值参数` | 权重值非法 |
| `--limit 需要非负整数参数: <X>` / `--limit 缺少非负整数参数` | 截断值非法 |
| `--tsv 与 --json 互斥` 等 | 输出通道互斥，去掉其一 |
| `--limit 仅在 --list/--json/--tsv 下生效` | `--limit` 需与列表型输出组合 |
| `init: 缺少 shell 参数（…）` / `init: 不支持的 shell: <X>（…）` | `init` 后缺失或拼错 shell 名 |
| `--hook 仅支持 pwd/prompt/none: <X>` | hook 取值非法 |

**无结果 / 运行失败（exit 1）**：

| 文案 | 含义与处置 |
|---|---|
| `无匹配: <关键词>` | 没查到，不是故障；确认关键词能锚定末组件（如 `projects` 匹配的是末组件含 projects 的目录），或先 `query --list --score` 看库里有什么 |
| `not a directory: <path>` | `add` 的目标不存在或不是目录 |
| `path not found in database: <path>` | `remove`/`describe` 的路径不在库里（可能已被 `_JB_EXCLUDE_DIRS` 查询懒删、或超 3 个月未访问的 TTL 懒删清出；`--exclude` 只过滤输出、不删库） |
| `describe: <path> 无标注` | 该条目没有人工标注（查看模式正常返回） |
| `could not find fzf, is it installed?` | fzf 未安装或不可执行；装 fzf 或改用非交互查询 |
| `fzf returned an error` / `fzf was terminated` / `fzf returned an unknown error` | fzf 自身异常退出；其 stderr 原文会一并打印，按 fzf 侧排查（常见：无可用终端） |
| `could not read <path>: <errno 短语> (os error N)` | import 读不到插件数据文件（如 `No such file or directory`）；核对 `$_Z_DATA` 等探测路径 |
| `解析路径失败: <path>: <errno 短语> (os error N)` | `_JB_RESOLVE_SYMLINKS=1` 时目标无法 realpath（如符号链接自环）；修链接或去掉该环境变量 |
| `保存数据库失败: 读写失败: <errno 短语> (os error N)` | 库文件写不进去（磁盘满/目录只读/权限）；解除后重试 |
| `current database is not empty, specify --merge to continue anyway` | 导入目标库非空，确认后加 `--merge` |
| `<file>:<行号>: invalid entry: <行>` | import 坏行逐条上报（不中止导入）；该行不符合插件标准格式 |
| `数据文件损坏: <原因>` / `打开数据库失败: <原因>` | 库文件无法解析，见下节处置 |

## 数据损坏处置

库文件（`<数据目录>/db.zo`）损坏无法自动修复。处置：

```bash
mv ~/.local/share/jumbit/db.zo ~/.local/share/jumbit/db.zo.bak   # 留档
jumbit status                                                    # 自此按空库重建
```

历史目录随后自然重新积累；已有插件数据可 `jumbit import --merge z` 等回灌。换库位置用 `_JB_DATA_DIR`（须绝对路径）
