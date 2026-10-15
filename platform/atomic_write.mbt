///|
/// Atomic write: create a tmp file in the same directory (tmp_ + 16 random characters, retried 5 times on collision)
/// -> write -> sync -> rename for an atomic replacement; on failure errdefer cleans up the tmp and rethrows as is.
/// (matching upstream src/util.rs util::write; rename is atomic on UNIX)
pub async fn write_atomic(path : String, contents : Bytes) -> Unit {
  let dir = match path.rev_find("/") {
    Some(i) => path[0:i + 1].to_owned()
    None => ""
  }
  let pair = for attempts = 0 {
    let tmp = dir + "tmp_" + rand_name()
    let opened = @afs.create(tmp, allow_existing=false) catch {
      e => if attempts >= 4 { raise e } else { continue attempts + 1 }
    }
    break (opened, tmp)
  }
  let (file, tmp) = pair
  errdefer remove_quiet(tmp)
  file.write(contents)
  file.sync()
  file.close()
  @afs.rename(tmp, path, replace=true)
}

///|
/// Delete a file and swallow errors (for errdefer cleanup; a tmp that never existed also counts as success)
async fn remove_quiet(path : String) -> Unit {
  @afs.remove(path) catch {
    err => ignore(err)
  }
}

///|
/// A process-level random source ([#11]): the global singleton advances the ChaCha8 sequence on every call, so tmp names are
/// unique within the process. Since moonc v0.10.15 a no-argument Rand() seeds from platform entropy (falling back to a fixed
/// built-in seed only when entropy is unavailable), so sequences differ across processes too; before that a no-argument Rand::new() used a fixed seed and a fresh one per call inside the function
/// produced the same sequence, so write_atomic\'s 5 retries kept colliding on one tmp name
let global_rand : @random.Rand = @random.Rand()

///|
/// The random tmp name: advanced from the process-level generator, 16 lowercase alphanumerics
fn rand_name() -> String {
  let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789".to_array()
  let sb = StringBuilder()
  for _ in 0..<16 {
    sb.write_char(alphabet[global_rand.int(limit=36)])
  }
  sb.to_string()
}
