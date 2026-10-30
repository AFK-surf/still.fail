// Files picked on the device that go onto the machine of a screen being driven (ember apps/android
// app/remote/ScreenDrops.kt; docs/remote-screens.md "Clipboard and files"): each up with the drive's upload
// (`drive.upload.part`), its root the folder the screen's state names (`drop`), one after another, under a free name
// beside one already there; once there, where it is, for the viewer to paste its path or show it in the machine's file
// manager. They go on past 只看 and the view opening again; the page's end ends them.

///|
/// The most names tried for one file before it is said to have failed.
let drop_tries : Int = 50

///|
/// A file picked to go onto the machine (Drop): its name there (a free one, once its own was taken), how far it has
/// got.
priv struct ScreenDropItem {
  serial : Int
  folder : String
  reveal : Bool
  bytes : Bytes
  name : @signals.Signal[String]
  /// the names refused for being taken there
  tried : @sf.LiveArray[String]
  sent : @signals.Signal[Int]
  /// `waiting`, `going`, `done` or `failed` (why in `error`)
  state : @signals.Signal[String]
  error : @signals.Signal[String]
  id : @signals.Signal[String]
}

///|
/// Where a file named `name` is in `folder` on the station's machine (its own separator, `\` for a Windows one).
fn drop_path(folder : String, name : String) -> String {
  let sep = if folder.contains("\\") && !folder.contains("/") { "\\" } else { "/" }
  if folder.has_suffix("/") || folder.has_suffix("\\") {
    folder + name
  } else {
    folder + sep + name
  }
}

///|
fn ScreenDropItem::path(self : ScreenDropItem) -> String {
  drop_path(self.folder, self.name.get())
}

///|
/// Files picked (`files`), for `to` (the state's `drop` as it was when they were asked for).
fn ScreenSess::send_files(self : ScreenSess, files : Array[@hostapi.Picked], to : DropTo) -> Unit {
  for f in files {
    self.drops_serial += 1
    self.drops.push({
      serial: self.drops_serial,
      folder: to.folder,
      reveal: to.reveal,
      bytes: f.bytes,
      name: @signals.signal(f.name),
      tried: @sf.LiveArray::from([]),
      sent: @signals.signal(0),
      state: @signals.signal("waiting"),
      error: @signals.signal("", same=fn(a, b) { a == b }),
      id: @signals.signal(""),
    })
  }
  self.pump()
}

///|
/// Let go of: off the list (stopped, if it was going: what the station says of it next is let go).
fn ScreenSess::dismiss(self : ScreenSess, d : ScreenDropItem) -> Unit {
  let going = d.state.get() == "going"
  self.drops.retain(fn(x) { x.serial != d.serial })
  if going {
    self.pumping = false
    self.pump()
  }
}

///|
/// Failed: tried again from the start.
fn ScreenSess::retry(self : ScreenSess, d : ScreenDropItem) -> Unit {
  if d.state.get() != "failed" {
    return
  }
  d.state.set("waiting")
  d.error.set("")
  d.sent.set(0)
  self.pump()
}

///|
/// The next file waiting, up (one at a time).
fn ScreenSess::pump(self : ScreenSess) -> Unit {
  if self.pumping {
    return
  }
  match self.drops.iter().find_first(fn(d) { d.state.get() == "waiting" }) {
    Some(d) => {
      if self.src.read_only {
        d.state.set("failed")
        d.error.set(read_only_words)
        self.pump()
        return
      }
      self.pumping = true
      d.state.set("going")
      d.sent.set(0)
      d.id.set(upload_id(
        "screen\u{1}\{d.folder}\u{1}" + file_seed(self.station, d.name.get(), d.bytes),
        d.serial,
      ))
      self.drop_part(d, 0, dv_part_first)
    }
    None => ()
  }
}

///|
/// Whether `d` is still on the list, going.
fn ScreenSess::still_going(self : ScreenSess, d : ScreenDropItem) -> Bool {
  self.drops.iter().any(fn(x) { x.serial == d.serial }) && d.state.get() == "going"
}

///|
/// One part of a file up from `have` (Calls.kt driveUpload: small first, doubling while parts go through): the
/// station answers with what it has (`have`), the last part in with the entry it now has; a name taken refuses the
/// first part (409 `exists`), and the file goes up again under the next free name.
fn ScreenSess::drop_part(self : ScreenSess, d : ScreenDropItem, have : Int, planned : Int) -> Unit {
  let size = d.bytes.length()
  let len = if size - have < planned { size - have } else { planned }
  let part = Bytes::makei(len, fn(i) { d.bytes[have + i] })
  let params : Map[String, Json] = {
    "station": Json::string(self.station),
    "root": Json::string(d.folder),
    "path": Json::string(d.name.get()),
    "id": Json::string(d.id.get()),
    "offset": Json::number(have.to_double()),
    "total": Json::number(size.to_double()),
  }
  (self.src.call_bytes)("drive.upload.part", Json::object(params), part, fn(r) {
    // let go of meanwhile: what the station says of it is not this list's any more
    if !self.still_going(d) {
      return
    }
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
          d.sent.set(size)
          d.state.set("done")
          self.pumping = false
          self.pump()
        } else if next <= have {
          // nothing more taken: a part the station could not take
          self.drop_failed(d, @sf.t("android-chat.file.uploadFailed"))
        } else {
          d.sent.set(next)
          let more = if next == have + len {
            if planned * 2 > dv_part_max {
              dv_part_max
            } else {
              planned * 2
            }
          } else {
            dv_part_first
          }
          self.drop_part(d, next, more)
        }
      }
      Err(e) => {
        let taken = number(Some(e), "status") == 409.0 || text(Some(e), "code") == "exists"
        if taken && d.tried.length() < drop_tries {
          // a name taken there: the next one beside it, from the first one asked, as the station keeps both (putFree)
          d.tried.push(d.name.get())
          dv_beside_name(self.src, self.station, d.folder, "", d.tried[0], d.tried.copy(), fn(r) {
            if !self.still_going(d) {
              return
            }
            match r {
              Ok(name) => {
                d.name.set(name)
                d.sent.set(0)
                d.id.set(upload_id(
                  "screen\u{1}\{d.folder}\u{1}" + file_seed(self.station, d.name.get(), d.bytes),
                  d.serial,
                ))
                self.drop_part(d, 0, dv_part_first)
              }
              Err(why) => self.drop_failed(d, why)
            }
          })
        } else {
          self.drop_failed(d, error_words(e))
        }
      }
    }
  })
}

///|
fn ScreenSess::drop_failed(self : ScreenSess, d : ScreenDropItem, why : String) -> Unit {
  d.state.set("failed")
  d.error.set(why)
  self.pumping = false
  self.pump()
}

