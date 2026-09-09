///|
/// 导入源的单条记录：行号（1 起，空行/空记录同样计数，对齐上游逐行读取语义）
/// result 为 UTF-8 解码结果；解码失败的行给原因，由调用方拼 `<来源>:<行号>` 上报
pub(all) struct ImportRecord {
  line_num : Int
  result : Result[String, String]
} derive(Debug)

///|
/// 读插件数据文件并切分为记录（\n 分隔、剥记录尾 \r）。
/// 按字节切分后逐行解码：坏 UTF-8 只影响所在行（对齐上游逐行 str::from_utf8）。
pub async fn read_import_lines(
  path : String,
) -> Result[Array[ImportRecord], String] {
  let data = @afs.read_file(path) catch {
    err => return Err("could not read \{path}: \{Repr(err)}")
  }
  Ok(split_records(data.binary(), b'\n', true))
}

///|
/// atuin 历史：起子进程 `atuin history list --format={time}\t{directory} --print0`
/// 读 NUL 分隔记录。上游为流式读取且不检查退出码，这里收集后同语义。
/// 返回 (记录, atuin 的 stderr 原文)——上游继承 stderr 直接可见，这里交调用方上报。
pub async fn atuin_history_records() -> Result[
  (Array[ImportRecord], String),
  String,
] {
  records_from_process("atuin", [
    "history", "list", "--format={time}\t{directory}", "--print0",
  ])
}

///|
/// 子进程记录读取的可测内核：NUL 分隔、不剥 \r（atuin 不做 CR 处理）
async fn records_from_process(
  cmd : String,
  args : Array[String],
) -> Result[(Array[ImportRecord], String), String] {
  let (_code, stdout, stderr) = @process.collect_output(cmd, args) catch {
    _ => return Err("failed to run `\{cmd}`; is it installed and on PATH?")
  }
  let err_text : String = stderr.text() catch { _ => "" }
  Ok((split_records(stdout.binary(), b'\x00', false), err_text))
}

///|
/// 按分隔符切字节流：分隔符不保留；strip_cr 时剥记录尾 \r（文件行尾 \r\n）；
/// 空记录保留占位（行号连续，调用方静默跳过）；末尾不足一条的残余按最后一条计
fn split_records(
  bytes : Bytes,
  sep : Byte,
  strip_cr : Bool,
) -> Array[ImportRecord] {
  let out : Array[ImportRecord] = []
  let chunk : Array[Byte] = []
  let mut line_num = 0
  for i in 0..<bytes.length() {
    let b = bytes[i]
    if b == sep {
      line_num += 1
      out.push(decode_chunk(chunk, line_num, strip_cr))
      chunk.clear()
    } else {
      chunk.push(b)
    }
  }
  if chunk.length() > 0 {
    line_num += 1
    out.push(decode_chunk(chunk, line_num, strip_cr))
  }
  out
}

///|
/// 单条记录解码：先剥 \r（strip_cr），再 UTF-8 解码（失败不中止，标记该行）。
/// 坏字节文案对齐上游 str::from_utf8 + anyhow context 的链式 Display
/// （2026-09-09 与 zoxide 0.10.0 逐类探针实测）：
/// - 行内坏字节：`invalid utf-8 sequence of N bytes from index M`，N 为
///   std Utf8Error::error_len——起始字节坏/双字节次字节坏=1、三字节第三字节
///   坏=2、四字节第四字节坏=3
/// - 序列在切片末尾截断：`incomplete utf-8 byte sequence from index M`
fn decode_chunk(
  chunk : Array[Byte],
  line_num : Int,
  strip_cr : Bool,
) -> ImportRecord {
  if strip_cr && chunk.length() > 0 && chunk[chunk.length() - 1] == b'\r' {
    ignore(chunk.pop())
  }
  match utf8_error(chunk) {
    Some(msg) => { line_num, result: Err("invalid utf-8: \{msg}"), }
    None => {
      let text : String = @utf8.decode(Bytes::from_array(chunk)) catch {
        _ => return { line_num, result: Err("invalid utf-8"), }
      }
      { line_num, result: Ok(text), }
    }
  }
}

///|
/// UTF-8 校验（RFC 3629，复刻 std 校验器的错误定位语义）；None = 合法。
/// 行切片内的截断与文件尾截断同型：std 对切片末尾的不完整序列报 incomplete
fn utf8_error(bytes : Array[Byte]) -> String? {
  let n = bytes.length()
  // 续字节域 80..BF
  fn cont(i : Int) -> Bool {
    let v = bytes[i].to_int()
    v >= 0x80 && v < 0xC0
  }
  let mut i = 0
  while i < n {
    let b = bytes[i].to_int()
    if b < 0x80 {
      i += 1
      continue
    }
    if b < 0xC2 {
      // 80-BF 起始错位 / C0-C1 过long起始
      return Some("invalid utf-8 sequence of 1 bytes from index \{i}")
    }
    if b < 0xE0 {
      // 双字节 C2-DF
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      if !cont(i + 1) {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i}")
      }
      i += 2
      continue
    }
    if b < 0xF0 {
      // 三字节 E0-EF；E0 二字节域 A0-BF（防过long），ED 域 80-9F（防代理区）
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      let b2 = bytes[i + 1].to_int()
      let ok2 = if b == 0xE0 {
        b2 >= 0xA0 && b2 < 0xC0
      } else if b == 0xED {
        b2 >= 0x80 && b2 < 0xA0
      } else {
        b2 >= 0x80 && b2 < 0xC0
      }
      if !ok2 {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i}")
      }
      if i + 2 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      if !cont(i + 2) {
        return Some("invalid utf-8 sequence of 2 bytes from index \{i}")
      }
      i += 3
      continue
    }
    if b < 0xF5 {
      // 四字节 F0-F4；F0 二字节域 90-BF，F4 域 80-8F（防 >U+10FFFF）
      if i + 1 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      let b2 = bytes[i + 1].to_int()
      let ok2 = if b == 0xF0 {
        b2 >= 0x90 && b2 < 0xC0
      } else if b == 0xF4 {
        b2 >= 0x80 && b2 < 0x90
      } else {
        b2 >= 0x80 && b2 < 0xC0
      }
      if !ok2 {
        return Some("invalid utf-8 sequence of 1 bytes from index \{i}")
      }
      if i + 2 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      if !cont(i + 2) {
        return Some("invalid utf-8 sequence of 2 bytes from index \{i}")
      }
      if i + 3 >= n {
        return Some("incomplete utf-8 byte sequence from index \{i}")
      }
      if !cont(i + 3) {
        return Some("invalid utf-8 sequence of 3 bytes from index \{i}")
      }
      i += 4
      continue
    }
    // F5-FF 非法起始
    return Some("invalid utf-8 sequence of 1 bytes from index \{i}")
  }
  None
}
