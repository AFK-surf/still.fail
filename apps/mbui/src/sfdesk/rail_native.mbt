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
/// The system's glass controls over the sidebar's band (native_glass_node), by the name of the anchor each is put at:
/// what it is now (None: none there).
let native_sidebar_items : Map[String, () -> @hostapi.NavItem?] = {}

///|
let floating_bar : Ref[@hostapi.NavBar?] = { val: None }

///|
let native_floating : Ref[Array[@hostapi.NavFloating]] = { val: [] }

///|
/// A box over which UIKit draws control `item` in its glass, as big as `style` says: put where the box is drawn each
/// frame (View::native_anchor, by `name`: native_workspace_placed), read out as a button.
fn native_glass_node(o : @view.View, name : String, style : () -> @ui.Style, item : () -> @hostapi.NavItem?) -> Unit {
  // (said again as each is built: a Tester starting anew lets go of what heard the anchors)
  @ui.on_native_anchors("sidebar glass", native_workspace_placed)
  native_sidebar_items[name] = item
  o.box(fn(b) {
    @sf.style_node(b, style)
    b.native_anchor(Is(name)) |> ignore
    b.says(By(fn() { item().map(fn(i) { @view.said(Button, label=i.title) }) })) |> ignore
  })
  |> ignore
}

///|
/// The workspace switch: its icon and name in one native glass capsule.
fn native_workspace_item(src : Source, w : Workspace) -> @hostapi.NavItem {
  let others = field((src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value, "others") is Some(String(_))
  {
    id: "workspace-switch", title: w.name, icon: ws_badge(w),
    dot: others || @sfpages.invitations_waiting(src).length() > 0, prominent: true, menu: [],
  }
}

///|
/// The controls the frame drew anchors for, handed to the system's bar where each was drawn, as the frame ends.
fn native_workspace_placed(c : @ui.Ctx, anchors : Array[(String, (Double, Double, Double, Double))]) -> Unit {
  guard floating_bar.val is Some(bar) else { return }
  let floating : Array[@hostapi.NavFloating] = []
  let blocked = @sf.presenter_visible()
  if !bar.bare && !switcher_open() && (!wide.tape || wide.tape_at.get() == Side) && !anchors.is_empty() {
    let semantics = c.semantics_tree()
    for a in anchors {
      let (name, (x, y, w, h)) = a
      match native_sidebar_items.get(name).bind(fn(f) { @signals.untracked(f) }) {
        Some(item) => {
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
          if !covered { floating.push({ item, x, y, w, h, blocked }) }
        }
        None => ()
      }
    }
  }
  native_floating.val = floating
  @hostapi.nav_bar({ ..bar, floating }) |> ignore
}

///|
/// A page's actions in the navigation bar (bar_action), in their order from the bar's end in, and what each does; the
/// ids bar_chat_waiting carried in for it from the chat before; the chat whose actions bar_chat handed (the chat's side
/// panel switch said again each frame by it: histories_ticked). Handed by a page's nodes at their causes (`node`: kept
/// till those let go of them, whatever page is on top meanwhile) or as a page's frame builds it (let go as it is no more
/// the page on top: nav_frame).
priv struct PageActs {
  page : Page
  acts : Array[(@hostapi.NavItem, () -> Unit)]
  carried : Array[String]
  mut chat : (Source, ChatRef)?
  mut node : Bool
}

///|
/// The pages' actions in the navigation bar, each page's its own (PageActs): the bars hand the page on top's.
// kept across runs: put back as the app begins anew (rail_native_reset)
let page_acts : Array[PageActs] = []

///|
/// Page `page`'s actions, made empty as it first hands one.
fn acts_of(page : Page) -> PageActs {
  match page_acts.iter().find_first(fn(a) { a.page == page }) {
    Some(a) => a
    None => {
      let a = { page, acts: [], carried: [], chat: None, node: false }
      page_acts.push(a)
      a
    }
  }
}

///|
/// The page on top's actions (acts_of).
fn top_acts() -> PageActs {
  acts_of(app.nav.top())
}

///|
/// Whether the frame that hands the system its bars is being built (nav_frame): what a page's nodes hand meanwhile
/// handed with the rest as it ends.
let nav_framing : Ref[Bool] = { val: false }

///|
/// What `f` hands as page `page`'s actions, at its cause (a page's node's): handed to the system there and then where
/// that changed what the page on top has in the bars (once a frame said what the bars hold: nav_want), not by a frame
/// built again for it.
fn page_acts_told(page : Page, f : () -> Unit) -> Unit {
  let was = acts_of(page).acts.map(fn(p) { p.0 })
  f()
  if nav_framing.val || nav_want.val is None || page != app.nav.top() || acts_of(page).acts.map(fn(p) { p.0 }) == was {
    return
  }
  histories_ticked()
  let handed = top_acts().acts.copy()
  nav_page_before.clear()
  nav_page_before.append(handed)
  nav_hand(handed)
}

///|
/// A page's actions its frame built let go as another comes on top (a node's kept: what handed them lets them go).
fn page_acts_left(top : Page) -> Unit {
  page_acts.retain(fn(a) { a.node || a.page == top })
}

///|
/// Page `page`'s actions its nodes handed let go (their node let go: the page gone from the stack).
fn page_acts_gone(page : Page) -> Unit {
  page_acts.retain(fn(a) { !(a.node && a.page == page) })
}

///|
let nav_page_was : Map[String, () -> Unit] = {}

///|
/// What each row of a page's action's menu does (bar_action rows), by the row's id, for what is chosen between frames.
let nav_rows_was : Map[String, () -> Unit] = {}

///|
/// What is up over the whole window handed the bars the frame before (@sf.native_over_act), by id, for what is chosen
/// between frames.
let nav_over_was : Map[String, () -> Unit] = {}

///|
/// The page of the stack being drawn now (frame.mbt's nav_flat), None outside one.
let drawn_page : Ref[Page?] = { val: None }

///|
/// Whether the page on top was drawn this frame: not while the one it came over is still shown in its place, its
/// coming held for what it shows (Nav::comes_when).
let top_drawn : Ref[Bool] = { val: false }

///|
/// The page's actions the frame before, as handed (nav_page), for a frame the page on top is not drawn in.
let nav_page_before : Array[(@hostapi.NavItem, () -> Unit)] = []

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
/// in the system's bars; `act` what it does chosen. With `rows`, a menu of the system's own opened from it instead (a
/// chat's "…": its items as the page's menu has them, None a line between groups; each chosen runs its own), which
/// the system keeps as a menu where it folds the column's actions into one of its own, short of room (a "…" of its
/// own among them, its rows a press away, not a "…" beside the system's and not a row opening a sheet of the page's:
/// the user, 2026-11-03). A page on its way out (a stack's move) hands none: the one on top does.
fn bar_action(
  id : String,
  title : String,
  icon : String,
  act : () -> Unit,
  raw? : String,
  rows? : Array[@sf.MenuItem?],
  dot? : Bool = false,
  page? : Page,
) -> Bool {
  if page is None && drawn_page.val is Some(p) && p != app.nav.top() {
    return false
  }
  let acts = acts_of(page.unwrap_or(app.nav.top())).acts
  let key = "page/" + id
  match acts.search_by(fn(p) { p.0.id == key }) {
    Some(i) => acts.remove(i) |> ignore
    None => ()
  }
  // Even the short system column needs its entries to the chat's info and menu. (Read as the page is built: the column
  // come to be short or no longer, what built it builds again and hands as it is now, what it handed before not left
  // in the bars.)
  if !@sf.native_on() || (column_short.get() && id != "chat/info" && id != "chat/more") {
    return false
  }
  let data = match raw {
    Some(d) => d
    None => @sf.icon_path(icon)
  }
  let menu : Array[(String, String, Bool, String)] = []
  match rows {
    Some(rows) => {
      let mut n = 0
      for row in rows {
        match row {
          Some(item) => {
            let rid = key + "/" + n.to_string()
            n += 1
            menu.push((rid, item.label, item.chosen == Some(true), @sf.icon_path(item.icon)))
            nav_rows_was[rid] = item.select
          }
          // (a line between groups: after a row only, as the page's menu draws it)
          None => if menu.length() > 0 && menu[menu.length() - 1].0 != "-" { menu.push(("-", "", false, "")) }
        }
      }
      // (no line closing the menu)
      if menu.length() > 0 && menu[menu.length() - 1].0 == "-" {
        menu.pop() |> ignore
      }
    }
    None => ()
  }
  acts.push(({ id: key, title, icon: data, dot, prominent: false, menu }, act))
  true
}

///|
/// A chat's actions in the system's bars, each its own button there being room (the user, 2026-10-28): its "…" (a
/// menu of the system's own: `rows` its items, `more` what opens with none of them), its info, its side panel's
/// switch (opening the first agent's history, or closing all its tabs), its services and jobs where it has them
/// (`jobs`: what opens them, with a dot while one is in trouble; the user 2026-11-04, 地球图标收进「…」), its station's
/// screens where it has them (`screen`: what opens them, with a dot while an agent drives one; the user 2026-11-03,
/// 共享屏幕没放到侧边栏),
/// archiving it where it may be.
/// In place of its buttons (who is in it and where it runs stay by its
/// title, as the desktop's); false where there are no system's bars (the page draws its own).
fn bar_chat(
  src : Source,
  r : ChatRef,
  agents : Array[Agent],
  info : () -> Unit,
  rows : Array[@sf.MenuItem?],
  more : () -> Unit,
  jobs : (() -> Unit, Bool)?,
  screen : (() -> Unit, Bool)?,
  archive : (() -> Unit)?,
  page? : Page,
) -> Bool {
  if !@sf.native_on() {
    return false
  }
  if page is None && drawn_page.val is Some(p) && p != app.nav.top() {
    return true
  }
  let pa = acts_of(page.unwrap_or(app.nav.top()))
  if page is Some(_) {
    pa.node = true
  }
  pa.chat = Some((src, r))
  // This is the chat's complete set, including absent optional actions. The previous view may have handed its
  // actions itself while kept on screen, rather than through bar_chat_waiting; none of those may remain either.
  pa.acts.retain(fn(p) { !p.0.id.has_prefix("page/chat/") })
  pa.carried.clear()
  bar_action("chat/more", @sf.t("common.more"), "more", more, rows?=if rows.iter().any(fn(i) { i is Some(_) }) { Some(rows) } else { None }, page?) |> ignore
  bar_action("chat/info", @sf.t("web-pages.chat.info"), "info", info, page?) |> ignore
  let (tabs, _) = side_now(src, r)
  // (a screen alone in its panel has no × of its own there: this one, as one)
  let icon = if screen_tab_alone(tabs) { "close" } else if tabs.length() > 0 { "panel-close" } else { "panel-open" }
  let title = @sf.t(if tabs.length() > 0 { "web-pages.chat.closePanel" } else { "web-pages.chat.openPanel" })
  if agents.length() > 0 || tabs.length() > 0 {
    let key = if agents.length() > 0 { Some(agents[0].key) } else { None }
    bar_action(history_item, title, icon, fn() {
      let (now, _) = side_now(src, r)
      if now.length() > 0 {
        side_change(src, r, "clear", None)
      } else if key is Some(_) {
        side_change(src, r, "open", key)
      }
    }, page?) |> ignore
  }
  match jobs {
    Some((act, alarm)) => bar_action("chat/jobs", @sf.t("web-pages.chat.services"), "web", act, dot=alarm, page?) |> ignore
    None => ()
  }
  match screen {
    Some((act, driven)) => bar_action("chat/screen", @sf.t("web-pages.chat.screen"), "monitor", act, dot=driven, page?) |> ignore
    None => ()
  }
  match archive {
    Some(act) => bar_action("chat/archive", @sf.t("web-pages.chat.archive"), "archive", act, page?) |> ignore
    None => ()
  }
  true
}

///|
/// A chat whose view is not read yet (another chat just opened): the actions the chat before it handed, as they were,
/// till its own come, so the system's column keeps its buttons in place rather than taking them away and bringing them
/// back (each brought back is a button made anew, faded in: the user, 2026-10-31, 按钮没变也会闪). Pressed meanwhile,
/// nothing. False where there are no system's bars.
fn bar_chat_waiting(page? : Page) -> Bool {
  if !@sf.native_on() {
    return false
  }
  if page is None && drawn_page.val is Some(p) && p != app.nav.top() {
    return true
  }
  let pa = acts_of(page.unwrap_or(app.nav.top()))
  if page is Some(_) {
    pa.node = true
  }
  for item in bar_chat_last {
    // (as bar_action hands them: the short column the info alone)
    if column_short.get() && item.id != "page/chat/info" && item.id != "page/chat/more" {
      continue
    }
    if !pa.acts.iter().any(fn(p) { p.0.id == item.id }) {
      pa.acts.push((item, fn() {  }))
      pa.carried.push(item.id)
      // (its menu's rows kept as they were, the other chat's: pressed meanwhile, nothing)
      for m in item.menu {
        nav_rows_was.remove(m.0)
      }
    }
  }
  true
}

///|
/// The chat's actions as the last chat whose view was read handed them (bar_chat_waiting).
// kept across runs: said by nav_frame as a chat hands its own, put back as the app begins anew (rail_native_reset)
let bar_chat_last : Array[@hostapi.NavItem] = []

///|
/// The chat's side panel switch in the system's bars (bar_chat).
let history_item : String = "chat/history"

///|
/// The open side panel's close in the short column (histories_ticked).
let side_close_item : String = "side/close"

///|
/// The chat's side panel switch as the panel is this frame (its icon and words open or closed): said again each
/// frame, the page that handed it kept as it was drawn or not (its part kept while the panel
/// changes).
fn histories_ticked() -> Unit {
  let pa = top_acts()
  guard pa.chat is Some((src, r)) else { return }
  let nav_page = pa.acts
  let (tabs, _) = side_now(src, r)
  let icon = @sf.icon_path(if screen_tab_alone(tabs) { "close" } else if tabs.length() > 0 { "panel-close" } else { "panel-open" })
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
  // (the short column has no switch of its own: the open panel's close there in place of the panel's own (side_panel).
  // Handed last, each frame: short of room the system keeps the last of them whatever its priority, and the page handing
  // its own again puts them after it: the user, 2026-11-04)
  let key = "page/" + side_close_item
  nav_page.retain(fn(p) { p.0.id != key })
  if column_short.get() && tabs.length() > 0 {
    let item : @hostapi.NavItem = {
      id: key,
      title: @sf.t("web-pages.chat.closePanel"),
      icon: @sf.icon_path("close"),
      dot: false,
      prominent: false,
      menu: [],
    }
    nav_page.push((item, fn() { side_change(src, r, "clear", None) }))
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
/// What opens from one of the page's actions as a menu of the page's (a station's screens): as bar_anchor's. A menu goes
/// under what opened it, so beside the column down the side it opens from the point left of the item, ending there,
/// not under the item and over the column (the user, 2026-11-04); `id` where the page has its own.
fn bar_menu_from(c : @ui.Ctx, id : Int) -> (@sf.Beside, @ui.Along) {
  if !@sf.native_on() || native_mark.val == 0 {
    return (Of(id), End)
  }
  if @sf.native_side() {
    let (x, y, _) = native_mark_at(c)
    (@sf.at_point(x - @sf.panel_offset, y), End)
  } else {
    (Of(native_mark.val), End)
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
  @sf.native_bars.side.set(if @sf.native_bars.on.get() { dmax(0.0, @ui.system_bars().right) } else { 0.0 })
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
  // (held by the tape while it shows: its frame is the window's tree's, what is under its panels built as what it reads
  // changes, not each frame: tape_view.mbt)
  nav_want.val = (nav_held.val)()
  // (where the system lays out the app's tabs, the wide frame hands it them each frame (frame.mbt: on the tape) and it
  // takes them: the frame is laid out with them from the first it can, as the frames after it are, not one laid out
  // without them (the cards on the tape with no room for its column, the page past the window's edge) and the next
  // with them; what came of it said as the frame ends, as it hands them. Not counted on after a frame that left it
  // without them: one it refused, or one that handed none)
  if !@signals.untracked(fn() { @sf.native_bars.on.get() }) && @sf.native_able() && !nav_untaken.val {
    @sf.native_bars.on.set(true)
  }
  floating_bar.val = None
  // (the column as the window is now, turned or not, before anything is laid out beside it)
  native_side_now()
  // (the page's actions as they were while the same page is shown: one built again hands them again)
  let page = app.nav.top()
  if nav_page_of.val != Some(page) {
    page_acts_left(page)
    nav_page_of.val = Some(page)
  }
  top_drawn.val = false
  nav_framing.val = true
  body()
  nav_framing.val = false
  // (what is up over the whole window as it said it, built again this frame or its part kept; gone once it is not)
  @sf.native_over_gone()
  // (the page come not drawn yet, the one before it still shown in its place: that one's actions kept in the bars as
  // they were, not taken away for a frame and brought back made anew, faded in: the user, 2026-10-31, 按钮没变也会闪)
  histories_ticked()
  // (one made once in the pane shows, built by no frame: what it hands, none)
  let made_top = pane_made_shown() is Some(_)
  let pa = top_acts()
  let nav_page = pa.acts
  let handed = if !top_drawn.val && !made_top && !pa.node && nav_page.is_empty() { nav_page_before.copy() } else { nav_page.copy() }
  nav_page_before.clear()
  nav_page_before.append(handed)
  nav_hand(handed)
}

///|
/// The page's actions `handed` to the system's bars, with the places and what is up over the whole window (nothing
/// where the frame wants none: nav_want).
fn nav_hand(handed : Array[(@hostapi.NavItem, () -> Unit)]) -> Unit {
  let pa = top_acts()
  let nav_page = pa.acts
  // (a chat's own as it handed them, not one on its way out handing none, nor what was kept for it)
  if pa.chat is Some(_) && pa.carried.length() == 0 && nav_page.iter().any(fn(p) { p.0.id.has_prefix("page/chat/") }) {
    bar_chat_last.clear()
    for p in nav_page {
      if p.0.id.has_prefix("page/chat/") {
        bar_chat_last.push(p.0)
      }
    }
  }
  nav_page_was.clear()
  for p in handed {
    nav_page_was[p.0.id] = p.1
  }
  match nav_want.val {
    Some((src, w, all)) => {
      // at the column's top the card in use's own: the chats' list's filter while it is, the page's actions while it is
      // (the page's actions said native: bar_action; the chats' list's filter stays in its card, the user 2026-10-27)
      // (a chat's agents first, on a glass of their own; its other actions, its ⋯, under them: the user 2026-10-27)
      let page = handed.filter(fn(p) { p.0.id.has_prefix("page/who/") })
      page.append(handed.filter(fn(p) { !p.0.id.has_prefix("page/who/") }))
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
      let on = @hostapi.nav_bar(bar)
      @sf.native_bars.on.set(on)
      nav_untaken.val = @sf.native_able() && !on
      floating_bar.val = Some(bar)
      native_side_now()
    }
    None => {
      @hostapi.nav_bar_none()
      nav_untaken.val = @sf.native_able()
      @sf.native_bars.on.set(false)
      @sf.native_bars.side.set(0.0)
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
    // (at the bell where the system says it is; else where the column has it: moved there as an item is chosen,
    // @sfbase.nav_tapped_said)
    @sfbase.nav_tapped_said.get() |> ignore
    let (tx, ty, th) = native_mark_at(c)
    let id = c.id("rail/attention")
    native_mark.val = id
    c.box(style=@ui.style(w=Fixed(native_mark_w), h=Fixed(th)), tx~, ty~, id~, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// Where the mark is: at the item last chosen, else where the column has the bell (its x, y and height).
fn native_mark_at(c : @ui.Ctx) -> (Double, Double, Double) {
  let at = @hostapi.nav_tapped_at
  if at[2] > 0.0 {
    (at[0], at[1], at[3])
  } else {
    let (ww, wh) = c.window_size()
    (dmax(0.0, ww - @sf.native_clear() - 1.0), dmax(0.0, wh - native_bell_up), 40.0)
  }
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
        items: [{ ..item("new", @sf.t("web-main.sidebar.newChat"), "plus"), prominent: true }],
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
  let now = FixedArray::makei(4, fn(k) { if @sf.native_on() { @ui.window_corner_at(k) } else { 0.0 } })
  if @signals.untracked(fn() { @sf.native_bars.corners.get() }) != now {
    // (told to what is drawn round by them, the window's tree's too; what was kept of the old frame's drawn anew)
    @sf.native_bars.corners.set(now)
    c.forget_parts()
  }
  rail_native_taps(c, src, w)
}

///|
/// What was chosen in the system's bars since the last frame: a place gone to as the rail's pressed (rail_go), the
/// settings opened, another workspace switched to.
fn rail_native_taps(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // (read so: this island built again as one is chosen, @sfbase.nav_tapped_said)
  @sfbase.nav_tapped_said.get() |> ignore
  let taps = @sfbase.nav_tapped.copy()
  @sfbase.nav_tapped.clear()
  // (another page come to by what was chosen, mid-frame: the actions the one left handed in frames before not its; the
  // one come to hands its own as it is drawn after this: nav_frame)
  defer {
    if nav_page_of.val != Some(app.nav.top()) {
      page_acts_left(app.nav.top())
      nav_page_of.val = Some(app.nav.top())
    }
  }
  for id in taps {
    // (anything else chosen in the bars closes 待处理's panel, as a tap off a popover of the system's does)
    if id != "act/attention" && id != "lead/attention" {
      attention_set(false)
    }
    // (a tab left keeps what it showed, given back as it is chosen again; the one shown chosen again changes nothing,
    // as the system's tab apps have it: the user, 2026-10-26)
    let now = tab_of_place(lit_place())
    if id.has_prefix("place/") && id != now {
      tabs_kept[tab_kept_key(w.id, now)] = app.nav.pages()
      // (what was open over the tab left closed with it: a chat's ⋯, a menu)
      chat_own.info_open.set(false)
      chat_own.jobs_open.set(false)
      @sf.close_all_presented()
    }
    if id == now {
      ()
    } else if id == "settings" {
      if lit_place() != "settings" {
        open_settings()
      }
    } else if id == "workspace-switch" {
      @sfpages.open_workspaces(src, match @ui.native_anchor_drawn("side/workspaces") {
        Some((x, y, w, h)) => At(x, y, w, h)
        None => Unanchored
      }, compact=true)
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
          wide.landed.set("")
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
        // (a row of an action's menu: bar_action rows)
        None =>
          match nav_rows_was.get(id) {
            Some(act) => act()
            None => ()
          }
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
/// Where the frame hands the system's bars the places and the page's actions while the tape shows, whatever of the old
/// view is built that frame (tape_view.mbt): the workspace in view and all of them, as they are then; None off it.
// kept across runs: put back as a run begins (rail_native_reset)
let nav_held : Ref[() -> (Source, Workspace, Array[Workspace])?] = Ref(fn() { None })

///|
/// The bars held by the frame made once in the window's tree (the tape's, the pane's): what is under it is an island,
/// built as what it reads changes, not each frame; handed none in a frame that did not build it, the host would take
/// the app's view out of the tabs and put it back, and a finger on it would never be told it went up.
fn nav_hold(src : Source) -> Unit {
  nav_held.val = fn() {
    if !@sf.native_able() {
      return None
    }
    match @sfbase.workspace_in_view(src) {
      (Some(w), all, _, _) => Some((src, w, all))
      _ => None
    }
  }
}

///|
/// What this file keeps put back as the app begins anew (desk.mbt reset).
fn rail_native_reset() -> Unit {
  column_short.set(false)
  @sf.native_bars_reset()
  nav_want.val = None
  nav_held.val = fn() { None }
  nav_untaken.val = false
  native_sidebar_items.clear()
  floating_bar.val = None
  native_floating.val = []
  page_acts.clear()
  nav_page_was.clear()
  nav_rows_was.clear()
  nav_over_was.clear()
  drawn_page.val = None
  nav_page_of.val = None
  bar_chat_last.clear()
  nav_page_before.clear()
  top_drawn.val = false
  native_mark.val = 0
  // (where the system said an item was last chosen: none yet, what opens from one by the bell till one says so)
  for k in 0..<4 {
    @hostapi.nav_tapped_at[k] = 0.0
  }
  tabs_kept.clear()
  nav_log_was.val = ""
  attention_size[0] = 0.0
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
