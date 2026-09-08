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
  let lower = path.to_lower()
  let last = keywords[keywords.length() - 1].to_lower()
  let mut limit = match lower.rev_find(last) {
    Some(idx) => {
      if lower[idx + last.length():].find("/") is Some(_) {
        return false
      }
      idx
    }
    None => return false
  }
  for i in (keywords.length() - 1)>..0 {
    let kw = keywords[i].to_lower()
    match lower[0:limit].rev_find(kw) {
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
  let lower = path.to_lower()
  for kw in keywords {
    let k = kw.to_lower()
    let mut hit = false
    for comp in lower.split("/") {
      if comp.find(k) is Some(_) {
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
