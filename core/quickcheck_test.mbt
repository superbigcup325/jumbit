// 性质测试（core @quickcheck）：与单测/golden 的分工=锁语义不变量（随机输入 +
// 失败收缩），不堆字节断言。check 种子固定保证 CI 复现；A=UInt64 作为「数据
// 种子」注入 chacha8，性质体内自建随机输入（roadmap 存量条目「quickcheck 纳入
// 测试面评估」的落地）

///|
fn qc_seed_bytes(s : UInt64) -> Bytes {
  // chacha8 种子定长 32 字节：十进制表示 + 定长填充拼到 32（ASCII 恒 32 字节；
  // String::to_bytes 已弃用，走 @encoding/utf8.encode）
  let base = s.to_string()
  let filler = "0123456789abcdefghij0123456789abcdefghij"
  @utf8.encode(base + filler[0:32 - base.length()].to_owned())
}

///|
test "property: 明文 codec 往返不变量" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      let dirs : Array[@core.Dir] = []
      for i in 0..<rand.int(limit=20) {
        dirs.push({
          path: "/home/user/\{rand.int(limit=64)}/dir-\{i}",
          // 两位小数域内生成（明文 rank 两位出，域内往返须精确无损）
          rank: rand.int(limit=1000000).to_double() / 100.0,
          last_accessed: rand.int(limit=100000).to_int64(),
          note: None,
        })
      }
      match @core.decode_plaintext(@core.encode_plaintext(dirs)) {
        Ok(out) => {
          let mut ok = out.length() == dirs.length()
          if ok {
            for i in 0..<dirs.length() {
              if out[i].path != dirs[i].path ||
                out[i].rank != dirs[i].rank ||
                out[i].last_accessed != dirs[i].last_accessed {
                ok = false
              }
            }
          }
          ok
        }
        Err(_) => false
      }
    },
    count=200U,
    seed=20260925UL,
  )
}

///|
test "property: glob 不跨路径分隔符" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      // 无分隔符 pattern：字母 + `*` + `?`（恒为合法 pattern，避开 `[` 未闭合）
      let alphabet = "abcxy*?".to_array()
      let n = 1 + rand.int(limit=8)
      let buf = StringBuilder()
      for _ in 0..<n {
        buf.write_char(alphabet[rand.int(limit=7)])
      }
      let pattern = buf.to_string()
      // 控制组：pattern 恒匹配自身（防「恒 false」的空洞性质）
      @core.glob_match(pattern, pattern) &&
      // 分隔符不跨：pattern 无 `/` 时，含 `/` 的路径必不匹配
      !@core.glob_match(pattern, "/" + pattern + "/x")
    },
    count=200U,
    seed=20260925UL,
  )
}

///|
test "property: resolve_path 幂等" {
  @quickcheck.check(
    fn(seed : UInt64) {
      let rand = @random.Rand::chacha8(seed=qc_seed_bytes(seed))
      let segs = ["a", "b", "c", "..", "."]
      let n = rand.int(limit=6)
      let buf = StringBuilder()
      for _ in 0..<n {
        buf.write_string(segs[rand.int(limit=5)])
        buf.write_string("/")
      }
      let mut path = buf.to_string()
      if rand.int(limit=2) == 0 {
        path = "/" + path
      }
      let base = ["/x/y", "/", "/x"][rand.int(limit=3)]
      let once = @core.resolve_path(path, base)
      // 二次规范化是恒等变换（含 .. 越界与点段消除后的不动点）
      @core.resolve_path(once, base) == once
    },
    count=200U,
    seed=20260925UL,
  )
}
