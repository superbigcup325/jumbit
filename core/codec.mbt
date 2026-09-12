///|
/// 数据库文件大小上限：32MiB（对齐上游 MAX_SIZE = 32 << 20）
pub const MAX_SIZE : Int = 32 * 1024 * 1024

///|
/// jumbit 自有持久化格式版本（与上游 bincode 格式不互通）。
/// v2 起条目尾部带 note：[u32 LE 长度][UTF-8 内容]，长度 0 表示 None；
/// v1（无 note 字段）仍可读，读作 None——旧库无需迁移
const CODEC_VERSION : Int = 2

///|
/// 解码侧兼容的最低版本
const MIN_DECODE_VERSION : Int = 1

///|
pub enum CodecError {
  CorruptedData
  UnsupportedVersion(Int)
  TooLarge
} derive(Debug)

///|
/// UTF-8 编码长度（按标量值计，与 @utf8.encode 输出一致）；预分配用，避免二次编码
fn utf8_len(s : String) -> Int {
  let mut n = 0
  for ch in s {
    n += if ch < '\u{0080}' {
      1
    } else if ch < '\u{0800}' {
      2
    } else if ch < '\u{10000}' {
      3
    } else {
      4
    }
  }
  n
}

///|
/// 编码（恒写当前版本）：4 字节 LE 版本号 +
/// 每条目 [u32 LE 路径字节长][UTF-8 路径][f64 LE rank][u64 LE last_accessed][u32 LE note 字节长][UTF-8 note]。
/// 两趟：先精确算大小预分配（百万条目级逐字节 push 的倍增拷贝是可测开销），再按下标填充
pub fn encode(dirs : Array[Dir]) -> Bytes {
  let mut size = 4
  for dir in dirs {
    size += 4 + utf8_len(dir.path) + 8 + 8 + 4
    match dir.note {
      Some(text) => size += utf8_len(text)
      None => ()
    }
  }
  let buf : Array[Byte] = Array::make(size, 0)
  let mut pos = 0
  put_u32(buf, pos, CODEC_VERSION)
  pos += 4
  for dir in dirs {
    let path_bytes = @utf8.encode(dir.path)
    put_u32(buf, pos, path_bytes.length())
    pos += 4
    for b in path_bytes {
      buf[pos] = b
      pos += 1
    }
    put_u64(buf, pos, dir.rank.reinterpret_as_uint64())
    pos += 8
    put_u64(buf, pos, dir.last_accessed.reinterpret_as_uint64())
    pos += 8
    match dir.note {
      Some(text) => {
        let note_bytes = @utf8.encode(text)
        put_u32(buf, pos, note_bytes.length())
        pos += 4
        for b in note_bytes {
          buf[pos] = b
          pos += 1
        }
      }
      None => {
        put_u32(buf, pos, 0)
        pos += 4
      }
    }
  }
  Bytes::from_array(buf)
}

///|
/// 解码：校验总长/版本号/条目边界/UTF-8 合法性，任何不规则字节拒绝为 CorruptedData。
/// 无条目数前缀，按「读满即停」解析，尾部多余字节若凑不成完整条目即报错。
pub fn decode(bytes : Bytes) -> Result[Array[Dir], CodecError] {
  let len = bytes.length()
  if len > MAX_SIZE {
    return Err(TooLarge)
  }
  if len < 4 {
    return Err(CorruptedData)
  }
  let version = get_u32(bytes, 0)
  if version < MIN_DECODE_VERSION || version > CODEC_VERSION {
    return Err(UnsupportedVersion(version))
  }
  let dirs : Array[Dir] = []
  let mut pos = 4
  while pos < len {
    if pos + 4 > len {
      return Err(CorruptedData)
    }
    let path_len = get_u32(bytes, pos)
    pos += 4
    // path_len 按有符号 Int 读出，0xFFFFFFFF 这类字节序列会成为负数，必须一并拒绝
    if path_len < 0 || path_len > len - pos {
      return Err(CorruptedData)
    }
    let path : String = @utf8.decode(bytes.view(start=pos, end=pos + path_len)) catch {
      _ => return Err(CorruptedData)
    }
    pos += path_len
    if pos + 8 > len {
      return Err(CorruptedData)
    }
    let rank = get_u64(bytes, pos).reinterpret_as_double()
    pos += 8
    if pos + 8 > len {
      return Err(CorruptedData)
    }
    let last_accessed = get_u64(bytes, pos).reinterpret_as_int64()
    pos += 8
    // v2 条目尾部带 note（长度 0 = None）；v1 无此字段，读作 None
    let note : String? = if version == 1 {
      None
    } else {
      if pos + 4 > len {
        return Err(CorruptedData)
      }
      let note_len = get_u32(bytes, pos)
      pos += 4
      if note_len < 0 || note_len > len - pos {
        return Err(CorruptedData)
      }
      if note_len == 0 {
        None
      } else {
        let text : String = @utf8.decode(
          bytes.view(start=pos, end=pos + note_len),
        ) catch {
          _ => return Err(CorruptedData)
        }
        pos += note_len
        Some(text)
      }
    }
    dirs.push({ path, rank, last_accessed, note, })
  }
  Ok(dirs)
}

///|
/// u32 小端写入（预分配缓冲按下标填）
fn put_u32(buf : Array[Byte], pos : Int, v : Int) -> Unit {
  for k in 0..<4 {
    buf[pos + k] = ((v >> (8 * k)) & 0xFF).to_byte()
  }
}

///|
/// u64 小端写入（预分配缓冲按下标填）
fn put_u64(buf : Array[Byte], pos : Int, v : UInt64) -> Unit {
  for k in 0..<8 {
    buf[pos + k] = ((v >> (8 * k)) & 255UL).to_int().to_byte()
  }
}

///|
/// u32 小端读取
fn get_u32(bytes : Bytes, pos : Int) -> Int {
  let mut v = 0
  for k in 0..<4 {
    v = v | (bytes[pos + k].to_int() << (8 * k))
  }
  v
}

///|
/// u64 小端读取
fn get_u64(bytes : Bytes, pos : Int) -> UInt64 {
  let mut v = 0UL
  for k in 0..<8 {
    v = v.lor(bytes[pos + k].to_uint64() << (8 * k))
  }
  v
}
