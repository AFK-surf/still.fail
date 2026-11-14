// The rail at the wide frame's left, in one block with the sidebar (frame.mbt
// dock): its top row (in a window with its buttons in the app's top row, their row, dragging the window), the places
// the person chose on this device as the core has them (prefs `railView`: which, their words and kinds, their order;
// the rail only draws them), at its foot every workspace to switch to (each with what waits in it; a ＋ over them for
// making one, another account, invitations) and the settings. It is changed where it is: its menu (a right click) goes
// to the places left out and takes one out, its 自定义侧边条 has the places dragged up and down, taken out with their −
// and added from a panel beside it by kind. And the sidebar's edge (SidebarEdge), dragged for its width, pressed to
// fold it or open it again.

///|
/// The rail as the core says it is drawn (prefs `railView`: core-ts rail.ts railView): every place, its words and kind,
/// the kinds the panel that adds them groups them by, the default, the rail of a workspace with none of its own (`all`)
/// and each one's own (`by`).
fn rail_view(src : Source) -> Json? {
  field(src.topic("prefs", {}).get().value, "railView")
}

///|
/// Workspace `ws`'s rail (railView's `by` its own, else `all`): its places in order (`items`), those left out
/// (`hidden`), whether it is other than the default (`changed`).
fn rail_of(src : Source, ws : String) -> Json? {
  let v = rail_view(src)
  match field(field(v, "by"), ws) {
    Some(Object(_)) as own => own
    _ => field(v, "all")
  }
}

///|
/// A list of words (a JSON array of strings).
fn words_in(a : Array[Json]) -> Array[String] {
  a.filter_map(fn(x) {
    match x {
      String(s) => Some(s)
      _ => None
    }
  })
}

///|
/// The rail's places in workspace `ws`, in their order.
pub fn rail_items(src : Source, ws : String) -> Array[String] {
  words_in(items(rail_of(src, ws), "items"))
}

///|
/// Every place the rail can show, in the order its settings list them (railView's `places`).
fn rail_places(src : Source) -> Array[String] {
  items(rail_view(src), "places").map(fn(p) { text(Some(p), "id") })
}

///|
/// A place's words (its tip, its menu's row): as the core says them.
fn rail_label(src : Source, place : String) -> String {
  match items(rail_view(src), "places").search_by(fn(p) { text(Some(p), "id") == place }) {
    Some(i) => text(Some(items(rail_view(src), "places")[i]), "label")
    None => place
  }
}

///|
/// Whether the place has no sidebar: its page is the pane's whole (连接).
pub fn place_bare(place : String) -> Bool {
  place == "connects" || place == "usage"
}

///|
/// The place lit in the rail: what the stack's root is, settings while a settings page is open.
pub fn lit_place() -> String {
  let pages = app.nav.pages()
  for p in pages {
    match p {
      Settings | Setting(_) => return "settings"
      _ => ()
    }
  }
  // the place of the page nearest the top that has one
  let mut k = pages.length() - 1
  while k >= 0 {
    match pages[k] {
      Files | Drive(_) | DriveRead(_) | DrivePlay(_) => return "files"
      Place(p) => return p
      // 已归档: one of the chats' lists
      Home | Chat(_) | NewChat | Archived => return "chats"
      _ => ()
    }
    k = k - 1
  }
  "chats"
}

///|
/// The places the rail shows: its own, and a place left out of it but in view at their foot while it is (not while the
/// rail is changed).
fn rail_shown(src : Source, w : Workspace) -> Array[String] {
  let places = rail_items(src, w.id)
  let in_view = rail_in_view(src, w)
  let shown = places.copy()
  if in_view != "" && !places.contains(in_view) && !wide.editing.get() {
    shown.push(in_view)
  }
  shown
}

///|
/// Whether `place` is lit in the rail now: the lit place's; a list's while its list is the one shown
/// (我参与的, 监控中 by the filter when they are in the rail, else 对话; 已归档 while the archive is open: shownList).
fn rail_lit(src : Source, w : Workspace, place : String) -> Bool {
  let lit = lit_place()
  match place {
    "chats" | "mine" | "watching" | "hidden" | "archive" => {
      let list = list_place(list_mode(src, w))
      let shown_list = if rail_shown(src, w).contains(list) { list } else { "chats" }
      lit == "chats" && shown_list == place
    }
    _ => lit == place
  }
}

///|
/// The place whose sidebar the block holds (what it draws, the width of its group), the archive's list its own
/// ("archive", list_place's): the lit place's; in a place with none of its own (place_bare), the one it had, which the
/// block closes holding (the web's WorkspaceShell `kept`), not the chats' list it would fall to: nothing opens the
/// sidebar there. The frame keeps it as it is built (wide.side_place).
pub fn side_place() -> String {
  let lit = lit_place()
  if place_bare(lit) {
    wide.side_place
  } else if lit == "chats" && app.nav.pages().contains(Archived) {
    "archive"
  } else {
    lit
  }
}

///|
/// Which of the lists is shown (the sidebar's mode): 全部 0, 我参与的 1, 监控中 2 (the
/// filter), 已归档 3.
pub fn list_mode(src : Source, w : Workspace) -> Int {
  match side_place() {
    "archive" => 4
    _ =>
      match filter_of(src, w.id) {
        "mine" => 1
        "watching" => 2
        "hidden" => 3
        _ => 0
      }
  }
}

///|
/// The rail's place of the list shown (Rail.tsx listed(mode)).
fn list_place(mode : Int) -> String {
  match mode {
    1 => "mine"
    2 => "watching"
    3 => "hidden"
    4 => "archive"
    _ => "chats"
  }
}

///|
/// The rail's top row's height (in a panel of the tape its first place as far under its top as its places are in from
/// its side; closed, none).
fn rail_top_h(bar : Bool) -> Double {
  if bar {
    0.0
  } else if @ui.window_keys_left() && wide.tape.get() {
    // (its first place's middle on the line of the sidebar's first row beside it, under the window's buttons: worked
    // out as that row's is, not read back from the frame's)
    tape_brand_under_buttons() + band_new_top + band_row_h() / 2.0 - rail_item_side / 2.0
  } else if @ui.window_keys_left() {
    dmax(rail_top_inset + rail_gap, @ui.window_points_to_content(side_top_inset))
  } else if wide.tape.get() {
    // (and its first place's middle on the line of the sidebar's first row beside it, 新建对话's: pengxiao, 2026-10-25)
    dmax(@sf.rail_in_tape(), tape_first_row_mid() - rail_item_side / 2.0)
  } else {
    rail_top_corner()
  }
}

///|
/// The open rail's top row where nothing stands over its first place (no window buttons at its left, off the tape): as
/// tall as its places are in from the window's side (rail_window_in), so its first place's ground stands as far under
/// the window's top as it is in from its side, concentric with the window's corner (the user, 2026-11-09: 新建对话往上挪一点).
fn rail_top_corner() -> Double {
  rail_window_in()
}

///|
/// The closed bar's padding round its places (rail_closed's p=S0_5).
let rail_closed_pad : Double = 2.0

///|
/// How far in from the closed bar's edges its places' grounds stand: its 2 (rail_closed), a place's 38 less its 30.
let rail_closed_ground_in : Double = 2.0 + rail_ground_in

///|
/// How far in from a place's edges its ground stands (its 38 less its 30).
let rail_ground_in : Double = (rail_item_side - rail_sq_side) / 2.0

///|
/// How wide the rail is drawn in the block (its look's width, its padding in it), what the sidebar stands beside: where
/// the block's move has got (`moving`: pane_view.mbt's FoldLook, as rail draws it then); else closed, the bar's; on the
/// tape, its panel's (rail_open_tape); open, as far in from the window's corner as its places stand (rail_window_in).
fn rail_box_w(bar : Bool, moving : FoldLook?) -> Double {
  match moving {
    Some(f) => f.rail_w
    None =>
      if bar {
        rail_closed_w
      } else if wide.tape.get() {
        rail_shown_w + rail_tape_more()
      } else {
        rail_shown_w + rail_window_in() - rail_in_px
      }
  }
}

///|
/// The rail's inset open (rail_in: 8).
let rail_in_px : Double = 8.0

///|
/// The open rail's place in the window's corner: its ground follows that corner where the system's corner and the
/// theme's ranges allow it. When the ground is round, its centre follows the system's circular corner instead.
fn rail_window_in() -> Double {
  let window : @ui.CornerOf = Window
  let corner = window.radius(@ui.corner_roots())
  let base = closed_bar_in + rail_closed_ground_in
  if corner <= base {
    return base - rail_ground_in
  }
  let (at, radius) = @sf.box_fit(corner, base, 0.0)
  let at = if corner > 0.0 && radius >= rail_sq_side / 2.0 - 0.5 {
    corner - rail_sq_side / 2.0
  } else {
    at
  }
  at - rail_ground_in
}

///|
/// How much more of the rail shows on the tape (its places further in: rail_open_tape), the sidebar as much narrower.
fn rail_tape_more() -> Double {
  @sf.rail_in_tape() - rail_in_px
}

///|
/// What of the rail shows beside the sidebar open: its 56 less the 8 the sidebar reaches over.
let rail_shown_w : Double = 48.0

///|
// kept across runs: a value (no field of it changes)
let rail_places_col : @ui.Style = @ui.css("gap=S1_5 align=AStart")

///|
/// A place lit in the closed bar: the words' colour at 12% (Rail.css.ts item, closed: color-mix(text 12%)).
let lit_in_bar : Double = 0.12

///|
/// The rail's places 6 apart; its top row 41 under the window's buttons (else rail_top_corner).
let rail_gap : Double = 6.0

///|
let rail_top_inset : Double = 41.0

///|
/// A place's icon (20).
let rail_icon_size : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let rail_item : @ui.Style = @ui.style(w=Fixed(rail_item_side), h=Fixed(rail_item_side), align=ACenter, justify=JCenter)

///|
let rail_item_side : Double = 38.0

///|
// kept across runs: a value (no field of it changes)
let rail_sq : @ui.Style = @ui.style(w=Fixed(rail_sq_side), h=Fixed(rail_sq_side), align=ACenter, justify=JCenter)

///|
let rail_sq_side : Double = 30.0

///|
/// The room a mark hangs in, its middle the corner's: as large as the largest with its disc (a ring 10 across, 2 round
/// it), each centred in it.
let rail_hung_side : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let rail_hung_room : @ui.Style = @ui.style(
  w=Fixed(rail_hung_side),
  h=Fixed(rail_hung_side),
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let rail_hung_ring : @ui.Style = @ui.css("p=S0_5 radius=Full")

///|
let mark_folded_from : Double = 0.4

///|
/// The sidebar's ground where it is a panel of its own: the closed bar's, floating over the page (closed_ground); on
/// the tape, a panel beside the page's as it is, the page's ground, which a phone's lists and pages share (the user,
/// 2026-10-25: the medium screen's grounds the phone's, no other colours).
pub fn apart_ground() -> Int64 {
  if wide.tape.get() {
    @sf.theme().p.bg
  } else {
    closed_ground()
  }
}

///|
/// The closed bar's ground (a floating panel's: the canvas, raised in the dark).
pub fn closed_ground() -> Int64 {
  let t = @sf.theme()
  if t.dark {
    t.p.raised
  } else {
    t.p.canvas
  }
}

///|
/// What waits on a place: a red dot 8 across hung on its ground's corner.
// kept across runs: a value (no field of it changes)
let rail_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Danger")

///|
/// Whether place `place` has a card as the pointer rests on it (the core's `railCard`: 对话, 用量; 2026-10-26 用户「stations
/// 和 profiles tab 的 hover 卡片去掉吧」); the others keep their tip.
fn rail_carded(place : String) -> Bool {
  place == "chats" || place == "usage"
}

///|
/// Back to the stack's root as another workspace comes into view: what is over the pages put down, the menu closed.
fn desk_home() -> Unit {
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
}

///|
/// A place gone to, from the rail or its menu: 待处理 its panel; a list of chats
/// its list in the sidebar, the chat last open beside it; 已归档 the archive; the others their page.
pub fn rail_go(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  rail_go_told(src, w, place, fn(key, f) { c.tell(key, f) })
}

///|
/// rail_go's, what it keeps in the prefs done by `tell` (an old view's build: once, whichever build asked; a node's
/// press: at once).
fn rail_go_told(src : Source, w : Workspace, place : String, tell : (String, () -> Unit) -> Unit) -> Unit {
  match place {
    "attention" => {
      attention_set(!wide.attention_open.get())
    }
    "chats" | "mine" | "watching" | "hidden" => {
      // its list in the sidebar: 对话 all of them, the others theirs
      let f = if place == "chats" { "all" } else { place }
      if filter_of(src, w.id) != f {
        app.filters[w.id] = f
        // (kept once, whichever build asked: Ctx::tell)
        tell("rail/list-filter", fn() {
          (src.call)("prefs.set", Json::object({ "listFilter": Json::object(Map::from_array([(w.id, Json::string(f))])) }), @sfbase.answer_unread)
        })
      }
      // the chats again: the chat last open stays open beside the list
      if app.nav.pages()[0] == Home && lit_place() == "chats" && !app.nav.pages().contains(Archived) {
        ()
      } else {
        @sfbase.go_place("chats") |> ignore
        wide.landed.set("")
      }
    }
    "archive" => {
      @sfbase.history_push()
      archive_side.landed = false
      app.nav.replace_above(1, [Archived])
    }
    p => @sfbase.go_place(p) |> ignore
  }
}

///|
/// The rail kept (`prefs.set {rails: {workspace: [...]}}`, on this device).
fn rail_keep(src : Source, ws : String, items : Array[String]) -> Unit {
  (src.call)(
    "prefs.set",
    { "rails": Json::object(Map::from_array([(ws, Json::array(items.map(fn(i) { Json::string(i) })))])) },
    fn(_) {  },
  )
}

///|
/// The place in view that is left out of the rail, if one is: a list shown (我参与的, 监控中, the archive; the chats'
/// when 对话 is out), the files, a place picked from the rail's menu (setExtra); "" none.
fn rail_in_view(src : Source, w : Workspace) -> String {
  let lit = lit_place()
  let in_view = if lit == "chats" {
    list_place(list_mode(src, w))
  } else if rail_places(src).contains(lit) {
    lit
  } else {
    ""
  }
  if rail_items(src, w.id).contains(in_view) {
    ""
  } else {
    in_view
  }
}

///|
/// What opens from the rail, over the frame (drawn after it, with the app's: sfapp's wide_overlays): its menu and,
/// while it is changed, what can be added beside it; the ＋'s menu and the list of what comes and goes.
pub fn rail_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  rail_menu(c, src, w)
  rail_adder(c, src, w)
  // (what opens from its foot's keys, nodes of the window's tree: beside where each was as it was pressed, else where it
  // is now)
  if !@sf.native_on() {
    let at = match (workspace_add_from.val, rail_add.val) {
      (Some(r), _) => r
      (None, Some(v)) if v.alive() => v.placed_window_now()
      _ => (0.0, 0.0, 0.0, 0.0)
    }
    @sfpages.workspace_menu(c, src, at)
    rail_transfers_list(src, w)
  }
}

///|
/// The rail's menu opened as a right click on `place` opens it (sffix's rail-menu).
pub fn open_rail_menu(place : String) -> Unit {
  wide.rail_menu.set(Some((place, rail_place_at(place))))
}

///|
/// The menu as last drawn open, held while it goes out so its contents and anchor do not change during its exit.
priv struct RailMenuDrawn {
  place : String
  from : (Double, Double, Double, Double)?
  kept : Array[String]
  entries : Array[@kit.Entry]
  icons : Map[String, String]
  mut replaced : Bool
}

///|
// kept across runs: put back by wide_reset
let rail_menu_drawn : Ref[RailMenuDrawn?] = Ref(None)

///|
/// The rail's menu (from a right click on it), beside the place right clicked (else its
/// first), 8 past it, clear of the window's buttons' row: the places not in it (pressed, their page; their ＋, shown on
/// the row pointed at, puts one in it and the rail is changed from there), 从侧边条移除 the place right clicked,
/// 自定义侧边条, 侧边条恢复默认 when it was changed.
fn rail_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let showing = wide.rail_menu.get()
  let drawn = match showing {
    Some((place, from)) => {
      let kept = rail_items(src, w.id)
      // (提醒 is no page, nor the one in view at the rail's foot: put in from 自定义侧边条)
      let extra = rail_in_view(src, w)
      let away = rail_places(src).filter(fn(i) { !kept.contains(i) && i != "attention" && i != extra })
      let entries : Array[@kit.Entry] = []
      let icons : Map[String, String] = Map([])
      if away.length() > 0 {
        entries.push(@kit.menu_label(@sf.t("web-main.rail.away")))
        for i in away {
          entries.push(@kit.menu_item("go:" + i, label=rail_label(src, i)))
          icons["go:" + i] = rail_icon(i)
        }
        entries.push(@kit.menu_separator())
      }
      if place != "" && kept.contains(place) && kept.length() > 1 {
        entries.push(@kit.menu_item("remove", label=@sf.t("web-main.rail.remove", args=[("name", rail_label(src, place))])))
        icons["remove"] = "minus"
      }
      entries.push(@kit.menu_item("customize", label=@sf.t("web-main.rail.customize")))
      icons["customize"] = "sliders"
      if flag(rail_of(src, w.id), "changed") {
        entries.push(@kit.menu_item("reset", label=@sf.t("web-main.rail.reset")))
        icons["reset"] = "refresh"
      }
      let drawn : RailMenuDrawn = { place, from, kept, entries, icons, replaced: false }
      rail_menu_drawn.val = Some(drawn)
      drawn
    }
    None if rail_menu_drawn.val is Some(m) => m
    None => {
      @sf.dropdown(c, "rail-menu", false, 0, [], {}, @sf.menu_w) |> ignore
      return
    }
  }
  let { place, from, kept, entries, icons, .. } = drawn
  // (beside the place it was asked on, where that was as it was asked: rail_node's)
  let (ax, ay, aw, ah) = from.unwrap_or((0.0, rail_menu_clear, rail_w - side_into_rail, 0.0))
  // a place's ＋: put in, the rail changed from there, the menu gone
  // (dismissed by the hand, Escape or a press outside it: closed at that moment)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(fn(_) { wide.rail_menu.set(None) }, fn() {
    menu.val = Some(
      @sf.dropdown(
        c,
        "rail-menu",
        showing is Some(_),
        0,
        entries,
        icons,
        @sf.menu_w,
        side=Right,
        offset=rail_menu_off,
        at=(ax, dmax(ay, rail_menu_clear), aw, ah),
        // The adder takes this menu's place: it must be reachable as soon as it opens.
        show_exit=!drawn.replaced,
        row_end=fn(c, s) {
          if s.entry.value.has_prefix("go:") {
            let i = s.entry.value.exact_view(start=3).to_owned()
            rail_menu_add(c, i, rail_label(src, i), s.hot, on_press=fn() {
              let next = kept.copy()
              next.push(i)
              rail_keep(src, w.id, next)
              drawn.replaced = true
              wide.editing.set(true)
              wide.rail_menu.set(None)
            })
          }
        },
      )
    )
  })
  let m = menu.val.unwrap()
  if !m.open {
    wide.rail_menu.set(None)
  }
  match m.chosen {
    Some("remove") => rail_keep(src, w.id, kept.filter(fn(i) { i != place }))
    Some("reset") => rail_keep(src, w.id, words_in(items(rail_view(src), "default")))
    Some("customize") => {
      drawn.replaced = true
      wide.editing.set(true)
    }
    Some(v) if v.has_prefix("go:") => rail_go(c, src, w, v.exact_view(start=3).to_owned())
    _ => ()
  }
}

///|
/// A place's ＋ at the end of its row in the rail's menu: 24 round, shown on the row pointed at,
/// in the pointer's ground pointed at itself; `on_press`, what a press on it does.
fn rail_menu_add(c : @ui.Ctx, place : String, label : String, hot : Bool, on_press~ : () -> Unit) -> Unit {
  let t = @sf.theme()
  let id = c.id("rail-menu/add/" + place)
  c.on_press(id, on_press)
  let over = c.lit(id)
  // in on its row pointed at; always to a finger, which hovers over
  // nothing
  // (built while it is shown or fading, till its fade's declared end; faded as it is drawn)
  let to = if @sf.pointed_or_finger(c, hot || over) { 1.0 } else { 0.0 }
  let shown = @motion.told(c, "rail-menu/add-shown/" + place, to, spec=nav_fade)
  let b = c.box(style=if over { rail_menu_plus_on } else { rail_menu_plus }, id~, fn() {
    if to > 0.0 || !shown.over(c) {
      let i = @sf.icon(c, "plus", size=rail_menu_plus_icon, color=if over { t.p.text } else { t.p.muted })
      c.look_by(i, fn() { @ui.look(alpha=dmax(0.0, dmin(1.0, shown.get(c)))) })
    }
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.rail.add", args=[("name", label)]))
}

///|
/// A ＋ in the rail's menu: 24 round, in its row's end (@sf.menu_row_end), its icon 14.
// kept across runs: a value (no field of it changes)
let rail_menu_plus : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter").then(@sf.menu_row_end)

///|
// kept across runs: a value (no field of it changes)
let rail_menu_plus_on : @ui.Style = rail_menu_plus.then(@ui.css("bg=Hover"))

///|
let rail_menu_plus_icon : Double = 14.0

///|
/// The rail's menu 8 past its place, and no higher than the window's buttons' row.
let rail_menu_off : Double = 8.0

///|
let rail_menu_clear : Double = 52.0


///|
/// A rail's place to the next (its 38 and the 6 between), and how far a press goes before it is a drag.
pub let rail_pitch : Double = 44.0

///|
let rail_slop : Double = 4.0

///|
/// A place's icon in the rail (the stations' is their glyph, rail_place).
fn rail_icon(place : String) -> String {
  match place {
    "attention" => "bell"
    "chats" => "chats"
    "mine" => "user"
    "watching" => "watch"
    "hidden" => "eye-off"
    "archive" => "archive"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    _ => "server"
  }
}

///|
/// Settings from the rail's gear (or ⌘,): their list, where the shell opens it (sfapp's open_where: beside it on a
/// medium or large screen the page of its first row, settings_landing; on a small one the list's own page).
pub fn open_settings() -> Unit {
  app.menu = false
  open_page(Settings)
}

///|
/// Settings at one of its pages, chosen (快捷键 from the shortcuts' dialog, 通知设置 from the bell's, ⌘K's): the sidebar
/// its list, the page shown (on the tape beside the sidebar in use, show_page), as a row of their list opens one.
pub fn open_settings_at(route : @settings.Route) -> Unit {
  settings_beside(route)
  show_page()
}

///|
/// Settings come to with `route`'s page beside their list (the gear's: the list in use on the tape, the page at its
/// side).
pub fn settings_beside(route : @settings.Route) -> Unit {
  @sfbase.history_push()
  app.menu = false
  app.nav.replace_above(1, [Setting(route)])
}

///|
/// Beside the rail while it is changed: what can be added, by kind, each pressed into the rail;
/// pressing anywhere but the rail (or Esc) ends the change.
fn rail_adder(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let kept = rail_items(src, w.id)
  // beside the rail (its 56: the sidebar reaches over its last 8), 8 past it, clear of the window's buttons' row
  // (collisionPadding top 52)
  // (ended as it is dismissed, at that moment: Esc, back, a press outside it and the rail, its anchor: one in the rail
  // dismisses nothing, its places moved and taken out there)
  c.with_dismissed(
    fn(_) { wide.editing.set(false) },
    fn() {
      @kit.popover(
        c,
        "rail/adder",
        wide.editing.get(),
        c.id("rail"),
        // (the rail a node of the window's tree: a press in it none outside, rail_node's)
        anchor_node?=rail_col.val,
        side=Right,
        along=Start,
        offset=rail_adder_off,
        at=(0.0, rail_menu_clear, rail_w, 0.0),
        look=@sf.beside_look(Px(rail_adder_w), inner=adder_body),
        fn() {
          @sf.panel_head(c, @sf.t("web-main.rail.customize"), note=@sf.t("web-main.rail.customizeLead"))
          // (by kind, as the core groups them: railView's `groups`)
          let kinds = items(rail_view(src), "groups").map(fn(g) {
            (text(Some(g), "label"), words_in(items(Some(g), "places")))
          })
          let mut none = true
          for k in kinds {
            let hidden = k.1.filter(fn(i) { !kept.contains(i) })
            if hidden.length() == 0 {
              continue
            }
            none = false
            @sf.panel_group(c, label=k.0, fn() {
              for i in hidden {
                adder_row(c, i, rail_label(src, i), on_press=fn() {
                  let next = kept.copy()
                  next.push(i)
                  rail_keep(src, w.id, next)
                })
              }
            })
          }
          if none {
            @sf.panel_note(c, @sf.t("web-main.rail.allIn"))
          }
        },
      )
      |> ignore
    },
  )
}

///|
/// A place that can be put in the rail, in the adder (parts.tsx PanelRow): its icon, its ＋ at its end; `on_press`,
/// what pressing it does, as it is let go.
fn adder_row(c : @ui.Ctx, place : String, label : String, on_press~ : () -> Unit) -> Unit {
  @sf.menu_item(
    c,
    label,
    key="rail/add/" + place,
    panel=true,
    icon=rail_icon(place),
    end="plus",
    on_press~,
  )
}

///|
/// The adder's panel: 248 wide, 8 past the rail.
let rail_adder_w : Double = 248.0

///|
let rail_adder_off : Double = 8.0

///|
/// The − 5 out past the place's top left corner, its icon 12.
let rail_remove_out : Double = -5.0

///|
let rail_remove_icon : Double = 12.0

///|
/// A place's dashed outline while the rail is changed: 1.5 wide from a pixel in to half a pixel out of its 38 (its
/// middle 0.25 in: 37.5 across, its corner 12's less as much), drawn from 0.75 further out.
let rail_dash_line : Double = 1.5

///|
let rail_dash_side : Double = 37.5

///|
let rail_dash_r : Double = 11.75

///|
let rail_dash_at : Double = -0.5

///|
// kept across runs: a value (no field of it changes)
let rail_remove_at : @ui.Style = @ui.css("w=Full")

///|
/// The −: 18 round in the words' colour, the rail's ground round it.
// kept across runs: a value (no field of it changes)
let rail_remove : @ui.Style = @ui.css("w=S4_5 h=S4_5 align=ACenter justify=JCenter bg=Fg radius=Full")

///|
/// The adder's head and its kinds 8 apart (gap 8).
// kept across runs: a value (no field of it changes)
let adder_body : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// The rail in the closed bar (closed): as narrow as the bar, its places 2 from its every edge.
pub let rail_closed_w : Double = 42.0

///|
/// What the stations' place says on hover (RailStations): what is wrong with them, else what the core waits on, else
/// how many and who works.
pub fn rail_stations_label(src : Source, ws : String) -> String {
  let chats = @sfbase.chats_topic(src, ws).value
  let status = src.topic("status", { "workspace": Json::string(ws) }).get().value
  let trouble = text(field(chats, "trouble"), "text")
  let waiting = if text(status, "state") != "" { text(status, "text") } else { "" }
  let summary = text(field(chats, "glyph"), "summary")
  if trouble != "" {
    trouble
  } else if waiting != "" {
    waiting
  } else if summary != "" {
    summary
  } else {
    "Station"
  }
}
