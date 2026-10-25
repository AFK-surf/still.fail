// A chat relayed to a channel (docs/relay.md), for both frames: the places its station's bots are in, read as the
// picker opens (`chat.relayPlaces`), what the picker shows of them for what is typed and the bot picked (the core's:
// `chat.relayView`, relay-pick.ts), and the chat relayed where it was picked (`chat.relay`). The desktop's dialog
// (sfdesk relay.mbt, Relay.tsx RelayDialog) and the phone's sheet (sfapp relay.mbt) draw it.

///|
/// The picker open (`thread` -1: none), its places as read (0 being read, 1 read, 2 not: `error` says why), the bot
/// picked ("" the chat's own), all the places asked for, the place picked (a row of the view), what the core showed
/// for what was asked last (kept while the next is on its way) and what that was.
pub(all) struct Relaying {
  mut station : String
  mut thread : Double
  mut read : Int
  mut connects : Array[Json]
  mut error : String
  mut bot : String
  mut all : Bool
  mut picked : Json?
  mut view : Json?
  mut asked : String
  mut busy : Bool
  /// what is typed to find a place (or a Slack message's link), and the note said with the chat where it goes
  query : @ui.Field
  note : @ui.Field
}

///|
pub let relaying : Relaying = {
  station: "",
  thread: -1.0,
  read: 0,
  connects: [],
  error: "",
  bot: "",
  all: false,
  picked: None,
  view: None,
  asked: "",
  busy: false,
  query: @ui.Field::new(),
  note: @ui.Field::new(),
}

///|
/// As before it was ever opened (the app's reset), and as it is closed.
pub fn relay_reset() -> Unit {
  relaying.station = ""
  relaying.thread = -1.0
  relaying.read = 0
  relaying.connects = []
  relaying.error = ""
  relaying.bot = ""
  relaying.all = false
  relaying.picked = None
  relaying.view = None
  relaying.asked = ""
  relaying.busy = false
  relaying.query.set("")
  relaying.note.set("")
}

///|
/// The picker opened for the chat `thread` of `station`: its places asked for (Relay.tsx useRelay's effect).
pub fn relay_open(src : Source, station : String, thread : Double) -> Unit {
  relay_reset()
  relaying.station = station
  relaying.thread = thread
  (src.call)("chat.relayPlaces", { "station": Json::string(station), "thread": Json::number(thread) }, fn(res) {
    if relaying.thread != thread || relaying.station != station {
      return
    }
    match res {
      Ok(v) => {
        relaying.connects = items(Some(v), "connects")
        relaying.read = 1
      }
      Err(e) => {
        relaying.error = error_words(e)
        relaying.read = 2
      }
    }
  })
}

///|
/// What the picker shows now (relay-pick.ts RelayView: `link`, `bot`, `bots`, `rows`, `recent`, `total`, `empty`,
/// `unread`), asked of the core once the frame is built when what is typed, the bot or all changed; what it showed for
/// what was asked before until it answers (None before its first answer).
pub fn relay_view(c : @ui.Ctx, src : Source) -> Json? {
  if relaying.read != 1 {
    return None
  }
  let params : Map[String, Json] = {
    "connects": Json::array(relaying.connects),
    "query": Json::string(relaying.query.text()),
  }
  if relaying.all {
    params["all"] = Json::boolean(true)
  }
  if relaying.bot != "" {
    params["bot"] = Json::string(relaying.bot)
  }
  let params = Json::object(params)
  let asked = params.stringify()
  if asked != relaying.asked {
    let thread = relaying.thread
    // (asked once the frame's builds are over: the last build's ask is the one kept)
    c.after_build("relay/chat.relayView", fn() {
      if relaying.asked != asked && relaying.thread == thread {
        relaying.asked = asked
        (src.call)("chat.relayView", params, fn(res) {
          match res {
            Ok(v) if relaying.thread == thread && relaying.asked == asked => relaying.view = Some(v)
            _ => ()
          }
        })
      }
    })
  }
  relaying.view
}

///|
/// The connect of id `id` as read (its name, kind, picture).
pub fn relay_connect(id : String) -> Json? {
  relaying.connects.iter().find_first(fn(c) { text(Some(c), "id") == id })
}

///|
/// The chat relayed to the place picked, or to the thread of the Slack message's link typed (through the bot gone on
/// through), with the note: said where it went when done (Relay.tsx go), why not when not; `done` told once it went.
pub fn relay_go(src : Source, view : Json?, done? : () -> Unit = fn() {  }) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(relaying.station), "thread": Json::number(relaying.thread) }
  match (opt_text(view, "link"), relaying.picked) {
    (Some(link), _) => {
      p["link"] = Json::string(link)
      match opt_text(view, "bot") {
        Some(b) => p["connect"] = Json::string(b)
        None => ()
      }
    }
    (None, Some(row)) => {
      p["connect"] = Json::string(text(Some(row), "connect"))
      p["channel"] = Json::string(text(field(Some(row), "place"), "id"))
    }
    (None, None) => return
  }
  let note = relaying.note.text()
  if note.trim(chars=" \n\t").to_owned() != "" {
    p["note"] = Json::string(note)
  }
  relaying.busy = true
  let thread = relaying.thread
  act(src, @sf.t("web-main.relay.verb"), "", "chat.relay", Json::object(p), ok=fn(v) {
    toast_later(@sf.t("web-main.relay.done", args=[("place", text(Some(v), "place"))]))
    if relaying.thread == thread {
      relay_reset()
    }
    done()
  }, failed=fn() { relaying.busy = false })
}
