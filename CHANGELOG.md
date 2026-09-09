# Changelog

本文件记录 jumbit 所有对外可见的变更，与 git 提交历史保持同步。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本（SemVer）。

## [Unreleased]

### Added
- 数据集对拍工具：`scripts/gen_dataset.py`（路径池采样 + Zipf 访问分布 + 时间衰减 + 边界行，固定种子可复现）与 `scripts/dataset_check.sh`（import 六插件 / aging / --merge 八场景与真 zoxide 0.10.0 差分对拍，含排序正确性、退出码与坏行 stderr 逐字节比对）

- `query --json`：单行 JSON 数组输出全部匹配（path/score/last_accessed/matched_by），面向脚本与 agent 的结构化通道，与 `--interactive` 互斥
- `query --limit <n>`：`--list`/`--json` 列表型输出的统一截断，取排序后前 n 条；`--limit 0` 为空输出加退出码 0，不触发无匹配错误路；与单结果路、`--interactive` 组合报参数错误
- `query --fuzzy`：精确匹配零命中时的兜底路——各关键词（ASCII 归一）为某路径组件的子串即命中，不限末组件、无序且允许同组件；`--json` 的 `matched_by` 出 `exact`/`fuzzy` 双值标注证据来源
- `import <plugin>`：从其他工具导入历史数据，支持 `atuin`/`autojump`/`fasd`/`z`/`z.lua`/`zsh-z`（对齐上游 cmd/import.rs + import/ 六模块）
  - 空库直灌、非空库须 `--merge`（可位于插件名前后，上游 global flag 语义）
  - 数据文件按各插件标准约定自动探测（`_Z_DATA`/`_FASD_DATA`/`ZSHZ_DATA`/`_ZL_DATA`/`XDG_DATA_HOME`）；z.lua 主路径缺失回落 fish 变体路径；atuin 经 `atuin history list --print0` 子进程读取
  - autojump rank 过 sigmoid 归一（last_accessed=0）；atuin UTC 时间戳解析为 epoch（rank=1.0，同目录连续记录折叠）
  - 坏行按 `<文件>:<行号>: <原因>` 逐条上报不中止（atuin 为 `line N`）；结束后 dedup + age(maxage) 再落盘
- glob 匹配器：`*`/`?`/`[...]`/`[!...]` 均不跨路径分隔符，`\` 转义，非法 pattern（未闭合/空类/倒序区间/尾转义）报错；`{a,b}` 不支持（与上游差异）
- 数据层：`Dir` 三字段模型（path/rank/last_accessed）与 frecency score 衰减（<1h ×4.0 / <1d ×2.0 / <1w ×0.5 / 其余 ×0.25）
- 数据库操作：权重累加（add/add_update，负增量 clamp 到 0）、按得分排序、dirty 标志
- 自有二进制持久化格式（4 字节版本号 + 长度前缀条目），32MiB 上限，畸形数据（截断/版本不符/非法 UTF-8/超限）明确报错
- db v2：条目尾部带 note 人工标注（`Dir::note`，长度 0 编码为无标注），v1 旧库免迁移兼容读；`Database::set_note` 设置/清除并置 dirty；dedup 合并时 note 一侧有值则保留
- `describe <path> [--note text]`：为已记录条目设置/清除（`--note ""`）/显示人工标注；标注拒绝换行；路径对齐 remove 的双重尝试（原串 → 规范化）
- `export --agents`：有标注条目按 frecency 降序输出 Markdown「项目地图」（路径/说明两列，`|` 转义保表格完整），可直接追加进 AGENTS.md 供 coding agent 认识工作区；不做存在性检查（离线视图），空库输出空表头
- 原子写：tmp 文件（系统熵随机名，冲突重试 5 次）+ sync 落盘 + rename 替换，失败自动清理
- 数据目录解析：`_JB_DATA_DIR`（须绝对路径）优先，回落 `$HOME/.local/share/jumbit`
- 项目脚手架：以 `moon new` 铺设，`preferred_target = "native"`，MIT 许可证，包结构按 `core`（纯函数内核）/ `platform`（IO 外壳）/ `config` / `cli` 分层
- 依赖锁定 `moonbitlang/async@0.21.2`：其 `fs` 子包提供带同步落盘的文件读写与 `rename`（原子写的基础），`process` 子包提供子进程调用（交互式选择的基础）
- 关键词查询：最后一个关键词锚定路径末组件、其余从右往左消耗不许重叠（对齐 zoxide 匹配语义，大小写归一仅 ASCII）
- 查询流过滤链：score 排序 → 关键词 → base_dir（组件级前缀）→ exclude glob（命中懒删除）→ exists 检查（最后执行）→ 不存在且超 3 个月 TTL 懒删除；exists 回调注入使过滤链可纯测试
- 数据库删除：按路径 remove 与 O(1) swap_remove（懒删除落库）
- 命令行入口 `jumbit`：`add <path>...` 记录目录（路径规范化、换行/非目录校验）、`query [kw]...` 按关键词过滤后输出最高得分目录、`query --list`（全部匹配，按得分降序）、`--score`（6.1f 得分前缀）、`--all`（跳过存在性检查）、`--exclude <path>`（精确路径排除，排除唯一命中时明确报错）
- 环境变量 `_JB_EXCLUDE_DIRS`（冒号分隔 glob，命中懒删除，默认排除 home 目录本身）、`_JB_RESOLVE_SYMLINKS=1`（add 解析符号链接、查询反向不跟随）、`_JB_MAXAGE`（数据库总分老化阈值，默认 10000，非法值报错）
- `remove <path>...`：按原始串与规范化路径双重尝试删除，未找到明确报错
- fzf 交互选择：`query --interactive` 按得分送入 fzf（未安装明确报错），`_JB_FZF_OPTS` 经 FZF_DEFAULT_OPTS 透传自定义参数
- 项目 README：构建方式、完整用法、shell 集成、环境变量表、与 zoxide 差异清单、许可证说明
- shell 集成：`jumbit init bash|zsh|fish` 生成集成脚本（`--cmd C` 自定义命令名、`--hook pwd|prompt|none` 触发方式、`--no-cmd` 不定义别名），脚本内环境变量 `_JB_ECHO`/`_JB_RESOLVE_SYMLINKS` 运行时生效
- `add --score N`：指定本次增量权重
- add 链路对齐上游：换行路径与排除 glob 命中静默跳过，非目录立即中止，写库前按总分老化
- 调试回显 `_JB_ECHO=1`：add 时回显记录的目录
- 端到端冒烟脚本 `scripts/smoke.sh`：真实二进制验证 add→query 回显与错误退出码
- 开发者回归脚本 `scripts/regression.sh`：`moon check --deny-warn`、`moon test`、`moon fmt --check`、`moon info` 接口面冻结四道闸，任一失败即非零退出
### Fixed

- 得分显示在精确半界（如陈旧条目 1.0×0.25=0.25）改按 Rust `{:.1}` 的半界取偶舍入，`--score` 前缀与上游逐字节一致（此前 `.round()` 半界远离零，0.25 误显 0.3）
- 持久化解码拒绝路径字节含 NUL/换行的库文件（此前仅 add 入口拦截，手工构造的库文件可绕过）

### Internal

- Database 封装收敛：字段改为外部不可构造/原地修改，`all()` 返回数组副本，保证 dirty 标志一致性

[Unreleased]: https://github.com/superbigcup325/jumbit
