///|
/// status 的库状态报表（jumbit 扩展，上游无）：计算与渲染分离（渲染可 wbtest 直断字节）。
/// existing 仅在 --check 时为 Some（O(N) 逐路径存在性扫描，默认快查不做）；
/// 无数据文件视为空库（file_size 0 / entries 0 / format None）。
/// format = 实际加载格式的标识（规格 docs/spec-plaintext-edit.md §3.4）：
/// "plaintext"（db.txt，主格式）/ "binary"（legacy db.zo，只读不迁移）/ None（无库）——
/// 二进制内部版本号不外泄（诊断价值由「数据文件损坏」路径承担）
struct DbStatus {
  data_file : String
  file_size : Int
  format : String?
  entries : Int
  notes : Int
  /// _JB_MAXAGE 现值（config 解析产物为 Double）
  maxage : Double
  existing : Int?
} derive(Debug)

///|
fn render_status_human(r : DbStatus) -> Array[String] {
  let fmt = match r.format {
    Some(v) => v
    None => "-"
  }
  let lines = [
    "数据文件      \{r.data_file}",
    "文件大小      \{r.file_size} 字节",
    "格式          \{fmt}",
    "条目          \{r.entries}",
    "标注          \{r.notes}",
    "老化阈值      \{r.maxage}",
  ]
  match r.existing {
    Some(k) => lines.push("存在          \{k}/\{r.entries}")
    None => ()
  }
  lines
}

///|
/// 单行 JSON 对象（键序固定，--json 纪律同 query --json）；existing 仅 --check 出现。
/// format_version 键 0.1.2 起更名 format、值改格式标识字符串（breaking，
/// CHANGELOG 注明）
fn render_status_json(r : DbStatus) -> String {
  let fmt = match r.format {
    Some(v) => "\"\{v}\""
    None => "null"
  }
  let existing = match r.existing {
    Some(k) => ",\"existing\":\{k}"
    None => ""
  }
  "{\"data_file\":\"\{json_escape(r.data_file)}\",\"file_size\":\{r.file_size},\"format\":\{fmt},\"entries\":\{r.entries},\"notes\":\{r.notes},\"maxage\":\{r.maxage}\{existing}}"
}

///|
/// 加载库并汇总条目/标注（统一走 platform.load 单一加载路径；legacy db.zo
/// 被标 dirty 但 status 只读不 save，不触发迁移）。返回 None = 加载失败
/// （stderr 已报）
async fn load_status_dirs(
  data_dir : String,
  errs : Array[String],
) -> Array[@core.Dir]? {
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(Io(msg)) => {
      err_line(errs, "无法读取数据文件: \{msg}")
      return None
    }
    Err(e) => {
      err_line(errs, "数据文件损坏: \{e.message()}")
      return None
    }
  }
  Some(store.database().all())
}

///|
async fn run_status(
  sopts : @cli.StatusOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let maxage = match cfg(@config.maxage(getenv), errs) {
    Some(maxage) => maxage
    None => return 1
  }
  let dirs = match load_status_dirs(data_dir, errs) {
    Some(dirs) => dirs
    None => return 1
  }
  // 数据文件事实：db.txt 主格式优先，回落 legacy db.zo；均无 → 主路径 + 零值
  let txt_path = data_dir + "/db.txt"
  let zo_path = data_dir + "/db.zo"
  let (data_file, format) = if @afs.exists(txt_path) {
    (txt_path, Some("plaintext"))
  } else if @afs.exists(zo_path) {
    (zo_path, Some("binary"))
  } else {
    (txt_path, None)
  }
  let file_size = if @afs.exists(data_file) {
    let data = @afs.read_file(data_file) catch {
      err => {
        err_line(
          errs,
          "无法读取数据文件: \{@platform.os_error_message(err)}",
        )
        return 1
      }
    }
    data.binary().length()
  } else {
    0
  }
  let mut notes = 0
  for d in dirs {
    if d.note is Some(_) {
      notes += 1
    }
  }
  let existing = if sopts.check {
    let mut k = 0
    for d in dirs {
      if @afs.exists(d.path) {
        k += 1
      }
    }
    Some(k)
  } else {
    None
  }
  let report : DbStatus = {
    data_file,
    file_size,
    format,
    entries: dirs.length(),
    notes,
    maxage,
    existing,
  }
  if sopts.json {
    println(render_status_json(report))
  } else {
    for line in render_status_human(report) {
      println(line)
    }
  }
  0
}
