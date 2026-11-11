// The chats' list as both frames read it (the phone's Home, the desktop's sidebar): the core's `chats` view of a
// workspace by its filter, the filter chosen, a row's name and tone, its agents by their mark, the days as last shown
// and held while a finger is on the list; a chat to open once it is listed (MBUI_OPEN_CHAT).

///|
/// The chats of workspace `scope` in list `filter` (all, mine, watching) as the core's view says them, worked out once
/// for each version of it; what went wrong reading it.
pub fn chats_of(src : Source, scope : String, filter : String) -> (ChatsView?, String?) {
  let (read, topic) = chats_read.read(src, chats_shown(src, scope, filter))
  let error = match topic.error {
    Some(e) => Some(text(Some(e), "message"))
    None => None
  }
  (read.map(fn(r) { r.view }), error)
}

///|
/// How many of a list's rows are asked of the core at first (`limit`), and how many more each time it is scrolled near
/// the last of them: the core sends the first ones and how many more it has, not the whole of a list of 1400.
pub let chats_page : Int = 50

///|
// kept across runs: let go of by reset (pages.mbt)
/// How many of each list's rows are asked of the core now, by workspace and filter (chats_page until scrolled).
let chat_limits : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
// kept across runs: let go of by reset (pages.mbt)
/// The limit each list was asked with before a page more, by workspace and filter, while the core has not answered
/// the page more yet.
let chat_limits_was : Map[String, Int] = {}

///|
/// The chats of workspace `scope` in list `filter` as they are asked of the core: as many of them as are asked now.
fn chats_params(scope : String, filter : String) -> Map[String, Json] {
  let params : Map[String, Json] = {
    "scope": Json::string(scope),
    "mine": Json::boolean(filter == "mine"),
  }
  if filter == "watching" {
    params["watching"] = Json::boolean(true)
  }
  if filter == "hidden" {
    params["hidden"] = Json::boolean(true)
  }
  let limit = chat_limits.get(scope + "\u{1}" + filter).unwrap_or(chats_page)
  params["limit"] = Json::number(limit.to_double())
  params
}

///|
/// The list `filter` of workspace `scope` as it is shown: as asked now once the core answered it, till then as it was
/// asked before a page more (its rows staying, not its skeleton for the core's round trip), let go of as it comes.
fn chats_shown(src : Source, scope : String, filter : String) -> Map[String, Json] {
  let key = scope + "\u{1}" + filter
  let now = chats_params(scope, filter)
  guard chat_limits_was.get(key) is Some(was) else { return now }
  let before = now.copy()
  before["limit"] = Json::number(was.to_double())
  let asked = src.topic("chats", now).get()
  if asked.value is None && asked.error is None {
    return before
  }
  chat_limits_was.remove(key)
  (src.leave)("chats", before, TopicLeave::Legacy)
  now
}

///|
/// How many rows list `filter` of workspace `scope` has past those the core sent (its `more`).
pub fn chats_more(src : Source, scope : String, filter : String) -> Int {
  match field(src.topic("chats", chats_params(scope, filter)).get().value, "more") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// A page more of list `filter`'s rows asked for, where `limit` is still how many are asked (asked once for it), the
/// list as it was asked shown till the core answers it (chats_shown).
pub fn chats_ask_more(src : Source, scope : String, filter : String, limit : Int) -> Unit {
  let key = scope + "\u{1}" + filter
  if chat_limits.get(key).unwrap_or(chats_page) == limit {
    // (a page more asked again before the last came: the one shown still the first's)
    if !chat_limits_was.contains(key) {
      chat_limits_was[key] = limit
    } else {
      (src.leave)("chats", chats_params(scope, filter), TopicLeave::Legacy)
    }
    chat_limits[key] = limit + chats_page
  }
}

///|
/// How many of list `filter`'s rows are asked now.
pub fn chats_limit(scope : String, filter : String) -> Int {
  chat_limits.get(scope + "\u{1}" + filter).unwrap_or(chats_page)
}

///|
/// The chats' list of workspace `scope` as it is asked (all of its chats, its first rows: chats_params), for what is
/// read of it beside its rows (its stations' trouble, its glyph).
pub fn chats_topic(src : Source, scope : String) -> Topic {
  src.topic("chats", chats_shown(src, scope, "all")).get().snapshot()
}

///|
/// As at the start: each list asked a page of at first.
pub fn chat_limits_reset() -> Unit {
  chat_limits.clear()
  chat_limits_was.clear()
  chats_read_last.val = []
}

///|
/// The chats' list as chats_read made it, and each row with the JSON it was read from (made_again).
priv struct ChatsRead {
  view : ChatsView
  read : Array[(Json, ChatItem)]
}

///|
/// The chats' list as the core's `chats` topic gives it: its rows read again only as they changed (one chat said
/// something: its row read).
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let chats_read : Derived[ChatsRead] = Derived::new("chats", fn(v, was) {
  let jsons : Array[Json] = []
  for d in items(Some(v), "days") {
    for j in items(Some(d), "items") {
      jsons.push(j)
    }
  }
  let read = made_again(
    jsons,
    match was {
      Some(w) => w.read
      // (a list asked anew, more of its rows: its rows as the list asked before had them, the same JSON where the
      // core's delta kept them, taken as they were made)
      None => chats_read_last.val
    },
    chat_row_key,
    chat_item,
  )
  chats_read_last.val = read
  // (each row's JSON to what was made of it, in the order the days hold them; as its station's state makes it)
  let stations = stations_said(v)
  let at = Ref(0)
  let view = chats_view_by(v, fn(_) {
    let item = read[at.val].1
    at.val += 1
    if stations.is_empty() {
      item
    } else {
      station_on(item, stations.get(item.station))
    }
  })
  { view, read }
})

///|
// kept across runs: let go of by reset (chat_limits_reset)
/// The rows chats_read made last, of whichever list: what a list asked anew is made from.
let chats_read_last : Ref[Array[(Json, ChatItem)]] = Ref([])

///|
/// A row's key in the list, as the core keys them (client/core-ts collections.ts: `station` and `id`).
fn chat_row_key(r : Json) -> String {
  text(Some(r), "station") + "\u{1}" + text(Some(r), "id")
}

///|
/// The list's filter in workspace `ws` (AppState.chatFilter): as chosen here, else as the prefs keep it.
pub fn filter_of(src : Source, ws : String) -> String {
  let f = match app.filters.get(ws) {
    Some(f) => f
    None => {
      let prefs = src.topic("prefs", {}).get().value
      match field(field(prefs, "listFilter"), ws) {
        Some(String(f)) => f
        _ =>
          if flag(prefs, "onlyWatching") {
            "watching"
          } else if flag(prefs, "onlyMine") {
            "mine"
          } else {
            "all"
          }
      }
    }
  }
  if f == "mine" || f == "watching" || f == "hidden" {
    f
  } else {
    "all"
  }
}

///|
/// A chat to open once Home lists it, by words in its title, or `#n` the n-th row (MBUI_OPEN_CHAT, for scripted
/// runs): "" none.
pub let open_titled : Ref[String] = { val: "" }

///|
/// The chat in `view` whose title has `open_titled`'s words: pushed once it is listed; said when the list, all read,
/// has none.
pub fn open_listed(view : ChatsView) -> Unit {
  let words = open_titled.val
  if words == "" {
    return
  }
  let mut rows = 0
  for d in view.days {
    for item in d.items {
      rows = rows + 1
      // #n: the n-th row (from 1)
      let nth = if words.has_prefix("#") {
        let mut k = 0
        for ch in words.view(start_offset=1) {
          let d = ch.to_int() - 48
          if d >= 0 && d <= 9 {
            k = k * 10 + d
          }
        }
        k
      } else {
        0
      }
      if (nth > 0 && rows == nth) || (nth == 0 && item.title.contains(words)) {
        open_titled.val = ""
        @hostapi.log("OPEN found among \{rows}+ rows")
        open_page(
          Chat({
            station: item.station,
            session: item.session,
            title: item.title,
            station_name: item.station_name,
          }),
        )
        return
      }
    }
  }
  let reading = match view.note {
    Some(n) => n.reading
    None => false
  }
  // (said of the rows as the core lists them: the same in each build of the frame)
  if !reading && rows > 0 {
    open_titled.val = ""
    @hostapi.log("OPEN not found among \{rows} rows")
  }
}

///|
/// The days as last shown, by list (held_order).
pub let shown_days : Map[String, Array[ChatDay]] = {}

///|
/// The days, by list, the order last shown was made from (held_order): while they are the same, so is it.
let held_from : Map[String, Array[ChatDay]] = {}

///|
/// Whether `days` (the very array: a view's, read once a version) are not what list `key`'s order shown was last made
/// from: something has come since.
pub fn days_new(key : String, days : Array[ChatDay]) -> Bool {
  match held_from.get(key) {
    Some(f) => !physical_equal(f, days)
    None => true
  }
}

///|
/// `days` as shown: while `hold` (a finger on the list, or it moving) rows keep their
/// places and their days, each with what is new of it, so the row about to be tapped does not move away; ones gone
/// go, new ones come in where they would be in their day (a day not shown yet comes where it would be). Let go, the
/// list is as it is.
pub fn held_order(key : String, days : Array[ChatDay], hold : Bool) -> Array[ChatDay] {
  let shown = shown_days.get(key).unwrap_or([])
  if !hold || shown.is_empty() {
    shown_days[key] = days
    held_from[key] = days
    return days
  }
  // (nothing come since the order shown was made: the very same, not made again each frame the list is held)
  if !days_new(key, days) {
    return shown
  }
  let fresh : Map[String, ChatItem] = {}
  for d in days {
    for item in d.items {
      fresh[row_name(item)] = item
    }
  }
  let held : Map[String, Bool] = {}
  let out : Array[(String, Array[ChatItem])] = shown.map(fn(d) {
    let items : Array[ChatItem] = []
    for item in d.items {
      match fresh.get(row_name(item)) {
        Some(now) => {
          items.push(now)
          held[row_name(item)] = true
        }
        None => ()
      }
    }
    (d.label, items)
  })
  for di, d in days {
    for i, item in d.items {
      if held.contains(row_name(item)) {
        continue
      }
      let into = match out.search_by(fn(o) { o.0 == d.label }) {
        Some(k) => k
        None => {
          // before the first day shown that comes after it now
          let mut at = out.length()
          for k, o in out {
            let later = days.search_by(fn(x) { x.label == o.0 })
            match later {
              Some(j) if j > di => {
                at = k
                break
              }
              _ => ()
            }
          }
          out.insert(at, (d.label, []))
          at
        }
      }
      let items = out[into].1
      items.insert(if i < items.length() { i } else { items.length() }, item)
    }
  }
  let result = out.filter(fn(o) { o.1.length() > 0 }).map(fn(o) { ChatDay::{ label: o.0, items: o.1 } })
  shown_days[key] = result
  held_from[key] = days
  result
}

///|
/// Whether a row shown in list `key` was moved by the viewer since: pinned or let go, or
/// written in by them, here or elsewhere (its last message theirs, one not shown before). It goes where it now is at
/// once, even while the list is held still: the hand on the list keeps rows from moving away under it, not the
/// viewer's own doing from showing (a pointer left resting on the list while they type is no tap to come). Nothing
/// come since the order shown was made, none was.
pub fn viewer_moved(key : String, days : Array[ChatDay]) -> Bool {
  if !days_new(key, days) {
    return false
  }
  let was : Map[String, ChatItem] = {}
  for d in shown_days.get(key).unwrap_or([]) {
    for item in d.items {
      was[row_name(item)] = item
    }
  }
  for d in days {
    for item in d.items {
      match was.get(row_name(item)) {
        Some(w) if (w.pinned == Some(true)) != (item.pinned == Some(true)) => return true
        Some(w) if item.wrote is Some(_) && item.wrote != w.wrote => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// Whether `item`'s row is chat `r`'s: by its agent or its id, and a chat asked for here also by the key it went by
/// before its station made it (`clientKey`), the key the page opened as it was sent keeps.
pub fn row_is(item : ChatItem, r : ChatRef) -> Bool {
  r.station == item.station &&
  (r.session == item.session || r.session == item.id || (item.client_key != "" && r.session == item.client_key))
}

///|
/// A row's name in the list, kept as it changes: its station and chat, a chat asked for here by
/// its `clientKey` before and after its station makes it.
pub fn row_name(item : ChatItem) -> String {
  item.station + "/" + (if item.client_key != "" { item.client_key } else { item.id })
}

///|
/// What leads a row's second line (the core's `stateLead`): done and offered to archive (`settled`), the archive box in
/// the check's place. Its title goes no lighter than the muted grey and still reads, so the mark
/// says it (mbui ui/contrast.mbt).
pub fn row_lead(item : ChatItem) -> String {
  if item.settled && item.state_lead == "done" {
    "archive"
  } else {
    item.state_lead
  }
}

///|
/// What a chat's row says of it: the core's `tone` when it says one, else from its state.
pub fn row_tone(item : ChatItem) -> String {
  match item.tone {
    "alert" | "busy" | "done" | "wait" => item.tone
    _ =>
      match item.state {
        "block" | "failed" => "alert"
        "run" => "busy"
        _ => if item.unread { "done" } else { "" }
      }
  }
}

///|
/// A row's agents by their mark: those that look the same (one maker's models) once (RowPicture agentGroups).
pub fn row_agent_groups(item : ChatItem) -> Array[RowAgent] {
  let groups : Array[RowAgent] = []
  for a in item.agents {
    let key = if a.maker != "" { a.maker } else { a.runtime }
    if !groups.iter().any(fn(g) { (if g.maker != "" { g.maker } else { g.runtime }) == key }) {
      groups.push(a)
    }
  }
  groups
}

///|
/// The stations at a glance, as the core has them in workspace `ws` (asleep while every station is down as the
/// device's network is), and in words: asleep, what the core cannot reach says it; else the stations (the core's),
/// and what is wrong with them.
pub fn stations_at_glance(src : Source, ws : String) -> (@sf.GlyphCounts, String) {
  let chats = chats_topic(src, ws)
  let g = field(chats.value, "glyph")
  let status = src.topic("status", { "workspace": Json::string(ws) }).get().value
  let asleep = flag(g, "asleep")
  let glyph : @sf.GlyphCounts = {
    online: count(g, "online"),
    dim: count(g, "dim"),
    failing: count(g, "failing"),
    working: count(g, "working"),
    connecting: count(g, "connecting"),
    asleep,
  }
  let said = if asleep && text(status, "text") != "" { text(status, "text") } else { text(g, "label") }
  let words = match field(chats.value, "trouble") {
    _ if said == "" => ""
    Some(Object(_)) as trouble => @sf.t("android-chat.home.stations.trouble", args=[("said", said), ("trouble", text(trouble, "text"))])
    _ => @sf.t("android-chat.home.stations", args=[("said", said)])
  }
  (glyph, words)
}

///|
/// A post's own key: its station, chat and place in it.
pub fn seq_key(station : String, thread : Double, seq : Double) -> String {
  station + "\t" + thread.to_int64().to_string() + "\t" + seq.to_int64().to_string()
}

///|
/// How many services are left up long in the workspace (the `longJobs` topic).
pub fn long_jobs(src : Source, w : Workspace) -> Int {
  items(src.topic("longJobs", { "scope": Json::string(w.id) }).get().value, "groups").fold(init=0, fn(n, g) {
    n + items(Some(g), "jobs").length()
  })
}

///|
/// What is left up long in the workspace in view (the `longJobs` topic) held by node `v` from when it is made, asked
/// with the chats' list it shows under (Home's) rather than once that list has come: Home's first page waits for both
/// (held_unanswered).
pub fn long_jobs_read(v : @view.View, src : Source, workspace : () -> Workspace?) -> Unit {
  v.reacts(
    fn() {
      match workspace() {
        Some(w) => src.topic("longJobs", { "scope": Json::string(w.id) }).get().value is Some(_)
        None => false
      }
    },
    fn(_) { () },
  )
}

///|
/// How one left up long (a row of the `longJobs` topic) is stopped: the core's call, its params and what they name
/// (for `core_doing`): a job's `job.stop`, a simulator's or a view's as its `stop` says (`screen.close`,
/// `screen.endView`).
pub fn long_stop(station : String, job : Json?) -> (String, Json, Array[(String, String)]) {
  match field(job, "stop") {
    Some(Object(_)) as stop => {
      let on = [("station", station), ("screen", text(stop, "screen"))]
      if text(stop, "view") != "" {
        on.push(("view", text(stop, "view")))
      }
      let m : Map[String, Json] = {}
      for kv in on {
        m[kv.0] = Json::string(kv.1)
      }
      (text(stop, "call"), Json::object(m), on)
    }
    _ => {
      let id = text(job, "id")
      ("job.stop", { "station": Json::string(station), "id": Json::string(id) }, [("station", station), ("id", id)])
    }
  }
}

///|
/// Whether those left up long light the rail's bell (the `longJobs` topic's `lit`: one it has not shown yet, and the
/// bell lit by them).
pub fn long_jobs_lit(src : Source, w : Workspace) -> Bool {
  flag(src.topic("longJobs", { "scope": Json::string(w.id) }).get().value, "lit")
}

///|
/// The bell has shown those left up long: kept, so they no longer light it (`prefs.set {jobsSeen}` with the
/// `longJobs` topic's `ids`).
pub fn long_jobs_seen(src : Source, w : Workspace) -> Unit {
  let ids = field(src.topic("longJobs", { "scope": Json::string(w.id) }).get().value, "ids").unwrap_or(Json::array([]))
  let m : Map[String, Json] = {}
  m[w.id] = ids
  (src.call)("prefs.set", Json::object({ "jobsSeen": Json::object(m) }), answer_unread)
}
