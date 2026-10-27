// The rail's places as the system's tabs where the platform has bars of its own (@hostapi.nav_bar: iOS's tab bar,
// laid out by the system as its own apps' are: down the trailing edge on an iPhone Duo's outer screen and on its inner
// one on its side, iOS 27.1; across the foot upright), in its own glass; the workspaces in a menu of the navigation
// bar's. The wide frame draws no rail then, the sidebar from the window's left, what the bars take of the view in the
// bars the system says (@ui.system_bars), as the status bar's. Elsewhere (the host has none) the rail as it was.

///|
/// The wide frame this frame drew (what the column is made of: rail_nav), handed to the host as the frame ends.
let nav_want : Ref[(Source, Workspace, Array[Workspace])?] = { val: None }

///|
/// The page's actions in the navigation bar this frame (bar_action), in their order from the bar's end in, and what
/// each does; those of the frame before, for what is chosen between frames.
let nav_page : Array[(@hostapi.NavItem, () -> Unit)] = []

///|
let nav_page_was : Map[String, () -> Unit] = {}

///|
/// What is up over the whole window handed the bars the frame before (@sf.native_over_act), by id, for what is chosen
/// between frames.
let nav_over_was : Map[String, () -> Unit] = {}

///|
/// The page of the stack being drawn now (frame.mbt's nav_flat), None outside one.
let drawn_page : Ref[Page?] = { val: None }

///|
/// The page the actions were handed for: kept from frame to frame while it is the one shown (a part kept as it was
/// drawn hands nothing again, its actions the same), dropped as another comes.
let nav_page_of : Ref[Page?] = { val: None }

///|
/// How much of the home indicator's room the cards keep clear beside the column (its line, 8 over the window's foot;
/// the rest of the system's 20 to 34 under them, as the system's own sidebars go).
let cards_foot : Double = 8.0

///|
/// Whether the wide frame lays its cards across beside the column of the system's glass (sfapp's sides: their ground
/// under the column).
pub fn on_cards() -> Bool {
  @sf.native_on() && wide.tape
}

// ---- what a page hands the system's bars: the one way a page has into them. Each answers whether it took it (the
// page then draws nothing of its own for it) or not (no system's bars, every other device: the page draws its own, as
// it did). A page asks nothing else of them.

///|
/// One of the page's actions (`id`, its words and icon: an icon's name, or `raw`, an icon as the host's bars take it)
/// in the system's bars; `act` what it does chosen. A page on its way out (a stack's move) hands none: the one on top
/// does.
fn bar_action(id : String, title : String, icon : String, act : () -> Unit, raw? : String) -> Bool {
  if !@sf.native_on() || column_short.val {
    return false
  }
  if drawn_page.val is Some(p) && p != app.nav.top() {
    return false
  }
  let key = "page/" + id
  match nav_page.search_by(fn(p) { p.0.id == key }) {
    Some(i) => nav_page.remove(i) |> ignore
    None => ()
  }
  let data = match raw {
    Some(d) => d
    None => @sf.icon_path(icon)
  }
  nav_page.push(({ id: key, title, icon: data, dot: false, prominent: false, menu: [] }, act))
  true
}

///|
/// A chat's agents in the system's bars, each its maker's mark, pressed its history in the side panel (opened or
/// closed: side_toggle), in place of their tiles by its title and the side panel's switch (the user, 2026-10-27).
fn bar_agents(src : Source, r : ChatRef, agents : Array[Agent]) -> Bool {
  if !@sf.native_on() || agents.is_empty() {
    return false
  }
  for a in agents {
    let key = a.key
    bar_action(
      "who/agent/" + key,
      @sf.t("web-pages.chat.historyOf", args=[("agent", a.who)]),
      "",
      fn() { side_toggle(src, r, key) },
      raw=@sf.maker_icon(a.maker, a.runtime),
    )
    |> ignore
  }
  true
}

///|
/// A chat's ⋯ in the system's bars, its people's faces its bubble (three at most: their colours, their letters), as
/// Slack's (the user, 2026-10-27); `act` its info opened.
fn bar_people(people : Array[Person], act : () -> Unit) -> Bool {
  let faces = people
    .iter()
    .take(3)
    .map(fn(p) { hex_of(@sf.avatar_color(p.id)) + "," + person_initial(p.display) })
    .collect()
  let raw = if faces.length() > 0 { Some("avatars:" + faces.join(";")) } else { None }
  bar_action("info", @sf.t("web-pages.chat.info"), "more", act, raw?=raw)
}

///|
/// What opens from one of the page's actions in the system's bars (its info's popover): the mark where it was chosen,
/// beside the column down the side, under it across the top; `id`, `side` and `along` where the page has its own.
fn bar_anchor(id : Int, side : @ui.Side, along : @ui.Along) -> (Int, @ui.Side, @ui.Along) {
  if !@sf.native_on() || native_mark.val == 0 {
    return (id, side, along)
  }
  if @sf.native_side() {
    (native_mark.val, Left, Start)
  } else {
    (native_mark.val, Bottom, End)
  }
}

///|
/// Whether the window turned or was folded since `was` (the width it had) beside the system's tabs: what opened from
/// their items is elsewhere now, closed as the system's popovers are. False elsewhere, always: nothing closes so.
fn native_turned(c : @ui.Ctx, was : FixedArray[Double]) -> Bool {
  let width = c.window_size().0
  let turned = was[0] > 0.0 && was[0] != width && @sf.native_on()
  was[0] = width
  turned
}

///|
/// The colour 0xRRGGBBAA as `rrggbbaa`, opaque, for an icon the host draws (ws_badge, bar_people).
fn hex_of(k : Int64) -> String {
  (k >> 8 & 0xFFFFFFL).to_string(radix=16).pad_start(6, '0') + "ff"
}

///|
/// The system's column down the window's trailing edge as the system says its bars take it now (none upright, nor
/// without its bars).
fn native_side_now() -> Unit {
  @sf.native_bars.side = if @sf.native_bars.on { dmax(0.0, @ui.system_bars().right) } else { 0.0 }
}

///|
/// A frame of the app, `body`: the system's bars as it wants them handed to the host once it is drawn (only as they
/// change: @hostapi.nav_bar), the page's actions in them, none where it wants none (a phone's frame).
pub fn nav_frame(body : () -> Unit) -> Unit {
  nav_want.val = None
  @sf.native_over_clear()
  // (the column as the window is now, turned or not, before anything is laid out beside it)
  native_side_now()
  // (the page's actions as they were while the same page is shown: one built again hands them again)
  let page = app.nav.top()
  if nav_page_of.val != Some(page) {
    nav_page.clear()
    nav_page_of.val = Some(page)
  }
  body()
  nav_page_was.clear()
  for p in nav_page {
    nav_page_was[p.0.id] = p.1
  }
  match nav_want.val {
    Some((src, w, all)) => {
      // at the column's top the card in use's own: the chats' list's filter while it is, the page's actions while it is
      // (the page's actions said native: bar_action; the chats' list's filter stays in its card, the user 2026-10-27)
      // (a chat's agents first, on a glass of their own; its other actions, its ⋯, under them: the user 2026-10-27)
      let page = nav_page.filter(fn(p) { p.0.id.has_prefix("page/who/") })
      page.append(nav_page.filter(fn(p) { !p.0.id.has_prefix("page/who/") }))
      let card : Array[@hostapi.NavItem] = page.map(fn(p) { p.0 })
      if @ui.env("MBUI_NAV_LOG") == "1" {
        let said = card.map(fn(i) { i.id + (if i.menu.length() > 0 { "{" + i.menu.map(fn(m) { m.1 }).join(",") + "}" } else { "" }) }).join(" ")
        if said != nav_log_was.val {
          nav_log_was.val = said
          @hostapi.log("NAVLOG depth \{app.nav.depth()} card: \{said}")
        }
      }
      // (something up over the whole window, the viewer: the tabs put away, its actions alone in the bars)
      let over = @sf.native_over
      nav_over_was.clear()
      let bar = if over.up {
        let acts : Array[@hostapi.NavItem] = over.acts.map(fn(a) {
          nav_over_was[a.0] = a.3
          { id: a.0, title: a.1, icon: @sf.icon_path(a.2), dot: false, prominent: false, menu: [] }
        })
        { ..rail_nav(src, w, all, acts), bare: true, title: over.title }
      } else {
        rail_nav(src, w, all, card)
      }
      @sf.native_bars.on = @hostapi.nav_bar(bar)
      native_side_now()
    }
    None => {
      @hostapi.nav_bar_none()
      @sf.native_bars.on = false
      @sf.native_bars.side = 0.0
    }
  }
}

///|
/// What of the window's width the rail takes at its left: none while the system's tabs show its places.
fn rail_left() -> Double {
  if @sf.native_on() {
    0.0
  } else {
    rail_w
  }
}

///|
/// Whether the sidebar's ground runs the window's height (its top and foot under the system's bars, what is in it
/// clear of them): open beside the system's tabs, off the tape, as the system's own sidebars do.
fn side_full_height(bar : Bool) -> Bool {
  @sf.native_on() && !bar && !wide.tape
}

///|
/// How much more of the rail shows on the tape (rail_tape_more): none while it is the system's tabs.
fn rail_more() -> Double {
  if @sf.native_on() {
    0.0
  } else {
    rail_tape_more()
  }
}

///|
/// Where what opens from the column's items is put beside (待处理's panel: attention.mbt, by the rail's ids): a mark at
/// the window's right edge where 待处理 is, at the column's foot over 新建对话.
fn rail_native_marks(c : @ui.Ctx) -> Unit {
  if !@sf.native_on() {
    return
  }
  c.layer(fn() {
    // (at the bell where the system says it is; else where the column has it)
    let at = @hostapi.nav_tapped_at
    let (tx, ty, th) = if at[2] > 0.0 {
      (at[0], at[1], at[3])
    } else {
      (dmax(0.0, c.width - @sf.native_clear() - 1.0), dmax(0.0, c.height - native_bell_up), 40.0)
    }
    let id = c.id("rail/attention")
    native_mark.val = id
    c.box(style=@ui.style(w=Fixed(native_mark_w), h=Fixed(th)), tx~, ty~, id~, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The mark at the item of the system's bars last chosen (rail_native_marks), for what opens from one elsewhere (a
/// chat's ⋯: chat_page.mbt bar_popovers), its ids scoped there as they are.
let native_mark : Ref[Int] = { val: 0 }

///|
/// How wide the mark at a chosen item of the system's bars is (rail_native_marks): a line, what opens from it beside it.
let native_mark_w : Double = 1.0

///|
/// How far over the window's foot 待处理's button ends (the host's column: 新建对话 under it, 12 apart, and the room the
/// home indicator keeps).
let native_bell_up : Double = 156.0


///|
/// The column of the system's glass, the Duo's shape in mind (its right thumb at the inner screen's right edge, low): at
/// its top the card in use's own (the chats' list's filter, the page's actions: `card`), then 对话 and 文件 and 更多 (the
/// other places, the settings, the workspaces), and at its foot what is most wanted, where the thumb rests: 待处理 and
/// 新建对话 (on the accent's glass). The place lit chosen (更多 for one in it).
fn rail_nav(src : Source, w : Workspace, all : Array[Workspace], card : Array[@hostapi.NavItem]) -> @hostapi.NavBar {
  let places = rail_items(src, w.id)
  let lit = lit_place()
  let item = fn(id : String, title : String, icon : String) -> @hostapi.NavItem {
    { id, title, icon: @sf.icon_path(icon), dot: false, prominent: false, menu: [] }
  }
  // 对话, 文件, Station, 待处理 (the chats that want the viewer: 奏), 我的 (the settings, the other places' pages in them)
  let tabs : Array[@hostapi.NavItem] = [item("place/chats", rail_label(src, "chats"), rail_icon("chats"))]
  if places.contains("files") {
    tabs.push(item("place/files", rail_label(src, "files"), rail_icon("files")))
  }
  // (the workspace's stations, whatever the rail shows: the user, 2026-10-26)
  // (its icon the stations at a glance, as the rail's: online ones lit, a dot while one fails)
  let glance = stations_at_glance(src, w.id).0
  tabs.push({
    ..item("place/stations", rail_label(src, "stations"), "stations"),
    icon: @sf.station_glyph_icon(glance),
    dot: glance.failing > 0,
  })
  // (the workspace's mark and its name, a button, not a tab: pressed, the workspaces and 设置 in the system's menu from it; by
  // 待处理's bell, in the column down the side by the tabs, upright at the bar's lead: the user 2026-10-27; its
  // picture, a link's or a data URL's, the host loads in place of its letter)
  let at = if @sf.native_side() { "act/" } else { "lead/" }
  // (its menu the system's own: each workspace with its mark, the one in view checked; a line; 设置)
  let rows = all.map(fn(x) { ("ws/" + x.id, x.name, x.id == w.id, ws_badge(x)) })
  rows.push(("-", "", false, ""))
  rows.push(("settings", @sf.t("android-settings.title"), false, @sf.icon_path("settings")))
  // (on the outer screen's short column, the navigation bar's, the bell the toolbar's: one of the app's own in each
  // is all the system shows there, the rest folded into a menu of its own: column_short)
  let ws_at = if column_short.val { "lead/" } else { at }
  tabs.push({ ..item(ws_at + "workspaces", w.name, "user"), icon: ws_badge(w), menu: rows })
  // (待处理 a popover over the page, as the bell's: pressed, never chosen; in the column down the side, upright at the
  // bar's lead, left of the top, on the status bar's row: the user 2026-10-27)
  tabs.push({ ..item(at + "attention", rail_label(src, "attention"), "bell"), dot: bell_lit(src, w) })
  let selected = tab_of_place(lit)
  let t = @sf.theme()
  {
    groups: [
      { items: card, foot: false, foldable: true },
      { items: tabs, foot: false, foldable: false },
      {
        items: [{ ..item("new", @sf.t("web-main.sidebar.newChat"), "compose"), prominent: true }],
        foot: true,
        foldable: false,
      },
    ],
    selected,
    ink: t.p.text,
    chosen_ink: t.p.accent,
    more_icon: @sf.icon_path("more"),
    bare: false,
    title: "",
  }
}

///|
/// The tab the place shown is in (rail_nav's `selected`).
fn tab_of_place(lit : String) -> String {
  match lit {
    "chats" | "mine" | "watching" | "archive" | "decisions" => "place/chats"
    "files" => "place/files"
    "stations" => "place/stations"
    // (the settings, opened from the workspace's button: no tab of theirs)
    _ => ""
  }
}

///|
/// What each tab showed as it was left (its stack's pages), by its workspace and its id (tab_kept_key); kept while the app
/// runs.
let tabs_kept : Map[String, Array[Page]] = {}

///|
/// The key of tab `tab` of workspace `ws` in tabs_kept: each workspace's tabs keep their own (a chat of one never shown
/// in another's chats).
fn tab_kept_key(ws : String, tab : String) -> String {
  ws + " " + tab
}

///|
/// The wide frame's part of this frame where the system has bars of its own (frame.mbt calls it once, as it starts):
/// what it is handed as the frame ends (nav_frame), the screen's corners the cards follow, what was chosen in the
/// bars since the last frame done.
fn native_frame(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  nav_want.val = Some((src, w, all))
  column_short.val = @sf.native_side() && c.window_size().0 < column_short_below
  // (the host says the screen's corner only where it lays out the tabs, ios_nav.h mb_host_window_corner; said once the
  // window is on the screen, what was kept before it is drawn anew, its corners its own then)
  let was = @sf.native_card_corner()
  @sf.native_bars.corner = if @sf.native_on() { @ui.window_corner() } else { 0.0 }
  if @sf.native_card_corner() != was {
    c.forget_parts()
  }
  rail_native_taps(c, src, w)
}

///|
/// What was chosen in the system's bars since the last frame: a place gone to as the rail's pressed (rail_go), the
/// settings opened, another workspace switched to.
fn rail_native_taps(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let taps = @sfbase.nav_tapped.copy()
  @sfbase.nav_tapped.clear()
  // (another page come to by what was chosen, mid-frame: the actions the one left handed in frames before not its; the
  // one come to hands its own as it is drawn after this: nav_frame)
  defer {
    if nav_page_of.val != Some(app.nav.top()) {
      nav_page.clear()
      nav_page_of.val = Some(app.nav.top())
    }
  }
  for id in taps {
    // (anything else chosen in the bars closes 待处理's panel, as a tap off a popover of the system's does)
    if id != "act/attention" && id != "lead/attention" {
      wide.attention_open = false
    }
    // (a tab left keeps what it showed, given back as it is chosen again; the one shown chosen again changes nothing,
    // as the system's tab apps have it: the user, 2026-10-26)
    let now = tab_of_place(lit_place())
    if id.has_prefix("place/") && id != now {
      tabs_kept[tab_kept_key(w.id, now)] = app.nav.pages()
      // (what was open over the tab left closed with it: a chat's ⋯, a menu)
      chat_own.info_open = false
      chat_own.jobs_open = false
      @sf.close_all_presented()
    }
    if id == now {
      ()
    } else if id == "settings" {
      if lit_place() != "settings" {
        open_settings()
      }
    } else if id.has_prefix("ws/") {
      let ws = id.substring(start=3)
      if ws != w.id {
        @sfpages.switch_workspace(src, ws)
      }
    } else if id == "new" {
      new_chat()
    } else if id.has_prefix("list/") {
      rail_go(c, src, w, id.substring(start=5))
    } else if id.has_prefix("place/") {
      let place = id.substring(start=6)
      match tabs_kept.get(tab_kept_key(w.id, id)) {
        // (its stack as it was left: the chat open in it, the list it showed)
        Some(pages) if pages.length() > 0 => {
          @sfbase.go_place(place) |> ignore
          app.nav.replace(pages[0])
          for i in 1..<pages.length() {
            app.nav.push(pages[i])
          }
          wide.landed = ""
        }
        _ => rail_go(c, src, w, place)
      }
    } else if id.has_prefix("over/") || id.has_prefix("lead/over/") {
      match nav_over_was.get(id) {
        Some(act) => act()
        None => ()
      }
    } else if id.has_prefix("page/") {
      match nav_page_was.get(id) {
        Some(act) => act()
        None => ()
      }
    } else if id == "act/attention" || id == "lead/attention" {
      rail_go(c, src, w, "attention")
    }
  }
}

///|
/// The frame's room as it is laid out now: beside the system's tab bar (an iPhone Duo's), the panels 4 in from the
/// window's edges and 4 apart (the user, 2026-10-26: room for what is in use);
/// elsewhere closed_bar_in and closed_bar_gap as they are.
fn bar_in_now() -> Double {
  if @sf.native_on() {
    @sf.native_in
  } else {
    closed_bar_in
  }
}

///|
fn bar_gap_now() -> Double {
  if @sf.native_on() {
    @sf.native_in
  } else {
    closed_bar_gap
  }
}

///|
/// What MBUI_NAV_LOG said last of the page's actions (a probe: said again only as they change).
let nav_log_was : Ref[String] = { val: "" }

///|
/// Whether the column down the side is the outer screen's, short under the status bar it holds: room in it for the
/// bell and the workspace's button alone (the system folds the rest into a menu of its own), a page's actions its
/// own, in its card (the user, 2026-10-27: the bell and the workspaces before any of a page's).
// kept across runs: said again each frame (native_frame), put back by rail_native_reset
let column_short : Ref[Bool] = { val: false }

///|
/// The outer screen's width and under (an iPhone Duo's, 466 across; its inner one on its side 951).
let column_short_below : Double = 600.0

///|
/// What this file keeps put back as the app begins anew (desk.mbt reset).
fn rail_native_reset() -> Unit {
  column_short.val = false
  @sf.native_bars_reset()
  nav_want.val = None
  nav_page.clear()
  nav_page_was.clear()
  nav_over_was.clear()
  drawn_page.val = None
  nav_page_of.val = None
  native_mark.val = 0
  tabs_kept.clear()
  nav_log_was.val = ""
  attention_size[0] = 0.0
  info_width[0] = 0.0
}

///|
/// A workspace's mark as an icon of the system's bars (@hostapi.NavItem `icon`): its letter (its emoji) on its colour,
/// its picture (a link's, a data URL's) the host loads in its place.
fn ws_badge(w : Workspace) -> String {
  let k = @sf.avatar_color(w.id)
  let mark = if w.emoji != "" {
    w.emoji
  } else {
    match w.name.iter().next() {
      Some(ch) => ch.to_string().to_upper()
      None => "?"
    }
  }
  let picture = if w.icon.has_prefix("https://") || w.icon.has_prefix("http://") || w.icon.has_prefix("data:image/") {
    "\u{1e}" + w.icon
  } else {
    ""
  }
  "badge:" + hex_of(k) + "," + mark + picture
}
