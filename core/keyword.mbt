///|
/// ASCII 大写预扫：to_lower 仅做 ASCII 归一（见 filter_by_keywords 注），
/// 路径无 ASCII 大写时可免小写化分配。非 ASCII 字节两路都不动，判定严格等价
fn has_ascii_upper(s : String) -> Bool {
  for i in 0..<s.length() {
    let c = s[i]
    if c >= 65 && c <= 90 {
      return true
    }
  }
  false
}

///|
/// 路径小写归一（等价 normalize_separators(path.to_lower())，无 ASCII 大写
/// 时零分配）：query 逐条目热路上的主要分配源；Windows 下 '\' 归一另计
/// （normalize_separators 内部自判，无反斜杠同样免分配）
fn path_lower(path : String) -> String {
  if has_ascii_upper(path) {
    normalize_separators(path.to_lower())
  } else {
    normalize_separators(path)
  }
}

///|
/// 关键词预小写（一次）：调用方（stream 每查询一次）先归一关键词数组，
/// 逐条目匹配不再重复分配
fn keywords_lower(keywords : Array[String]) -> Array[String] {
  // 全小写（最常见形态）直接返回原数组零分配：to_lower 仅 ASCII 归一，
  // 无 ASCII 大写时关键词本就无需变更，非 ASCII 大写两路同样不归一
  for kw in keywords {
    if has_ascii_upper(kw) {
      let out : Array[String] = []
      for kw in keywords {
        out.push(kw.to_lower())
      }
      return out
    }
  }
  keywords
}

///|
/// 关键词匹配（对齐上游 src/db/stream.rs filter_by_keywords）：
/// 1. 关键词与路径先做大小写归一（`to_lower` 仅 ASCII；上游为 Unicode 全量，
///    全角/西里尔等不归一——已知差异，README 注明）
/// 2. 最后一个关键词取**最右**命中点，且命中点右侧到路径末尾不得再出现分隔符
///    （末组件锚定）
/// 3. 其余关键词从右往左逐个消耗，命中区间不许重叠
/// 空关键词数组恒为 true。
pub fn filter_by_keywords(keywords : Array[String], path : String) -> Bool {
  if keywords.is_empty() {
    return true
  }
  filter_by_keywords_lower(keywords_lower(keywords), path_lower(path))
}

///|
/// 匹配内核：keywords 与 path 均已小写归一。逐条目热路由 stream 层预归一
/// 关键词后调用，本函数体内零分配
fn filter_by_keywords_lower(keywords : Array[String], path : String) -> Bool {
  if keywords.is_empty() {
    return true
  }
  let last = keywords[keywords.length() - 1]
  let mut limit = match path.rev_find(last) {
    Some(idx) => {
      if path[idx + last.length():].find("/") is Some(_) {
        return false
      }
      idx
    }
    None => return false
  }
  for i in (keywords.length() - 1)>..0 {
    match path[0:limit].rev_find(keywords[i]) {
      Some(idx) => limit = idx
      None => return false
    }
  }
  true
}

///|
/// 模糊关键词匹配（jumbit 扩展，上游无此语义；README 注明）：
/// 全部关键词（ASCII 小写归一，与 filter_by_keywords 一致）各自命中至少一个
/// 路径组件的子串即通过——不限末组件、关键词间无序且允许同组件。
/// 仅作 `query --fuzzy` 的精确零命中兜底路，不进入默认语义；空数组恒 true。
pub fn filter_by_keywords_fuzzy(
  keywords : Array[String],
  path : String,
) -> Bool {
  if keywords.is_empty() {
    return true
  }
  let lower = path_lower(path)
  for kw in keywords_lower(keywords) {
    let mut hit = false
    for comp in lower.split("/") {
      if comp.find(kw) is Some(_) {
        hit = true
        break
      }
    }
    if !hit {
      return false
    }
  }
  true
}
