// A chat relayed to a channel (docs/relay.md), for both frames: the places its station's bots are in, read as the
// picker opens (`chat.relayPlaces`), what the picker shows of them for what is typed and the bot picked (the core's:
// `chat.relayView`, relay-pick.ts), the people there its note can mention once an `@` is typed in it (`chat.relayPeople`,
// then the core's `chat.relayMentions`), and the chat relayed where it was picked (`chat.relay`). The desktop's dialog
// (sfdesk relay.mbt, Relay.tsx RelayDialog) and the phone's sheet (sfapp relay.mbt) draw it.

///|
/// The picker open (`thread` -1: none), its places as read (0 being read, 1 read, 2 not: `error` says why), the bot
/// picked ("" the chat's own), all the places asked for, the place picked (a row of the view), what the core showed
/// for what was asked last (kept while the next is on its way) and what that was; the people of where it goes (read for
/// `people_of`, the place as `relay_target` says it, "" none yet) and whom the note can mention (as `relay_view`): the
/// one chosen among them (for the `@` and words it was chosen for) and the `@` whose menu was closed (-1 none).
pub(all) struct Relaying {
  station : @signals.Signal[String]
  thread : @signals.Signal[Double]
  read : @signals.Signal[Int]
  connects : @signals.Signal[Array[Json]]
  error : @signals.Signal[String]
  bot : @signals.Signal[String]
  all : @signals.Signal[Bool]
  picked : @signals.Signal[Json?]
  view : @signals.Signal[Json?]
  asked : @signals.Signal[String]
  busy : @signals.Signal[Bool]
  people : @signals.Signal[Array[Json]]
  people_of : @signals.Signal[String]
  mentions : @signals.Signal[Json?]
  mentions_asked : @signals.Signal[String]
  mention_active : @signals.Signal[Int]
  mention_for : @signals.Signal[String]
  mention_closed : @signals.Signal[Int]
  /// what is typed to find a place (or a Slack message's link), and the note said with the chat where it goes
  query : @ui.Field
  note : @ui.Field
}

///|
pub let relaying : Relaying = {
  station: @signals.signal("", same=fn(a, b) { a == b }),
  thread: @signals.signal(-1.0, same=fn(a, b) { a == b }),
  read: @signals.signal(0, same=fn(a, b) { a == b }),
  connects: @signals.signal([], same=fn(a, b) { a == b }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  bot: @signals.signal("", same=fn(a, b) { a == b }),
  all: @signals.signal(false, same=fn(a, b) { a == b }),
  picked: @signals.signal(None, same=fn(a, b) { a == b }),
  view: @signals.signal(None, same=fn(a, b) { a == b }),
  asked: @signals.signal("", same=fn(a, b) { a == b }),
  busy: @signals.signal(false, same=fn(a, b) { a == b }),
  people: @signals.signal([], same=fn(a, b) { a == b }),
  people_of: @signals.signal("", same=fn(a, b) { a == b }),
  mentions: @signals.signal(None, same=fn(a, b) { a == b }),
  mentions_asked: @signals.signal("", same=fn(a, b) { a == b }),
  mention_active: @signals.signal(0, same=fn(a, b) { a == b }),
  mention_for: @signals.signal("", same=fn(a, b) { a == b }),
  mention_closed: @signals.signal(-1, same=fn(a, b) { a == b }),
  query: @ui.Field::new(),
  note: @ui.Field::new(),
}

///|
/// As before it was ever opened (the app's reset), and as it is closed.
pub fn relay_reset() -> Unit {
  relaying.station.set("")
  relaying.thread.set(-1.0)
  relaying.read.set(0)
  relaying.connects.set([])
  relaying.error.set("")
  relaying.bot.set("")
  relaying.all.set(false)
  relaying.picked.set(None)
  relaying.view.set(None)
  relaying.asked.set("")
  relaying.busy.set(false)
  relaying.people.set([])
  relaying.people_of.set("")
  relaying.mentions.set(None)
  relaying.mentions_asked.set("")
  relaying.mention_active.set(0)
  relaying.mention_for.set("")
  relaying.mention_closed.set(-1)
  relaying.query.set("")
  relaying.note.set("")
}

///|
/// The picker opened for the chat `thread` of `station`: its places asked for (Relay.tsx useRelay's effect).
pub fn relay_open(src : Source, station : String, thread : Double) -> Unit {
  relay_reset()
  relaying.station.set(station)
  relaying.thread.set(thread)
  (src.call)("chat.relayPlaces", { "station": Json::string(station), "thread": Json::number(thread) }, fn(res) {
    if relaying.thread.get() != thread || relaying.station.get() != station {
      return
    }
    match res {
      Ok(v) => {
        relaying.connects.set(items(Some(v), "connects"))
        relaying.read.set(1)
      }
      Err(e) => {
        relaying.error.set(error_words(e))
        relaying.read.set(2)
      }
    }
  })
}

///|
/// What the picker shows now (relay-pick.ts RelayView: `link`, `bot`, `bots`, `rows`, `recent`, `total`, `empty`,
/// `unread`), asked of the core once the frame is built when what is typed, the bot or all changed; what it showed for
/// what was asked before until it answers (None before its first answer).
pub fn relay_view(c : @ui.Ctx, src : Source) -> Json? {
  if relaying.read.get() != 1 {
    return None
  }
  let params : Map[String, Json] = {
    "connects": Json::array(relaying.connects.get()),
    "query": Json::string(relaying.query.text()),
  }
  if relaying.all.get() {
    params["all"] = Json::boolean(true)
  }
  if relaying.bot.get() != "" {
    params["bot"] = Json::string(relaying.bot.get())
  }
  let params = Json::object(params)
  let asked = params.stringify()
  if asked != relaying.asked.get() {
    let thread = relaying.thread.get()
    // (asked once the frame's builds are over: the last build's ask is the one kept)
    c.after_build("relay/chat.relayView", fn() {
      if relaying.asked.get() != asked && relaying.thread.get() == thread {
        relaying.asked.set(asked)
        (src.call)("chat.relayView", params, fn(res) {
          match res {
            Ok(v) if relaying.thread.get() == thread && relaying.asked.get() == asked => relaying.view.set(Some(v))
            _ => ()
          }
        })
      }
    })
  }
  relaying.view.get()
}

///|
/// The connect of id `id` as read (its name, kind, picture).
pub fn relay_connect(id : String) -> Json? {
  relaying.connects.get().iter().find_first(fn(c) { text(Some(c), "id") == id })
}

///|
/// Where the chat goes, as `chat.relay` and `chat.relayPeople` take it: the place picked, or the thread of the Slack
/// message's link typed (through the bot gone on through); None, nowhere yet.
fn relay_target(view : Json?) -> Map[String, Json]? {
  let p : Map[String, Json] = { "station": Json::string(relaying.station.get()), "thread": Json::number(relaying.thread.get()) }
  match (opt_text(view, "link"), relaying.picked.get()) {
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
    (None, None) => return None
  }
  Some(p)
}

///|
/// Whom the note can mention now (relay-pick.ts MentionView `rows`: each person, with the note as it is once they are
/// picked), none till an `@` is typed in it, nor for an `@` whose menu was closed: the people of where it goes read then
/// (once for each place), the core asked once the frame is built when they or the note changed (as `relay_view`).
pub fn relay_mentions(c : @ui.Ctx, src : Source, view : Json?) -> Array[Json] {
  let shown = relay_mentions_asked(c, src, view)
  let at = if shown is Some(_) { number(shown, "at").to_int() } else { -1 }
  if at < 0 || at == relaying.mention_closed.get() {
    return []
  }
  // (another `@`, or other words after it: the first chosen again)
  let typed = at.to_string() + "\u{1}" + text(shown, "query")
  if relaying.mention_for.get() != typed {
    relaying.mention_for.set(typed)
    relaying.mention_active.set(0)
  }
  items(shown, "rows")
}

///|
/// The one chosen among the `n` offered (as the composer's refs_active): moved `by` (round), or put `to` one.
pub fn relay_mention_active(n : Int, by? : Int = 0, to? : Int) -> Int {
  match to {
    Some(i) => relaying.mention_active.set(i)
    None => ()
  }
  if n <= 0 {
    return 0
  }
  relaying.mention_active.set(((relaying.mention_active.get() + by) % n + n) % n)
  relaying.mention_active.get()
}

///|
/// The menu closed for the `@` it is at (Escape, a press away): not opened again till another.
pub fn relay_mentions_close() -> Unit {
  relaying.mention_closed.set(number(relaying.mentions.get(), "at").to_int())
}

///|
/// The core's MentionView for the note as it is (None till an `@` is typed and it has answered).
fn relay_mentions_asked(c : @ui.Ctx, src : Source, view : Json?) -> Json? {
  let note = relaying.note.text()
  let target = match relay_target(view) {
    Some(p) if note.contains("@") => p
    _ => return None
  }
  let thread = relaying.thread.get()
  let of = Json::object(target).stringify()
  if relaying.people_of.get() != of {
    c.after_build("relay/chat.relayPeople", fn() {
      if relaying.people_of.get() != of && relaying.thread.get() == thread {
        relaying.people_of.set(of)
        relaying.people.set([])
        (src.call)("chat.relayPeople", Json::object(target), fn(res) {
          match res {
            Ok(v) if relaying.thread.get() == thread && relaying.people_of.get() == of => relaying.people.set(items(Some(v), "people"))
            _ => ()
          }
        })
      }
    })
    return None
  }
  let params = Json::object({ "people": Json::array(relaying.people.get()), "note": Json::string(note) })
  let asked = params.stringify()
  if asked != relaying.mentions_asked.get() {
    c.after_build("relay/chat.relayMentions", fn() {
      if relaying.mentions_asked.get() != asked && relaying.thread.get() == thread {
        relaying.mentions_asked.set(asked)
        (src.call)("chat.relayMentions", params, fn(res) {
          match res {
            Ok(v) if relaying.thread.get() == thread && relaying.mentions_asked.get() == asked => relaying.mentions.set(Some(v))
            _ => ()
          }
        })
      }
    })
  }
  relaying.mentions.get()
}

///|
/// The chat relayed to the place picked, or to the thread of the Slack message's link typed (through the bot gone on
/// through), with the note: said where it went when done (Relay.tsx go), why not when not; `done` told once it went.
pub fn relay_go(src : Source, view : Json?, done? : () -> Unit = fn() {  }) -> Unit {
  let p = match relay_target(view) {
    Some(p) => p
    None => return
  }
  let note = relaying.note.text()
  if note.trim(chars=" \n\t").to_owned() != "" {
    p["note"] = Json::string(note)
  }
  relaying.busy.set(true)
  let thread = relaying.thread.get()
  act(src, @sf.t("web-main.relay.verb"), "", "chat.relay", Json::object(p), ok=fn(v) {
    toast_later(@sf.t("web-main.relay.done", args=[("place", text(Some(v), "place"))]))
    if relaying.thread.get() == thread {
      relay_reset()
    }
    done()
  }, failed=fn() { relaying.busy.set(false)})
}
