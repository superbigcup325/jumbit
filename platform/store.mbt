///|
/// 数据库存取错误：IO 失败、二进制编解码失败、明文行级失败
pub enum StoreError {
  Io(String)
  Codec(@core.CodecError)
  Plaintext(@core.PlaintextError)
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
/// 数据库失败: 」等）；明文行级错误多行（每行一条，decode 已截断到 8+N）
pub fn StoreError::message(self : StoreError) -> String {
  match self {
    Io(msg) => "读写失败: \{msg}"
    Codec(e) => codec_error_message(e)
    Plaintext(e) => e.message()
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
      // Windows 数值回落（probe run 36044327191 实证：async 的 is_E* 谓词在
      // Windows 构建下对短语表失效）；四类 errno 数值 POSIX 与 Windows CRT
      // 一致（2/13/20/17），上游修复谓词后可撤
      let phrase = if ose.is_ENOENT() || (is_windows() && errno == 2) {
        "No such file or directory"
      } else if ose.is_EACCES() || (is_windows() && errno == 13) {
        "Permission denied"
      } else if ose.is_ENOTDIR() || (is_windows() && errno == 20) {
        "Not a directory"
      } else if ose.is_EEXIST() || (is_windows() && errno == 17) {
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
/// Windows 判定（编译期）：数值回落只圈 Windows，Linux/macOS 语义保持
/// 谓词驱动不变
#cfg(platform="windows")
fn is_windows() -> Bool {
  true
}

///|
#warnings("-unused_value")
#cfg(not(platform="windows"))
fn is_windows() -> Bool {
  false
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
/// note 侧文件路径（明文 db.txt 不含 note 列，人工标注存独立 TSV；
/// 格式 `path\tnote`，path 含 tab 为病态路径，读写均按首个 tab 切分——
/// 错位属已知限制，TROUBLESHOOTING 注记）
fn notes_path(data_dir : String) -> String {
  data_dir + "/notes.tsv"
}

///|
/// 读取 notes.tsv 并按 path 就地附着到 dirs（文件缺失 = 无标注，正常态；
/// 未命中 db 条目的行静默忽略——remove/lazy-delete 后孤儿 note 宽松跟随；
/// note 空串行 = 清除标记，跳过附着）
async fn attach_notes(data_dir : String, dirs : Array[@core.Dir]) -> Unit {
  let path = notes_path(data_dir)
  if !@afs.exists(path) {
    return
  }
  let data = @afs.read_file(path) catch {
    _ => return // notes 读失败不阻塞主库加载（best-effort 标注）
  }
  let text = data.text()
  for line in text.split("\n") {
    let line = line.to_owned()
    if line.is_empty() {
      continue
    }
    match line.find("\t") {
      Some(tab) => {
        let p = line[0:tab].to_owned()
        let note = line[tab + 1:].to_owned()
        for d in dirs {
          if d.path == p {
            if note != "" {
              d.note = Some(note)
            }
            break
          }
        }
      }
      None => () // 无 tab 的行不是合法条目，忽略
    }
  }
}

///|
/// 打开数据库（规格 docs/spec-plaintext-edit.md §1.3）：
/// 1. db.txt 存在 → 明文解码（note 经 notes.tsv 附着），dirty=false
/// 2. db.txt 不存在、legacy db.zo 存在 → 二进制解码 + 强制标脏（下次 save
///    落成明文 db.txt，即迁移；只读命令不 save 故不触发）
/// 3. 均不存在 → 建数据目录返回空库（上游 open 语义）
/// 磁盘文件与内存 Database 的唯一交汇点。
pub async fn load(data_dir : String) -> Result[Store, StoreError] {
  let txt_path = data_dir + "/db.txt"
  let zo_path = data_dir + "/db.zo"
  if @afs.exists(txt_path) {
    let data = @afs.read_file(txt_path) catch {
      err => return Err(Io(os_error_message(err)))
    }
    match @core.decode_plaintext(data.binary()) {
      Ok(dirs) => {
        attach_notes(data_dir, dirs)
        Ok({ db: @core.Database::from_dirs(dirs), data_dir, })
      }
      Err(e) => Err(Plaintext(e))
    }
  } else if @afs.exists(zo_path) {
    let data = @afs.read_file(zo_path) catch {
      err => return Err(Io(os_error_message(err)))
    }
    match @core.decode(data.binary()) {
      Ok(dirs) => {
        // legacy 迁移态：只读命令不落盘，首个写命令 save 时转明文；
        // note 随 bincode 读入（v2），save 时汇入 notes.tsv
        let db = @core.Database::from_dirs(dirs)
        db.mark_dirty()
        Ok({ db, data_dir, })
      }
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
/// 保存：dirty 才写（tmp + sync + rename 原子替换），成功后清 dirty。
/// 明文面：db.txt（主库）+ notes.tsv（标注侧文件，以内存有标注集合为唯一
/// 事实源整体重写，孤儿行自然消亡）；先主库后侧文件，双文件无跨文件事务
/// （note 为 best-effort 标注，崩溃窗口丢失可接受，规格 §1.2）
pub async fn Store::save(self : Store) -> Result[Unit, StoreError] {
  if !self.db.is_dirty() {
    return Ok(())
  }
  let dirs = self.db.all()
  let bytes = @core.encode_plaintext(dirs)
  write_atomic(self.data_dir + "/db.txt", bytes) catch {
    err => return Err(Io(os_error_message(err)))
  }
  // notes.tsv：有标注的条目全量重写
  let sb = StringBuilder()
  for d in dirs {
    match d.note {
      Some(note) => {
        sb.write_string(d.path)
        sb.write_char('\t')
        sb.write_string(note)
        sb.write_char('\n')
      }
      None => ()
    }
  }
  let notes_bytes = @utf8.encode(sb.to_string())
  write_atomic(notes_path(self.data_dir), notes_bytes) catch {
    err => return Err(Io(os_error_message(err)))
  }
  self.db.mark_clean()
  Ok(())
}
