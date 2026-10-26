// The core's downloads made up (sfbase/downloads.mbt, client/core-ts views/downloads.ts): one asked comes in a
// twentieth at a time, `fix_download_step_ms` apart, then waits to be taken; taken, it is being saved; done or called
// off, it leaves the list. A drive's file or folder the same (its root and path; a folder zipped first). MBUI_FIXTURE=
// chat-download: the chat with 发布包.zip and a recording from its agent last (scripts/motion/download.drive films one
// asked from the preview, on as the preview closes, on its card); drive-download: a file and a folder of the drive
// downloading (drive_fixture.mbt).

///|
/// A download made up: its file (`station`; a chat's session `key`, or a drive's `root` and `path`, a folder `zip`ped;
/// its name), how big, how much is here, how it stands.
pub(all) struct FixDownload {
  station : String
  key : String
  root : String
  path : String
  zip : Bool
  name : String
  size : Double
  mut loaded : Double
  mut state : String
}

///|
/// A download's id, as the made-up core gives it.
pub fn fix_download_id(d : FixDownload) -> String {
  if d.root == "" {
    d.station + "|" + d.key + "|" + d.name
  } else {
    d.station + "|" + d.root + "|" + d.path
  }
}

///|
/// The fixture's downloads, newest first.
pub let fix_downloads : Array[FixDownload] = []

///|
/// How long each twentieth of a download made up takes.
pub let fix_download_step_ms : Double = 200.0

///|
/// A download as the core lists it (views/downloads.ts shown), its words as the core's (core-logic.download.*).
pub fn fix_download_shown(d : FixDownload) -> Json {
  let percent = if d.size > 0.0 { (d.loaded / d.size * 100.0).floor().to_int() } else { 100 }
  let total = @sf.file_size(d.size)
  let o : Map[String, Json] = {
    "id": Json::string(fix_download_id(d)),
    "station": Json::string(d.station),
    "name": Json::string(d.name),
    "size": Json::number(d.size),
    "loaded": Json::number(d.loaded),
    "progress": Json::number(
      if d.size > 0.0 {
        d.loaded / d.size
      } else if d.state == "going" {
        0.0
      } else {
        1.0
      },
    ),
    "state": Json::string(d.state),
    "active": Json::boolean(d.state != "failed"),
    "statusText": Json::string(
      match d.state {
        "going" if d.zip && d.size == 0.0 => "正在打包"
        "going" => "正在下载 \{percent}% · \{total}"
        "saving" => "正在保存 · \{total}"
        _ => "已下载 · \{total}"
      },
    ),
    "startedAt": 0.0,
  }
  if d.root == "" {
    o["key"] = Json::string(d.key)
  } else {
    o["root"] = Json::string(d.root)
    o["path"] = Json::string(d.path)
    if d.zip {
      o["zip"] = Json::boolean(true)
    }
  }
  Json::object(o)
}

///|
/// The `downloads` topic made up.
pub fn fixture_downloads_topic() -> Json {
  { "downloads": Json::array(fix_downloads.map(fix_download_shown)) }
}

///|
/// `download.start`, `download.retry`, `download.take`, `download.done` and `download.cancel` made up; None for any
/// other call.
pub fn fixture_downloads_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  match name {
    "download.start" => {
      let d : FixDownload = {
        station: text(p, "station"),
        key: text(p, "key"),
        root: text(p, "root"),
        path: text(p, "path"),
        zip: flag(p, "zip"),
        name: text(p, "name"),
        size: number(p, "size"),
        loaded: 0.0,
        state: "going",
      }
      for was in fix_downloads {
        if fix_download_id(was) == fix_download_id(d) {
          return Some(Ok({ "download": fix_download_shown(was) }))
        }
      }
      fix_downloads.insert(0, d)
      for k in 1..=20 {
        fix_later(k.to_double() * fix_download_step_ms, fn() {
          d.loaded = d.size * k.to_double() / 20.0
          if k == 20 {
            d.state = "ready"
          }
        })
      }
      f.changed()
      Some(Ok({ "download": fix_download_shown(d) }))
    }
    "download.take" => {
      let id = text(p, "id")
      let mut taken = false
      for d in fix_downloads {
        if d.state == "ready" && fix_download_id(d) == id {
          d.state = "saving"
          taken = true
        }
      }
      f.changed()
      Some(Ok({ "taken": Json::boolean(taken) }))
    }
    "download.done" | "download.cancel" => {
      let id = text(p, "id")
      fix_downloads.retain(fn(d) { fix_download_id(d) != id })
      f.changed()
      Some(Ok({}))
    }
    "download.retry" => Some(Ok({}))
    _ => None
  }
}

///|
/// `download.read` made up: a part of the download `id`'s file, as the made-up chat's files are (preview_fixture.mbt);
/// false when there is no such download.
pub fn fixture_download_read(params : Json, done : (Result[(Json, Bytes), Json]) -> Unit) -> Bool {
  let p = Some(params)
  for d in fix_downloads {
    if fix_download_id(d) == text(p, "id") && d.root != "" {
      // a drive's, as the made-up drive reads (drive_fixture.mbt)
      let asked : Map[String, Json] = {
        "station": Json::string(d.station),
        "root": Json::string(d.root),
        "path": Json::string(d.path),
        "offset": Json::number(number(p, "offset")),
        "length": Json::number(number(p, "length")),
      }
      match fixture_drive_read("drive.read", Json::object(asked)) {
        Some(r) => done(r)
        None => done(Err({ "code": "not_found", "message": "这份假数据没有 " + d.path }))
      }
      return true
    }
    if fix_download_id(d) == text(p, "id") {
      let asked : Map[String, Json] = {
        "station": Json::string(d.station),
        "key": Json::string(d.key),
        "name": Json::string(d.name),
        "offset": Json::number(number(p, "offset")),
        "length": Json::number(number(p, "length")),
      }
      fixture_fetch("station.file.part", Json::object(asked), done)
      return true
    }
  }
  false
}

///|
/// MBUI_FIXTURE=drive-download: a file of the drive downloading (40% here), a folder of it being zipped for it.
pub fn fix_drive_downloads(station : String, root : String) -> Unit {
  fix_downloads.push({
    station,
    key: "",
    root,
    path: "首页截图.png",
    zip: false,
    name: "首页截图.png",
    size: 1000.0,
    loaded: 400.0,
    state: "going",
  })
  fix_downloads.push({ station, key: "", root, path: "设计稿", zip: true, name: "设计稿.zip", size: 0.0, loaded: 0.0, state: "going" })
}

///|
/// MBUI_FIXTURE=chat-download: the chat with its agent's 发布包.zip and a recording last, to be downloaded.
pub fn with_download_message(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), "打好的发布包在这里，下载下来装一下看看。", "1 分钟前", {
          "ending": "all_done",
          "attachments": [file("发布包.zip", 0, 0, 52428800), film_file("演示录屏.mp4", 1280, 720, 5242880, 12500, 375)],
        }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}
