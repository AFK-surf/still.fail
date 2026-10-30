// The rail's places as the system's tabs where the platform has bars of its own (@hostapi.nav_bar: iOS's tab bar,
// laid out by the system as its own apps' are: down the trailing edge on an iPhone Duo's outer screen and on its inner
// one on its side, iOS 27.1; across the foot upright), in its own glass; the workspaces in a menu of the navigation
// bar's. The wide frame draws no rail then, the sidebar from the window's left, what the bars take of the view in the
// bars the system says (@ui.system_bars), as the status bar's. Elsewhere (the host has none) the rail as it was.

///|
/// The wide frame this frame drew (what the column is made of: rail_nav), handed to the host as the frame ends.
let nav_want : Ref[(Source, Workspace, Array[Workspace])?] = { val: None }

///|
/// Whether the last frame left the system, able to lay out the app's tabs, without them (nav_frame): it refused those
/// handed, or the frame handed none.
// kept across runs: said by each frame that hands them, put back with the app (rail_native_reset)
let nav_untaken : Ref[Bool] = { val: false }

///|
let native_workspace_anchor : Ref[Int] = { val: 0 }

///|
let native_sidebar_items : Map[Int, @hostapi.NavItem] = {}

///|
let floating_bar : Ref[@hostapi.NavBar?] = { val: None }

///|
let native_floating : Ref[Array[@hostapi.NavFloating]] = { val: [] }

///|
// kept across runs: the layout hook is installed once
let floating_installed : Ref[Bool] = { val: false }

///|
/// Reserve a place in the list; UIKit draws the actual button there after this frame's layout and motion.
fn native_workspace(c : @ui.Ctx, src : Source, w : Workspace, node : Int, id : Int) -> Unit {
  ignore(c)
  ignore(node)
  native_workspace_anchor.val = id
  if !floating_installed.val {
    floating_installed.val = true
    @ui.on_after_layout(native_workspace_placed)
  }
  let others = field((src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value, "others") is Some(String(_))
  native_sidebar_items[id] = {
    id: "workspace-switch", title: w.name, icon: ws_badge(w),
    dot: others || @sfpages.invitations_waiting(src).length() > 0, prominent: true, menu: [],
  }
}

///|
fn native_workspace_placed(c : @ui.Ctx) -> Unit {
  guard floating_bar.val is Some(bar) else { return }
  let floating : Array[@hostapi.NavFloating] = []
  let blocked = @sf.presenter_visible()
  let semantics = c.semantics_tree()
  if !bar.bare && !switcher_open() && (!wide.tape || wide.tape_at == Side) {
    // Semantic anchors also survive a sidebar drawn from its kept part.
    for s in semantics {
      if !s.hidden || blocked {
        match native_sidebar_items.get(s.id) {
          Some(item) => {
            let (x, y, w, h) = s.rect
            // Native views sit above the canvas: keep uncovered controls visible but inert,
            // and never draw them through a presenter that physically covers their bounds.
            // Direct kit popovers (the chat menu and services) are not sf presenters.
            // Their visible bounds still cover native controls, including during exit.
            let covered = semantics.iter().any(fn(p) {
              let (px, py, pw, ph) = p.rect
              // Accessibility-hidden popovers can still be painted over a kept pane.
              (p.role == @ui.Role::Dialog || p.role == @ui.Role::Menu) &&
                x < px + pw && x + w > px && y < py + ph && y + h > py
            })
            if w > 0.0 && h > 0.0 && !covered { floating.push({ item, x, y, w, h, blocked }) }
          }
          None => ()
        }
      }
    }
  }
  native_floating.val = floating
  @hostapi.nav_bar({ ..bar, floating }) |> ignore
}

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
/// How much of the home indicator's room the cards keep clear beside the column: none, its line over their ground as
/// over the system's own apps', the cards as far from the screen's foot as from its side (native_in), so their corners
/// there are concentric with the screen's (the user, 2026-10-28: 跟手机的圆角对上).
let cards_foot : Double = 0.0

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
  if drawn_page.val is Some(p) && p != app.nav.top() {
    return false
  }
  let key = "page/" + id
  match nav_page.search_by(fn(p) { p.0.id == key }) {
    Some(i) => nav_page.remove(i) |> ignore
    None => ()
  }
  // Even the short system column needs one entry to the chat's complete menu. (Read as the page is built: the column
  // come to be short or no longer, what built it builds again and hands as it is now, what it handed before not left
  // in the bars.)
  if !@sf.native_on() || (column_short.get() && id != "chat/info") {
    return false
  }
  let data = match raw {
    Some(d) => d
    None => @sf.icon_path(icon)
  }
  nav_page.push(({ id: key, title, icon: data, dot: false, prominent: false, menu: [] }, act))
  true
}

///|
/// A chat's actions in the system's bars, each its own button there being room (the user, 2026-10-28): its info, its
/// side panel's switch (opening the first agent's history, or closing all its tabs), archiving it where it may be.
/// In place of its buttons (who is in it and where it runs stay by its
/// title, as the desktop's); false where there are no system's bars (the page draws its own).
fn bar_chat(src : Source, r : ChatRef, agents : Array[Agent], info : () -> Unit, archive : (() -> Unit)?) -> Bool {
  if !@sf.native_on() {
    return false
  }
  bar_chat_of.val = Some((src, r))
  bar_action("chat/info", @sf.t("web-pages.chat.info"), "more", info) |> ignore
  let (tabs, _) = side_now(src, r)
  let icon = if tabs.length() > 0 { "panel-close" } else { "panel-open" }
  let title = @sf.t(if tabs.length() > 0 { "web-pages.chat.closePanel" } else { "web-pages.chat.openPanel" })
  if agents.length() > 0 {
    let key = agents[0].key
    bar_action(history_item, title, icon, fn() {
      let (now, _) = side_now(src, r)
      if now.length() > 0 {
        side_change(src, r, "clear", None)
      } else {
        side_change(src, r, "open", Some(key))
      }
    }) |> ignore
  }
  match archive {
    Some(act) => bar_action("chat/archive", @sf.t("web-pages.chat.archive"), "archive", act) |> ignore
    None => ()
  }
  true
}

///|
/// The chat's side panel switch in the system's bars (bar_chat).
let history_item : String = "chat/history"

///|
/// The chat whose actions bar_chat handed (kept with it while the page's part is kept), None as another page comes.
// kept across runs: said by bar_chat, put back with the page's actions (nav_frame)
let bar_chat_of : Ref[(Source, ChatRef)?] = Ref(None)

///|
/// The chat's side panel switch as the panel is this frame (its icon and words open or closed): said again each
/// frame, the page that handed it kept as it was drawn or not (its part kept while the panel
/// changes).
fn histories_ticked() -> Unit {
  guard bar_chat_of.val is Some((src, r)) else { return }
  let (tabs, _) = side_now(src, r)
  let icon = @sf.icon_path(if tabs.length() > 0 { "panel-close" } else { "panel-open" })
  let title = @sf.t(if tabs.length() > 0 { "web-pages.chat.closePanel" } else { "web-pages.chat.openPanel" })
  for i, p in nav_page {
    let (item, act) = p
    if item.id != "page/" + history_item {
      continue
    }
    if title != item.title || icon != item.icon {
      nav_page[i] = ({ ..item, icon, title }, act)
    }
  }
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
/// The colour 0xRRGGBBAA as `rrggbbaa`, opaque, for an icon the host draws (ws_badge).
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
/// Whether the column's cards are logged as they change (MBUI_NAV_LOG=1).
fn nav_logged() -> Bool {
  if nav_log_on.val < 0 {
    nav_log_on.val = if @ui.env("MBUI_NAV_LOG") == "1" { 1 } else { 0 }
  }
  nav_log_on.val == 1
}

///|
/// MBUI_NAV_LOG as the process was given it, asked once (-1: not yet).
// kept across runs: the process's environment, the same for each
let nav_log_on : Ref[Int] = Ref(-1)

///|
/// A frame of the app, `body`: the system's bars as it wants them handed to the host once it is drawn (only as they
/// change: @hostapi.nav_bar), the page's actions in them, none where it wants none (a phone's frame).
pub fn nav_frame(body : () -> Unit) -> Unit {
  nav_want.val = None
  // (where the system lays out the app's tabs, the wide frame hands it them each frame (frame.mbt: on the tape) and it
  // takes them: the frame is laid out with them from the first it can, as the frames after it are, not one laid out
  // without them (the cards on the tape with no room for its column, the page past the window's edge) and the next
  // with them; what came of it said as the frame ends, as it hands them. Not counted on after a frame that left it
  // without them: one it refused, or one that handed none)
  if !@sf.native_bars.on && @sf.native_able() && !nav_untaken.val {
    @sf.native_bars.on = true
  }
  floating_bar.val = None
  @sf.native_over_clear()
  // (the column as the window is now, turned or not, before anything is laid out beside it)
  native_side_now()
  // (the page's actions as they were while the same page is shown: one built again hands them again)
  let page = app.nav.top()
  if nav_page_of.val != Some(page) {
    nav_page.clear()
    bar_chat_of.val = None
    nav_page_of.val = Some(page)
  }
  body()
  histories_ticked()
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
      if nav_logged() {
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
          { id: a.0, title: a.1, icon: @sf.icon_path(a.2), dot: false, prominent: over.active.contains(a.0), menu: [] }
        })
        { ..rail_nav(src, w, all, acts), bare: true, title: over.title }
      } else {
        rail_nav(src, w, all, card)
      }
      @sf.native_bars.on = @hostapi.nav_bar(bar)
      nav_untaken.val = @sf.native_able() && !@sf.native_bars.on
      floating_bar.val = Some(bar)
      native_side_now()
    }
    None => {
      @hostapi.nav_bar_none()
      nav_untaken.val = @sf.native_able()
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
fn rail_nav(src : Source, w : Workspace, _all : Array[Workspace], card : Array[@hostapi.NavItem]) -> @hostapi.NavBar {
  let places = rail_items(src, w.id)
  let lit = lit_place()
  let item = fn(id : String, title : String, icon : String) -> @hostapi.NavItem {
    { id, title, icon: @sf.icon_path(icon), dot: false, prominent: false, menu: [] }
  }
  // 对话, 文件, Station, 待处理 (the chats that want the viewer), 我的 (the settings, the other places' pages in them)
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
  // Workspace selection lives at the list heading; settings remains a separate action.
  let at = if @sf.native_side() { "act/" } else { "lead/" }
  tabs.push(item("settings", @sf.t("android-settings.title"), "settings"))
  // (待处理 a popover over the page, as the bell's: pressed, never chosen; in the column down the side, upright at the
  // bar's lead, left of the top, on the status bar's row: the user 2026-10-27)
  tabs.push({ ..item(at + "attention", rail_label(src, "attention"), "bell"), dot: bell_lit(src, w) })
  let selected = tab_of_place(lit)
  let t = @sf.theme()
  {
    floating: native_floating.val,
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
    "chats" | "mine" | "watching" | "archive" => "place/chats"
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
  column_short.set(@sf.native_side() && c.window_size().0 < column_short_below)
  // (the host says the screen's corner only where it lays out the tabs, ios_nav.h mb_host_window_corner; said once the
  // window is on the screen, what was kept before it is drawn anew, its corners its own then)
  let mut changed = false
  for k in 0..<4 {
    let r = if @sf.native_on() { @ui.window_corner_at(k) } else { 0.0 }
    if @sf.native_bars.corners[k] != r {
      @sf.native_bars.corners[k] = r
      changed = true
    }
  }
  if changed {
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
      bar_chat_of.val = None
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
    } else if id == "workspace-switch" {
      @sfpages.open_workspaces(src, Of(native_workspace_anchor.val), compact=true)
    } else if id == "sidebar/search" {
      switcher_toggle(c)
    } else if id.has_prefix("sidebar/filter/") {
      match id.substring(start=15) {
        "all" => rail_go(c, src, w, "chats")
        f => rail_go(c, src, w, f)
      }
    } else if id.has_prefix("ws/") {
      let ws = id.substring(start=3)
      if ws != w.id {
        // The frame still holds `w`: switching here would let land restore its chat into the new workspace.
        // Change after this build, so the next frame resolves the workspace before it lands on a page.
        c.tell("native-workspace", fn() { @sfpages.switch_workspace(src, ws) })
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
/// bell and the chat's complete menu. The workspace switch lives in the sidebar heading;
/// other page actions stay in their cards when the column has no room for them.
// kept across runs: said again each frame (native_frame), put back by rail_native_reset
let column_short : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// The outer screen's width and under (an iPhone Duo's, 466 across; its inner one on its side 951).
let column_short_below : Double = 600.0

///|
/// What this file keeps put back as the app begins anew (desk.mbt reset).
fn rail_native_reset() -> Unit {
  native_workspace_anchor.val = 0
  column_short.set(false)
  @sf.native_bars_reset()
  nav_want.val = None
  nav_untaken.val = false
  native_sidebar_items.clear()
  floating_bar.val = None
  native_floating.val = []
  nav_page.clear()
  bar_chat_of.val = None
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
