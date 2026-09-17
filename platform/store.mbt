///|
/// 数据库存取错误：IO 失败（含消息）或编解码失败
pub enum StoreError {
  Io(String)
  Codec(@core.CodecError)
} derive(Debug)

///|
/// CodecError → 用户可读原因（status 读头诊断与 StoreError 共用的单一出口，
/// Debug 枚举名不外泄到 stderr）
pub fn codec_error_message(e : @core.CodecError) -> String {
  match e {
    @core.CorruptedData => "无法解析"
    @core.UnsupportedVersion(v) => "格式版本不受支持: \{v}"
    @core.TooLarge => "文件过大"
  }
}

///|
/// StoreError → 用户可读原因（不含场景前缀，调用方拼「数据文件损坏: 」「打开
/// 数据库失败: 」等）
pub fn StoreError::message(self : StoreError) -> String {
  match self {
    Io(msg) => "读写失败: \{msg}"
    Codec(e) => codec_error_message(e)
  }
}

///|
/// Error → 单行短文案：OSError 展开为 strerror 式短语 + (os error N)，对齐
/// std io::Error Display；其余错误兜底 Repr（仅诊断文本，不进正常输出路）。
/// 短语经 OSError 公开谓词判定，覆盖高频 errno；其余保数字后缀
/// （errno_to_string 标注 alert_internal，deny-warn 下不可用）
pub fn os_error_message(err : Error) -> String {
  match err {
    @os_error.OSError(errno, ..) as ose => {
      let phrase = if ose.is_ENOENT() {
        "No such file or directory"
      } else if ose.is_EACCES() {
        "Permission denied"
      } else if ose.is_ENOTDIR() {
        "Not a directory"
      } else if ose.is_EEXIST() {
        "File exists"
      } else {
        return "(os error \{errno})"
      }
      "\{phrase} (os error \{errno})"
    }
    other => "\{Repr(other)}"
  }
}

///|
/// 存取上下文：数据库 + 数据目录位置
pub(all) struct Store {
  db : @core.Database
  data_dir : String
} derive(Debug)

///|
pub fn Store::database(self : Store) -> @core.Database {
  self.db
}

///|
/// 打开数据库：db.zo 存在则解码加载；不存在则建数据目录返回空库（上游 open 语义）。
/// 磁盘文件与内存 Database 的唯一交汇点。
pub async fn load(data_dir : String) -> Result[Store, StoreError] {
  let db_path = data_dir + "/db.zo"
  if @afs.exists(db_path) {
    let data = @afs.read_file(db_path) catch {
      err => return Err(Io(os_error_message(err)))
    }
    match @core.decode(data.binary()) {
      Ok(dirs) => Ok({ db: @core.Database::from_dirs(dirs), data_dir, })
      Err(e) => Err(Codec(e))
    }
  } else {
    // async/fs 的 mkdir 对已存在目录也报 EEXIST，先探测
    if !@afs.exists(data_dir) {
      @afs.mkdir(data_dir, recursive=true) catch {
        err => return Err(Io(os_error_message(err)))
      }
    }
    Ok({ db: @core.Database::new(), data_dir, })
  }
}

///|
/// 保存：dirty 才写（tmp + sync + rename 原子替换），成功后清 dirty
pub async fn Store::save(self : Store) -> Result[Unit, StoreError] {
  if !self.db.is_dirty() {
    return Ok(())
  }
  let bytes = @core.encode(self.db.all())
  write_atomic(self.data_dir + "/db.zo", bytes) catch {
    err => return Err(Io(os_error_message(err)))
  }
  self.db.mark_clean()
  Ok(())
}
