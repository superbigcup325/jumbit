# jumbit

a MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes.

jumbit 记录你去过的目录并按 frecency（频次 × 时间衰减）排序，用少量关键词跳转：

```bash
j projects      # 记录过的目录里匹配 projects 的最高分
j backend api   # 多关键词：api 锚定路径末组件，backend 向左消耗
```

## 构建

```bash
export PATH="$HOME/.moon/bin:$PATH"   # MoonBit 工具链
moon check && moon test
moon build --release
# 产物：_build/native/release/build/cmd/main/main.exe
```

## 用法

```bash
jumbit add ~/projects/backend        # 记录目录（hook 自动调用；也可手动）
jumbit add --score 3.5 ~/projects    # 指定本次增量权重
jumbit query backend                 # 输出匹配的最高分目录
jumbit query --list --score          # 全部匹配，按得分降序带分数前缀
jumbit query --interactive           # fzf 交互选择
jumbit query --all --exclude ~/tmp   # 跳过存在性检查 / 排除指定目录
jumbit remove ~/projects/backend     # 从数据库移除
jumbit help
```

## shell 集成

```bash
# bash：加入 ~/.bashrc
eval "$(jumbit init bash)"
# zsh：~/.zshrc；fish：~/.config/fish/config.fish 用 `jumbit init fish | source`

j backend        # 跳转（自动补全）
ji               # fzf 交互式跳转
```

参数：`--cmd C` 自定义命令名（默认 `j`，如 `--cmd=cd`）、`--hook pwd|prompt|none` 选择记录触发方式（默认 `pwd`）、`--no-cmd` 只生成内部函数。

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

- 持久化格式为自定义二进制（版本号 + 长度前缀条目），与上游 `db.zo` **不互通**
- 环境变量前缀 `_ZO_*` → `_JB_*`，两者可共存
- 关键词大小写归一仅限 ASCII（上游为 Unicode 全量）
- glob 排除不支持 `{a,b}` 括号展开；`**` 按两个 `*` 处理、不跨分隔符（上游 glob crate 的 `**` 为递归通配）；`*`/`?`/`[...]` 语义对齐
- 仅支持 Linux；fzf 预览窗口的平台定制未实现
- 未移植：`import`（外部工具历史导入）、`edit` 子命令、elvish/nushell/posix/powershell/tcsh/xonsh 模板

## 许可证

MIT License。基于 [zoxide](https://github.com/ajeetdsouza/zoxide)（MIT）的语义重写，许可证附原始版权声明。
