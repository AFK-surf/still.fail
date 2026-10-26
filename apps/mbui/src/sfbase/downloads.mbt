// Files downloaded to this device by the core (client/core-ts views/downloads.ts): a chat's, a drive's, a folder of it
// zipped, asked of it from whatever page (a preview's 下载, a card's ↻, a drive's row), fetched by it whatever becomes
// of that page and of the app (written down until saved, going on as the app starts again); how far each has come said
// by its `downloads` topic, which every page reads (the preview, the message's file, the drive's row). Once all of one
// is here, the app takes it (`download.take`, once) whatever page shows, reads it a part at a time (`download.read`:
// off the device, not from the station again) into
// the system's downloads (@ui.keep_begin: never whole in memory), and once the host has answered says it is done, with
// where the system put it (`download.done`: read back from there, that is the file's copy on the device).

///|
/// The ready ones being saved (by their id: taken, not taken again while the core's list still says ready), and how
/// many could not be read since the last frame (下载失败).
priv struct Downloads {
  saving : Map[String, Bool]
  mut unread : Int
}

///|
let downloads : Downloads = { saving: {}, unread: 0 }

///|
/// None being saved (a sign-out, a test's start).
pub fn downloads_reset() -> Unit {
  downloads.saving.clear()
  downloads.unread = 0
}

///|
/// The file a message names (`station`, its session `key`, its `name` at the station, its `size` as the message says)
/// downloaded by the core: one under way or ready is that one, a failed one starts again. `keep`: only brought onto
/// this device, as its viewer keeps it (加载: a video played from here at once), not saved.
pub fn download_start(src : Source, station : String, key : String, name : String, size : Double, keep? : Bool = false) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(key),
    "name": Json::string(name),
    "size": Json::number(size),
  }
  if keep {
    p["keep"] = Json::boolean(true)
  }
  (src.call)("download.start", Json::object(p), fn(_) {  })
}

///|
/// A file of a station's drive (`root`, `path`; its `name`, its `size` and `mtime` as its folder lists it, 0 where not
/// known) downloaded by the core: one under way or ready is that one, a failed one starts again.
pub fn download_start_drive(
  src : Source,
  station : String,
  root : String,
  path : String,
  name : String,
  size : Double,
  mtime : Double,
) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
    "name": Json::string(name),
    "size": Json::number(size),
    "mtime": Json::number(mtime),
  }
  (src.call)("download.start", Json::object(p), fn(_) {  })
}

///|
/// A folder of a station's drive downloaded by the core, zipped on the station first (`name`: what the zip is called
/// until the station says).
pub fn download_start_zip(src : Source, station : String, root : String, path : String, name : String) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
    "name": Json::string(name),
    "zip": Json::boolean(true),
  }
  (src.call)("download.start", Json::object(p), fn(_) {  })
}

///|
/// The core's download of a file or folder of a station's drive while it is listed; None when there is none.
pub fn download_of_drive(src : Source, station : String, root : String, path : String) -> Json? {
  let v = (src.topic)("downloads", {}).value
  for d in items(v, "downloads") {
    let d = Some(d)
    if text(d, "station") == station && text(d, "root") == root && text(d, "path") == path && field(d, "root") is Some(_) {
      return d
    }
  }
  None
}

///|
/// The core's download `id`, failed (or waiting for its station), tried again now.
pub fn download_retry(src : Source, id : String) -> Unit {
  (src.call)("download.retry", { "id": Json::string(id) }, fn(_) {  })
}

///|
/// The core's download `id` called off: stopped, what was fetched of it let go.
pub fn download_cancel(src : Source, id : String) -> Unit {
  (src.call)("download.cancel", { "id": Json::string(id) }, fn(_) {  })
}

///|
/// The core's download of that file while it is listed: its `progress` (0 to 1), `state`, `active` (not failed) and
/// `statusText`; None when there is none.
pub fn download_of(src : Source, station : String, key : String, name : String) -> Json? {
  let v = (src.topic)("downloads", {}).value
  for d in items(v, "downloads") {
    let d = Some(d)
    if text(d, "station") == station && text(d, "key") == key && text(d, "name") == name {
      return d
    }
  }
  None
}

///|
/// Each frame, whatever page shows: a download all here taken (once) and saved.
pub fn downloads_frame(c : @ui.Ctx, src : Source) -> Unit {
  if downloads.unread > 0 {
    downloads.unread = 0
    say(c, @sf.t("android-chat.file.saveFailed"))
  }
  let listed = items((src.topic)("downloads", {}).value, "downloads")
  // (taken once the frame's builds are over: every build works it out alike from the list)
  c.after_build("downloads-take", fn() { take_ready(src, listed) })
}

///|
/// Each download of `listed` all here taken (once) and saved.
fn take_ready(src : Source, listed : Array[Json]) -> Unit {
  let ready : Map[String, Bool] = {}
  for d in listed {
    if text(Some(d), "state") == "ready" {
      ready[text(Some(d), "id")] = true
    }
  }
  // one taken is not taken again while the list still has it ready (the core's word that it is being saved comes a
  // turn later); once it is not, it is forgotten here
  let gone = []
  for id, _ in downloads.saving {
    if !ready.contains(id) {
      gone.push(id)
    }
  }
  for id in gone {
    downloads.saving.remove(id)
  }
  for d in listed {
    let d = Some(d)
    let id = text(d, "id")
    if text(d, "state") != "ready" || downloads.saving.contains(id) {
      continue
    }
    downloads.saving[id] = true
    let (name, size) = (text(d, "name"), number(d, "size"))
    (src.call)("download.take", { "id": Json::string(id) }, fn(r) {
      match r {
        Ok(a) if flag(Some(a), "taken") => save_download(src, id, name, size)
        // taken by another page: being saved by it
        Ok(_) => ()
        // (asked again as the list next says it is ready)
        Err(_) => downloads.saving.remove(id)
      }
    })
  }
}

///|
/// A download taken, read off the device a part at a time into the host's keep; done once the host has answered (or
/// when it could not be read: 下载失败).
fn save_download(src : Source, id : String, name : String, size : Double) -> Unit {
  let done = fn(at : String) {
    let p : Map[String, Json] = { "id": Json::string(id) }
    if at != "" {
      p["at"] = Json::string(at)
    }
    (src.call)("download.done", Json::object(p), fn(_) {  })
  }
  let keep : Ref[@ui.Keep?] = { val: None }
  let failed = fn() {
    match keep.val {
      Some(k) => k.end()
      None => ()
    }
    downloads.unread += 1
    done("")
  }
  fn next(at : Double) {
    let p : Map[String, Json] = {
      "id": Json::string(id),
      "offset": Json::number(at),
      "length": Json::number(drive_part.to_double()),
    }
    (src.read_bytes)("download.read", Json::object(p), fn(r) {
      match r {
        Ok((head, bytes)) => {
          let k = match keep.val {
            Some(k) => Some(k)
            None => {
              keep.val = @ui.keep_begin(name, text(Some(head), "type"))
              keep.val
            }
          }
          guard k is Some(k) else {
            failed()
            return
          }
          if bytes.length() > 0 && !k.append(bytes) {
            failed()
            return
          }
          let total = match field(Some(head), "total") {
            Some(Number(n, ..)) => n
            _ => size
          }
          let to = at + bytes.length().to_double()
          if bytes.length() == 0 || to >= total {
            k.finish()
            keepings.push({
              keep: k,
              name,
              saved: @sf.t("android-chat.file.saved"),
              failed: @sf.t("android-chat.file.saveFailed"),
              then: fn(kept) {
                match kept {
                  KeptAt(at) => done(at)
                  _ => done("")
                }
              },
            })
          } else {
            next(to)
          }
        }
        Err(_) => failed()
      }
    })
  }
  next(0.0)
}
