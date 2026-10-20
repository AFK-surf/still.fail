// Photos over the core's media module (ember docs/media-service.md, the
// second part): `media.timeline` for the days, newest first, more of them
// as the timeline is scrolled down; `media.thumbs` for the grid's pictures,
// asked for together (up to 64 a call) as they come into view;
// `media.thumb` for the viewer's large one.

///|
/// How many days back the timeline reads (it grows as it is scrolled, up
/// to what one read gives: 120).
let photo_days : Ref[Int] = { val: 30 }

///|
/// The timeline's days as last converted, and the version they came from.
let photo_cache : Ref[(Int, Int, Array[@gallery.Day])?] = { val: None }

///|
/// Pictures asked for, by image key; those waiting to be asked, by id.
let thumbs_asked : Map[String, Bool] = {}

///|
let thumbs_queue : Array[String] = []

///|
fn time_of(v : Json?) -> String {
  match v {
    // milliseconds since 1970, shown in the device's day: the core has no
    // time zone here yet, so as UTC+8 (the person's)
    Some(Number(ms, ..)) => {
      let mins = ((ms / 60000.0).floor().to_int64() + 8L * 60L) % (24L * 60L)
      let h = (mins / 60L).to_int()
      let m = (mins % 60L).to_int()
      (if h < 10 { "0" } else { "" }) + "\{h}:" + (if m < 10 { "0" } else { "" }) + "\{m}"
    }
    // ISO: its hours and minutes
    Some(String(s)) if s.length() >= 16 =>
      s.view(start_offset=11, end_offset=16).to_string()
    _ => ""
  }
}

///|
fn photo_days_now() -> Result[Array[@gallery.Day], String]? {
  guard media_station() is Some(station) else { return None }
  add_photo_folder()
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "before": Json::number(photo_days.val.to_double()),
  }
  let s = @core.subscribe("media.timeline", params~)
  // MBUI_CORE_DUMP=1: what the timeline says, as it changes
  if env("MBUI_CORE_DUMP") == "1" {
    dump_one("media.timeline", s)
  }
  match (s.value, s.error) {
    (Some(Object(m)), _) => {
      match photo_cache.val {
        Some((v, n, days)) if v == s.version && n == photo_days.val => return Some(Ok(days))
        _ => ()
      }
      let days = []
      match m.get("days") {
        Some(Array(list)) =>
          for d in list {
            let items = []
            match d {
              Object(dm) =>
                match dm.get("items") {
                  Some(Array(its)) =>
                    for it in its {
                      let im = match it {
                        Object(x) => x
                        _ => continue
                      }
                      let item : @gallery.Item = {
                        id: str(Some(it), "id"),
                        video: str(Some(it), "kind") == "video",
                        time: time_of(im.get("taken")),
                        w: num(Some(it), "w").unwrap_or(0.0),
                        h: num(Some(it), "h").unwrap_or(0.0),
                        thumbhash: str(Some(it), "thumbhash"),
                        duration: num(Some(it), "duration"),
                      }
                      items.push(item)
                    }
                  _ => ()
                }
              _ => ()
            }
            let day : @gallery.Day = { day: str(Some(d), "day"), items }
            days.push(day)
          }
        _ => ()
      }
      photo_cache.val = Some((s.version, photo_days.val, days))
      Some(Ok(days))
    }
    (_, Some(e)) if str(Some(e), "code") == "module_starting" => None
    (_, Some(e)) => {
      let code = str(Some(e), "code")
      let status = num(Some(e), "status").unwrap_or(0.0)
      if code == "forbidden" || status == 403.0 {
        Some(Err("只读成员看不到照片"))
      } else {
        Some(Err("照片读不到：" + str(Some(e), "message")))
      }
    }
    // the days before, while more are read
    _ =>
      match photo_cache.val {
        Some((_, _, days)) => Some(Ok(days))
        None => None
      }
  }
}

///|
fn photo_thumb(it : @gallery.Item) -> String {
  let key = "mem:photo/\{it.id}/grid"
  if !thumbs_asked.contains(key) {
    thumbs_asked[key] = true
    thumbs_queue.push(it.id)
  }
  key
}

///|
/// The pictures asked for this frame, in calls of up to 64.
fn flush_thumbs() -> Unit {
  guard media_station() is Some(station) else { return }
  while thumbs_queue.length() > 0 {
    let n = if thumbs_queue.length() > 64 { 64 } else { thumbs_queue.length() }
    let ids = thumbs_queue[0:n].to_array()
    thumbs_queue.drain(0, n) |> ignore
    let params : Map[String, Json] = {
      "station": Json::string(station),
      "ids": Json::array(ids.map(Json::string(_))),
      "size": Json::string("grid"),
    }
    @core.call_bytes("media.thumbs", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok((Object(m), Some(bytes))) => {
          match m.get("index") {
            Some(Array(index)) =>
              for e in index {
                let off = num(Some(e), "offset").unwrap_or(0.0).to_int()
                let len = num(Some(e), "length").unwrap_or(0.0).to_int()
                if off >= 0 && len > 0 && off + len <= bytes.length() {
                  @ui.add_image(
                    "mem:photo/\{str(Some(e), "id")}/grid",
                    bytes[off:off + len].to_bytes(),
                  )
                }
              }
            _ => ()
          }
        }
        // not had: asked again the next time they show
        _ =>
          for id in ids {
            thumbs_asked.remove("mem:photo/\{id}/grid")
          }
      }
    })
  }
}

///|
fn photo_large(it : @gallery.Item) -> String {
  let key = "mem:photo/\{it.id}/large"
  if !thumbs_asked.contains(key) {
    thumbs_asked[key] = true
    match media_station() {
      Some(station) => {
        let params : Map[String, Json] = {
          "station": Json::string(station),
          "id": Json::string(it.id),
          "size": Json::string("large"),
        }
        @core.call_bytes("media.thumb", params=Json::object(params), on_done=fn(r) {
          match r {
            Ok((_, Some(bytes))) => {
              @ui.add_image(key, bytes)
            }
            _ => thumbs_asked.remove(key)
          }
        })
      }
      None => thumbs_asked.remove(key)
    }
  }
  key
}

///|
fn photo_older() -> Unit {
  // one read gives at most 120 days
  match photo_cache.val {
    Some((_, n, _)) if n == photo_days.val && photo_days.val < 120 =>
      photo_days.val = photo_days.val + 30
    _ => ()
  }
}

///|
let photo_source : @gallery.Source = {
  days: photo_days_now,
  thumb: photo_thumb,
  large: photo_large,
  older: photo_older,
}

///|
/// MBUI_PHOTO_FOLDER="<drive root>|<path>": adds that folder to those the
/// photo library scans (media.photos.folders, then setFolders with it added),
/// once, printing PHOTOS … with the answer.
let folder_done : Ref[Bool] = { val: false }

///|
fn add_photo_folder() -> Unit {
  let spec = env("MBUI_PHOTO_FOLDER")
  if folder_done.val || spec.length() == 0 {
    return
  }
  guard media_station() is Some(station) else { return }
  folder_done.val = true
  let (root, path) = match spec.find("|") {
    Some(i) => (spec.view(end_offset=i).to_owned(), spec.view(start_offset=i + 1).to_owned())
    None => (spec, "")
  }
  let ask : Map[String, Json] = { "station": Json::string(station) }
  @core.call("media.photos.folders", params=Json::object(ask), on_done=fn(r) {
    let folders : Array[Json] = match r {
      Ok(Object(m)) =>
        match m.get("folders") {
          Some(Array(list)) => list
          _ => []
        }
      Ok(Array(list)) => list
      _ => []
    }
    @host.log("PHOTOS folders before " + Json::array(folders).stringify())
    let have = folders.iter().any(fn(f) { str(Some(f), "root") == root && str(Some(f), "path") == path })
    if !have {
      let one : Map[String, Json] = { "root": Json::string(root), "path": Json::string(path) }
      folders.push(Json::object(one))
    }
    let params : Map[String, Json] = {
      "station": Json::string(station),
      "folders": Json::array(folders),
    }
    @core.call("media.photos.setFolders", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok(v) => @host.log("PHOTOS setFolders ok " + v.stringify())
        Err(e) => @host.log("PHOTOS setFolders failed " + e.stringify())
      }
    })
  })
}
