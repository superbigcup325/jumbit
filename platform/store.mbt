///|
/// 数据库存取错误：IO 失败（含消息）或编解码失败
pub enum StoreError {
  Io(String)
  Codec(@core.CodecError)
} derive(Debug)

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
      err => return Err(Io("\{Repr(err)}"))
    }
    match @core.decode(data.binary()) {
      Ok(dirs) => Ok({ db: @core.Database::from_dirs(dirs), data_dir, })
      Err(e) => Err(Codec(e))
    }
  } else {
    // async/fs 的 mkdir 对已存在目录也报 EEXIST，先探测
    if !@afs.exists(data_dir) {
      @afs.mkdir(data_dir, recursive=true) catch {
        err => return Err(Io("\{Repr(err)}"))
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
    err => return Err(Io("\{Repr(err)}"))
  }
  self.db.mark_clean()
  Ok(())
}
