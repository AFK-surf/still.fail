// A chat's files downloaded to this device by the core (client/core-ts views/downloads.ts): asked of it from whatever
// page (a preview's 下载), fetched by it whatever becomes of that page (the preview closed, another opened), a part at
// a time; how far each has come said by its `downloads` topic, which every page reads (the preview's bar, the
// message's file). Once all of it is here, the app takes it (`download.take`, once) whatever page shows, reads it as
// the core keeps it on the device (`station.file` with `keep`: not from the station again) and keeps it where the
// system keeps downloads (keep_bytes: 已保存到「下载」, or 下载失败).

///|
/// Whether one was asked of the core in this run (its list is this run's: none asked, none to read), the ready ones
/// being taken and read (by their id), and the files read, to be kept in a frame (keep_bytes asks the host once the
/// frame's builds are over), or how many could not be read since the last frame (下载失败).
priv struct Downloads {
  mut asked : Bool
  taking : Map[String, Bool]
  read : Array[(String, String, Bytes)]
  mut unread : Int
}

///|
let downloads : Downloads = { asked: false, taking: {}, read: [], unread: 0 }

///|
/// None taken, none read (a sign-out, a test's start).
pub fn downloads_reset() -> Unit {
  downloads.asked = false
  downloads.taking.clear()
  downloads.read.clear()
  downloads.unread = 0
}

///|
/// The file a message names (`station`, its session `key`, its `name` at the station, its `size` as the message says)
/// downloaded by the core: one under way or ready is that one, a failed one starts again.
pub fn download_start(src : Source, station : String, key : String, name : String, size : Double) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(key),
    "name": Json::string(name),
    "size": Json::number(size),
  }
  downloads.asked = true
  (src.call)("download.start", Json::object(p), fn(_) {  })
}

///|
/// The core's download of that file while it is listed (under way, ready, or failed): its `progress` (0 to 1),
/// `state` and `statusText`; None when there is none.
pub fn download_of(src : Source, station : String, key : String, name : String) -> Json? {
  if !downloads.asked {
    return None
  }
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
/// Each frame, whatever page shows: a download all here taken (once) and read as the core keeps it, then kept where
/// the system keeps downloads.
pub fn downloads_frame(c : @ui.Ctx, src : Source) -> Unit {
  for got in downloads.read {
    let (name, mime, bytes) = got
    keep_bytes(c, name, mime, bytes)
  }
  downloads.read.clear()
  if downloads.unread > 0 {
    downloads.unread = 0
    say(c, @sf.t("android-chat.file.saveFailed"))
  }
  if !downloads.asked {
    return
  }
  let v = (src.topic)("downloads", {}).value
  let listed = items(v, "downloads")
  // (taken once the frame's builds are over: every build works it out alike from the list)
  c.after_build("downloads-take", fn() { take_ready(src, listed) })
}

///|
/// Each download of `listed` all here taken (once), read as the core keeps it, then to be kept in the next frame.
fn take_ready(src : Source, listed : Array[Json]) -> Unit {
  let ready : Map[String, Bool] = {}
  for d in listed {
    if text(Some(d), "state") == "ready" {
      ready[text(Some(d), "id")] = true
    }
  }
  // one taken is not taken again while the list still has it ready (the core's word that it is gone comes a turn
  // later); once it is out of the list it is forgotten, so the same file downloaded again is taken again
  let gone = []
  for id, _ in downloads.taking {
    if !ready.contains(id) {
      gone.push(id)
    }
  }
  for id in gone {
    downloads.taking.remove(id)
  }
  for d in listed {
    let d = Some(d)
    let id = text(d, "id")
    if text(d, "state") != "ready" || downloads.taking.contains(id) {
      continue
    }
    downloads.taking[id] = true
    let (station, key, name, size) = (text(d, "station"), text(d, "key"), text(d, "name"), number(d, "size"))
    (src.call)("download.take", { "id": Json::string(id) }, fn(r) {
      match r {
        Ok(a) if flag(Some(a), "taken") => {
          let p : Map[String, Json] = {
            "station": Json::string(station),
            "key": Json::string(key),
            "name": Json::string(name),
            "keep": Json::boolean(true),
            "size": Json::number(size),
          }
          (src.read_bytes)("station.file", Json::object(p), fn(file) {
            match file {
              Ok((head, bytes)) => downloads.read.push((name, text(Some(head), "type"), bytes))
              Err(_) => downloads.unread += 1
            }
          })
        }
        // taken by another page: out of the list by the next turn
        Ok(_) => ()
        // (asked again in the next frame)
        Err(_) => downloads.taking.remove(id)
      }
    })
  }
}
