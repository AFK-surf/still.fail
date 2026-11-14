// The chats' list as both frames read it (the phone's Home, the desktop's sidebar): the core's `chats` view of a
// workspace by its filter, the filter chosen, a row's name and tone, its agents by their mark, the days as last shown
// and held while a finger is on the list; a chat to open once it is listed (MBUI_OPEN_CHAT).

///|
/// The chats of workspace `scope` in list `filter` (all, mine, watching) as the core's view says them, worked out once
/// for each version of it; what went wrong reading it.
pub fn chats_of(src : Source, scope : String, filter : String) -> (ChatsView?, String?) {
  let (read, topic) = chats_read.read(src, chats_params(scope, filter))
  let error = match topic.error {
    Some(e) => Some(text(Some(e), "message"))
    None => None
  }
  (read.map(fn(r) { r.view }), error)
}

///|
/// List `filter` of workspace `scope` as it is asked of the core (chats_params): what a replay of a run from before the
/// list's rows were what they draw reads a chat's whole row out of (sfreplay's source.mbt).
pub fn chats_asked(scope : String, filter : String) -> Map[String, Json] {
  chats_params(scope, filter)
}

///|
/// The chats of workspace `scope` in list `filter` as they are asked of the core: the list alone. How many of its rows
/// the core sends is no part of it: its window, told the core before it is asked (chats_told_before) and raised as it is
/// scrolled near its foot (chats_grow), so that more of its rows come as the rows added, never the list whole again as
/// another topic (a `limit` of 50 more each time was, 2026-11-11).
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
  params
}

///|
// kept across runs: put back as a run begins (reset), set by the app's tree as it is given its window (sfapp app_tree)
/// How tall the app's window is, in its points (0 before its tree is laid out): what a chat list's first window is
/// worked out of, wherever the list is first asked (place_reads, home_opens, frame_opens, a workspace switched to, its
/// page), its own room not laid out yet there. A list's room is never taller than the window, so the rows the window
/// holds are never fewer than the list shows; the sidebar's header and Home's bar (under 2 rows) go in the rounding.
pub let window_tall : Ref[Double] = Ref(0.0)

///|
/// How many rows of a chat list `tall` points hold, the last in part (the library's row: @sf ChatList `row_h`).
fn rows_held(tall : Double) -> Int {
  (tall / @sf.theme().chat_list.row_h).ceil().to_int()
}

///|
/// `n` rounded up to ten: a window resized a little asks the same.
fn by_tens(n : Int) -> Int {
  (n + 9) / 10 * 10
}

///|
/// A chat list's first window in a window `tall` points high: the rows its room shows and a screen more below them,
/// rounded up to ten (30 on 小屏's 390×844 with a finger's rows, 30 on a wide 1280×800 with a mouse's); 0 before it is
/// laid out (the core sends its untold window then, 50).
pub fn first_window(tall : Double) -> Int {
  if tall <= 0.0 {
    0
  } else {
    by_tens(2 * rows_held(tall))
  }
}

///|
/// The least height a row the core counts in a chat's window has, in points: a station's notice joined to the one before
/// it (38 on 小屏's 390×844 with a finger's rows and on a wide 1280×800 with a mouse's; one alone 54 and 62; a message
/// of a person's or an agent's joined to the one before 55 and 57, with its author's name 71 and 81), measured in the
/// Tester. Rows the core does not count (a day's line, what an agent is at) only add to what is laid out above.
/// chat_window_wbtest.mbt holds it.
pub let chat_row_least : Double = 38.0

///|
/// A chat's first window in a window `tall` points high: as many of its last messages as fill it for sure, at the least
/// height a row it counts has (chat_row_least), rounded up to ten (30 on 小屏's 390×844 and on a wide 1280×800): no
/// more, a screen above what shows kept once the reader moves it off its end (chat_grow_rows). 0 before it is laid out
/// (the core opens on its untold page then, 50 entries). Where the chat opens at something unread or where it was left,
/// the core's window about that wins over the count.
pub fn chat_first_window(tall : Double) -> Int {
  if tall <= 0.0 {
    0
  } else {
    by_tens((tall / chat_row_least).ceil().to_int())
  }
}

///|
/// How many of a chat's messages more its page asks for (`chat.older`'s `rows`) once the reader has moved it off its
/// end and less than a screen of it is laid out above what shows, or while what it lays out does not fill its window,
/// the core having more (chat_list.mbt chat_short_above): at least 760 points at chat_row_least, what a fling at its
/// fastest goes in the frames the core's answer takes, a frame on a Mac (chat_window_wbtest.mbt measures it).
pub let chat_grow_rows : Int = 20

///|
/// How many rows more a chat list scrolled near its foot is told: a screen of them, rounded up to ten, 20 at least.
pub fn window_step(tall : Double) -> Int {
  let n = by_tens(rows_held(tall))
  if n < 20 {
    20
  } else {
    n
  }
}

///|
// kept across runs: let go of by reset (chat_windows_reset), and of a list as it is asked again (chats_told_before)
/// The window each list was last told it grows to while the core has not answered it yet, by its params
/// (list_window_key): told once.
let windows_asked : Map[String, Int] = Map([])

///|
/// How many rows list `filter` of workspace `scope` was last told its window grows to (windows_asked's; 0, none asked
/// since it was asked anew): what tells a page more that comes from rows that arrive (the sidebar's RowsMotion).
pub fn chats_window_asked(scope : String, filter : String) -> Int {
  windows_asked.get(list_window_key(chats_params(scope, filter))).unwrap_or(0)
}

///|
/// A chat list's key among windows_asked: its workspace and filter as asked.
fn list_window_key(p : Map[String, Json]) -> String {
  let on = fn(k : String) { if p.get(k) is Some(True) { "1" } else { "0" } }
  text(Some(Json::object(p)), "scope") + "\u{1}" + on("mine") + on("watching") + on("hidden")
}

///|
/// What the core is told before topic `name` (its JSON as asked, `topic`) is asked (@core.Client::tells_before, as each
/// time it is asked): before a chat list, its first window (`chats.window`, first_window), so that its first answer is
/// made of no more rows than the screen shows and a screen more. Its window grown before is not said: a list asked anew
/// (let go of, a core started again) starts from what it shows; one the core still holds keeps what it showed (the
/// core's window only grows while it holds it). Before a chat, how many of its last messages it opens on (`chat.window`,
/// chat_first_window), grown from there by its page (`chat.older`).
pub fn chats_told_before(name : String, topic : Json) -> Array[(String, Json)] {
  if name == "chat" {
    return chat_told_before(topic)
  }
  guard name == "chats" && topic is Object(t) else { return [] }
  let params : Map[String, Json] = Map([])
  for k in ["scope", "mine", "watching", "hidden"] {
    match t.get(k) {
      Some(v) => params[k] = v
      None => ()
    }
  }
  windows_asked.remove(list_window_key(params))
  let rows = first_window(window_tall.val)
  if rows <= 0 {
    return []
  }
  params["rows"] = Json::number(rows.to_double())
  [("chats.window", Json::object(params))]
}

///|
/// What the core is told before chat `topic` is asked: how many of its last messages it opens on (`chat.window`), by
/// the chat as the topic names it (its station, and its session or thread).
fn chat_told_before(topic : Json) -> Array[(String, Json)] {
  guard topic is Object(t) && t.get("station") is Some(String(_) as station) else { return [] }
  let rows = chat_first_window(window_tall.val)
  if rows <= 0 {
    return []
  }
  let params : Map[String, Json] = { "station": station }
  for k in ["session", "thread"] {
    match t.get(k) {
      Some(v) => params[k] = v
      None => ()
    }
  }
  guard params.length() > 1 else { return [] }
  params["rows"] = Json::number(rows.to_double())
  [("chat.window", Json::object(params))]
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
/// List `filter` of workspace `scope` told a window of `rows` (`chats.window`), where it holds fewer (`has`), the core
/// has more (`more`) and it was not told as many already: what it shows grows by the rows added.
fn chats_window_at_least(src : Source, scope : String, filter : String, rows : Int, has : Int, more : Int) -> Unit {
  let params = chats_params(scope, filter)
  let key = list_window_key(params)
  if more <= 0 || rows <= has || rows <= windows_asked.get(key).unwrap_or(0) {
    return
  }
  windows_asked[key] = rows
  params["rows"] = Json::number(rows.to_double())
  (src.call)("chats.window", Json::object(params), answer_unread)
}

///|
/// How many rows a list's view holds (chats_of's).
pub fn chats_held(view : ChatsView?) -> Int {
  match view {
    Some(v) => v.days.fold(init=0, fn(n, d) { n + d.items.length() })
    None => 0
  }
}

///|
/// List `filter` of workspace `scope`, holding `has` rows with `more` past them, scrolled near its foot: its window a
/// step more (window_step) than the rows it holds, asked once for them.
pub fn chats_grow(src : Source, scope : String, filter : String, has : Int, more : Int) -> Unit {
  chats_window_at_least(src, scope, filter, has + window_step(window_tall.val), has, more)
}

///|
/// List `filter` of workspace `scope`, holding `has` rows with `more` past them, shown in a window `tall` points high:
/// told the first window of that where it holds fewer (a window made taller).
pub fn chats_window_for(src : Source, scope : String, filter : String, tall : Double, has : Int, more : Int) -> Unit {
  chats_window_at_least(src, scope, filter, first_window(tall), has, more)
}

///|
/// The chats' list of workspace `scope` as it is asked (all of its chats: chats_params), for what is read of it beside
/// its rows (its stations' trouble, its glyph).
pub fn chats_topic(src : Source, scope : String) -> Topic {
  src.topic("chats", chats_params(scope, "all")).get().snapshot()
}

///|
/// What workspace `ws`'s chats' list opens on as it is filtered (Home's, the wide frame's sidebar's: chats_of's), asked
/// of `ask` (opens_answered's): answered once the core gave it or said why not.
pub fn list_opens(src : Source, ws : String, ask : (String, Map[String, Json]) -> TopicState) -> Bool {
  opens_answered(ask("chats", chats_params(ws, filter_of(src, ws))))
}

///|
/// What is read of workspace `ws`'s chats beside the rows of a list (chats_topic's: all of its chats, its stations'
/// trouble, its glyph), asked of `ask` as list_opens.
pub fn chats_all_opens(_src : Source, ws : String, ask : (String, Map[String, Json]) -> TopicState) -> Bool {
  opens_answered(ask("chats", chats_params(ws, "all")))
}

///|
/// As at the start: no list told a window to grow to.
pub fn chat_windows_reset() -> Unit {
  windows_asked.clear()
  window_tall.val = 0.0
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
      // (a list asked anew (another of a workspace's lists, a workspace switched to): its rows as the list read before
      // had them, the same JSON where the core's delta kept them, taken as they were made)
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
// kept across runs: let go of by reset (chat_windows_reset)
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
        for ch in words.exact_view(start=1) {
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
pub let shown_days : Map[String, Array[ChatDay]] = Map([])

///|
/// The days, by list, the order last shown was made from (held_order): while they are the same, so is it.
let held_from : Map[String, Array[ChatDay]] = Map([])

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
  let fresh : Map[String, ChatItem] = Map([])
  for d in days {
    for item in d.items {
      fresh[row_name(item)] = item
    }
  }
  let held : Map[String, Bool] = Map([])
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
  let was : Map[String, ChatItem] = Map([])
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
/// What is left up long in workspace `ws` as it is asked (the `longJobs` topic): one ask wherever it is read.
pub fn long_jobs_asked(ws : String) -> Map[String, Json] {
  { "scope": Json::string(ws) }
}

///|
/// How many services are left up long in the workspace (the `longJobs` topic).
pub fn long_jobs(src : Source, w : Workspace) -> Int {
  items(src.topic("longJobs", long_jobs_asked(w.id)).get().value, "groups").fold(init=0, fn(n, g) {
    n + items(Some(g), "jobs").length()
  })
}

///|
/// What is left up long in the workspace in view (the `longJobs` topic) held by node `v` from when it is made, asked
/// with the chats' list it shows under (Home's) rather than once that list has come: Home opens on both (sfapp's
/// home_opens).
pub fn long_jobs_read(v : @view.View, src : Source, workspace : () -> Workspace?) -> Unit {
  v.reacts(
    fn() {
      match workspace() {
        Some(w) => src.topic("longJobs", long_jobs_asked(w.id)).get().value is Some(_)
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
      let m : Map[String, Json] = Map([])
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
  let m : Map[String, Json] = Map([])
  m[w.id] = ids
  (src.call)("prefs.set", Json::object({ "jobsSeen": Json::object(m) }), answer_unread)
}
