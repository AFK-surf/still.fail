// Files going up into a folder of a drive (web/src/drive/model.ts upload, DriveScreen.kt DriveUpload): picked from
// the system's picker or dropped, each a row of the folder until it is there, one at a time whatever page is shown; a
// name taken there asked about on its row. The phone's drive pages and the desktop's files' page show them.

///|
/// A file going up into a folder of a drive (DriveScreen.kt DriveUpload): its row in the folder's list until it is
/// there.
pub(all) struct DvUpload {
  serial : Int
  station : String
  root : String
  dir : String
  name : @signals.Signal[String]
  bytes : Bytes
  sent : @signals.Signal[Int]
  /// waiting | going | taken (asked: 替换 or 保留两者) | naming (kept beside: its name asked of the core) | failed
  state : @signals.Signal[String]
  error : @signals.Signal[String]
  replace : @signals.Signal[Bool]
  id : @signals.Signal[String]
}


///|
/// The files going up, the serial of the last, whether one is going now; a file being picked to go up, and where to.
pub(all) struct DriveUploads {
  uploads : @sf.LiveArray[DvUpload]
  // (plain: the next upload's number, read only as one is added)
  mut serial : Int
  pumping : @signals.Signal[Bool]
  picking : @signals.Signal[@ui.Pick?]
  picking_for : @signals.Signal[DriveAt]
}

///|
pub let ups : DriveUploads = {
  uploads: @sf.LiveArray::new(),
  serial: 0,
  pumping: @signals.signal(false, same=fn(a, b) { a == b }),
  picking: @signals.signal(None),
  picking_for: @signals.signal({ station: "", root: None, path: "" }),
}

///|
fn ups_reset() -> Unit {
  ups.uploads.clear()
  ups.serial = 0
  ups.pumping.set(false)
  ups.picking.set(None)
  ups.picking_for.set({ station: "", root: None, path: "" })
}

///|
pub let dv_part_first : Int = 256 * 1024

///|
/// The part a file goes up in at most (Calls.kt UPLOAD_PART); the first is a quarter of a megabyte, doubling while
/// parts go through, so a name taken is told early.
pub let dv_part_max : Int = 4 * 1024 * 1024

///|
/// The system's file picker, for files to go up into `at`.
pub fn dv_upload(c : @ui.Ctx, at : DriveAt) -> Unit {
  // det-ok(build-effect): its pages call it only under the press that asks for it
  match @ui.pick(Files) {
    Some(p) => {
      ups.picking.set(Some(p))
      ups.picking_for.set(at)
    }
    None => say(c, @sf.t("android-chat.composer.noFiles"))
  }
}

///|
/// The files picked, once the system has answered: each a row of the folder, going up one after another.
pub fn dv_take_picked(src : Source, at : DriveAt, entries : Array[DvEntry]) -> Unit {
  ignore(entries)
  match ups.picking.get() {
    Some(p) if ups.picking_for.get() == at =>
      match p.files() {
        Some(files) => {
          ups.picking.set(None)
          let root = at.root.unwrap_or("")
          for f in files {
            ups.serial += 1
            ups.uploads.push({
              serial: ups.serial,
              station: at.station,
              root,
              dir: at.path,
              name: @signals.signal(f.name),
              bytes: f.bytes,
              sent: @signals.signal(0),
              state: @signals.signal("waiting"),
              error: @signals.signal(""),
              replace: @signals.signal(false, same=fn(a, b) { a == b }),
              id: @signals.signal("", same=fn(a, b) { a == b }),
            })
          }
          dv_pump(src)
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// The next file waiting, up (one at a time, whatever page is shown).
pub fn dv_pump(src : Source) -> Unit {
  if ups.pumping.get() {
    return
  }
  // (the next file waiting, sent once: its bytes are what was picked, whichever build sends it)
  match ups.uploads.iter().find_first(fn(u) { u.state.get() == "waiting" }) {
    Some(u) => {
      if src.read_only {
        u.state.set("failed")
        u.error.set(read_only_words)
        dv_pump(src)
        return
      }
      ups.pumping.set(true)
      u.state.set("going")
      u.sent.set(0)
      u.id.set(upload_id("drive\u{1}\{u.root}\u{1}\{u.dir}\u{1}" + file_seed(u.station, u.name.get(), u.bytes), u.serial))
      dv_up_part(src, u, 0, dv_part_first)
    }
    None => ()
  }
}

///|
pub fn dv_up_done(src : Source, u : DvUpload) -> Unit {
  ups.uploads.retain(fn(x) { x.serial != u.serial })
  ups.pumping.set(false)
  dv_pump(src)
}

///|
/// One part of a file up from `have` (Calls.kt driveUpload): the station answers with what it has (`have`), the last
/// part in with the entry it now has; a name taken refuses the first part (409), asked in its row.
pub fn dv_up_part(src : Source, u : DvUpload, have : Int, planned : Int) -> Unit {
  if !ups.uploads.iter().any(fn(x) { x.serial == u.serial }) {
    ups.pumping.set(false)
    dv_pump(src)
    return
  }
  let size = u.bytes.length()
  let len = if size - have < planned { size - have } else { planned }
  let part = Bytes::makei(len, fn(i) { u.bytes[have + i] })
  let params : Map[String, Json] = {
    "station": Json::string(u.station),
    "root": Json::string(u.root),
    "path": Json::string(dv_join(u.dir, u.name.get())),
    "id": Json::string(u.id.get()),
    "offset": Json::number(have.to_double()),
    "total": Json::number(size.to_double()),
  }
  if u.replace.get() {
    params["replace"] = Json::boolean(true)
  }
  (src.call_bytes)("drive.upload.part", Json::object(params), part, fn(r) {
    match r {
      Ok(answer) => {
        let entry = match field(Some(answer), "entry") {
          Some(Null) | None => false
          _ => true
        }
        let next = match field(Some(answer), "have") {
          Some(Number(n, ..)) => n.to_int()
          _ => have + len
        }
        if entry || next >= size {
          u.sent.set(size)
          dv_up_done(src, u)
        } else if next <= have {
          u.state.set("failed")
          u.error.set(@sf.t("android-chat.file.uploadFailed"))
          ups.pumping.set(false)
          dv_pump(src)
        } else {
          u.sent.set(next)
          let more = if next == have + len {
            if planned * 2 > dv_part_max {
              dv_part_max
            } else {
              planned * 2
            }
          } else {
            dv_part_first
          }
          dv_up_part(src, u, next, more)
        }
      }
      Err(e) => {
        let taken = number(Some(e), "status") == 409.0 || text(Some(e), "code") == "exists"
        if taken && !u.replace.get() {
          u.state.set("taken")
        } else {
          u.state.set("failed")
          u.error.set(dv_error(e))
        }
        ups.pumping.set(false)
        dv_pump(src)
      }
    }
  })
}

///|
/// An upload's id: 32 hex digits (the Android app's UUID without its dashes), from what goes up and where, never
/// from a clock: `what` (where it goes, its name, its bytes' hash) and `n` (its place among what goes up there: a
/// draft's files, a folder's uploads). The same upload made over any run, recorded or replayed, has the same id.
pub fn upload_id(what : String, n : Int) -> String {
  let seed = "\{what}/\{n}"
  let hex = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = StringBuilder::new()
  // two FNV-1a (@ui.stable_hash: the same in every run and on js and native), 16 digits each
  for half in [@ui.stable_hash(seed), @ui.stable_hash(seed + "\u{1}")] {
    let mut h = half
    for _ in 0..<16 {
      out.write_char(hex[(h & 15L).to_int()])
      h = h >> 4
    }
  }
  out.to_string()
}

///|
/// What a file going up is known by for its id (upload_id): the station, its name, its size and its bytes' hash.
pub fn file_seed(station : String, name : String, bytes : Bytes) -> String {
  "\{station}\u{1}\{name}\u{1}\{bytes.length()}\u{1}\{@ui.stable_hash_bytes(bytes)}"
}

///|
/// What a file the host holds (@hostapi.Picked.held) going up to `station` is known by, as file_seed says one read
/// whole: its name, its size and where the host has it.
pub fn held_seed(station : String, f : @hostapi.Picked) -> String {
  "\{station}\u{1}held\u{1}\{f.name}\u{1}\{f.size}\u{1}\{f.src}"
}


///|
/// What a read-only run says it does not do.
pub let read_only_words : String = "只读运行：不发送，不上传，不保存草稿"

///|
pub fn say(c : @ui.Ctx, words : String) -> Unit {
  ignore(c)
  toast_later(words)
}

///|
pub fn dv_error(e : Json) -> String {
  match text(Some(e), "message") {
    "" => @sf.t("android-misc.failed")
    m => m
  }
}

