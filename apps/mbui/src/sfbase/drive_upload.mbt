// Files going up into a folder of a drive (web/src/drive/model.ts upload): picked from
// the system's picker or dropped, each a row of the folder until it is there, one at a time whatever page is shown; a
// name taken there asked about on its row. The phone's drive pages and the desktop's files' page show them.

///|
/// A file going up into a folder of a drive: its row in the folder's list until it is
/// there.
pub(all) struct DvUpload {
  serial : Int
  station : String
  root : String
  dir : String
  name : @signals.Signal[String]
  bytes : Bytes
  sent : @signals.Signal[Int]
  /// waiting | going | taken (asked: 替换 or 保留两者) | naming (kept beside: its name asked of the core) | failed | done
  /// (up, its row kept till the folder's own comes: dv_up_listed)
  state : @signals.Signal[String]
  error : @signals.Signal[String]
  mut replace : Bool
  mut id : String
}


///|
/// The files going up, the serial of the last, whether one is going now.
pub(all) struct DriveUploads {
  uploads : @sf.LiveArray[DvUpload]
  mut serial : Int
  pumping : @signals.Signal[Bool]
}

///|
pub let ups : DriveUploads = {
  uploads: @sf.LiveArray::new(),
  serial: 0,
  pumping: @signals.signal(false, same=fn(a, b) { a == b }),
}

///|
fn ups_reset() -> Unit {
  ups.uploads.clear()
  ups.serial = 0
  ups.pumping.set(false)
}

///|
pub let dv_part_first : Int = 256 * 1024

///|
/// The part a file goes up in at most; the first is a quarter of a megabyte, doubling while
/// parts go through, so a name taken is told early.
pub let dv_part_max : Int = 4 * 1024 * 1024

///|
/// The system's file picker, for files to go up into `at`: each answered file pushed onto `ups.uploads` (waking the
/// folder's view) and going up one after another.
pub fn dv_upload(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let root = at.root.unwrap_or("")
  c.tell("drive-upload/" + at.station + ":" + root + ":" + at.path, fn() {
    match
      @ui.pick(Files, on_got=fn(files) {
        if files.is_empty() {
          return
        }
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
            replace: false,
            id: "",
          })
        }
        dv_pump(src)
      }) {
      Some(_) => ()
      None => say(c, @sf.t("android-chat.composer.noFiles"))
    }
  })
}

///|
/// The next file waiting, up (one at a time, whatever page is shown).
pub fn dv_pump(src : Source) -> Unit {
  // (those up whose folder has them now: let go)
  if ups.uploads.iter().any(fn(x) { x.state.get() == "done" && dv_up_listed(src, x) }) {
    ups.uploads.retain(fn(x) { !(x.state.get() == "done" && dv_up_listed(src, x)) })
  }
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
      u.id = dv_upload_id(u)
      dv_up_part(src, u, 0, dv_part_first)
    }
    None => ()
  }
}

///|
pub fn dv_up_done(src : Source, u : DvUpload) -> Unit {
  // (its row kept till the folder's own row of it comes, told by the core's drive topic, a message of its own: the
  // one taking the other's place as it comes, not the list's room going back a moment before it comes (rows_steady.mbt))
  u.state.set("done")
  ups.pumping.set(false)
  dv_pump(src)
}

///|
/// Whether file `u`, up, is in its folder's entries as the core has them now.
pub fn dv_up_listed(src : Source, u : DvUpload) -> Bool {
  match dv_entries(src, u.station, u.root, u.dir) {
    Some(es) => es.iter().any(fn(e) { e.name == u.name.get() })
    None => false
  }
}

///|
/// One part of a file up from `have`: the station answers with what it has (`have`), the last
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
    "id": Json::string(u.id),
    "offset": Json::number(have.to_double()),
    "total": Json::number(size.to_double()),
  }
  if u.replace {
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
        if taken && !u.replace {
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
/// A file going up into a drive's id (upload_id): the station, where in the drive it goes (the folder under its root,
/// its name), its size and bytes' hash, its place among the uploads. Not the root: that is a path on the station's
/// machine (a home folder's, a temporary one's), and a recording says it as `/test-station` (tools/trace), so a replay
/// of the run would make another id. The station keeps a part beside where the file goes (the folder, by the id:
/// station/src/drive/drive.ts `upload`), so two roots' files of the same name and bytes never meet there.
pub fn dv_upload_id(u : DvUpload) -> String {
  upload_id("drive\u{1}\{u.dir}\u{1}" + file_seed(u.station, u.name.get(), u.bytes), u.serial)
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
  let out = StringBuilder()
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

