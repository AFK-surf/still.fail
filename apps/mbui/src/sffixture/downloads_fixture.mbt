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
    "title": Json::string(d.name),
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
/// A file opened and let go, being brought after everything else, or one a person asked to load (`wanted`), made up
/// (client/core-ts fill.ts): its file (a chat's session `key`, or a drive's `root` and `path`), what it is called, how
/// big, how much is here, how it stands (going, yielding, waiting, queued).
pub(all) struct FixKeeping {
  station : String
  key : String
  root : String
  path : String
  name : String
  title : String
  size : Double
  mut loaded : Double
  state : String
  wanted : Bool
}

///|
/// The fixture's files being brought after everything else, the one coming first.
pub let fix_keeping : Array[FixKeeping] = []

///|
/// Whether they are brought (the prefs' `fillOff` not so), and up to how big (`fillMax`: None the core's 1 GB, 0 any).
priv struct FixFill {
  mut off : Bool
  mut max : Double?
}

///|
let fix_fill : FixFill = { off: false, max: None }

///|
/// The made-up bringing as it starts: none, on, up to 1 GB.
pub fn fix_keeping_reset() -> Unit {
  fix_keeping.clear()
  fix_fill.off = false
  fix_fill.max = None
}

///|
/// A file being brought's id, as the made-up core gives it (drive-kept.ts chatKeptId, keptId).
pub fn fix_keeping_id(k : FixKeeping) -> String {
  if k.root == "" {
    "chat\n" + k.station + "\n" + k.key + "\n" + k.name
  } else {
    k.station + "\n" + k.root + "\n" + k.path
  }
}

///|
/// A file being brought as the core lists it (fill.ts shown), its words as the core's (core-logic.keeping.*).
pub fn fix_keeping_shown(k : FixKeeping) -> Json {
  let percent = if k.size > 0.0 { (k.loaded / k.size * 100.0).floor().to_int() } else { 0 }
  let o : Map[String, Json] = {
    "id": Json::string(fix_keeping_id(k)),
    "station": Json::string(k.station),
    "name": Json::string(k.name),
    "title": Json::string(k.title),
    "size": Json::number(k.size),
    "loaded": Json::number(k.loaded),
    "progress": Json::number(if k.size > 0.0 { k.loaded / k.size } else { 0.0 }),
    "state": Json::string(k.state),
    "statusText": Json::string(
      match k.state {
        _ if k.wanted && k.state != "waiting" => "正在加载 \{percent}% · \{@sf.file_size(k.size)}"
        "going" => "后台缓存 \{percent}% · \{@sf.file_size(k.size)}"
        "yielding" => "后台缓存暂停，正在看的优先 · \{percent}%"
        "waiting" => "后台缓存等待连接 station · \{percent}%"
        _ => "后台缓存排队中 · \{percent}%"
      },
    ),
  }
  if k.wanted {
    o["wanted"] = Json::boolean(true)
  }
  // where it was opened (KeptFrom): a chat's in its chat, a drive's where it is
  if k.root == "" {
    o["key"] = Json::string(k.key)
    o["from"] = {
      "thread": 7.0,
      "session": Json::string(k.key),
      "file": { "name": Json::string(k.title), "path": Json::string("work/" + k.key + "/" + k.name), "size": Json::number(k.size) },
    }
  } else {
    o["root"] = Json::string(k.root)
    o["path"] = Json::string(k.path)
    o["from"] = { "root": Json::string(k.root), "path": Json::string(k.path) }
  }
  Json::object(o)
}

///|
/// The `downloads` topic made up.
pub fn fixture_downloads_topic() -> Json {
  let keeping = if fix_fill.off { [] } else { fix_keeping.map(fix_keeping_shown) }
  { "downloads": Json::array(fix_downloads.map(fix_download_shown)), "keeping": Json::array(keeping) }
}

///|
/// The prefs' `fillOff`, `fillMax` as the made-up core keeps them, into the `prefs` topic's `o`.
pub fn fix_fill_prefs_into(o : Map[String, Json]) -> Unit {
  if fix_fill.off {
    o["fillOff"] = Json::boolean(true)
  }
  match fix_fill.max {
    Some(n) => o["fillMax"] = Json::number(n)
    None => ()
  }
}

///|
/// `prefs.set`'s `fillOff`, `fillMax` (null: none) put in.
pub fn fix_fill_prefs_set(params : Json) -> Unit {
  match field(Some(params), "fillOff") {
    Some(True) => fix_fill.off = true
    Some(False) | Some(Null) => fix_fill.off = false
    _ => ()
  }
  match field(Some(params), "fillMax") {
    Some(Number(n, ..)) => fix_fill.max = Some(n)
    Some(Null) => fix_fill.max = None
    _ => ()
  }
}

///|
/// MBUI_FIXTURE=chat-keeping: the chat-download's message, both its files opened and let go, being brought (the
/// package coming, the recording after it).
pub fn fix_keeping_message(station : String, key : String) -> Unit {
  let mb = 1024.0 * 1024.0
  fix_keeping.push({ station, key, root: "", path: "", name: "发布包.zip", title: "发布包.zip", size: 50.0 * mb, loaded: 21.0 * mb, state: "going", wanted: false })
  fix_keeping.push({ station, key, root: "", path: "", name: "演示录屏.mp4", title: "演示录屏.mp4", size: 5.0 * mb, loaded: 1.0 * mb, state: "queued", wanted: false })
}

///|
/// MBUI_FIXTURE=transfers, home-transfers, settings-kept-fill: what comes to this device in every way at once, as the transfers' list shows
/// it: a chat's file downloading, a video and a recording opened and let go being brought (the video coming, the
/// recording after it), a drive's video waiting for its station.
pub fn fix_every_transfer(station : String, key : String, root : String) -> Unit {
  fix_downloads.push({
    station,
    key,
    root: "",
    path: "",
    zip: false,
    name: "发布包.zip",
    size: 48.0 * 1024.0 * 1024.0,
    loaded: 29.0 * 1024.0 * 1024.0,
    state: "going",
  })
  fix_keeping.push({
    station,
    key,
    root: "",
    path: "",
    name: "2026-10-24T21-59-13-dc7ed5-产品演示.mp4",
    title: "产品演示.mp4",
    size: 186.0 * 1024.0 * 1024.0,
    loaded: 84.0 * 1024.0 * 1024.0,
    state: "going",
    wanted: false,
  })
  fix_keeping.push({
    station,
    key,
    root: "",
    path: "",
    name: "周会录音.m4a",
    title: "周会录音.m4a",
    size: 42.0 * 1024.0 * 1024.0,
    loaded: 5.0 * 1024.0 * 1024.0,
    state: "queued",
    wanted: false,
  })
  fix_keeping.push({
    station: "ws1/st2",
    key: "",
    root,
    path: "录屏/上线演练.mov",
    name: "上线演练.mov",
    title: "上线演练.mov",
    size: 320.0 * 1024.0 * 1024.0,
    loaded: 64.0 * 1024.0 * 1024.0,
    state: "waiting",
    wanted: false,
  })
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
    "fill.want" => {
      let k : FixKeeping = {
        station: text(p, "station"),
        key: text(p, "key"),
        root: "",
        path: "",
        name: text(p, "name"),
        title: text(p, "name"),
        size: number(p, "size"),
        loaded: 0.0,
        state: "going",
        wanted: true,
      }
      if fix_keeping.iter().any(fn(was) { fix_keeping_id(was) == fix_keeping_id(k) }) {
        return Some(Ok({}))
      }
      fix_keeping.insert(0, k)
      for i in 1..=20 {
        fix_later(i.to_double() * fix_download_step_ms, fn() {
          k.loaded = k.size * i.to_double() / 20.0
          if i == 20 {
            fix_keeping.retain(fn(x) { fix_keeping_id(x) != fix_keeping_id(k) })
          }
        })
      }
      f.changed()
      Some(Ok({}))
    }
    "fill.stop" => {
      let id = text(p, "id")
      fix_keeping.retain(fn(k) { fix_keeping_id(k) != id })
      f.changed()
      Some(Ok({}))
    }
    "fill.stopAll" => {
      fix_keeping.clear()
      f.changed()
      Some(Ok({}))
    }
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
