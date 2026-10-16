///|
/// The database file size cap: 32MiB (matching upstream MAX_SIZE = 32 << 20)
pub const MAX_SIZE : Int32 = 32 * 1024 * 1024

///|
/// The version of jumbit\'s own persistence format (not interoperable with upstream\'s bincode format).
/// From v2 an entry carries a trailing note: [u32 LE length][UTF-8 content], with length 0 meaning None;
/// v1 (no note field) is still readable as None -- an old database needs no migration
const CODEC_VERSION : Int32 = 2

///|
/// The lowest version the decode side accepts
const MIN_DECODE_VERSION : Int32 = 1

///|
pub enum CodecError {
  CorruptedData
  UnsupportedVersion(Int32)
  TooLarge
} derive(Debug)

///|
/// The UTF-8 encoded length (counted per scalar value, matching @utf8.encode\'s output); used for pre-sizing, avoiding a second encode
fn utf8_len(s : String) -> Int32 {
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
/// Encode (always writing the current version): a 4-byte LE version number +
/// per entry [u32 LE path byte length][UTF-8 path][f64 LE rank][u64 LE last_accessed][u32 LE note byte length][UTF-8 note].
/// Two passes: compute the exact size and pre-allocate first (the doubling copies of a million-entry byte-by-byte push are a measurable cost), then fill by index
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
/// Decode: validate the total length, version, entry boundaries and UTF-8 validity; any irregular byte is rejected as CorruptedData.
/// There is no entry-count prefix, so parsing runs "until the data is consumed"; trailing extra bytes that cannot form a complete entry are an error.
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
    // path_len is read as a signed Int, so a byte sequence like 0xFFFFFFFF becomes negative and must be rejected too
    if path_len < 0 || path_len > len - pos {
      return Err(CorruptedData)
    }
    let path : String = @utf8.decode(
      bytes.exact_view(start=pos, end=pos + path_len),
    ) catch {
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
    // a v2 entry carries a trailing note (length 0 = None); v1 has no such field and reads as None
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
          bytes.exact_view(start=pos, end=pos + note_len),
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
/// Write a little-endian u32 (filling the pre-allocated buffer by index)
fn put_u32(buf : Array[Byte], pos : Int32, v : Int32) -> Unit {
  for k in 0..<4 {
    buf[pos + k] = ((v >> (8 * k)) & 0xFF).to_byte()
  }
}

///|
/// Write a little-endian u64 (filling the pre-allocated buffer by index)
fn put_u64(buf : Array[Byte], pos : Int32, v : UInt64) -> Unit {
  for k in 0..<8 {
    buf[pos + k] = ((v >> (8 * k)) & 255UL).to_int().to_byte()
  }
}

///|
/// Read a little-endian u32
fn get_u32(bytes : Bytes, pos : Int32) -> Int32 {
  let mut v = 0
  for k in 0..<4 {
    v = v | (bytes[pos + k].to_int() << (8 * k))
  }
  v
}

///|
/// Read a little-endian u64
fn get_u64(bytes : Bytes, pos : Int32) -> UInt64 {
  let mut v = 0UL
  for k in 0..<8 {
    v = v.lor(bytes[pos + k].to_uint64() << (8 * k))
  }
  v
}
