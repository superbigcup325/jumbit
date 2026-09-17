///|
/// status 的库状态报表（jumbit 扩展，上游无）：计算与渲染分离（渲染可 wbtest 直断字节）。
/// existing 仅在 --check 时为 Some（O(N) 逐路径存在性扫描，默认快查不做）；
/// db.zo 不存在视为空库（file_size 0 / entries 0 / format_version None）
struct DbStatus {
  data_file : String
  file_size : Int
  /// 数据文件头部的实际格式版本；无文件时 None
  format_version : Int?
  entries : Int
  notes : Int
  /// _JB_MAXAGE 现值（config 解析产物为 Double）
  maxage : Double
  existing : Int?
} derive(Debug)

///|
fn render_status_human(r : DbStatus) -> Array[String] {
  let version = match r.format_version {
    Some(v) => v.to_string()
    None => "-"
  }
  let lines = [
    "数据文件      \{r.data_file}",
    "文件大小      \{r.file_size} 字节",
    "格式版本      \{version}",
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
/// 单行 JSON 对象（键序固定，--json 纪律同 query --json）；existing 仅 --check 出现
fn render_status_json(r : DbStatus) -> String {
  let version = match r.format_version {
    Some(v) => v.to_string()
    None => "null"
  }
  let existing = match r.existing {
    Some(k) => ",\"existing\":\{k}"
    None => ""
  }
  "{\"data_file\":\"\{json_escape(r.data_file)}\",\"file_size\":\{r.file_size},\"format_version\":\{version},\"entries\":\{r.entries},\"notes\":\{r.notes},\"maxage\":\{r.maxage}\{existing}}"
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
  let db_path = data_dir + "/db.zo"
  let (file_size, format_version, dirs) = if @afs.exists(db_path) {
    let data = @afs.read_file(db_path) catch {
      err => {
        err_line(
          errs,
          "无法读取数据文件: \{@platform.os_error_message(err)}",
        )
        return 1
      }
    }
    let bytes = data.binary()
    // 版本号 = 头 4 字节 LE（decode 的最低校验位之前就 available，诊断如实报告）
    let version = bytes[0].to_int() |
      (bytes[1].to_int() << 8) |
      (bytes[2].to_int() << 16) |
      (bytes[3].to_int() << 24)
    match @core.decode(bytes) {
      Ok(dirs) => (bytes.length(), Some(version), dirs)
      Err(e) => {
        err_line(
          errs,
          "数据文件损坏: \{@platform.codec_error_message(e)}",
        )
        return 1
      }
    }
  } else {
    (0, None, [])
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
    data_file: db_path,
    file_size,
    format_version,
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
