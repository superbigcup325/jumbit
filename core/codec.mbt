///|
/// 数据库文件大小上限：32MiB（对齐上游 MAX_SIZE = 32 << 20）
pub const MAX_SIZE : Int = 32 * 1024 * 1024

///|
/// jumbit 自有持久化格式版本（与上游 bincode 格式不互通）
const CODEC_VERSION : Int = 1

///|
pub enum CodecError {
  CorruptedData
  UnsupportedVersion(Int)
  TooLarge
} derive(Debug)

///|
/// 编码：4 字节 LE 版本号 + 每条目 [u32 LE 路径字节长][UTF-8 路径][f64 LE rank][u64 LE last_accessed]
pub fn encode(dirs : Array[Dir]) -> Bytes {
  let buf : Array[Byte] = []
  put_u32(buf, CODEC_VERSION)
  for dir in dirs {
    let path_bytes = @utf8.encode(dir.path)
    put_u32(buf, path_bytes.length())
    for b in path_bytes {
      buf.push(b)
    }
    put_u64(buf, dir.rank.reinterpret_as_uint64())
    put_u64(buf, dir.last_accessed.reinterpret_as_uint64())
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
  if version != CODEC_VERSION {
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
    dirs.push({ path, rank, last_accessed, })
  }
  Ok(dirs)
}

///|
/// u32 小端写入
fn put_u32(buf : Array[Byte], v : Int) -> Unit {
  for k in 0..<4 {
    buf.push(((v >> (8 * k)) & 0xFF).to_byte())
  }
}

///|
/// u64 小端写入
fn put_u64(buf : Array[Byte], v : UInt64) -> Unit {
  for k in 0..<8 {
    buf.push(((v >> (8 * k)) & 255UL).to_int().to_byte())
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
