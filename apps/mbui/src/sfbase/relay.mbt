// A chat relayed to a channel, for both frames: the places its station's bots are in, read as the
// picker opens (`chat.relayPlaces`), what the picker shows of them for what is typed and the bot picked (the core's:
// `chat.relayView`, relay-pick.ts), the people there its note can mention once an `@` is typed in it (`chat.relayPeople`,
// then the core's `chat.relayMentions`), and the chat relayed where it was picked (`chat.relay`). The desktop's dialog
// (sfdesk relay.mbt) and the phone's sheet (sfapp relay.mbt) draw it.

///|
/// The picker open (`thread` -1: none), its places as read (0 being read, 1 read, 2 not: `error` says why), the bot
/// picked ("" the chat's own), all the places asked for, the place picked (a row of the view), what the core showed
/// for what was asked last (kept while the next is on its way) and what that was; the people of where it goes (read for
/// `people_of`, the place as `relay_target` says it, "" none yet) and whom the note can mention (as the view): the
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
/// The picker opened for the chat `thread` of `station`: its places asked for.
pub fn relay_open(src : Source, station : String, thread : Double) -> Unit {
  relay_reset()
  relay_opened.val = relay_opened.val + 1
  let opened = relay_opened.val
  relaying.station.set(station)
  relaying.thread.set(thread)
  (src.call)("chat.relayPlaces", { "station": Json::string(station), "thread": Json::number(thread) }, fn(res) {
    if relay_opened.val != opened || relaying.thread.get() != thread || relaying.station.get() != station {
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
/// The menu closed for the `@` it is at (Escape, a press away): not opened again till another.
pub fn relay_mentions_close() -> Unit {
  relaying.mention_closed.set(number(relaying.mentions.get(), "at").to_int())
}

///|
/// The chat relayed to the place picked, or to the thread of the Slack message's link typed (through the bot gone on
/// through), with the note: said where it went when done, why not when not; `done` told once it went (the picker
/// closing on it), what it held left as it was for the picker's way out: put back as it opens next (relay_open).
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
      relaying.busy.set(false)
    }
    done()
  }, failed=fn() { relaying.busy.set(false)})
}

///|
/// Which opening of the picker this is (relay_open's): what the core answers for one before another is let fall.
// kept across runs: counted as it opens, read by what it asked
let relay_opened : Ref[Int] = Ref(0)

///|
/// What the picker is asked for now (relay_view's params, written out; "" while its places are not read).
fn relay_view_asking() -> String {
  if relaying.read.get() != 1 {
    return ""
  }
  relay_view_params().stringify()
}

///|
/// What `chat.relayView` is asked with: the connects read, what is typed, all of them or not, the bot gone on through.
fn relay_view_params() -> Json {
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
  Json::object(params)
}

///|
/// The picker's asks of the core in node `v` (its body's, made once as it opens): what it shows asked as what is typed,
/// the bot or all changes (`chat.relayView`, each once), the people where it goes once an `@` is typed in the note
/// (`chat.relayPeople`, once for each place), whom the note can mention as they or the note change
/// (`chat.relayMentions`), the first of them chosen for another `@` or other words after it; each at the moment what it
/// is asked by changes, what is answered for an ask made before or for an opening before this one let fall.
pub fn relay_asks_node(v : @view.View, src : Source) -> Unit {
  let opened = relay_opened.val
  let now = fn(thread : Double) { relay_opened.val == opened && relaying.thread.get() == thread }
  v.reacts(relay_view_asking, fn(asked) {
    if asked == "" || asked == relaying.asked.get() {
      return
    }
    let thread = relaying.thread.get()
    relaying.asked.set(asked)
    (src.call)("chat.relayView", @signals.untracked(relay_view_params), fn(res) {
      match res {
        Ok(view) if now(thread) && relaying.asked.get() == asked => relaying.view.set(Some(view))
        _ => ()
      }
    })
  })
  v.reacts(relay_people_asking, fn(of) {
    if of == "" || of == relaying.people_of.get() {
      return
    }
    let thread = relaying.thread.get()
    relaying.people_of.set(of)
    relaying.people.set([])
    let target = @json.parse(of) catch { _ => Json::null() }
    (src.call)("chat.relayPeople", target, fn(res) {
      match res {
        Ok(p) if now(thread) && relaying.people_of.get() == of => relaying.people.set(items(Some(p), "people"))
        _ => ()
      }
    })
  })
  v.reacts(relay_mentions_asking, fn(asked) {
    if asked == "" || asked == relaying.mentions_asked.get() {
      return
    }
    let thread = relaying.thread.get()
    relaying.mentions_asked.set(asked)
    let params = Json::object({ "people": Json::array(relaying.people.get()), "note": Json::string(relaying.note.text()) })
    (src.call)("chat.relayMentions", params, fn(res) {
      match res {
        Ok(m) if now(thread) && relaying.mentions_asked.get() == asked => relaying.mentions.set(Some(m))
        _ => ()
      }
    })
  })
  // (another `@`, or other words after it: the first chosen again)
  v.reacts(relay_mention_typed, fn(typed) {
    if typed != "" && relaying.mention_for.get() != typed {
      relaying.mention_for.set(typed)
      relaying.mention_active.set(0)
    }
  })
}

///|
/// What the picker shows now (relay-pick.ts RelayView), what it showed for what was asked before till the core answers;
/// None while its places are not read, or before its first answer.
pub fn relay_view_now() -> Json? {
  if relaying.read.get() != 1 {
    return None
  }
  relaying.view.get()
}

///|
/// Where the note's people are read for now (relay_target written out), "" where the note has no `@` or it goes nowhere
/// yet.
fn relay_people_asking() -> String {
  if !relaying.note.text().contains("@") {
    return ""
  }
  match relay_target(relay_view_now()) {
    Some(p) => Json::object(p).stringify()
    None => ""
  }
}

///|
/// What whom the note can mention is asked with now (the people read and the note, written out), "" till the people of
/// where it goes are asked for.
fn relay_mentions_asking() -> String {
  let of = relay_people_asking()
  if of == "" || relaying.people_of.get() != of {
    return ""
  }
  Json::object({ "people": Json::array(relaying.people.get()), "note": Json::string(relaying.note.text()) }).stringify()
}

///|
/// The core's MentionView for the note as it is, where it is asked for now (None: no `@`, nowhere to go, or no answer).
fn relay_mentions_shown() -> Json? {
  if relay_mentions_asking() == "" {
    return None
  }
  relaying.mentions.get()
}

///|
/// The `@` and the words after it the people shown are for ("" none, or one whose menu was closed).
fn relay_mention_typed() -> String {
  let shown = relay_mentions_shown()
  let at = if shown is Some(_) { number(shown, "at").to_int() } else { -1 }
  if at < 0 || at == relaying.mention_closed.get() {
    return ""
  }
  at.to_string() + "\u{1}" + text(shown, "query")
}

///|
/// Whom the note can mention now (relay_mentions' rows, as it is asked of no frame): none till an `@` is typed in it,
/// nor for an `@` whose menu was closed.
pub fn relay_mentions_now() -> Array[Json] {
  if relay_mention_typed() == "" {
    return []
  }
  items(relay_mentions_shown(), "rows")
}

///|
/// What the people the note can mention are shown for: the words typed after the `@` ("" none).
pub fn relay_mention_query() -> String {
  text(relay_mentions_shown(), "query")
}
