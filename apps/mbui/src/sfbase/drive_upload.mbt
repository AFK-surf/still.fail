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
  mut name : String
  bytes : Bytes
  mut sent : Int
  /// waiting | going | taken | failed
  mut state : String
  mut error : String
  mut replace : Bool
  mut id : String
}


///|
/// The files going up, the serial of the last, whether one is going now; a file being picked to go up, and where to.
pub(all) struct DriveUploads {
  uploads : Array[DvUpload]
  mut serial : Int
  mut pumping : Bool
  mut picking : @ui.Pick?
  mut picking_for : DriveAt
}

///|
pub let ups : DriveUploads = {
  uploads: [],
  serial: 0,
  pumping: false,
  picking: None,
  picking_for: { station: "", root: None, path: "" },
}

///|
fn ups_reset() -> Unit {
  ups.uploads.clear()
  ups.serial = 0
  ups.pumping = false
  ups.picking = None
  ups.picking_for = { station: "", root: None, path: "" }
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
      ups.picking = Some(p)
      ups.picking_for = at
    }
    None => say(c, @sf.t("android-chat.composer.noFiles"))
  }
}

///|
/// The files picked, once the system has answered: each a row of the folder, going up one after another.
pub fn dv_take_picked(src : Source, at : DriveAt, entries : Array[DvEntry]) -> Unit {
  ignore(entries)
  match ups.picking {
    Some(p) if ups.picking_for == at =>
      match p.files() {
        Some(files) => {
          ups.picking = None
          let root = at.root.unwrap_or("")
          for f in files {
            ups.serial += 1
            ups.uploads.push({
              serial: ups.serial,
              station: at.station,
              root,
              dir: at.path,
              name: f.name,
              bytes: f.bytes,
              sent: 0,
              state: "waiting",
              error: "",
              replace: false,
              id: "",
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
  if ups.pumping {
    return
  }
  // (the next file waiting, sent once: its bytes are what was picked, whichever build sends it)
  match ups.uploads.iter().find_first(fn(u) { u.state == "waiting" }) {
    Some(u) => {
      if src.read_only {
        u.state = "failed"
        u.error = read_only_words
        dv_pump(src)
        return
      }
      ups.pumping = true
      u.state = "going"
      u.sent = 0
      u.id = upload_id("drive\u{1}\{u.root}\u{1}\{u.dir}\u{1}" + file_seed(u.station, u.name, u.bytes), u.serial)
      dv_up_part(src, u, 0, dv_part_first)
    }
    None => ()
  }
}

///|
pub fn dv_up_done(src : Source, u : DvUpload) -> Unit {
  ups.uploads.retain(fn(x) { x.serial != u.serial })
  ups.pumping = false
  dv_pump(src)
}

///|
/// One part of a file up from `have` (Calls.kt driveUpload): the station answers with what it has (`have`), the last
/// part in with the entry it now has; a name taken refuses the first part (409), asked in its row.
pub fn dv_up_part(src : Source, u : DvUpload, have : Int, planned : Int) -> Unit {
  if !ups.uploads.iter().any(fn(x) { x.serial == u.serial }) {
    ups.pumping = false
    dv_pump(src)
    return
  }
  let size = u.bytes.length()
  let len = if size - have < planned { size - have } else { planned }
  let part = Bytes::makei(len, fn(i) { u.bytes[have + i] })
  let params : Map[String, Json] = {
    "station": Json::string(u.station),
    "root": Json::string(u.root),
    "path": Json::string(dv_join(u.dir, u.name)),
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
          u.sent = size
          dv_up_done(src, u)
        } else if next <= have {
          u.state = "failed"
          u.error = @sf.t("android-chat.file.uploadFailed")
          ups.pumping = false
          dv_pump(src)
        } else {
          u.sent = next
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
          u.state = "taken"
        } else {
          u.state = "failed"
          u.error = dv_error(e)
        }
        ups.pumping = false
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
/// What a read-only run says it does not do.
pub let read_only_words : String = "只读运行：不发送，不上传，不保存草稿"

///|
pub fn say(c : @ui.Ctx, words : String) -> Unit {
  ignore(c)
  app.toast = words
  app.toast_n += 1
}

///|
pub fn dv_error(e : Json) -> String {
  match text(Some(e), "message") {
    "" => @sf.t("android-misc.failed")
    m => m
  }
}

