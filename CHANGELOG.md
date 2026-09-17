# Changelog

本文件记录 jumbit 所有对外可见的变更，与 git 提交历史保持同步。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本（SemVer）。

## [Unreleased]

### Added
- `status`：数据库自检命令（jumbit 扩展，上游无）——默认快查输出数据文件路径/大小/实际格式版本（读自文件头）/条目数/标注数/`_JB_MAXAGE` 现值；`--check` 显式触发 O(N) 存在性扫描并追加 `存在 K/N`；`--json` 输出键序固定的单行对象（agent 通道）；库损坏退出码 1 并报 `数据文件损坏: <原因>`，空库（无 db.zo）按零值报告。human 面与 JSON 面已入 golden 冻结（含随机数据目录路径的归一化）
- shell 集成模板扩至 9 shell 全量（对齐上游）：新增 elvish / nushell / posix / powershell / tcsh / xonsh，`jumbit init <shell>` 参数矩阵与语法门禁（elvish 编译、nu-check、sh -n、pwsh 解析、tcsh -n、py_compile）全部真机验证

### Changed
- import/query 内存与分配优化（行为与输出字节面不变）：坏行消息与行定位串惰性构造、db 编码预分配、--tsv 输出流式化、stderr 批量写、import 改单趟流式（对齐上游 import.rs::run 惰性迭代结构，六插件文件源逐行回调解析+入库，atuin 折叠保持物化）——百万行 import 峰值内存 499→203MB、耗时 2.29→1.62s，--tsv 全量输出峰值 217→85MB

### Fixed
- 用户面错误文案清理，Debug 枚举名与 Repr 结构不再外泄：`could not read <path>: <errno 短语> (os error N)`（原 `<@os_error.OSError: …>` 调试结构）、`数据文件损坏: <中文短句>`（原 `UnsupportedVersion(1651663207)` 等枚举名）、`打开数据库失败: <中文短句>`（原 `Codec(CorruptedData)`）；重审补齐同族残留——save 失败 `保存数据库失败: 读写失败: …`、`_JB_RESOLVE_SYMLINKS` realpath 失败 `解析路径失败: <path>: …`、status 读文件失败 `无法读取数据文件: …`（errno 短语走 OSError 公开谓词覆盖 ENOENT/EACCES/ENOTDIR/EEXIST，其余保 `(os error N)` 数字后缀——`errno_to_string` 标注 alert_internal 不可用）；golden status-corrupt.err 同步冻结
- `query --interactive` 的 fzf 定位改为 spawn 前沿 PATH 预解析（取首个「普通文件 + 可执行」候选）：裸名命中不可执行文件或同名目录时，旧实现把 exec 失败留给子进程 wait 退出码路，报 `fzf returned an error` 且伴随子进程 stderr 泄漏（黑盒实测 `inappropriate ioctl for device`），违背「spawn 失败统一报 `could not find fzf, is it installed?`」口径——现统一归 NotFound（exit 1）；不可执行候选在前时跳过并选中后续可执行者
- CLI 解析支持 `--flag=value` 等号形式（对齐上游 clap 双形态）：`init --cmd=`/`--hook=`、`query --exclude=`/`--limit=`、`add --score=`、`describe --note=`。此前 README 记载的 `--cmd=cd` 写法实际被拒（exit 2「未知命令」）；布尔/未知 flag 的等号形式维持报原文 exit 2，`--` 之后不拆分
- `query --interactive` 对齐上游 zoxide 0.10.0（伪 fzf 探针矩阵实测）：选中输出不再额外追加换行（此前 `println` 多出一个）；fzf 返回短于 7 字节的 selection 改走错误路 `could not read selection from fzf`（exit 1，此前输出空行且 exit 0）；fzf 异常退出码从原样透传改为上游语义表——2 报 `fzf returned an error`、128..=254 与信号杀死报 `fzf was terminated`、其余（3..=127、255）报 `fzf returned an unknown error`，均 exit 1；130（用户中断）静默透传不变
- fzf 候选投喂在 fzf 提前退出时不再因 Broken pipe 中断命令（对齐上游 write 的 BrokenPipe → wait 处理：静默停止投喂）
- shell 经 PATH 裸名调用报「未知命令: jumbit」：argv[0] 处理从「含 `/` 才剥」改为无条件剥（对齐上游 clap「首参即 bin_name」约定）。原启发式基于「moon run 不传程序名」的假设，实测钉死工具链（moon 0.1.20260904）下 moon run native/wasm 均传 exe/wasm 路径、OS 直跑传裸名或完整路径——所有启动路径 argv[0] 皆为程序名；旧逻辑在 bash/zsh/fish 裸名调用下把程序名当子命令报错（exit 2），hook 自动记录随之静默失败

## [0.1.0] - 2026-09-11

### Added
- 数据集对拍工具：`scripts/gen_dataset.py`（路径池采样 + Zipf 访问分布 + 时间衰减 + 边界行，固定种子可复现）与 `scripts/dataset_check.sh`（import 六插件 / aging / --merge 八场景与真 zoxide 0.10.0 差分对拍，含排序正确性、退出码与坏行 stderr 逐字节比对）

- `query --json`：单行 JSON 数组输出全部匹配（path/score/last_accessed/matched_by），面向脚本与 agent 的结构化通道，与 `--interactive` 互斥
- `query --tsv`：无表头 Tab 分隔数据行（`path\tscore\tlast_accessed\tmatched_by`，列序同 `--json` 键序），path 原样不转义；NaN/±Infinity 出 `NaN`/`Infinity`/`-Infinity` 原文；与 `--json`/`--interactive` 互斥，`--list` 组合时 `--list` 胜出（既有先例）
- `query --limit <n>`：`--list`/`--json`/`--tsv` 列表型输出的统一截断，取排序后前 n 条；`--limit 0` 为空输出加退出码 0，不触发无匹配错误路；与单结果路、`--interactive` 组合报参数错误
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

### 已知问题

- 非 finite rank 毒库（继承自上游 0.10.0，2026-09-10 与真 zoxide Linux 探针逐字节对拍一致）：`import`（z 系/autojump；atuin rank 恒 1.0 不受影响）接受 `inf`/`nan` 字面量与 `1e309` 等溢出饱和为 inf 的大数入库（Rust `f64::from_str` 语义），`add --score` 同样接受。后果：`age()` 遇 `total=inf` 因子归零，库内其余条目被清出（rank < 1）而 NaN 条目幸存；`total=NaN` 使 `total > max_age` 永假，老化从此永久停摆；全程退出码 0 无告警。上游修复 [ajeetdsouza/zoxide#1280](https://github.com/ajeetdsouza/zoxide/pull/1280) 为 open PR 未合并，合并后跟进调整（import 拒收非 finite rank、按行号报错）

### Internal

- Database 封装收敛：字段改为外部不可构造/原地修改，`all()` 返回数组副本，保证 dirty 标志一致性

[Unreleased]: https://github.com/superbigcup325/jumbit
