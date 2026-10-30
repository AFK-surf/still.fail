// The chats' lists (ember web/src/Sidebar.tsx ChatList, ChatPane; SidebarList.tsx NavSection; web/src/mobile/Home.tsx
// Home, ChatPane, Empty, FilterButton; Sidebar.css.ts navSlider, navTrack, navScroll, navEmpty; mobile/Home.css.ts
// mHomePanes, mHomePane), one in every tier: 全部, 我参与的 and 监控中 side by side on one track, slid from one to
// another as the filter changes (240 ms) with nothing to wait for, as the core's `chats` view lists each: its days
// under their headings, a row each (chat_row.mbt); while it is read the rows to come, what is wrong over them, an
// empty list's words. While a finger is on a list, the pointer over it or it moves, its rows keep their places
// (listMotion.ts useHeldOrder); they move as it changes (useListMotion). The frame it is drawn in says what is over
// it and at its foot (the bar it is under, the bottom bar), what it adds at each list's top (a search's field, what is
// left up long), and the lists that follow the three on the track (已归档, where the frame has it so).

///|
/// What the frame gives the lists: the room over them (the bar they run under) and at their foot, what is over the
/// box they are in where the search's bar goes under it (a phone's status bar, the sidebar's top row), their ground (what a
/// row's faces' rings are cut in), what stands at a list's top before its words and rows (`before`) and after its
/// words (`after`), each said for a list's filter and its view; the lists on the track after the three (each drawn the
/// pane's whole), and which of all of them is shown (0 all, 1 mine, 2 watching, then the others'); where the lists
/// stand (`at`: a side column's, their rows in and rounded, or across the whole screen: @sf.ListAt); how far down
/// what is over them covers the box (`under`: the bar's foot, the room `top` keeps under it aside), what is tucked over
/// a list's rows going out of view under it.
pub(all) struct ListsFrame {
  top : Double
  under : Double
  foot : Double
  inset : Double
  ground : Int64
  before : (String, ChatsView?) -> Array[ListPart]
  after : (String, ChatsView?) -> Array[ListPart]
  others : Array[() -> Unit]
  shown : Int
  at : @sf.ListAt
}

///|
/// Something a frame puts in a list: its key among the list's lines, what draws it, and whether the list is first
/// shown scrolled past it (a phone's search over the first row, there once scrolled to: Home.kt).
pub(all) struct ListPart {
  key : String
  draw : () -> Unit
  tucked : Bool
}

///|
/// A frame's lists with nothing of the frame's own in them, standing `at`.
pub fn bare_lists(top : Double, foot : Double, inset : Double, ground : Int64, shown : Int, at : @sf.ListAt) -> ListsFrame {
  { top, under: top, foot, inset, ground, before: fn(_, _) { [] }, after: fn(_, _) { [] }, others: [], shown, at }
}

///|
/// The lists the track holds first, in this order (Sidebar.tsx, mobile/Home.tsx: all, mine, watching).
// kept across runs: a table, never written
pub let list_filters : Array[String] = ["all", "mine", "watching"]

///|
/// Which of the lists the filter shows (0 all, 1 mine, 2 watching).
pub fn filter_at(src : Source, w : Workspace) -> Int {
  list_filters.search(@sfbase.filter_of(src, w.id)).unwrap_or(0)
}

///|
/// The chats' lists of workspace `w` in the box they are given, as `frame` says (ListsFrame).
pub fn chats_lists(c : @ui.Ctx, src : Source, w : Workspace, frame : ListsFrame) -> Unit {
  rows_frame(c, src)
  let last = list_filters.length() + frame.others.length() - 1
  // (its track a list's width a step: a Move as long as it goes)
  let x = @motion.animate(c, "lists/" + w.id, frame.shown.to_double(), spec=@sf.theme().chat_list.slide.per_unit(c.width))
  // the others read once switching to them is in sight: as the filter's menu opens (what it would show is there by
  // the time one is picked)
  if @sf.presented_drawn_of(filter_menu_serial.val) {
    for f in list_filters {
      @sfbase.chats_of(src, w.id, f) |> ignore
    }
  }
  let width = c.width
  // the search's page open over them (search.mbt: from a list's field, or by ⌘K laid out Small): the lists up and
  // away under it, whatever opened it (its page over them: chats_search)
  search_start(c)
  let away = search_away(c)
  c.box(style=lists_window, fn() {
    let track = c.layer(fn() {
      for p in x.floor().to_int()..=x.ceil().to_int() {
        if p < 0 || p > last {
          continue
        }
        c.layer(fn() {
          c.box(style=lists_fill, tx=(p.to_double() - x) * width, fn() {
            if p < list_filters.length() {
              chats_pane(c, src, w, list_filters[p], frame, p == frame.shown)
            } else {
              (frame.others[p - list_filters.length()])()
            }
          })
          |> ignore
        })
        |> ignore
      }
    })
    if away > 0.0 {
      c.look(track, { ..@ui.still_look, alpha: 1.0 - away, dy: -search_list_rise * away })
    }
  })
  |> ignore
}

///|
/// A finger's search over the lists, while it is open (search.mbt): drawn by the frame after what it lays over the
/// lists (their bar, faded by `search_away`), in the same box, `inset` what is over it there; its lines standing as the
/// lists do (`at`).
pub fn chats_search(c : @ui.Ctx, src : Source, w : Workspace, inset : Double, at : @sf.ListAt) -> Unit {
  // (opened from the field at a list's top, or by ⌘K laid out Small; over another page, the shell's: search_over)
  if !search.over {
    search_page(c, src, w, inset, at)
  }
}

///|
/// One of a list's lines.
priv enum Line {
  /// room for the bar over the list, and at its foot
  Top
  Foot
  /// what the frame puts in it
  Part(ListPart)
  /// read the first time: the rows to come, what the core waits on or cannot read, what went wrong
  Wait(ListNote?, String?)
  Empty(ChatsView)
  Heading(String)
  Row(ChatItem)
}

///|
/// A line's key among the list's (listMotion.ts: a row by its station and key, a day by its heading).
fn line_key(line : Line) -> String {
  match line {
    Top => "top"
    Foot => "foot"
    Part(p) => "part/" + p.key
    Wait(_, _) => "wait"
    Empty(_) => "empty"
    Heading(label) => "h/" + label
    Row(item) => "r/" + @sfbase.row_name(item)
  }
}

///|
/// The lists first shown once with their rows (scrolled past what is tucked over them).
// kept across runs: put back by sidebar_reset (reset)
let placed : Map[String, Bool] = {}

///|
fn sidebar_reset() -> Unit {
  placed.clear()
  rows_laid.clear()
  filter_menu_serial.val = -1
}

///|
/// A list's days as lines (a heading and its rows each), made once for the days shown (the very array: a view's, read
/// once a version, or the order held while a finger is on it), not every frame: as many as the list has rows, of
/// which a frame builds only those in view. Their keys among the list's lines, the chats in them, and the names they
/// move by (the list's key and a line's).
priv struct DayLines {
  days : Array[ChatDay]
  lines : Array[Line]
  keys : Array[String]
  shown : Array[ChatItem]
  moving : Array[String]
}

///|
/// Each list's days as lines, as last laid out (DayLines).
// kept across runs: put back by sidebar_reset (reset)
let rows_laid : Map[String, DayLines] = {}

///|
/// List `key`'s days `days` as lines: those made for them last, while they are the same.
fn day_lines(key : String, days : Array[ChatDay]) -> DayLines {
  match rows_laid.get(key) {
    Some(l) if physical_equal(l.days, days) => l
    _ => {
      let lines : Array[Line] = []
      let shown : Array[ChatItem] = []
      for d in days {
        lines.push(Heading(d.label))
        for item in d.items {
          lines.push(Row(item))
          shown.push(item)
        }
      }
      let keys = lines.map(line_key)
      let l = { days, lines, keys, shown, moving: keys.map(fn(k) { key + "\u{1}" + k }) }
      rows_laid[key] = l
      l
    }
  }
}

///|
/// One of the lists (ChatPane): its states (being read, failing, empty) and its days under the bar's room; `current`,
/// the one shown (its rows the ones an archived chat's neighbour is looked for in).
fn chats_pane(c : @ui.Ctx, src : Source, w : Workspace, filter : String, frame : ListsFrame, current : Bool) -> Unit {
  let key = "chats/" + w.id + "/" + filter
  let pane = c.id(key + "/pane")
  let (view, error) = @sfbase.chats_of(src, w.id, filter)
  match view {
    Some(v) if current => @sfbase.open_listed(v)
    _ => ()
  }
  // the lines over its days (its room under the bar, what the frame puts at its top, its states), then its days', then
  // its foot
  let lines : Array[Line] = [Top]
  // its search at its top where the screen has no keys for ⌘K (touch's: the theme's), out of view until
  // scrolled to (Home.kt top), while it has rows to look in
  if !@sf.theme().chat_list.keys && !@sf.native_able() {
    match view {
      Some({ note: Some({ empty: true, .. }), .. }) | None => ()
      Some(_) => lines.push(Part({ key: "search", draw: fn() { search_field(c, frame.at) }, tucked: true }))
    }
  }
  for p in (frame.before)(filter, view) {
    lines.push(Part(p))
  }
  let mut rows : DayLines? = None
  match view {
    None => lines.push(Wait(None, error))
    Some(v) => {
      match v.note {
        Some(n) if v.days.length() == 0 && (n.reading || n.failing.length() > 0) => lines.push(Wait(Some(n), None))
        _ => ()
      }
      match v.note {
        Some(n) if n.empty && v.days.length() == 0 => lines.push(Empty(v))
        _ => ()
      }
      for p in (frame.after)(filter, Some(v)) {
        lines.push(Part(p))
      }
      // while a finger is on the list, the pointer over it or it moves, the rows keep their places (a row pinned or
      // let go moves at once: Sidebar.tsx pinMoved)
      let days = @sfbase.held_order(key, v.days, list_held(c, key, pane) && !pin_moved(key, v.days))
      rows = Some(day_lines(key, days))
    }
  }
  let head = lines.length()
  let (day, day_keys, moving) = match rows {
    Some(r) => (r.lines, r.keys, r.moving)
    None => ([], [], [])
  }
  let count = head + day.length() + 1
  let line_at = fn(i : Int) -> Line {
    if i < head {
      lines[i]
    } else if i - head < day.length() {
      day[i - head]
    } else {
      Foot
    }
  }
  let key_at = fn(i : Int) -> String {
    if i >= head && i - head < day_keys.length() {
      day_keys[i - head]
    } else {
      line_key(line_at(i))
    }
  }
  if current {
    listed.val = match rows {
      Some(r) => r.shown
      None => []
    }
  }
  let lead = match view {
    Some(v) => v.leading
    None => "agents"
  }
  let open = open_chat()
  // the rows and days move as the list changes (listMotion.ts useListMotion: by their keys); only they count: the
  // first rows, after the list waited, come as they are
  let lid = @motion.list_keys(c, key, moving, liftable=fn(k) { !k.contains("\u{1}h/") })
  let l = @sf.theme().chat_list
  c.box(style=lists_fill, id=pane, fn() {
    c.list(key, count, l.row_h, fn(i) {
      let n = c.box(style=@sf.list_line(frame.at), fn() {
        match line_at(i) {
          Top => list_space(c, frame.top + l.top_in)
          Foot => list_space(c, frame.foot + @sf.list_foot_in(frame.at))
          Part(p) => (p.draw)()
          Wait(note, error) => list_waiting(c, note, error, frame.at)
          Empty(v) => list_empty(c, v, filter)
          Heading(label) => @sf.list_heading(c, label, frame.at)
          Row(item) => {
            let name = key + "\u{1}" + key_at(i)
            let on = match open {
              Some(r) => @sfbase.row_is(item, r)
              None => false
            }
            chat_row(
              c,
              src,
              item,
              lead,
              on~,
              list_ground=frame.ground,
              at=frame.at,
              more=i + 1 < count && line_at(i + 1) is Row(_),
              lifted=@motion.lifted(c, lid, name),
              unghost=fn(off) { @motion.list_unghost(c, lid, name, off~) },
            )
            |> ignore
          }
        }
      })
      match line_at(i) {
        Heading(_) | Row(_) => row_moving(c, lid, key, key_at(i), n)
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
  // the list's first time with its rows: what is tucked over them out of view, its foot at the foot of what covers the
  // list (frame.under: a phone's top bar, not the room under it, where its rounded foot showed), there once scrolled to
  if !placed.contains(key) && view is Some(_) {
    placed[key] = true
    let mut at = -1
    for i, l in lines {
      match l {
        Part(p) if p.tucked => at = i
        _ => ()
      }
    }
    if at >= 0 {
      c.list_scroll_to(key, at + 1, offset=-(frame.under + tucked_foot))
    }
  }
}

///|
/// The chat in the page pane, if one is.
fn open_chat() -> ChatRef? {
  let pages = app.nav.pages()
  for k = pages.length() - 1; k >= 0; k = k - 1 {
    match pages[k] {
      Chat(r) => return Some(r)
      _ => ()
    }
  }
  None
}

///|
/// The room over a list under its bar with keyboard and mouse's lists (navScroll: 4).
pub let lists_top_in : Double = 4.0

///|
/// Whether list `key` keeps its rows where they are (listMotion.ts usePointerOver, ListMotion.kt HeldOrder): it moving,
/// or the pointer over it (a mouse's, a finger down on it).
fn list_held(c : @ui.Ctx, key : String, pane : Int) -> Bool {
  if c.list_moving(key) {
    return true
  }
  // (the hand as the frame sees it, read as it comes on the list and goes off it: a press gone down on it, a mouse's
  // pointer over it. Not where the pointer is against where the list was drawn: read every build, every move of the
  // pointer built the list's pane again, and what it read of the frame before kept it from being kept, every frame
  // the hand was on it)
  c.press_within(pane) || (@sf.pointer_rests() && c.hovered(pane))
}

///|
/// Whether a row shown in list `key` was pinned or let go since: it moves at once, even while the list is held still
/// (Sidebar.tsx pinMoved). Nothing come since the order shown was made, none was.
fn pin_moved(key : String, days : Array[ChatDay]) -> Bool {
  if !@sfbase.days_new(key, days) {
    return false
  }
  let was : Map[String, Bool] = {}
  for d in @sfbase.shown_days.get(key).unwrap_or([]) {
    for item in d.items {
      was[@sfbase.row_name(item)] = item.pinned == Some(true)
    }
  }
  for d in days {
    for item in d.items {
      match was.get(@sfbase.row_name(item)) {
        Some(p) if p != (item.pinned == Some(true)) => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// How a row or a day's heading moves as the list changes (listMotion.ts useListMotion; ListMotion.kt Moving): from
/// where it was to where it is (a mouse's on motion.ts MOVE, a finger's on the phone's row spring), carrying on from
/// wherever it had got to; growing in where it is when new (240 ms after 100, from 90% and nothing); one gone drawn
/// where it was as it shrinks to 90% and fades (200 ms, ease-out), the rows after it closing over it; one going up
/// past others both: gone from where it was, grown in where it is (motion's list_keys), never across them.
pub fn row_moving(c : @ui.Ctx, lid : Int, list : String, key : String, i : Int) -> Unit {
  @motion.layout(
    c,
    i,
    list + "\u{1}" + key,
    spec=@sf.theme().chat_list.move,
    enter=@sf.row_grown_in,
    exit=@sf.leave,
  )
  if @motion.lifted(c, lid, list + "\u{1}" + key) >= 0.0 {
    c.put_over(i)
  }
}

///|
/// Room in a list, `h` high (for the bar over it, at its foot).
fn list_space(c : @ui.Ctx, h : Double) -> Unit {
  c.box(style=@ui.style(h=Fixed(h)), fn() {  }) |> ignore
}

///|
/// The list read the first time, or no rows to show while it waits on a station or cannot read one (the library's
/// Waiting, Status.tsx: the rows to come in their bones, what is wrong over them in red), as many as the theme's chats'
/// list has them, where it stands (`at`).
fn list_waiting(c : @ui.Ctx, note : ListNote?, error : String?, at : @sf.ListAt) -> Unit {
  let l = @sf.theme().chat_list
  let reading = match note {
    Some(n) => n.reading
    None => true
  }
  @sf.waiting(
    c,
    fn() { chat_rows_sample(c, if reading { l.waiting_rows } else { l.waiting_noted }, at) },
    text=@sf.t("common.reading"),
    error=error.unwrap_or(""),
    note?=match note {
      Some(nt) => Some({ reading: nt.reading, text: nt.text.unwrap_or(""), failing: nt.failing })
      None => None
    },
  )
}

///|
/// A list with nothing in it (mobile/Home.tsx Empty; Sidebar.tsx's navEmpty): in a box a phone wide or wider, the
/// phone's illustration and what to do (a new chat; with no station, the stations); narrower, the sidebar's words
/// (with no station, its link to the stations).
fn list_empty(c : @ui.Ctx, v : ChatsView, filter : String) -> Unit {
  let t = @sf.theme()
  if c.width < illustrated_from {
    c.box(style=said_box, fn() {
      match filter {
        "mine" => c.text(@sf.t("web-main.sidebar.noneMine"), style=said_words) |> ignore
        "watching" => c.text(@sf.t("web-main.sidebar.noneWatching"), style=said_words) |> ignore
        _ if v.stations > 0 => c.text(@sf.t("web-main.sidebar.none"), style=said_words) |> ignore
        _ =>
          c.rich(
            [
              @ui.span(@sf.t("web-main.sidebar.noStation.before")),
              @ui.span(@sf.t("web-main.sidebar.noStation.link"), link="stations"),
              @ui.span(@sf.t("web-main.sidebar.noStation.after")),
            ],
            style=said_words,
            link_color=t.p.blue,
            on_link=fn(_) { open_page(Place("stations")) },
          )
          |> ignore
      }
    })
    |> ignore
    return
  }
  if v.stations == 0 && filter == "all" {
    c.box(style=empty_first, fn() {
      @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, illustration_w) |> ignore
      c.text(@sf.t("android-settings.station.first"), style=empty_title) |> ignore
      c.text(@sf.t("android-settings.station.firstNote"), style=empty_note) |> ignore
    })
    |> ignore
    return
  }
  c.box(style=empty_box, fn() {
    @sf.drawable(c, if t.dark { "illus_new_chat_dark" } else { "illus_new_chat" }, illustration_w) |> ignore
    match filter {
      "mine" => c.text(@sf.t("android-chat.home.empty.mine"), style=empty_words) |> ignore
      "watching" => c.text(@sf.t("android-chat.home.empty.watching"), style=empty_words) |> ignore
      _ => {
        c.text(
          @sf.t(if v.stations > 1 { "android-chat.home.empty.many" } else { "android-chat.home.empty.one" }),
          style=empty_note,
        )
        |> ignore
        let new = c.id("chats/empty-new")
        if c.clicked(new) {
          open_page(NewChat)
        }
        let b = c.box(id=new, fn() { c.text(@sf.t("android-chat.newChat"), style=empty_link) |> ignore })
        c.semantics(b, Button, id=new, label=@sf.t("android-chat.newChat"))
      }
    }
  })
  |> ignore
}

///|
/// How wide a list is at least for its empty state to be the phone's, with its illustration (240 wide, 30 each side).
let illustrated_from : Double = 300.0

///|
let illustration_w : Double = 240.0

///|
// kept across runs: a value (no field of it changes)
let said_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S4")

///|
// kept across runs: a value (no field of it changes)
let said_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let empty_first : @ui.Style = @ui.style(w=Full, p=@sf.empty_in, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let empty_box : @ui.Style = @ui.style(w=Full, px=@sf.empty_in, py=S5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let empty_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let empty_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, leading=L6, w=Full)

///|
// kept across runs: a value (no field of it changes)
let empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let empty_link : @ui.TextStyle = @ui.text_style(size=Ui, color=Link)

///|
// kept across runs: a value (no field of it changes)
let lists_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The window the track slides in (Sidebar.css.ts navSlider: overflow hidden): a list on its way out or in shows only
/// in the lists' own box, never over what is beside it (the rail, beside a sidebar).
// kept across runs: a value (no field of it changes)
let lists_window : @ui.Style = @ui.css("w=Full h=Full clip")

///|
/// The filter's menu last opened (its presenter).
// kept across runs: put back by sidebar_reset (reset)
let filter_menu_serial : Ref[Int] = Ref(-1)

///|
/// Whether the filter's menu is open.
pub fn filter_menu_open() -> Bool {
  @sf.presented_drawn_of(filter_menu_serial.val)
}

///|
/// The filter's menu (components.tsx MineFilter's DropdownMenu, mobile/Home.tsx FilterButton), opened by `from`: 全部会话,
/// 我参与的, 监控中, then 已归档, a menu of choices, the list `shown` (all, mine, watching, archive) checked. Chosen, `go` is
/// given which: where it goes is the frame's (a filter its list, 已归档 its page or list).
pub fn filter_menu(from : @sf.Beside, shown : String, go : (String) -> Unit) -> Unit {
  let item = fn(key : String, words : String) -> @sf.MenuItem? {
    Some(@sf.menu_item_of(@sf.t(words), chosen=shown == key, fn() { go(key) }))
  }
  @sf.menu(
    [
      item("all", "web-main.filter.chats.all"),
      item("mine", "web-main.filter.chats.mine"),
      item("watching", "web-main.filter.watching"),
      None,
      item("archive", "web-main.filter.archived"),
    ],
    from~,
    along=End,
  )
  filter_menu_serial.val = @sf.last_presented()
}

///|
/// The list's filter in workspace `w` chosen (`all`, `mine`, `watching`): kept here at once, and in the prefs (the
/// core's `listFilter`, by workspace).
pub fn set_filter(src : Source, w : Workspace, f : String) -> Unit {
  if @sfbase.filter_of(src, w.id) == f {
    return
  }
  app.filters[w.id] = f
  (src.call)("prefs.set", Json::object({ "listFilter": Json::object(Map::from_array([(w.id, Json::string(f))])) }), fn(_) {  })
}
