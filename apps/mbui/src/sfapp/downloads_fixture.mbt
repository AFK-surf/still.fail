// The core's downloads made up (sfbase/downloads.mbt, client/core-ts views/downloads.ts): one asked comes in a
// twentieth at a time, `fix_download_step_ms` apart, then waits to be taken; taken, it is being saved; done or called
// off, it leaves the list. MBUI_FIXTURE=chat-download: the chat with 发布包.zip and a recording from its agent last
// (scripts/motion/download.drive films one asked from the preview, on as the preview closes, on its card).

///|
/// A download made up: its file (`station`, its session, its name), how big, how much is here, how it stands.
priv struct FixDownload {
  station : String
  key : String
  name : String
  size : Double
  mut loaded : Double
  mut state : String
}

///|
/// The fixture's downloads, newest first.
let fix_downloads : Array[FixDownload] = []

///|
/// How long each twentieth of a download made up takes.
let fix_download_step_ms : Double = 200.0

///|
/// A download as the core lists it (views/downloads.ts shown), its words as the core's (core-logic.download.*).
fn fix_download_shown(d : FixDownload) -> Json {
  let percent = if d.size > 0.0 { (d.loaded / d.size * 100.0).floor().to_int() } else { 100 }
  let total = @sf.file_size(d.size)
  {
    "id": Json::string(d.station + "|" + d.key + "|" + d.name),
    "station": Json::string(d.station),
    "key": Json::string(d.key),
    "name": Json::string(d.name),
    "size": Json::number(d.size),
    "loaded": Json::number(d.loaded),
    "progress": Json::number(if d.size > 0.0 { d.loaded / d.size } else { 1.0 }),
    "state": Json::string(d.state),
    "active": Json::boolean(d.state != "failed"),
    "statusText": Json::string(
      match d.state {
        "going" => "正在下载 \{percent}% · \{total}"
        "saving" => "正在保存 · \{total}"
        _ => "已下载 · \{total}"
      },
    ),
    "startedAt": 0.0,
  }
}

///|
/// The `downloads` topic made up.
fn fixture_downloads_topic() -> Json {
  { "downloads": Json::array(fix_downloads.map(fix_download_shown)) }
}

///|
/// `download.start`, `download.take`, `download.done` and `download.cancel` made up; None for any other call.
fn fixture_downloads_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  match name {
    "download.start" => {
      let (station, key, file) = (text(p, "station"), text(p, "key"), text(p, "name"))
      for d in fix_downloads {
        if d.station == station && d.key == key && d.name == file {
          return Some(Ok({ "download": fix_download_shown(d) }))
        }
      }
      let d : FixDownload = { station, key, name: file, size: number(p, "size"), loaded: 0.0, state: "going" }
      fix_downloads.insert(0, d)
      for k in 1..=20 {
        fix_later(k.to_double() * fix_download_step_ms, fn() {
          d.loaded = d.size * k.to_double() / 20.0
          if k == 20 {
            d.state = "ready"
          }
        })
      }
      f.version += 1
      Some(Ok({ "download": fix_download_shown(d) }))
    }
    "download.take" => {
      let id = text(p, "id")
      let mut taken = false
      for d in fix_downloads {
        if d.state == "ready" && d.station + "|" + d.key + "|" + d.name == id {
          d.state = "saving"
          taken = true
        }
      }
      f.version += 1
      Some(Ok({ "taken": Json::boolean(taken) }))
    }
    "download.done" | "download.cancel" => {
      let id = text(p, "id")
      fix_downloads.retain(fn(d) { d.station + "|" + d.key + "|" + d.name != id })
      f.version += 1
      Some(Ok({}))
    }
    _ => None
  }
}

///|
/// MBUI_FIXTURE=chat-download: the chat with its agent's 发布包.zip and a recording last, to be downloaded.
fn with_download_message(v : Json) -> Json {
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
          "attachments": [file("发布包.zip", 0, 0, 52428800), file("演示录屏.mp4", 1280, 720, 5242880)],
        }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}
