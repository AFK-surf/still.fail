// Home (ember apps/android chat/screens/Home.kt): the workspace's chats as the `chats` view lists them, newest first
// and grouped by day, under a top bar (settings · the workspace, its switcher · the filter). A row (ChatRowBody): the
// chat's state a mark before its title (bold while something in it is unread), its station's mark, under it where it
// stands or the last thing said, who is in it small at the second line's end (RowPicture.kt); the time while it is
// held. Its states: the rows to come breathing while it is read, what is wrong over them, and an empty list's words.

///|
/// Home's list items, in order.
priv enum Item {
  /// room for the top bar over the list
  Top
  Search
  /// what the last update brought, until it is seen (home_news.mbt)
  News
  Wait(Int, ListNote?, String?)
  Empty
  /// the jobs left up a long while (OpenJobs.kt: sheets.mbt open_jobs)
  OpenJobs
  Header(String)
  Row(ChatItem)
  Foot
}

///|
/// The views read, by topic: the version they were read at.
let read_views : Map[String, (Int, ChatsView)] = {}

///|
fn chats_of(src : Source, scope : String, filter : String) -> (ChatsView?, String?) {
  let params : Map[String, Json] = {
    "scope": Json::string(scope),
    "mine": Json::boolean(filter == "mine"),
  }
  if filter == "watching" {
    params["watching"] = Json::boolean(true)
  }
  let topic = (src.topic)("chats", params)
  let error = match topic.error {
    Some(e) => Some(text(Some(e), "message"))
    None => None
  }
  match topic.value {
    Some(v) => {
      let key = scope + "/" + filter
      match read_views.get(key) {
        Some((version, view)) if version == topic.version => (Some(view), error)
        _ => {
          let view = chats_view(v)
          read_views[key] = (topic.version, view)
          (Some(view), error)
        }
      }
    }
    None => (None, error)
  }
}

///|
/// The list's filter in workspace `ws` (AppState.chatFilter): as chosen here, else as the prefs keep it.
fn filter_of(src : Source, ws : String) -> String {
  let f = match app.filters.get(ws) {
    Some(f) => f
    None => {
      let prefs = (src.topic)("prefs", {}).value
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
  if f == "mine" || f == "watching" {
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
fn open_listed(view : ChatsView) -> Unit {
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
        @host.log("OPEN found among \{rows}+ rows")
        app.nav.push(
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
    @host.log("OPEN not found among \{rows} rows")
  }
}

///|
/// The top bar's height (8 + 34 + 8), under which the list starts.
let bar_h : Double = 50.0

///|
fn home_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  ignore(all)
  search_start(c)
  let filter = filter_of(src, w.id)
  let (view, error) = chats_of(src, w.id, filter)
  match view {
    Some(v) => open_listed(v)
    None => ()
  }
  let list : Array[Item] = [Top]
  match view {
    None => {
      // (even while the list is read)
      if news_of(src) is Some(_) {
        list.push(News)
      }
      list.push(Wait(7, None, error))
    }
    Some(v) => {
      let empty = match v.note {
        Some(n) => n.empty
        None => false
      }
      if !empty {
        list.push(Search)
      }
      if news_of(src) is Some(_) {
        list.push(News)
      }
      match v.note {
        Some(n) if n.reading || n.failing.length() > 0 =>
          list.push(Wait(if n.reading { 7 } else { 4 }, Some(n), None))
        _ => ()
      }
      if empty {
        list.push(Empty)
      }
      // what is left up a long while on the stations: nothing while there is none
      if items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups").length() > 0 {
        list.push(OpenJobs)
      }
      // while a finger is on the list or it moves, the rows keep their places (ListMotion.kt HeldOrder)
      let key = "home/" + w.id + "/" + filter
      let (_, _, down) = c.pointer()
      let days = held_order(key, v.days, down || c.list_moving(key))
      for d in days {
        list.push(Header(d.label))
        for item in d.items {
          list.push(Row(item))
        }
      }
    }
  }
  list.push(Foot)
  let lead = match view {
    Some(v) => v.leading
    None => "agents"
  }
  let key = "home/" + w.id + "/" + filter
  // the rows move as the list changes (ListMotion.kt): by their keys
  match view {
    Some(v) => note_marks(c, v)
    None => ()
  }
  let keys = list.map(item_key)
  // only the days and rows count (ListMotion.kt update): the list's first rows, after it waited, come as they are,
  // not growing in (nothing moves the first time)
  let moved = keys.filter(fn(k) { k.has_prefix("h/") || k.has_prefix("r/") })
  let row_keys = moved.map(fn(k) { key + "\u{1}" + k })
  home_rows.val = row_keys
  let lid = @motion.list_keys(c, key, row_keys, liftable=fn(k) { !k.contains("\u{1}h/") })
  // under the search (search.mbt): the list up 56 and away, the bar faded (Home.kt `away`)
  let away = search_away(c)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let li = c.list(key, list.length(), 66.0, fn(i) {
      match list[i] {
        Top => c.box(h=Px(bar_h + 8.0), fn() {  }) |> ignore
        Search => search_field(c)
        News => changelog_news(c, src)
        Wait(n, note, error) => waiting(c, n, note, error)
        Empty =>
          match view {
            Some(v) => empty(c, v, filter)
            None => ()
          }
        OpenJobs => open_jobs(c, src, w)
        Header(label) => moving(c, lid, key, keys[i], section_header(c, label))
        Row(item) =>
          moving(c, lid, key, keys[i], chat_row(c, src, item, lead, lifted=@motion.lifted(c, lid, key + "\u{1}" + keys[i])))
        // room for the bottom bar (Home.kt: LocalBarRoom)
        Foot => c.box(h=Px(bar_room), fn() {  }) |> ignore
      }
    })
    // the list's first time with its rows: at its first row, the search above it out of view, there once scrolled to
    // (Home.kt top: as the list first read, which the search comes in over)
    if !home_placed.contains(key) {
      home_placed[key] = true
      if list.search_by(fn(it) { it is Search }) is Some(at) {
        c.list_scroll_to(key, at + 1, offset=-(bar_h + 8.0))
      }
    }
    if away > 0.0 {
      c.look(li, { ..@ui.still_look, alpha: 1.0 - away, dy: -search_list_rise * away })
    }
    let bar = c.layer(fn() {
      top_bar(c, src, w, view, filter, invited)
    })
    if away > 0.0 {
      c.look(bar, { ..@ui.still_look, alpha: 1.0 - away })
    }
    search_page(c, src, w)
  })
  |> ignore
}

///|
/// The top bar (PlacePage.kt TopGlassBar), over the list's top: settings, the workspace's name (its switcher, a
/// dot when another has something waiting), the filter.
fn top_bar(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  view : ChatsView?,
  filter : String,
  invited : Bool,
) -> Unit {
  let t = @sf.theme()
  // frosted glass over the list (the page's paper at 70% over a 24px blur), a hairline under it
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, pb=8.0, gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="home-settings") {
        app.nav.push(Settings)
      }
      let wid = c.id("home-workspace")
      if c.clicked(wid) {
        raise_sheet(Workspaces)
      }
      c.box(dir=Row, w=Fill(1.0), h=Px(34.0), gap=6.0, align=ACenter, id=wid, fn() {
        // the name as long as there is room for it
        let room = c.width - 16.0 * 2.0 - 34.0 * 2.0 - 10.0 * 2.0 - 6.0 * 2.0 - 16.0 - 10.0
        c.box(max_w=dmax(room, 40.0), fn() {
          c.text(w.name, size=24.0, weight=700, color=t.p.text, wrap=false, line=30.0)
          |> ignore
        })
        |> ignore
        let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
        match field(marks.value, "others") {
          Some(String(tone)) => workspace_mark(c, tone)
          _ =>
            if invited {
              c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.accent, fn() {  })
              |> ignore
            }
        }
        @sf.icon(c, "chevron-down", size=16.0, color=t.p.muted) |> ignore
      })
      |> ignore
      // a newer build that brings something (updates.mbt): its key, or how far it has come
      update_button(c, src)
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station
      match view {
        Some(v) if v.stations > 0 =>
          if nav_button(
              c,
              "filter",
              20.0,
              key="home-filter",
              color=if filter != "all" { t.p.accent } else { t.p.text },
            ) {
            app.menu = true
          }
        _ => ()
      }
    })
    |> ignore
    c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A round button in a bar (Parts.kt NavButton): 34 across, the icon alone, no disc behind it (a ground while
/// pressed). True on the frame after it was pressed.
fn nav_button(
  c : @ui.Ctx,
  icon : String,
  size : Double,
  key~ : String,
  color? : Int64,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    bg=@sf.alpha(t.p.text, 0.08 * @motion.pressing(c, id)),
    id~,
    fn() { @sf.icon(c, icon, size~, color=color.unwrap_or(t.p.text)) |> ignore },
  )
  |> ignore
  c.clicked(id)
}

///|
/// A day's heading (Parts.kt SectionHeader).
fn section_header(c : @ui.Ctx, label : String) -> Int {
  let t = @sf.theme()
  c.box(pl=20.0, pr=20.0, pt=14.0, pb=6.0, fn() {
    c.text(label, size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0)
    |> ignore
  })
}

///|
/// The days as last shown, by list (held_order).
let shown_days : Map[String, Array[ChatDay]] = {}

///|
/// `days` as shown (ListMotion.kt HeldOrder): while `hold` (a finger on the list, or it moving) rows keep their
/// places and their days, each with what is new of it, so the row about to be tapped does not move away; ones gone
/// go, new ones come in where they would be in their day (a day not shown yet comes where it would be). Let go, the
/// list is as it is.
fn held_order(key : String, days : Array[ChatDay], hold : Bool) -> Array[ChatDay] {
  let shown = shown_days.get(key).unwrap_or([])
  if !hold || shown.is_empty() {
    shown_days[key] = days
    return days
  }
  let fresh : Map[String, ChatItem] = {}
  for d in days {
    for item in d.items {
      fresh[item.station + "/" + item.id] = item
    }
  }
  let held : Map[String, Bool] = {}
  let out : Array[(String, Array[ChatItem])] = shown.map(fn(d) {
    let items : Array[ChatItem] = []
    for item in d.items {
      match fresh.get(item.station + "/" + item.id) {
        Some(now) => {
          items.push(now)
          held[item.station + "/" + item.id] = true
        }
        None => ()
      }
    }
    (d.label, items)
  })
  for di, d in days {
    for i, item in d.items {
      if held.contains(item.station + "/" + item.id) {
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
  let result = out.filter(fn(o) { o.1.length() > 0 }).map(fn(o) { { label: o.0, items: o.1 } })
  shown_days[key] = result
  result
}

///|
/// An item's key in the list (ListMotion.kt rowKey, dayKey): a row by its station and chat, a day by its heading.
fn item_key(it : Item) -> String {
  match it {
    Top => "top"
    Search => "search"
    News => "changelog-news"
    Wait(_, _, _) => "wait"
    Empty => "empty"
    OpenJobs => "open-jobs"
    Header(label) => "h/" + label
    Row(item) => "r/" + item.station + "/" + item.id
    Foot => "foot"
  }
}

///|
/// Home's rows and days' headings as last built, by their motion keys (home_rest).
let home_rows : Ref[Array[String]] = Ref([])

///|
/// When Home's rows and headings are in their places and in (the frames' clock: the latest of their moves' and
/// entrances' ends, @motion.layout_rest; -1 when all are at rest): what a test of the app over its pages
/// (src/sfreplay) runs to at its end.
pub fn home_rest() -> Double {
  let mut e = -1.0
  for k in home_rows.val {
    let r = @motion.layout_rest(k)
    if r > e {
      e = r
    }
  }
  e
}

///|
/// How a row or day's heading moves as the list changes (Home.kt Moving, Leaving): from where it was to where it is
/// on the MOVE spring (a little late while closing over one gone), growing in when new (240 ms after 100, Ease.Out,
/// from 90% and nothing), and one gone drawn where it was as it shrinks to 90% and fades (200 ms, CSS's ease-out);
/// one that went ahead of others passes over them.
fn moving(c : @ui.Ctx, lid : Int, list : String, key : String, i : Int) -> Unit {
  @motion.layout(
    c,
    i,
    list + "\u{1}" + key,
    spec=@motion.row_spring,
    enter=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(240.0, ease=Out, delay=100.0)),
    exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=CssOut)),
  )
  if @motion.lifted(c, lid, list + "\u{1}" + key) >= 0.0 {
    c.put_over(i)
  }
}

///|
/// The mark each chat has had (ListMotion.kt MarksSeen), from the whole list: a mark that came while the list shows
/// pops in, its pop set out as it comes (mark_pop_of); one there from the first does not.
let marks_seen : Map[String, String] = {}

///|
fn note_marks(c : @ui.Ctx, v : ChatsView) -> Unit {
  for d in v.days {
    for item in d.items {
      let k = item.station + "/" + item.id
      let tone = row_tone(item)
      match marks_seen.get(k) {
        None => marks_seen[k] = tone
        Some(was) if was != tone => {
          marks_seen[k] = tone
          let p = mark_pop_of(c, k, tone)
          p.snap(0.0)
          p.animate(1.0, @motion.tween(mark_pop_ms, ease=CssOut))
        }
        _ => ()
      }
    }
  }
}

///|
// kept across runs: a table, never written
let titles : Array[Double] = [150.0, 110.0, 170.0, 130.0, 96.0, 160.0, 120.0]

///|
// kept across runs: a table, never written
let lines : Array[Double] = [230.0, 190.0, 250.0, 170.0, 210.0, 200.0, 180.0]

///|
/// The list read the first time (Waiting.kt Waiting, WaitShapes Rows): rows to come breathing, what is wrong over
/// them in red (the shapes then still).
fn waiting(c : @ui.Ctx, n : Int, note : ListNote?, error : String?) -> Unit {
  let t = @sf.theme()
  let failing : Array[String] = []
  match error {
    Some(e) => failing.push(e)
    None => ()
  }
  match note {
    Some(nt) => failing.append(nt.failing)
    None => ()
  }
  let reading = error is None &&
    (match note {
      Some(nt) => nt.reading
      None => true
    })
  c.box(w=Fill(1.0), fn() {
    if failing.length() > 0 {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=14.0, pb=4.0, gap=8.0, align=ACenter, fn() {
        for f in failing {
          c.box(padx=12.0, pady=6.0, radius=15.0, bg=t.p.chip, fn() {
            c.text(f, size=13.0, color=t.p.red, line=18.0, center=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    let breath = if reading { @sf.breath(c) } else { 0.6 }
    c.box(w=Fill(1.0), opacity=breath, fn() {
      for i in 0..<n {
        c.box(dir=Row, w=Fill(1.0), h=Px(66.0), pl=22.0, pr=16.0, gap=12.0, align=ACenter, fn() {
          c.box(w=Fill(1.0), gap=10.0, fn() {
            @sf.bar(c, Px(titles[i % titles.length()]), 13.0)
            @sf.bar(c, Px(lines[i % lines.length()]), 10.0)
          })
          |> ignore
          @sf.bar(c, Px(22.0), 22.0)
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Nothing in the list (Home.kt Empty): with no station yet, adding the first one is the page; else the
/// illustration and what to do.
fn empty(c : @ui.Ctx, v : ChatsView, filter : String) -> Unit {
  let t = @sf.theme()
  if v.stations == 0 && filter == "all" {
    c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_no_station_dark"
        } else {
          "illus_no_station"
        },
        240.0,
      )
      |> ignore
      c.text(
        tr("android-settings.station.first"),
        size=17.0,
        weight=600,
        color=t.p.text,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(
        tr("android-settings.station.firstNote"),
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
    })
    |> ignore
    return
  }
  c.box(w=Fill(1.0), padx=30.0, pady=20.0, gap=8.0, align=ACenter, fn() {
    @sf.drawable(
      c,
      if t.dark {
        "illus_new_chat_dark"
      } else {
        "illus_new_chat"
      },
      240.0,
    )
    |> ignore
    if filter == "mine" {
      c.text(tr("android-chat.home.empty.mine"), size=14.0, color=t.p.muted) |> ignore
    } else if filter == "watching" {
      c.text(tr("android-chat.home.empty.watching"), size=14.0, color=t.p.muted)
      |> ignore
    } else {
      c.text(
        if v.stations > 1 {
          tr("android-chat.home.empty.many")
        } else {
          tr("android-chat.home.empty.one")
        },
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(tr("android-chat.newChat"), size=14.0, color=t.p.accent) |> ignore
    }
  })
  |> ignore
}

///|
/// The marks' colours (SettingParts.kt MarkBlue, MarkRed; Home.kt MarkYellow).
let mark_blue : Int64 = 0x3B82F6FFL

///|
let mark_red : Int64 = 0xE5484DFFL

///|
let mark_yellow : Int64 = 0xF2B01EFFL

///|
/// What a workspace has waiting (SettingParts.kt WorkspaceMark): `alert` a red dot with a soft halo, `wait` a blue
/// ring, `done` a blue dot.
fn workspace_mark(c : @ui.Ctx, tone : String) -> Unit {
  c.box(w=Px(10.0), h=Px(10.0), fn() {
    match tone {
      "alert" => halo_dot(c, mark_red)
      "wait" => ring(c, mark_blue)
      _ => dot(c, mark_blue)
    }
  })
  |> ignore
}

///|
/// A dot 8 across in the middle of a mark's 10.
fn dot(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=color, tx=1.0, ty=1.0, fn() {  })
  |> ignore
}

///|
/// A red dot with its halo (the halo 14 across, past the mark's edges).
fn halo_dot(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(
    w=Px(14.0),
    h=Px(14.0),
    radius=7.0,
    bg=@sf.alpha(color, 0.25),
    tx=-2.0,
    ty=-2.0,
    align=ACenter,
    justify=JCenter,
    fn() { c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=color, fn() {  }) |> ignore },
  )
  |> ignore
}

///|
/// A hollow ring 9 across, 2 thick.
fn ring(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(
    w=Px(9.0),
    h=Px(9.0),
    radius=4.5,
    border=2.0,
    border_color=color,
    tx=0.5,
    ty=0.5,
    fn() {  },
  )
  |> ignore
}

///|
/// What a chat's row says of it (Home.kt rowTone): the core's `tone` when it says one, else from its state.
fn row_tone(item : ChatItem) -> String {
  match item.tone {
    "alert" | "busy" | "done" | "wait" | "other" => item.tone
    _ =>
      match item.state {
        "block" | "failed" => "alert"
        "run" => "busy"
        _ => if item.unread { "done" } else { "" }
      }
  }
}

///|
/// A chat's state, a mark before its title (Home.kt ChatMark): a blue dot done and unread, a red one with a soft
/// halo to be seen now, a turning yellow ring with a gap at work, a blue ring when something waits on the viewer, a
/// grey one when only on others.
fn chat_mark(c : @ui.Ctx, tone : String, pop? : String = "") -> Unit {
  let t = @sf.theme()
  let mark = c.box(w=Px(10.0), h=Px(10.0), fn() {
    match tone {
      "done" => dot(c, mark_blue)
      "alert" => halo_dot(c, mark_red)
      "wait" => ring(c, mark_blue)
      "other" => ring(c, t.p.subtle)
      _ =>
        @sf.spinner(
          c,
          size=10.0,
          ring=@sf.alpha(mark_yellow, 0.25),
          arc=mark_yellow,
          sweep=0.75,
          period=1200.0,
        )
        |> ignore
    }
  })
  // one that came while the list shows pops in (Home.kt ChatMark: 320 ms, CSS's ease-out, 0 → 1.3 at 60% → 1)
  if pop != "" {
    let v = mark_pop_of(c, pop, tone).get()
    if v < 1.0 {
      let s = if v < 0.6 { 1.3 * v / 0.6 } else { 1.3 - 0.3 * (v - 0.6) / 0.4 }
      c.look(mark, @ui.look(scale=s))
    }
  }
}

///|
/// The pop's length.
let mark_pop_ms : Double = 320.0

///|
/// A chat's pop of its mark `tone` (whole, 1, unless one set out as the mark came: note_marks).
fn mark_pop_of(c : @ui.Ctx, chat : String, tone : String) -> @motion.Anim {
  @motion.anim(c, "mark-pop/" + chat + "/" + tone, 1.0, global=true)
}

///|
/// How long a row is held before its time shows (a long press).
let hold_ms : Double = 450.0

///|
/// A row (Home.kt ChatRow, ChatRowBody): 66 high, two lines; tapped, its chat is pushed.
fn chat_row(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  lead : String,
  lifted? : Double = -1.0,
  found? : Bool = false,
) -> Int {
  let t = @sf.theme()
  let id = c.id("row/" + item.station + "/" + item.id)
  // a chat the search found (Search.kt: ChatRowBody alone, a tap its chat): not held, archived nor swiped
  let pressed = c.pressed(id) && !found
  if pressed && app.held != id {
    app.held = id
    app.held_long = false
  }
  // held hold_ms (a frame asked for when it will have been)
  let held = @kit.after(c, "row-hold/" + item.station + "/" + item.id, pressed && app.held == id, hold_ms)
  if held {
    app.held_long = true
    // held long: what can be done to the chat (home_menu.mbt)
    row_held(c, id, item)
  }
  if c.clicked(id) {
    // a long press is not a tap
    let long = app.held == id && app.held_long
    app.held = 0
    if !long {
      app.nav.push(
        Chat({
          station: item.station,
          session: item.session,
          title: item.title,
          station_name: item.station_name,
        }),
      )
    }
  } else if !pressed && app.held == id {
    app.held = 0
  }
  let dim = if item.offline is Some(_) { 0.45 } else { 1.0 }
  let archivable = item.archivable && item.offline is None && !item.pending && !found
  let busy = row_busy(item)
  let failed = row_failed(c, item)
  let row = fn(tx : Double) -> Int {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(66.0),
      tx~,
      pl=22.0,
      pr=16.0,
      gap=6.0,
      align=ACenter,
      bg=if held || row_menu_open(item) {
        @sf.alpha(t.p.text, 0.05)
      } else if lifted >= 0.0 {
        // going ahead of others, on a ground of its own over them: held to 60% of its 480 ms, then fading
        let p = lifted / 480.0
        @sf.alpha(@sf.over(t.p.bg, @sf.alpha(t.p.text, 0.06)), if p < 0.6 { 1.0 } else { 1.0 - (p - 0.6) / 0.4 })
      } else if tx != 0.0 {
        // swiped, over its 归档 (home_menu.mbt swipe_to_archive)
        t.p.bg
      } else {
        0L
      },
      id~,
      fn() {
        if archivable {
          archive_chip(c, src, item, busy)
        }
        c.box(w=Fill(1.0), justify=JCenter, opacity=if item.settled { 0.45 } else { 1.0 }, fn() {
          c.box(dir=Row, w=Fill(1.0), h=Px(22.0), gap=8.0, align=ACenter, fn() {
            let tone = row_tone(item)
            if tone != "" {
              chat_mark(c, tone, pop=item.station + "/" + item.id)
            }
            c.box(w=Fill(1.0), opacity=dim, fn() {
              c.text(
                item.title,
                size=16.0,
                weight=if item.unread { 600 } else { 400 },
                color=t.p.text,
                wrap=false,
                line=22.0,
              )
              |> ignore
            })
            |> ignore
            if @sf.has_station_mark(item.station_emoji, item.station_icon) {
              c.box(opacity=dim, fn() {
                @sf.station_mark(c, item.station_emoji, item.station_icon, 12.0, t.p.muted)
              })
              |> ignore
            }
            if busy || failed {
              // its pin or archive under way: a spinner; failed a moment ago: a red mark (DoingMark)
              c.box(w=Px(14.0), align=ACenter, fn() {
                if busy {
                  @sf.spinner(c, size=12.0) |> ignore
                } else {
                  @sf.icon(c, "info", size=12.0, color=t.p.red) |> ignore
                }
              })
              |> ignore
            } else if item.offline is Some(_) || item.reconnecting is Some(_) {
              c.box(w=Px(14.0), align=ACenter, fn() {
                @sf.icon(c, "unplug", size=13.0, color=t.p.subtle) |> ignore
              })
              |> ignore
            } else if item.connect {
              c.box(w=Px(14.0), align=ACenter, fn() { @sf.slack_mark(c, 13.0) |> ignore })
              |> ignore
            }
          })
          |> ignore
          c.box(dir=Row, w=Fill(1.0), h=Px(20.0), gap=8.0, align=ACenter, fn() {
            c.box(w=Fill(1.0), opacity=dim, fn() {
              let state = match item.state_text {
                Some(s) => Some(s)
                None => item.decision_text
              }
              match state {
                Some(s) => state_line(c, s)
                None =>
                  match item.last {
                    Some(l) =>
                      c.text(l, size=14.0, color=t.p.muted, wrap=false, line=20.0)
                      |> ignore
                    None => ()
                  }
              }
            })
            |> ignore
            if held {
              c.text(item.ago, size=12.0, color=t.p.subtle, wrap=false) |> ignore
            } else {
              c.box(opacity=dim, fn() { row_aside(c, src, item, lead) }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      },
    )
  }
  if archivable {
    swipe_to_archive(c, src, item, busy, row)
  } else {
    row(0.0)
  }
}

///|
/// A small 归档 at a row's start, for a chat with nothing left in it: a tap archives it (home_menu.mbt archive_from_row), not
/// while its pin or archive is under way.
fn archive_chip(c : @ui.Ctx, src : Source, item : ChatItem, busy : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("archive/" + item.station + "/" + item.id)
  if c.clicked(id) && !busy {
    archive_from_row(src, item)
  }
  c.box(
    padx=10.0,
    pady=4.0,
    radius=12.0,
    bg=if c.pressed(id) { @sf.mix(t.p.chip, 0.9, t.p.text) } else { t.p.chip },
    id~,
    fn() {
      c.text(
        tr("android-chat.archive"),
        size=12.0,
        weight=500,
        color=t.p.muted,
        wrap=false,
        line=16.0,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// The length of `word` and what follows it at the start of `s` when `s` starts so: one of `after` next, or
/// nothing at all when `end` lets it end there.
fn lead_of(s : String, words : Array[String], after : Array[String], end : Bool) -> Int? {
  for w in words {
    if s.has_prefix(w) {
      let n = w.length()
      if n == s.length() {
        if end {
          return Some(n)
        }
        continue
      }
      let rest = s.view(start_offset=n).to_owned()
      for a in after {
        if rest.has_prefix(a) {
          let mut k = n + a.length()
          // what the core's ：or : leaves after it
          while k < s.length() && s.at(k).to_int() == 32 {
            k += 1
          }
          return Some(k)
        }
      }
    }
  }
  None
}

///|
/// Where the chat stands, in its last message's place (Home.kt StateLine): a lead said as an icon (要你帮忙 a bell,
/// in ink; 在等 the wait mark, 监控中 the watch before its words, 做完了 a check) where the title's mark is; 奏 · …
/// (a card waiting for the viewer) in ink with its 奏 bold; anything else in the secondary colour.
fn state_line(c : @ui.Ctx, state : String, size? : Double = 14.0, line? : Double = 20.0) -> Unit {
  let t = @sf.theme()
  let need = lead_of(state, ["要你帮忙", "需要你处理", "Needs you"], ["：", ":"], true)
  let done = if need is None {
    match lead_of(state, ["做完了", "已完成"], ["："], true) {
      Some(n) => Some(n)
      None => lead_of(state, ["Done"], [": "], true)
    }
  } else {
    None
  }
  let wait = if need is None && done is None {
    match lead_of(state, ["在等", "等待"], ["："], false) {
      Some(n) => Some(n)
      None =>
        if state == "等待中" {
          Some(state.length())
        } else {
          lead_of(state, ["Waiting"], [": "], true)
        }
    }
  } else {
    None
  }
  let watch = if need is None && done is None && wait is None {
    lead_of(state, ["监控中", "Watching"], ["：", ": "], true)
  } else {
    None
  }
  let (icon, n) = match (need, done, wait, watch) {
    (Some(n), _, _, _) => ("bell", n)
    (_, Some(n), _, _) => ("check", n)
    (_, _, Some(n), _) => ("wait", n)
    // watching keeps its words after its radar
    (_, _, _, Some(_)) => ("watch", 0)
    _ => ("", 0)
  }
  if icon != "" {
    let rest = state.view(start_offset=n).to_owned()
    let tint = if need is Some(_) { t.p.text } else { t.p.muted }
    c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
      // the title's mark's place (10), the icon 14 centred on it
      c.box(w=Px(10.0), h=Px(14.0), fn() {
        c.box(tx=-2.0, fn() { @sf.icon(c, icon, size=14.0, color=tint) |> ignore })
        |> ignore
      })
      |> ignore
      if rest != "" {
        c.box(w=Fill(1.0), fn() {
          c.text(rest, size~, color=tint, wrap=false, line~) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    return
  }
  // the core's lead in either language: 奏 · …, Decision · …
  let lead = if state == "奏" || state.has_prefix("奏 · ") {
    "奏"
  } else if state == "Decision" || state.has_prefix("Decision · ") {
    "Decision"
  } else {
    ""
  }
  if lead != "" {
    c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
      c.text(lead, size~, weight=700, color=t.p.text, wrap=false, line~)
      |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(
          state.view(start_offset=lead.length()).to_owned(),
          size~,
          color=t.p.text,
          wrap=false,
          line~,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    return
  }
  c.text(state, size~, color=t.p.muted, wrap=false, line~) |> ignore
}

///|
/// Who is in a chat, small at its second line's end (RowPicture.kt RowAside): its agents (a mark per maker) and its
/// people, those that lead first; the people only when they lead or someone other than the viewer is in it.
fn row_aside(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, face_size? : Double = 18.0) -> Unit {
  let t = @sf.theme()
  // those that look the same (one maker's models) drawn once
  let groups : Array[RowAgent] = []
  for a in item.agents {
    let key = if a.maker != "" { a.maker } else { a.runtime }
    if !groups.iter().any(fn(g) { (if g.maker != "" { g.maker } else { g.runtime }) == key }) {
      groups.push(a)
    }
  }
  let people = item.people
  let with_people = people.length() > 0 &&
    (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  let agents = fn() {
    c.box(dir=Row, gap=4.0, align=ACenter, fn() {
      for k, g in groups {
        if k < 3 {
          @sf.maker_mark(c, g.maker, g.runtime, 14.0) |> ignore
        }
      }
      if groups.length() > 3 {
        c.text("+\{groups.length() - 3}", size=12.0, color=t.p.muted, wrap=false)
        |> ignore
      }
    })
    |> ignore
  }
  let faces = fn() {
    let shown = if people.length() > 3 { people[:3].to_array() } else { people }
    c.box(dir=Row, align=ACenter, fn() {
      for i, p in shown {
        let starter = people.length() > 1 && p.id == item.creator
        face(c, src, p, face_size, starter, -3.0 * i.to_double())
      }
      if people.length() > shown.length() {
        c.box(tx=-3.0 * (shown.length() - 1).to_double() + 3.0, fn() {
          c.text(
            "+\{people.length() - shown.length()}",
            size=12.0,
            color=t.p.muted,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  c.box(dir=Row, gap=6.0, align=ACenter, fn() {
    if lead == "people" {
      if with_people {
        faces()
      }
      if groups.length() > 0 {
        agents()
      }
    } else {
      if groups.length() > 0 {
        agents()
      }
      if with_people {
        faces()
      }
    }
  })
  |> ignore
}

///|
/// The people's colours (Parts.kt AVATAR).
// kept across runs: a table, never written
let avatar_colors : Array[Int64] = [
  0x5B7BB2FFL, 0x2F8F5BFFL, 0xB9471FFFL, 0x8A6BB0FFL, 0x3F8C99FFL, 0xB0842FFFL,
]

///|
fn lower(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    let k = ch.to_int()
    sb.write_char(if k >= 65 && k <= 90 { (k + 32).unsafe_to_char() } else { ch })
  }
  sb.to_string()
}

///|
/// A person's colour, by their email or id (Parts.kt avatarColor).
pub fn avatar_color(id : String) -> Int64 {
  let n = avatar_colors.length()
  let h = java_hash(lower(id)) % n
  avatar_colors[if h < 0 { h + n } else { h }]
}

///|
/// The first letter of a name, as a lettered picture shows it.
fn initial(name : String) -> String {
  for ch in name {
    let k = ch.to_int()
    if k == 32 || k == 9 || k == 10 {
      continue
    }
    return if k >= 97 && k <= 122 {
      (k - 32).unsafe_to_char().to_string()
    } else {
      ch.to_string()
    }
  }
  "?"
}

///|
/// A person, round (RowPicture.kt Face, Parts.kt Avatar): their account's picture once it is here, their initial on
/// their colour until then; ringed in ink when they started the chat, else in the page's ground.
fn face(
  c : @ui.Ctx,
  src : Source,
  p : Person,
  size : Double,
  starter : Bool,
  dx : Double,
) -> Unit {
  let t = @sf.theme()
  let picture = if p.picture != "" { (src.picture)(p.picture) } else { "" }
  c.box(
    w=Px(size),
    h=Px(size),
    radius=size / 2.0,
    bg=avatar_color(if p.email != "" { p.email } else { p.id }),
    align=ACenter,
    justify=JCenter,
    tx=dx,
    fn() {
      if picture != "" {
        c.image(picture, w=Px(size), h=Px(size), radius=size / 2.0, bg=0L) |> ignore
      } else {
        c.text(
          initial(p.name),
          size=size * 0.5,
          weight=600,
          color=0xFFFFFFFFL,
          wrap=false,
          line=size * 0.5,
        )
        |> ignore
      }
      c.layer(fn() {
        if starter {
          c.box(
            w=Px(size + 4.0),
            h=Px(size + 4.0),
            radius=size / 2.0 + 2.0,
            border=1.5,
            border_color=t.p.text,
            tx=-2.0,
            ty=-2.0,
            fn() {  },
          )
          |> ignore
        } else {
          c.box(
            w=Px(size),
            h=Px(size),
            radius=size / 2.0,
            border=1.5,
            border_color=t.p.bg,
            fn() {  },
          )
          |> ignore
        }
      })
      |> ignore
    },
  )
  |> ignore
}
