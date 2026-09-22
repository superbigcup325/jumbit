///|
/// edit 执行层（jumbit 扩展，规格 docs/spec-plaintext-edit.md §1.4）：
/// 三形态共享「加载 → 变换 → 校验 → save」管线，语义权威源单一。
/// 默认形态：$VISUAL/$EDITOR 编辑 db.txt 副本，读回解析，无变化静默、
/// 有变化整库替换；--rename 改路径（note 跟随）；--prune 清除不存在条目
async fn run_edit(
  eopts : @cli.EditOptions,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  let data_dir = match cfg(@config.data_dir(getenv), errs) {
    Some(data_dir) => data_dir
    None => return 1
  }
  let store = match @platform.load(data_dir) {
    Ok(s) => s
    Err(e) => {
      err_line(errs, "打开数据库失败: \{e.message()}")
      return 1
    }
  }
  let db = store.database()
  // 结构化形态先于交互形态（互斥已在解析层裁定）
  if eopts.prune {
    return run_edit_prune(db, store, errs)
  }
  match eopts.rename_old {
    Some(old) => {
      let new = match eopts.rename_new {
        Some(n) => n
        None => return 1 // 解析层保证不达
      }
      return run_edit_rename(db, store, old, new, errs)
    }
    None => ()
  }
  run_edit_interactive(data_dir, db, store, getenv, errs)
}

///|
/// --rename：精确路径匹配（remove 同款双重尝试：原串 → 规范化）；
/// note 跟随迁移；new 撞库内既有条目报错不合并
async fn run_edit_rename(
  db : @core.Database,
  store : @platform.Store,
  old : String,
  new : String,
  errs : Array[String],
) -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/"
  }
  // 撞名预检：new 已在库中（双重尝试同款）→ 报错不合并（规格 §1.4；
  // old==new 视为撞自身，同样拒绝——重命名到自身无意义且语义含糊）
  let new_norm = @core.resolve_path(new, cwd)
  if db.find_idx(new_norm) is Some(_) {
    err_line(errs, "path already in database: \{new}")
    return 1
  }
  let renamed = try_twice(db, old, cwd, fn(db, p) { db.rename(p, new) })
  if !renamed {
    err_line(errs, "path not found in database: \{old}")
    return 1
  }
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "保存数据库失败: \{e.message()}")
      1
    }
  }
}

///|
/// --prune：全量存在性扫描（status --check 同款），移除不存在条目并逐行
/// 输出清单（stdout）；无移除静默 exit 0
async fn run_edit_prune(
  db : @core.Database,
  store : @platform.Store,
  errs : Array[String],
) -> Int {
  let removed : Array[String] = []
  for d in db.all() {
    if !(@afs.exists(d.path) catch { _ => false }) {
      removed.push(d.path)
    }
  }
  if removed.is_empty() {
    return 0
  }
  for p in removed {
    // remove 的 swap_remove 语义（懒删除同款）；已确认存在才会进清单
    let _ = db.remove(p)
    println(p)
  }
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "保存数据库失败: \{e.message()}")
      1
    }
  }
}

///|
/// 默认形态：db.txt 当前内容写临时文件 → $VISUAL/$EDITOR 继承终端编辑 →
/// 读回解析（decode_plaintext 全套行级校验）→ 与编辑前比对：无变化静默、
/// 有变化整库替换 + save。note 不进编辑面（notes.tsv 侧文件），编辑后按
/// path 匹配保留原标注（path 改名 = 丢标注，规格 §1.4 注明）
async fn run_edit_interactive(
  data_dir : String,
  db : @core.Database,
  store : @platform.Store,
  getenv : (String) -> String?,
  errs : Array[String],
) -> Int {
  // 编辑面内容 = 当前主库序列化（不含 note 列）
  let before = @core.encode_plaintext(db.all())
  let tmp = data_dir + "/db.txt.edit"
  let opened = @afs.create(tmp) catch {
    err => {
      err_line(
        errs,
        "无法写入临时文件: \{@platform.os_error_message(err)}",
      )
      return 1
    }
  }
  opened.write(before) catch {
    err => {
      ignore(err)
      let _ = @afs.remove(tmp)
      err_line(errs, "无法写入临时文件")
      return 1
    }
  }
  opened.sync()
  // 起编辑器（继承终端；退出码非 0 = 用户取消/编辑器故障，不落库）
  match @platform.run_editor(tmp, getenv) {
    Err(NotFound) => {
      err_line(errs, "no editor: set $EDITOR or $VISUAL")
      let _ = @afs.remove(tmp)
      return 1
    }
    Err(Failed(code)) => {
      err_line(errs, "editor exited with code \{code}")
      let _ = @afs.remove(tmp)
      return 1
    }
    Err(Spawn) => {
      err_line(errs, "could not launch editor")
      let _ = @afs.remove(tmp)
      return 1
    }
    Ok(_) => ()
  }
  // 读回 + 行级校验（坏行 → 不落库，报「数据文件损坏」同款前缀）
  let data = @afs.read_file(tmp) catch {
    err => {
      err_line(
        errs,
        "无法读取编辑结果: \{@platform.os_error_message(err)}",
      )
      let _ = @afs.remove(tmp)
      return 1
    }
  }
  let dirs = match @core.decode_plaintext(data.binary()) {
    Ok(dirs) => dirs
    Err(e) => {
      err_line(errs, "数据文件损坏: \{e.message()}")
      let _ = @afs.remove(tmp)
      return 1
    }
  }
  let _ = @afs.remove(tmp)
  // 无变化判定：字节级（编码确定 ⇒ 内容等价）
  if @core.encode_plaintext(dirs) == before {
    return 0
  }
  // note 保留：编辑前有标注的 path 在新集合中仍存在则继承
  let old_notes : Array[@core.Dir] = db.all()
  for nd in dirs {
    for od in old_notes {
      if od.path == nd.path && nd.note is None {
        nd.note = od.note
      }
    }
  }
  db.replace_all(dirs)
  match store.save() {
    Ok(_) => 0
    Err(e) => {
      err_line(errs, "保存数据库失败: \{e.message()}")
      1
    }
  }
}
