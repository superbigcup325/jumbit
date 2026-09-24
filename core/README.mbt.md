# `core`

jumbit 的纯函数内核：路径规范化、glob 匹配、关键词过滤、浮点解析与数据库编解码。
本文件同时是 docstring 测试载体：` ```mbt check ` 代码块会编译进测试（`moon test`），
示例即用例

## 路径规范化

`resolve_path` 将相对路径基于 base（当前目录）绝对化，解析 `.` 与 `..`，
不解析符号链接（对齐上游 zoxide 的 `util::resolve_path`）；分隔符语义按目标平台
编译期分发（POSIX 走 `/`，Windows 走 win32 盘符与双分隔符组件模型）

```mbt check
///|
test "resolve_path 绝对化与点段规范化" {
  // 相对路径基于 base 拼接
  inspect(@core.resolve_path("a/b", "/x/y"), content="/x/y/a/b")
  // `..` 与 `.` 在规范化的同时消除
  inspect(@core.resolve_path("../a", "/x/y"), content="/x/a")
  inspect(@core.resolve_path("/a/./b", "/"), content="/a/b")
  // 越界 `..` 停在根
  inspect(@core.resolve_path("/../../a", "/"), content="/a")
}
```

`starts_with` 是组件级前缀判断（对齐 `std::path::Path::starts_with`）：
字符串前缀不算数，按路径组件逐段比较

```mbt check
///|
test "starts_with 组件级前缀" {
  inspect(@core.starts_with("/foo/bar/baz", "/foo/bar"), content="true")
  // 字符串前缀不构成组件前缀
  inspect(@core.starts_with("/foo/ba", "/foo/bar"), content="false")
}
```

## glob 匹配

`*` / `?` / `[...]` / `[!...]` 均不跨路径分隔符，`\` 转义；`{a,b}` 括号展开
不支持（与上游 glob crate 的已定差异）。非法 pattern 用 `validate_glob` 前置校验，
`glob_matches` 返回 `Result`，`glob_match` 供已校验 pattern 的快路径

```mbt check
///|
test "glob 不跨分隔符与非法 pattern" {
  // `*` 只在单组件内展开
  inspect(@core.glob_match("/usr/*", "/usr/local"), content="true")
  inspect(@core.glob_match("/usr/*", "/usr/local/bin"), content="false")
  // 未闭合字符类报错（`{a,b}` 为合法 pattern，按字面量处理不展开）
  inspect(@core.validate_glob("/usr/[ab") is Some(_), content="true")
  // 校验与匹配一步完成
  inspect(
    @core.glob_matches("/usr/lo*al", "/usr/local") is Ok(true),
    content="true",
  )
}
```

## 关键词过滤

`filter_by_keywords` 实现上游 zoxide 的关键词语义：末关键词必须落在路径末组件，
其余关键词从右往左消耗且不许重叠；大小写归一仅限 ASCII（与上游的已定差异）。
`filter_by_keywords_fuzzy` 为精确零命中时的兜底：各关键词为某路径组件的子串即命中

```mbt check
///|
test "关键词末组件锚定与 fuzzy 兜底" {
  // 末关键词锚定末组件，其余从右往左消耗
  inspect(
    @core.filter_by_keywords(["user", "work"], "/home/user/work"),
    content="true",
  )
  // 顺序反了则 miss（work 不在末组件）
  inspect(
    @core.filter_by_keywords(["work", "user"], "/home/user/work"),
    content="false",
  )
  // fuzzy：`ork` 是 `work` 的连续子串即命中，不限末组件（子串匹配非缩写）
  inspect(
    @core.filter_by_keywords_fuzzy(["ork"], "/home/user/work"),
    content="true",
  )
}
```

## 浮点解析

`parse_f64` 对齐 Rust `f64::from_str` 语义（jumbit 与上游逐字节对齐的根基）：
科学计数法、`inf`/`nan` 字面量接受，溢出饱和为无穷，非法串拒绝

```mbt check
///|
test "parse_f64 对齐 Rust from_str" {
  match @core.parse_f64("3.5") {
    Ok(v) => inspect(v, content="3.5")
    Err(_) => fail("3.5 应解析成功")
  }
  // 溢出饱和为无穷（Rust 语义）
  match @core.parse_f64("1e309") {
    Ok(v) => inspect(v.is_inf(), content="true")
    Err(_) => fail("1e309 应饱和为 inf")
  }
  // 非法串拒绝
  inspect(@core.parse_f64("abc") is Err(_), content="true")
}
```

## 数据库编解码

明文格式 `db.txt` 的行编解码：每行 `timestamp\trank\tpath`，人工标注走侧文件
`notes.tsv` 不进主格式；坏行整库拒绝并按行号报错（见 `PlaintextError`）

```mbt check
///|
test "明文编解码 roundtrip" {
  let dirs = [
    @core.Dir::{
      path: "/home/user/work",
      rank: 3.0,
      last_accessed: 0L,
      note: None,
    },
  ]
  let bytes = @core.encode_plaintext(dirs)
  match @core.decode_plaintext(bytes) {
    Ok(decoded) => {
      inspect(decoded[0].path, content="/home/user/work")
      inspect(decoded[0].rank == 3.0, content="true")
    }
    Err(_) => fail("decode_plaintext 不应失败")
  }
}
```
