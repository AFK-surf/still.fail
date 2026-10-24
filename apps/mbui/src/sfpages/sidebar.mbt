// The chats' lists (ember web/src/Sidebar.tsx ChatList, ChatPane; SidebarList.tsx NavSection; web/src/mobile/Home.tsx
// Home, ChatPane, Empty, FilterButton; Sidebar.css.ts navSlider, navTrack, navScroll, navEmpty; mobile/Home.css.ts
// mHomePanes, mHomePane), one in every tier: 全部, 我参与的 and 监控中 side by side on one track, slid from one to
// another as the filter changes (240 ms) with nothing to wait for, as the core's `chats` view lists each: its days
// under their headings, a row each (chat_row.mbt); while it is read the rows to come, what is wrong over them, an
// empty list's words. While a finger is on a list, the pointer over it or it moves, its rows keep their places
// (listMotion.ts useHeldOrder); they move as it changes (useListMotion). The frame it is drawn in says what is over
// it and at its foot (the bar it is under, the bottom bar), what it adds at each list's top (a search's field, what is
// left up long), and the lists that follow the three on the track (奏, 已归档, where the frame has them so).

///|
/// What the frame gives the lists: the room over them (the bar they run under) and at their foot, what is over the
/// box they are in where the search's bar goes under it (a phone's status bar, the sidebar's top row), their ground (what a
/// row's faces' rings are cut in), what stands at a list's top before its words and rows (`before`) and after its
/// words (`after`), each said for a list's filter and its view; the lists on the track after the three (each drawn the
/// pane's whole), and which of all of them is shown (0 all, 1 mine, 2 watching, then the others').
pub(all) struct ListsFrame {
  top : Double
  foot : Double
  inset : Double
  ground : Int64
  before : (String, ChatsView?) -> Array[ListPart]
  after : (String, ChatsView?) -> Array[ListPart]
  others : Array[() -> Unit]
  shown : Int
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
/// A frame's lists with nothing of the frame's own in them.
pub fn bare_lists(top : Double, foot : Double, inset : Double, ground : Int64, shown : Int) -> ListsFrame {
  { top, foot, inset, ground, before: fn(_, _) { [] }, after: fn(_, _) { [] }, others: [], shown }
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
/// How the track slides (Sidebar.css.ts navTrack: transform 240ms ease-out; mobile/Home.css.ts mHomePane: 240ms
/// standard), by the hand: a mouse's the web's desktop, a finger's its phone's.
pub let list_slide_ms : Double = 240.0

///|
/// The chats' lists of workspace `w` in the box they are given, as `frame` says (ListsFrame).
pub fn chats_lists(c : @ui.Ctx, src : Source, w : Workspace, frame : ListsFrame) -> Unit {
  rows_frame(c, src)
  let finger = @sf.touch_system()
  let last = list_filters.length() + frame.others.length() - 1
  let x = @motion.animate(c, "lists/" + w.id, frame.shown.to_double(), spec=@motion.tween(list_slide_ms, ease=if finger {
    Standard
  } else {
    Out
  }))
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
  c.box(style=lists_fill, fn() {
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
/// lists (their bar, faded by `search_away`), in the same box, `inset` what is over it there.
pub fn chats_search(c : @ui.Ctx, src : Source, w : Workspace, inset : Double) -> Unit {
  // (opened from the field at a list's top, or by ⌘K laid out Small; over another page, the shell's: search_over)
  if !search.over {
    search_page(c, src, w, inset)
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
  filter_menu_serial.val = -1
}

///|
/// One of the lists (ChatPane): its states (being read, failing, empty) and its days under the bar's room; `current`,
/// the one shown (its rows the ones an archived chat's neighbour is looked for in).
fn chats_pane(c : @ui.Ctx, src : Source, w : Workspace, filter : String, frame : ListsFrame, current : Bool) -> Unit {
  let finger = @sf.touch_system()
  let key = "chats/" + w.id + "/" + filter
  let pane = c.id(key + "/pane")
  let (view, error) = @sfbase.chats_of(src, w.id, filter)
  match view {
    Some(v) if current => @sfbase.open_listed(v)
    _ => ()
  }
  let lines : Array[Line] = [Top]
  // a finger's search at the list's top, out of view until scrolled to (Home.kt top), while it has rows to look in;
  // a mouse has ⌘K (a finger has no keys to press)
  if finger {
    match view {
      Some({ note: Some({ empty: true, .. }), .. }) | None => ()
      Some(_) => lines.push(Part({ key: "search", draw: fn() { search_field(c) }, tucked: true }))
    }
  }
  for p in (frame.before)(filter, view) {
    lines.push(Part(p))
  }
  let shown : Array[ChatItem] = []
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
      for d in days {
        lines.push(Heading(d.label))
        for item in d.items {
          lines.push(Row(item))
          shown.push(item)
        }
      }
    }
  }
  lines.push(Foot)
  if current {
    listed.val = shown
  }
  let lead = match view {
    Some(v) => v.leading
    None => "agents"
  }
  let open = open_chat()
  // the rows and days move as the list changes (listMotion.ts useListMotion: by their keys); only they count: the
  // first rows, after the list waited, come as they are
  let keys = lines.map(line_key)
  let lid = @motion.list_keys(
    c,
    key,
    keys.filter(fn(k) { k.has_prefix("h/") || k.has_prefix("r/") }).map(fn(k) { key + "\u{1}" + k }),
    liftable=fn(k) { !k.contains("\u{1}h/") },
  )
  let row_h = if finger { touch_row_h } else { mouse_row_h }
  c.box(style=lists_fill, id=pane, fn() {
    c.list(key, lines.length(), row_h, fn(i) {
      let n = c.box(style=if finger { line_touch } else { line_mouse }, fn() {
        match lines[i] {
          Top => list_space(c, frame.top + (if finger { 0.0 } else { lists_top_in }))
          Foot => list_space(c, frame.foot + (if finger { 0.0 } else { lists_foot_in }))
          Part(p) => (p.draw)()
          Wait(note, error) => list_waiting(c, note, error)
          Empty(v) => list_empty(c, v, filter)
          Heading(label) => list_heading(c, label)
          Row(item) => {
            let name = key + "\u{1}" + keys[i]
            let on = match open {
              Some(r) => r.station == item.station && (r.session == item.session || r.session == item.id)
              None => false
            }
            chat_row(
              c,
              src,
              item,
              lead,
              on~,
              list_ground=frame.ground,
              more=i + 1 < lines.length() && lines[i + 1] is Row(_),
              lifted=@motion.lifted(c, lid, name),
              unghost=fn(off) { @motion.list_unghost(c, lid, name, off~) },
            )
            |> ignore
          }
        }
      })
      match lines[i] {
        Heading(_) | Row(_) => row_moving(c, lid, key, keys[i], n)
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
  // the list's first time with its rows: at its first, what is tucked over it out of view, there once scrolled to
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
      c.list_scroll_to(key, at + 1, offset=-frame.top)
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
/// A chat's row's height with a mouse (Sidebar.css.ts navSession), the room over a list under its bar and at its foot
/// (navScroll: 4, 12).
let mouse_row_h : Double = 54.0

///|
pub let lists_top_in : Double = 4.0

///|
pub let lists_foot_in : Double = 12.0

///|
/// Whether list `key` keeps its rows where they are (listMotion.ts usePointerOver, ListMotion.kt HeldOrder): it moving,
/// or the pointer over it (a mouse's, a finger down on it).
fn list_held(c : @ui.Ctx, key : String, pane : Int) -> Bool {
  if c.list_moving(key) {
    return true
  }
  let (px, py, down) = c.pointer()
  let over = match c.rect_of(pane) {
    Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
    None => false
  }
  over && (down || @ui.pointing() is Mouse)
}

///|
/// Whether a row shown in list `key` was pinned or let go since: it moves at once, even while the list is held still
/// (Sidebar.tsx pinMoved).
fn pin_moved(key : String, days : Array[ChatDay]) -> Bool {
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
/// past others over them.
pub fn row_moving(c : @ui.Ctx, lid : Int, list : String, key : String, i : Int) -> Unit {
  @motion.layout(
    c,
    i,
    list + "\u{1}" + key,
    spec=if @sf.touch_system() { @motion.row_spring } else { @motion.move_spring },
    enter=@motion.trans(fade=0.0, scale=row_from, spec=row_enter),
    exit=@motion.trans(fade=0.0, scale=row_from, spec=row_leave),
  )
  if @motion.lifted(c, lid, list + "\u{1}" + key) >= 0.0 {
    c.put_over(i)
  }
}

///|
let row_from : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
let row_enter : @motion.Spec = @motion.tween(row_enter_ms, ease=Out, delay=row_enter_after)

///|
// kept across runs: a value (no field of it changes)
let row_leave : @motion.Spec = @motion.tween(row_leave_ms, ease=CssOut)

///|
let row_enter_ms : Double = 240.0

///|
let row_enter_after : Double = 100.0

///|
let row_leave_ms : Double = 200.0

///|
/// Room in a list, `h` high (for the bar over it, at its foot).
fn list_space(c : @ui.Ctx, h : Double) -> Unit {
  c.box(style=@ui.style(h=Fixed(h)), fn() {  }) |> ignore
}

///|
/// A day's heading (SidebarList.tsx NavSection): a mouse's 12 on 18, muted, 14 above and 4 under (Sidebar.css.ts
/// navHeading); a finger's the phone's, 15 bold in ink, 20 in, 14 above and 6 under (SidebarList.css.ts
/// phoneHeading, Parts.kt SectionHeader).
pub fn list_heading(c : @ui.Ctx, label : String) -> Unit {
  if @sf.touch_system() {
    c.box(style=heading_touch, fn() { c.text(label, style=heading_touch_words) |> ignore }) |> ignore
  } else {
    c.box(style=heading_mouse, fn() { c.text(label, style=heading_mouse_words) |> ignore }) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let heading_mouse : @ui.Style = @ui.css("w=Full px=S2 pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let heading_mouse_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let heading_touch : @ui.Style = @ui.css("w=Full px=S5 pt=S3_5 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let heading_touch_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false)

///|
/// The list read the first time, or no rows to show while it waits on a station or cannot read one (the library's
/// Waiting, Status.tsx: the rows to come breathing, what is wrong over them in red), dense with a mouse.
fn list_waiting(c : @ui.Ctx, note : ListNote?, error : String?) -> Unit {
  let finger = @sf.touch_system()
  let reading = match note {
    Some(n) => n.reading
    None => true
  }
  @sf.waiting(
    c,
    shape=Rows,
    count=if !finger { 6 } else if reading { 7 } else { 4 },
    dense=!finger,
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
        c.cursor(new, Hand)
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
let said_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let empty_first : @ui.Style = @ui.style(w=Full, p=@sf.empty_in, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let empty_box : @ui.Style = @ui.style(w=Full, px=@sf.empty_in, py=S5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let empty_title : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Semibold, color=Fg, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let empty_note : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, center=true, leading=L6, w=Full)

///|
// kept across runs: a value (no field of it changes)
let empty_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let empty_link : @ui.TextStyle = @ui.text_style(size=Base, color=Link)

///|
// kept across runs: a value (no field of it changes)
let lists_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A list's lines: with a mouse 8 in from its sides (Sidebar.css.ts navScroll), with a finger across it.
// kept across runs: a value (no field of it changes)
let line_mouse : @ui.Style = @ui.css("w=Full px=S2")

///|
// kept across runs: a value (no field of it changes)
let line_touch : @ui.Style = @ui.css("w=Full")

///|
/// A row's or a place's ground as the web moves it (Sidebar.css.ts navRow, Rail.css.ts item: `transition: background
/// 140ms` ease out): the pointer's ground in and out, the lit one's (`lit`, the selected grey by default), as the state
/// changes.
pub fn nav_ground(c : @ui.Ctx, key : String, hover : Bool, on : Bool, lit? : Int64) -> Int64 {
  let t = @sf.theme()
  let lit = lit.unwrap_or(t.p.selected)
  let h = @kit.animate(c, key + "/hover", if hover { 1.0 } else { 0.0 }, transition=nav_fade)
  let o = @kit.animate(c, key + "/on", if on { 1.0 } else { 0.0 }, transition=nav_fade)
  if h <= 0.0 && o <= 0.0 {
    0L
  } else {
    @sf.over(@sf.alpha(t.p.hover, h * (1.0 - o)), @sf.alpha(lit, o))
  }
}

///|
/// What a state's ground changes over (vars.dur: 140 ms, ease out).
// kept across runs: a value (no field of it changes)
pub let nav_fade : @motion.Spec = @motion.tween(@sf.dur_ms, ease=Out)

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
/// 我参与的, 监控中, 奏, then 已归档, the list `shown` (all, mine, watching, decisions, archive) checked. Chosen, `go` is
/// given which: where it goes is the frame's (a filter its list, 奏 and 已归档 their pages or lists).
pub fn filter_menu(from : @sf.Anchor, shown : String, go : (String) -> Unit) -> Unit {
  let item = fn(key : String, words : String) -> @sf.MenuItem? {
    Some(@sf.menu_item_of(@sf.t(words), icon=if shown == key { "check" } else { "" }, fn() { go(key) }))
  }
  @sf.menu(
    [
      item("all", "web-main.filter.chats.all"),
      item("mine", "web-main.filter.chats.mine"),
      item("watching", "web-main.filter.watching"),
      item("decisions", "web-main.decisions.title"),
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
