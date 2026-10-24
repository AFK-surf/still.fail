// The desktop's dock (ember docs/desktop-dock.md, apps/desktop/src/dock.mts): on a Mac, the chats that want the person
// on the screen's right edge, also with no window in front, drawn by the desktop app's SwiftUI helper
// (apps/desktop/dock: its host starts it, @ui.dock_send). This side follows the core for what to show (every
// workspace's chats of the person's and the cards waiting on them), sends it a JSON object a line (items, its words,
// its settings), and does what it asks (open a chat, read it, answer its card; turned off from its menu).

///|
/// Where an item's chat is and what it is at: for opening it, reading it and answering its card.
priv struct DockPlace {
  workspace : String
  station : String
  session : String
  thread : Double?
  seq : Double?
  card : Double?
}

///|
/// What was told the dock (its items, as a line), whether its words and settings were, how often it came back, where
/// each item's chat is, what it said not done yet.
priv struct DockUi {
  mut told : String
  mut set_up : String
  mut running : Bool
  mut restarts : Int
  places : Map[String, DockPlace]
  heard : Array[Json]
}

///|
let dock_ui : DockUi = { told: "", set_up: "", running: false, restarts: 0, places: {}, heard: [] }

///|
fn dock_reset() -> Unit {
  dock_ui.told = ""
  dock_ui.set_up = ""
  dock_ui.running = false
  dock_ui.restarts = 0
  dock_ui.places.clear()
  dock_ui.heard.clear()
}

///|
/// A message as the dock's card shows it: one paragraph, not more than it can hold.
fn dock_line(s : String) -> String {
  let words = s.split(" ").filter(fn(w) { w != "" }).map(fn(w) { w.to_string() }).collect().join(" ")
  let one = words.replace_all(old="\n", new=" ")
  if one.length() > dock_most {
    one.view(end_offset=dock_most).to_string() + "…"
  } else {
    one
  }
}

///|
/// How much of a message the dock is given.
let dock_most : Int = 400

///|
/// A workspace's chats that want the person as the dock shows them (dock.mts dockItems), with where each is and its
/// kind: a card waiting on them (its question and options), then a chat with something unread (red when it failed).
fn dock_items(ws : String, chats : Json?, decisions : Json?) -> Array[(Json, DockPlace, String)] {
  let out : Array[(Json, DockPlace, String)] = []
  let seen : Map[String, Bool] = {}
  for d in items(decisions, "items") {
    let d = Some(d)
    if flag(d, "deferred") {
      continue
    }
    let station = text(d, "station")
    let session = text(d, "session")
    let id = station + "|" + session
    let card = text(field(d, "card"), "type")
    let options = if card == "options" || field(d, "card") is None {
      items(d, "options").map(fn(o) {
        let o = Some(o)
        let m : Map[String, Json] = { "label": Json::string(text(o, "label")) }
        if flag(o, "recommended") {
          m["recommended"] = Json::boolean(true)
        }
        Json::object(m)
      })
    } else {
      []
    }
    let message = field(d, "message")
    let item : Map[String, Json] = {
      "id": Json::string(id),
      "key": Json::string(id + "#card" + number(d, "seq").to_int().to_string()),
      "title": Json::string(text(d, "title")),
      "station": Json::string(text(d, "stationName")),
      "tone": Json::string("wait"),
      "text": Json::string(
        match dock_line(text(message, "text")) {
          "" => dock_line(text(d, "text"))
          t => t
        },
      ),
      "ask": Json::string(
        match text(d, "question") {
          "" => text(d, "title")
          q => q
        },
      ),
      "at": Json::number(number(message, "createdAt")),
    }
    match text(field(message, "by"), "name") {
      "" => ()
      who => item["who"] = Json::string(who)
    }
    if options.length() > 0 {
      item["options"] = Json::array(options)
    }
    seen[id] = true
    out.push((
      Json::object(item),
      { workspace: ws, station, session, thread: Some(number(d, "thread")), seq: None, card: Some(number(d, "seq")) },
      "wait",
    ))
  }
  for day in items(chats, "days") {
    for c in items(Some(day), "items") {
      let c = Some(c)
      let station = text(c, "station")
      let session = match text(c, "session") {
        "" => text(c, "id")
        s => s
      }
      let id = station + "|" + session
      if seen.contains(id) || !flag(c, "unread") {
        continue
      }
      seen[id] = true
      let tone = if text(c, "tone") == "alert" { "alert" } else { "done" }
      let last = field(c, "last")
      let last_seq = field(last, "seq")
      let item : Map[String, Json] = {
        "id": Json::string(id),
        "key": Json::string(
          id +
          "#" +
          (match last_seq {
            Some(Number(n, ..)) => n.to_int().to_string()
            _ => number(c, "lastActiveAt").to_int64().to_string()
          }) +
          tone,
        ),
        "title": Json::string(text(c, "title")),
        "station": Json::string(text(c, "stationName")),
        "tone": Json::string(tone),
        "text": Json::string(
          dock_line(
            match text(last, "text") {
              "" => text(last, "preview")
              t => t
            },
          ),
        ),
        "at": Json::number(
          match field(last, "createdAt") {
            Some(Number(n, ..)) => n
            _ => number(c, "lastActiveAt")
          },
        ),
      }
      match text(field(last, "by"), "name") {
        "" => ()
        who => item["who"] = Json::string(who)
      }
      let kind = if tone == "alert" {
        "failed"
      } else if text(field(last, "by"), "kind") == "" || text(field(last, "by"), "kind") == "person" {
        "message"
      } else {
        "done"
      }
      out.push((
        Json::object(item),
        {
          workspace: ws,
          station,
          session,
          thread: match field(c, "thread") {
            Some(Number(n, ..)) => Some(n)
            _ => None
          },
          seq: match last_seq {
            Some(Number(n, ..)) => Some(n)
            _ => None
          },
          card: None,
        },
        kind,
      ))
    }
  }
  out
}

///|
/// The dock's words, in the app's language (main.ts dockWords).
fn dock_words() -> String {
  let words : Map[String, Json] = {}
  for name in ["open", "read", "later", "empty", "waiting", "hide"] {
    words[name] = Json::string(@sf.t("desktop.dock." + name))
  }
  words["locale"] = Json::string(if @sf.language() == "en" { "en" } else { "zh-Hans" })
  ({ "type": "words", "words": Json::object(words) } : Json).stringify()
}

///|
/// Each frame signed in on a Mac with a dock: while it is on, every workspace's chats that want the person (its
/// kinds), told it as they change, its words and settings as it starts; off, stopped. What it said is done here.
pub fn dock_frame(c : @ui.Ctx, src : Source, all : Array[Workspace]) -> Unit {
  if @ui.platform() != 0 || !@ui.dock_available() {
    return
  }
  // what it said
  if dock_ui.heard.length() > 0 {
    let heard = dock_ui.heard.copy()
    dock_ui.heard.clear()
    c.after_build("dock-heard", fn() {
      for m in heard {
        dock_do(src, m)
      }
    })
  }
  if !@settings.dock_setting("on") {
    if dock_ui.running {
      dock_ui.running = false
      dock_ui.told = ""
      dock_ui.set_up = ""
      c.after_build("dock-stop", fn() { @ui.dock_stop() })
    }
    return
  }
  let kinds = ["wait", "failed", "done", "message"].filter(fn(k) { @settings.dock_setting(k) })
  let shown : Array[Json] = []
  dock_ui.places.clear()
  for w in all {
    let chats = (src.topic)("chats", { "scope": Json::string(w.id), "mine": Json::boolean(true) }).value
    let decisions = (src.topic)("decisions", { "workspace": Json::string(w.id) }).value
    for x in dock_items(w.id, chats, decisions) {
      let (item, place, kind) = x
      if kinds.contains(kind) {
        shown.push(item)
        dock_ui.places[text(Some(item), "id")] = place
      }
    }
  }
  let set_up = dock_words() + "\n" + ({ "type": "settings", "peek": Json::boolean(@settings.dock_setting("peek")) } : Json).stringify()
  let told = ({ "type": "items", "items": Json::array(shown) } : Json).stringify()
  if set_up != dock_ui.set_up || told != dock_ui.told {
    let first = !dock_ui.running
    let setup_changed = set_up != dock_ui.set_up
    dock_ui.running = true
    dock_ui.set_up = set_up
    dock_ui.told = told
    c.after_build("dock-tell", fn() {
      if first || setup_changed {
        for line in set_up.split("\n") {
          @ui.dock_send(line.to_string())
        }
      }
      @ui.dock_send(told)
    })
  }
}

///|
/// What the dock asked (dock.mts heard): open a chat (its workspace in view), read it, answer its card; turned off
/// from its menu; gone by itself, back (a few times).
fn dock_do(src : Source, m : Json) -> Unit {
  let m = Some(m)
  match text(m, "type") {
    "off" => @settings.dock_set("on", false)
    "gone" =>
      // (the next frame starts it again, telling it all, a few times; then the app runs without it until turned on)
      if dock_ui.restarts < dock_restarts {
        dock_ui.restarts += 1
        dock_ui.running = false
        dock_ui.told = ""
        dock_ui.set_up = ""
      } else {
        @settings.dock_set("on", false)
      }
    kind =>
      match dock_ui.places.get(text(m, "id")) {
        None => ()
        Some(p) =>
          match (kind, p.thread, p.seq, p.card) {
            ("open", _, _, _) => open_item(src, p.workspace, p.station, p.session, None, None)
            ("read", Some(thread), Some(seq), _) =>
              (src.call)(
                "chat.read",
                { "station": Json::string(p.station), "thread": Json::number(thread), "seq": Json::number(seq) },
                fn(_) {  },
              )
            ("answer", Some(thread), _, Some(card)) =>
              (src.call)(
                "decision.answer",
                {
                  "station": Json::string(p.station),
                  "thread": Json::number(thread),
                  "seq": Json::number(card),
                  "option": Json::string(text(m, "option")),
                },
                fn(_) {  },
              )
            _ => ()
          }
      }
  }
}

///|
/// How often the dock is started again after it went by itself.
let dock_restarts : Int = 5

///|
fn init {
  @ui.on_message(@hostapi.dock_channel, fn(json, _) {
    let said = @json.parse(json) catch { _ => Json::null() }
    dock_ui.heard.push(said)
  })
}
