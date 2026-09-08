# jumbit

a MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes.

[![CI](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml/badge.svg)](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml)

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
jumbit query --json                  # 单行 JSON 数组输出全部匹配（agent 通道）
jumbit query --fuzzy blog            # 精确零命中时按组件子串兜底（jumbit 扩展）
jumbit remove ~/projects/backend     # 从数据库移除
jumbit import z                      # 从 z/zsh-z/fasd/z.lua/autojump/atuin 导入历史
jumbit import --merge zsh-z          # 非空库须加 --merge 合并
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

`import` 按各插件标准约定自动探测数据文件，可用 `_Z_DATA`、`_FASD_DATA`、`ZSHZ_DATA`、`_ZL_DATA`、`XDG_DATA_HOME` 定位；atuin 经 `atuin history list` 子进程读取。

## 与 zoxide 的差异

- 持久化格式为自定义二进制（版本号 + 长度前缀条目），与上游 `db.zo` **不互通**；v2 起条目带 note 标注（jumbit 扩展），旧 v1 库免迁移兼容读
- 环境变量前缀 `_ZO_*` → `_JB_*`，两者可共存
- 关键词大小写归一仅限 ASCII（上游为 Unicode 全量）
- glob 排除不支持 `{a,b}` 括号展开；`**` 按两个 `*` 处理、不跨分隔符（上游 glob crate 的 `**` 为递归通配）；`*`/`?`/`[...]` 语义对齐
- 仅支持 Linux；fzf 预览窗口的平台定制未实现（import 的 autojump/z.lua 路径探测同按 Linux 语义）
- 未移植：`edit` 子命令、elvish/nushell/posix/powershell/tcsh/xonsh 模板
- 扩展（上游无）：`query --json`（单行 JSON 数组，含 `matched_by` 证据字段）与 `query --fuzzy`（仅精确匹配零命中时启用，各关键词为某路径组件的子串即命中——不限末组件、无序且允许同组件，大小写归一同主路仅 ASCII）

## 许可证

MIT License。基于 [zoxide](https://github.com/ajeetdsouza/zoxide)（MIT）的语义重写，许可证附原始版权声明。
