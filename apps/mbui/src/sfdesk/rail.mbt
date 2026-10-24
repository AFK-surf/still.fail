// The rail at the wide frame's left (ember web/src/Rail.tsx, Rail.css.ts), in one block with the sidebar (frame.mbt
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
  field((src.topic)("prefs", {}).value, "railView")
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
/// Whether the place has no sidebar: its page is the pane's whole (连接, 用量: Rail.tsx `own`).
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
      Decisions => return "decisions"
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
/// Which of the lists is shown (the sidebar's mode, station.tsx useSidebarMode): 全部 0, 我参与的 1, 监控中 2 (the
/// filter), 奏 3, 已归档 4.
pub fn list_mode(src : Source, w : Workspace) -> Int {
  if app.nav.pages().contains(Archived) {
    4
  } else if lit_place() == "decisions" {
    3
  } else {
    match filter_of(src, w.id) {
      "mine" => 1
      "watching" => 2
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
    3 => "decisions"
    4 => "archive"
    _ => "chats"
  }
}

///|
/// The rail: its top (in a window with its buttons in the app's top row, their row, dragging the window), the places,
/// then the workspaces and settings at its foot. In the closed bar (`bar`) as narrow as it (42), its places 2 from its
/// every edge (their grounds 6), no top row: the bar starts under it.
fn rail(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace], bar : Bool) -> Unit {
  let lit = lit_place()
  let rail_id = c.id("rail")
  match c.menu_asked(rail_id) {
    Some((x, y)) if wide.rail_menu is None => wide.rail_menu = Some(("", x, y))
    _ => ()
  }
  let inset = @ui.window_inset()
  // Rail.css.ts rail, top: 56 wide, its places in its middle (9 from its edge; the sidebar reaches over its last 8, so
  // the rail is as wide as the rest), 9 under the last; its top row (41 under the window's buttons, else 5) 6 over its
  // first place; in the bar none, its first place 2 from the bar's top
  let look = if bar { rail_closed } else { rail_open }
  let top_h = if bar { 0.0 } else if inset { rail_top_inset + rail_gap } else { rail_top_web + rail_gap }
  c.box(style=look, moves="rail", id=rail_id, fn() {
    c.box(style=rail_head, fn() {
      // its top row drags the window (the macOS app's buttons in it), not in the closed bar
      let top = c.id("rail/top")
      if inset && !bar {
        c.window_drag(top)
      }
      c.box(style=rail_top.then(@ui.style(h=Fixed(top_h))), moves="rail-top", id=top, fn() {  }) |> ignore
      let places = rail_items(src, w.id)
      // a list's place lit while its list is the one shown (Rail.tsx `on`): 我参与的, 监控中 by the filter when they
      // are in the rail, else 对话; 已归档 while the archive is open (shownList)
      let list = list_place(list_mode(src, w))
      let listy = lit == "chats" || lit == "decisions"
      // a place left out of the rail but in view: at the foot of its places, lit, while it is
      let in_view = rail_in_view(src, w)
      let shown = places.copy()
      if in_view != "" && !places.contains(in_view) && !wide.editing {
        shown.push(in_view)
      }
      let shown_list = if shown.contains(list) { list } else { "chats" }
      c.box(style=rail_places_col, fn() {
        for place in shown {
          let on = match place {
            "chats" | "mine" | "watching" | "decisions" | "archive" => listy && shown_list == place
            _ => lit == place
          }
          rail_place(c, src, w, place, on, places)
        }
      })
      |> ignore
    })
    |> ignore
    c.spacer()
    rail_workspaces(c, src, w, all)
    // settings
    let gear = c.id("rail/settings")
    c.cursor(gear, Hand)
    if c.clicked(gear) {
      // lit (in the settings): back out of them, to the chat last open (Rail.tsx: the settings' NavLink, in them); their
      // list folded for the page's room: shown over the page, or folded again (返回会话 at its top goes back)
      if lit == "settings" && wide.crowded {
        wide.peeking = !wide.peeking
      } else if lit == "settings" {
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        wide.landed = ""
      } else {
        open_settings()
        wide.peek_next = wide.crowded
      }
    }
    rail_ground(
      c,
      gear,
      lit == "settings",
      fn(color) { @sf.icon(c, "settings", size=rail_icon_size, color~) |> ignore },
      label=@sf.t("web-pages.settings.title"),
      tipped=false,
    )
  })
  |> ignore
}

///|
/// The rail open and in the closed bar (Rail.css.ts rail): its places 9 in and 9 under the last, 6 apart (open, as
/// wide as the rail less the 8 the sidebar reaches over); as narrow as the bar, 2 from its every edge.
// kept across runs: a value (no field of it changes)
let rail_open : @ui.Style = @ui.style(
  w=Fixed(rail_shown_w),
  h=Full,
  pl=@sf.rail_in,
  pb=@sf.rail_in,
  gap=S1_5,
  align=AStart,
)

///|
// kept across runs: a value (no field of it changes)
let rail_closed : @ui.Style = @ui.style(w=Fixed(rail_closed_w), h=Full, p=S0_5, gap=S1_5, align=AStart)

///|
/// What of the rail shows beside the sidebar open: its 56 less the 8 the sidebar reaches over.
let rail_shown_w : Double = 48.0

///|
/// The rail's top row and its places (the top row's 6 under it its own: in the closed bar it has none).
// kept across runs: a value (no field of it changes)
let rail_head : @ui.Style = @ui.css("align=AStart")

///|
// kept across runs: a value (no field of it changes)
let rail_top : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let rail_places_col : @ui.Style = @ui.css("gap=S1_5 align=AStart")

///|
/// A place lit in the closed bar: the words' colour at 12% (Rail.css.ts item, closed: color-mix(text 12%)).
let lit_in_bar : Double = 0.12

///|
/// The rail's places 6 apart; its top row 41 under the window's buttons, else 5.
let rail_gap : Double = 6.0

///|
let rail_top_inset : Double = 41.0

///|
let rail_top_web : Double = 5.0

///|
/// A place's icon (20), the rail's words' (奏).
let rail_icon_size : Double = 20.0

///|
/// A place's 38 to press, its ground (hovered, lit) 30 square under the icon (Rail.css.ts item).
fn rail_ground(
  c : @ui.Ctx,
  id : Int,
  on : Bool,
  body : (Int64) -> Unit,
  label? : String = "",
  tipped? : Bool = true,
) -> Unit {
  let t = @sf.theme()
  let hover = c.lit(id)
  // its ground and its icon's colour moved over 140 ms (Rail.css.ts item: transition background, color)
  let key = "rail/ground/" + id.to_string()
  let ink = @kit.animate(c, key + "/ink", if on || hover { 1.0 } else { 0.0 }, transition=nav_fade)
  let b = c.box(style=rail_item, id~, fn() {
    // (lit in the closed bar, on its floating ground: the words' colour at 12%, as plain a step above it as the
    // selected grey is above the sidebar; Rail.css.ts item, closed)
    let lit = if wide.closed { @sf.alpha(t.p.text, lit_in_bar) } else { t.p.selected }
    rail_square(c, nav_ground(c, key, hover, on, lit~), fn() { body(@sf.mix(t.p.text, ink, t.p.muted)) })
    |> ignore
  })
  // named for a screen reader (Rail.tsx's aria-label), and on hover beside it (its Tip, side right; not the
  // settings')
  if label != "" {
    c.semantics(b, Button, id~, label~)
    if tipped {
      @sf.tip(c, "rail/tip/" + id.to_string(), id, label, side=Right)
    }
  }
}

///|
// kept across runs: a value (no field of it changes)
let rail_item : @ui.Style = @ui.style(w=Fixed(rail_item_side), h=Fixed(rail_item_side), align=ACenter, justify=JCenter)

///|
let rail_item_side : Double = 38.0

///|
/// A square of the rail (Rail.css.ts item's ground, workspaceItem, workspaceAdd): 30, its corner 9, on `ground`; `id`
/// to press it; its node.
fn rail_square(c : @ui.Ctx, ground : Int64, body : () -> Unit, id? : Int) -> Int {
  c.box(style=rail_sq.then(@ui.style(bg=Data(ground))), id?, body)
}

///|
// kept across runs: a value (no field of it changes)
let rail_sq : @ui.Style = @ui.style(w=Fixed(rail_sq_side), h=Fixed(rail_sq_side), radius=@sf.rail_corner, align=ACenter, justify=JCenter)

///|
let rail_sq_side : Double = 30.0

///|
/// What waits in a list of chats or another workspace (Rail.css.ts listMark, mark): its rows' mark (ChatMark.css.ts
/// chatMarkInline) on a disc of the rail's ground 2 round it, at the place's 38 top right corner 3 in (`at` -3: a
/// list's) or the workspace's square's 4 out (4); a list's `shown` of the way in as the sidebar folds (listMark: from
/// clear at 40%, moved with it).
fn rail_corner_mark(c : @ui.Ctx, tone : String, at? : Double = 4.0, shown? : Double = 1.0) -> Unit {
  let ground = if wide.in_bar || side_folded() { rail_mark_bar } else { rail_mark_side }
  c.layer(fn() {
    c.box(style=corner_end, fn() {
      let i = c.box(style=ground, tx=at, ty=-at, fn() {
        if tone == "invite" {
          c.box(style=invite_dot, fn() {  }) |> ignore
        } else {
          chat_mark(c, tone) |> ignore
        }
      })
      if shown < 1.0 {
        c.look(i, @ui.look(alpha=shown, scale=fold_at(mark_folded_from, 1.0, shown)))
      }
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let rail_mark_side : @ui.Style = @ui.css("p=S0_5 radius=Full bg=Sidebar")

///|
// kept across runs: a value (no field of it changes)
let rail_mark_bar : @ui.Style = @ui.css("p=S0_5 radius=Full bg=Surface")

///|
/// What stands at a square's top right (a layer's whole, its end).
// kept across runs: a value (no field of it changes)
let corner_end : @ui.Style = @ui.css("w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let invite_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Accent")

///|
let mark_folded_from : Double = 0.4

///|
/// A list's mark 3 in from its place's corner (Rail.css.ts listMark: top 3, right 3).
let list_mark_in : Double = -3.0

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
/// The workspaces at the rail's foot (Rail.tsx RailWorkspaces, Rail.css.ts workspaces, workspaceItem): each on a
/// square, 6 apart; a letter on a square of its own, a mark (an icon, an emoji) on nothing, the places' ground under
/// the pointer; the one in view a short bar at its left; another with what waits in it (the core's marks' tone) its
/// mark at its corner. Over them the ＋ (making one, another account, invitations), seen as the pointer comes over them
/// or while an invitation waits. Pressed, that workspace.
fn rail_workspaces(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  let t = @sf.theme()
  let marks = field((src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value, "workspaces")
  let area = c.id("rail/workspaces")
  let add = c.id("rail/ws-add")
  let open = wide.add_open
  // (always to a finger, which hovers over nothing: Rail.css.ts workspaceAdd `hover: none`)
  let over = open ||
    @ui.pointing() is Finger ||
    c.lit(area) ||
    c.lit(add) ||
    all.iter().any(fn(x) { c.lit(c.id("rail/ws/" + x.id)) })
  let waiting = invitations_waiting(src).length() > 0
  let switch_to = fn(x : Workspace) {
    app.picked = x.id
    (src.call)("prefs.set", Json::object({ "workspace": Json::string(x.id) }), fn(_) {  })
    desk_home()
  }
  // ⌃1 … ⌃9 on a Mac (Alt elsewhere): the workspace at that place, as the web's keys (keymap.ts workspaceIndexOf)
  let held = if @ui.platform() == 0 { @ui.mod_ctrl } else { @ui.mod_alt }
  for k in 0..<dmin(9.0, all.length().to_double()).to_int() {
    if c.key_pressed(@ui.key_of_char((49 + k).unsafe_to_char()), mods=held, in_field=true) && all[k].id != w.id {
      switch_to(all[k])
    }
  }
  c.box(style=rail_ws_list, id=area, fn() {
    // the ＋
    c.cursor(add, Hand)
    if c.clicked(add) {
      wide.add_open = !open
    }
    let hot = c.lit(add) || open
    let plus = rail_square(
      c,
      if hot { t.p.hover } else { 0L },
      fn() {
        if over || waiting {
          @sf.icon(c, "plus", size=rail_plus_size, color=if hot { t.p.text } else { t.p.muted }) |> ignore
        }
        // an invitation waiting: the accent's dot (workspace.css.ts inviteDot)
        if waiting {
          rail_corner_mark(c, "invite")
        }
      },
      id=add,
    )
    c.semantics(plus, Button, id=add, label=@sf.t("web-main.rail.addWorkspace"))
    @sf.tip(c, "rail/ws-add-tip", add, @sf.t("web-main.rail.addWorkspace"), side=Right)
    for x in all {
      let id = c.id("rail/ws/" + x.id)
      c.cursor(id, Hand)
      if c.clicked(id) && x.id != w.id {
        switch_to(x)
      }
      let on = x.id == w.id
      let hot = c.lit(id)
      let marked = @sf.has_station_mark(x.emoji, x.icon)
      let square = rail_square(c, if !marked || hot { t.p.hover } else { 0L }, fn() {
        if marked {
          @sf.station_mark(c, x.emoji, x.icon, rail_ws_mark, t.p.text)
        } else {
          let ink = if on || hot { rail_letter_on } else { rail_letter }
          c.text(@sf.initial(x.name), style=ink) |> ignore
        }
        // the one in view: a short bar in the margin at its left
        if on {
          c.layer(fn() {
            c.box(style=rail_bar_at, fn() { c.box(style=rail_bar, tx=-rail_bar_out, fn() {  }) |> ignore }) |> ignore
          })
          |> ignore
        }
        // another's: what waits there, as its rows' marks
        let tone = if on { "" } else { text(field(marks, x.id), "tone") }
        if tone != "" {
          rail_corner_mark(c, tone)
        }
      }, id~)
      let said = text(field(marks, x.id), "label")
      let label = if on || said == "" { x.name } else { x.name + " · " + said }
      c.semantics(square, Button, id~, label~)
      @sf.tip(c, "rail/ws-tip/" + x.id, id, label, side=Right)
    }
  })
  |> ignore
  rail_ws_menu(c, src, add)
}

///|
/// The ＋'s icon (16), a workspace's mark (18).
let rail_plus_size : Double = 16.0

///|
let rail_ws_mark : Double = 18.0

///|
/// A workspace's letter (Rail.css.ts workspaceItem: textUi, 600), muted unless it is the one in view or pointed at.
// kept across runs: a value (no field of it changes)
let rail_letter : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rail_letter_on : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)

///|
/// The workspaces' column: 4 in from the rail's 38 (its squares where the places' grounds are), 4 above and under, 6
/// between.
// kept across runs: a value (no field of it changes)
let rail_ws_list : @ui.Style = @ui.css("pl=S1 pt=S1 pb=S1 gap=S1_5")

///|
/// The bar at the left of the workspace in view: 8 down its square, 6 out past it, 3 by 14, its corner 2.
// kept across runs: a value (no field of it changes)
let rail_bar_at : @ui.Style = @ui.css("pt=S2")

///|
// kept across runs: a value (no field of it changes)
let rail_bar : @ui.Style = @ui.style(w=Fixed(rail_bar_w), h=S3_5, radius=Sm, bg=Fg)

///|
let rail_bar_w : Double = 3.0

///|
let rail_bar_out : Double = 6.0

///|
/// What waits on a place: its dot 4 in from its 38's top right (Rail.css.ts count: 6 from the 38's corner, 2 of it the
/// ring cut out of the rail's ground).
// kept across runs: a value (no field of it changes)
let rail_dot_at : @ui.Style = @ui.css("w=Full pt=S1 pr=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let rail_dot_ring : @ui.Style = @ui.css("w=S3 h=S3 p=S0_5 radius=Full bg=Sidebar")

///|
// kept across runs: a value (no field of it changes)
let rail_dot : @ui.Style = @ui.css("w=Full h=Full radius=Full bg=Danger")

///|
/// 奏, the word, its size the icons' (Rail.css.ts zou: textTitle, 20 high, 600).
// kept across runs: a value (no field of it changes)
let rail_zou : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, leading=L6, wrap=false)

///|
/// One place of the rail: its icon (奏 its word), what waits on it a dot at its corner; pressed, its page.
fn rail_place(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  place : String,
  on : Bool,
  places : Array[String],
) -> Unit {
  let t = @sf.theme()
  let id = c.id("rail/" + place)
  c.cursor(id, Hand)
  match c.menu_asked(id) {
    Some((x, y)) => wide.rail_menu = Some((place, x, y))
    None => ()
  }
  // dragged up or down (past a few points) while the rail is changed or with ⌘ held as it was pressed: to another place
  // in the rail, the others as they were until let go
  let (_, py, _) = c.pointer()
  let dragged = match wide.rail_drag {
    Some((p, y0, _)) if p == place =>
      if c.pressed(id) {
        wide.rail_drag = Some((p, y0, py - y0))
        true
      } else {
        // let go: its place by how far it went
        let dy = py - y0
        let from = places.search_by(fn(x) { x == place }).unwrap_or(0)
        let to = dmax(0.0, dmin((places.length() - 1).to_double(), from.to_double() + (dy / rail_pitch).round())).to_int()
        wide.rail_drag = None
        if dy.abs() > rail_slop && to != from {
          let next = places.filter(fn(x) { x != place })
          next.insert(to, place)
          rail_keep(src, w.id, next)
        }
        dy.abs() > rail_slop
      }
    // (only while the rail is changed, or pressed with ⌘ held: Rail.tsx drag)
    None if c.pressed(id) && (wide.editing || (c.press().mods & @ui.mod_cmd) != 0) => {
      wide.rail_drag = Some((place, py, 0.0))
      false
    }
    _ => false
  }
  let moved = match wide.rail_drag {
    Some((p, _, dy)) if p == place && dy.abs() > rail_slop => dy
    _ => 0.0
  }
  if c.clicked(id) && !dragged && !wide.editing {
    // the lit place pressed again (not 待处理, a panel): its sidebar folded or opened, not gone to; folded so with the
    // pointer on the rail, it is shown a while (Rail.tsx's rail onClickCapture); on the tape, the page brought over
    if on && place != "attention" && !place_bare(lit_place()) {
      // (folded for the page's room: shown over it, or folded again)
      if wide.crowded {
        wide.peeking = !wide.peeking
      } else {
        sidebar_toggle()
        wide.peeking = side_folded()
      }
    } else {
      rail_go(c, src, w, place)
      // (pressed into a place whose sidebar is folded for the page's room: shown a while from the start, as the web's
      // pressed into a folded one)
      wide.peek_next = wide.crowded && !place_bare(place) && place != "attention"
    }
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let here = field(field(marks.value, "workspaces"), w.id)
  let dot = match place {
    "attention" => bell_lit(src, w)
    "decisions" => count(here, "decisions") > 0
    _ => false
  }
  let label = match place {
    "stations" => "Station：" + rail_stations_label(src, w.id)
    "decisions" if count(here, "decisions") > 0 =>
      @sf.t("web-main.decisions.entry", args=[("n", count(here, "decisions").to_string())])
    _ => rail_label(src, place)
  }
  rail_edit_frame(c, src, w, place, moved, fn() {
    rail_ground(c, id, on || (place == "attention" && wide.attention_open), fn(color) {
      if place == "decisions" {
        c.text("奏", style=rail_zou.then(@ui.text_style(color=Data(color)))) |> ignore
      } else if place == "stations" {
        // the stations at a glance (Sidebar.tsx RailStations: StationGlyph, 20)
        @sf.station_glyph(c, stations_at_glance(src, w.id).0, rail_icon_size, color, t.p.red) |> ignore
      } else {
        @sf.icon(c, rail_icon(place), size=rail_icon_size, color~) |> ignore
      }
    }, label~)
    // what wants the person in a list, as its rows' marks: on its icon's corner while the sidebar is folded (open,
    // the rows show it; Rail.css.ts listMark)
    let tone = match place {
      "chats" => text(here, "tone")
      "mine" => text(here, "mineTone")
      "watching" => text(here, "watchingTone")
      _ => ""
    }
    if tone != "" && wide.mark > 0.0 {
      rail_corner_mark(c, tone, at=list_mark_in, shown=wide.mark)
    }
    if dot {
      c.layer(fn() {
        c.box(style=rail_dot_at, fn() {
          c.box(style=rail_dot_ring, fn() { c.box(style=rail_dot, fn() {  }) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
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
/// A place gone to (sfapp's go_place, as the web's NavLink: no switch of its own): its page the stack's root, in place;
/// the same place again changes nothing.
fn go_place(place : String) -> Unit {
  let page : Page = match place {
    "chats" => Home
    "files" => Files
    "decisions" => Decisions
    p => Place(p)
  }
  if app.nav.depth() == 1 && app.nav.top() == page {
    return
  }
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.replace(page)
}

///|
/// A place gone to, from the rail or its menu (Rail.tsx `drawn`'s presses and `go`): 待处理 its panel; a list of chats
/// its list in the sidebar, the chat last open beside it; 已归档 the archive; the others their page.
pub fn rail_go(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  ignore(c)
  match place {
    "attention" => {
      wide.attention_open = !wide.attention_open
    }
    "chats" | "mine" | "watching" => {
      // its list in the sidebar (Rail.tsx toList): 对话 all of them, the others theirs
      let f = if place == "chats" { "all" } else { place }
      if filter_of(src, w.id) != f {
        app.filters[w.id] = f
        (src.call)("prefs.set", Json::object({ "listFilter": Json::object(Map::from_array([(w.id, Json::string(f))])) }), fn(_) {  })
      }
      // the chats again: the chat last open stays open beside the list
      if app.nav.pages()[0] == Home && lit_place() == "chats" && !app.nav.pages().contains(Archived) {
        ()
      } else {
        go_place("chats")
        wide.landed = ""
      }
    }
    "archive" => {
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      archive_side.landed = false
      app.nav.push(Archived)
    }
    p => go_place(p)
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
/// The place in view that is left out of the rail, if one is: a list shown (我参与的, 监控中, 奏, the archive; the chats'
/// when 对话 is out), the files, a place picked from the rail's menu (Rail.tsx inView, setExtra); "" none.
fn rail_in_view(src : Source, w : Workspace) -> String {
  let lit = lit_place()
  let in_view = if lit == "chats" || lit == "decisions" {
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
/// while it is changed, what can be added beside it.
pub fn rail_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  rail_menu(c, src, w)
  rail_adder(c, src, w)
}

///|
/// The rail's menu (Rail.tsx's DropdownMenu, from a right click on it), beside the place right clicked (else its
/// first), 8 past it, clear of the window's buttons' row: the places not in it (pressed, their page; their ＋, shown on
/// the row pointed at, puts one in it and the rail is changed from there), 从侧边条移除 the place right clicked,
/// 自定义侧边条, 侧边条恢复默认 when it was changed.
fn rail_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (place, _, _) = match wide.rail_menu {
    Some(m) => m
    None => {
      @sf.dropdown(c, "rail-menu", false, 0, [], {}, @sf.menu_w) |> ignore
      return
    }
  }
  let kept = rail_items(src, w.id)
  // (提醒 is no page, nor the one in view at the rail's foot: put in from 自定义侧边条)
  let extra = rail_in_view(src, w)
  let away = rail_places(src).filter(fn(i) { !kept.contains(i) && i != "attention" && i != extra })
  let entries : Array[@kit.Entry] = []
  let icons : Map[String, String] = {}
  if away.length() > 0 {
    entries.push(@kit.menu_label(@sf.t("web-main.rail.away")))
    for i in away {
      entries.push(@kit.menu_item("go:" + i, label=rail_label(src, i)))
      icons["go:" + i] = if i == "decisions" { "zou" } else { rail_icon(i) }
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
  let by = c.rect_of(c.id("rail/" + (if place != "" { place } else { kept.get(0).unwrap_or("") })))
  let (ax, ay, aw, ah) = by.unwrap_or((0.0, rail_menu_clear, rail_w - side_into_rail, 0.0))
  // a place's ＋: put in, the rail changed from there (once the menu has gone)
  let added : Ref[String] = Ref("")
  let m = @sf.dropdown(
    c,
    "rail-menu",
    true,
    0,
    entries,
    icons,
    @sf.menu_w,
    side=Right,
    offset=rail_menu_off,
    at=(ax, dmax(ay, rail_menu_clear), aw, ah),
    row_end=fn(c, s) {
      if s.entry.value.has_prefix("go:") {
        let i = s.entry.value.view(start_offset=3).to_string()
        if rail_menu_add(c, i, rail_label(src, i), s.hot) {
          added.val = i
          let next = kept.copy()
          next.push(i)
          rail_keep(src, w.id, next)
          wide.editing = true
        }
      }
    },
  )
  if !m.open || added.val != "" {
    wide.rail_menu = None
  }
  if added.val != "" {
    return
  }
  match m.chosen {
    Some("remove") => rail_keep(src, w.id, kept.filter(fn(i) { i != place }))
    Some("reset") => rail_keep(src, w.id, words_in(items(rail_view(src), "default")))
    Some("customize") => wide.editing = true
    Some(v) if v.has_prefix("go:") => rail_go(c, src, w, v.view(start_offset=3).to_string())
    _ => ()
  }
}

///|
/// A place's ＋ at the end of its row in the rail's menu (Rail.css.ts menuAdd): 24 round, shown on the row pointed at,
/// in the pointer's ground pointed at itself; true on the frame after it was pressed.
fn rail_menu_add(c : @ui.Ctx, place : String, label : String, hot : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("rail-menu/add/" + place)
  c.cursor(id, Hand)
  let over = c.lit(id)
  // in on its row pointed at (Rail.css.ts menuAdd: transition opacity 140 ms); always to a finger, which hovers over
  // nothing
  let shown = @kit.animate(
    c,
    "rail-menu/add-shown/" + place,
    if hot || over || @ui.pointing() is Finger { 1.0 } else { 0.0 },
    transition=nav_fade,
  )
  let b = c.box(style=if over { rail_menu_plus_on } else { rail_menu_plus }, id~, fn() {
    if shown > 0.0 {
      @sf.icon(c, "plus", size=rail_menu_plus_icon, color=@sf.alpha(if over { t.p.text } else { t.p.muted }, shown))
      |> ignore
    }
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.rail.add", args=[("name", label)]))
  c.clicked(id)
}

///|
/// A ＋ in the rail's menu: 24 round, at its row's end, its icon 14.
// kept across runs: a value (no field of it changes)
let rail_menu_plus : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let rail_menu_plus_on : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter bg=Hover")

///|
let rail_menu_plus_icon : Double = 14.0

///|
/// The rail's menu 8 past its place, and no higher than the window's buttons' row (Rail.tsx: collisionPadding top 52).
let rail_menu_off : Double = 8.0

///|
let rail_menu_clear : Double = 52.0

///|
/// The rail's ＋'s menu (workspace.tsx accountMenu): 260 at least.
let rail_ws_menu_w : Double = 260.0

///|
/// A rail's place to the next (its 38 and the 6 between), and how far a press goes before it is a drag.
pub let rail_pitch : Double = 44.0

///|
let rail_slop : Double = 4.0

///|
/// A place's icon in the rail (Rail.tsx RAIL_ICONS; the stations' is their glyph, rail_place).
fn rail_icon(place : String) -> String {
  match place {
    "attention" => "bell"
    "chats" => "chats"
    "mine" => "user"
    "watching" => "watch"
    "archive" => "archive"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    _ => "server"
  }
}

///|
/// Settings from the rail's gear (or ⌘,): its first page, 外观, the sidebar its list.
pub fn open_settings() -> Unit {
  open_settings_at(@settings.Route::Appearance)
}

///|
/// Settings at one of its pages (快捷键 from the shortcuts' dialog), the sidebar its list.
pub fn open_settings_at(route : @settings.Route) -> Unit {
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Setting(route))
}

///|
/// A place of the rail as it is drawn, `moved` with its drag; while the rail is changed (自定义侧边条), outlined, its
/// − at its top left corner (Rail.css.ts editing, remove).
fn rail_edit_frame(c : @ui.Ctx, src : Source, w : Workspace, place : String, moved : Double, body : () -> Unit) -> Unit {
  if !wide.editing {
    c.box(ty=moved, body) |> ignore
    return
  }
  let t = @sf.theme()
  let rm = c.id("rail/remove/" + place)
  c.cursor(rm, Hand)
  let items = rail_items(src, w.id)
  if c.clicked(rm) && items.length() > 1 {
    rail_keep(src, w.id, items.filter(fn(i) { i != place }))
  }
  c.box(ty=moved, fn() {
    c.box(style=rail_editing, body) |> ignore
    // its outline dashed, 1.5 wide, a pixel in from its edge (Rail.css.ts editing: outline-offset -1)
    c.layer(fn() {
      c.box(tx=rail_dash_at, ty=rail_dash_at, fn() {
        @sf.dashed_frame(c, rail_dash_side, rail_dash_side, rail_dash_r, rail_dash_line, t.p.line_strong) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.box(style=rail_remove_at, tx=rail_remove_out, ty=rail_remove_out, fn() {
        let b = c.box(style=rail_remove, id=rm, fn() {
          @sf.icon(c, "minus", size=rail_remove_icon, color=t.p.sidebar) |> ignore
        })
        c.semantics(b, Button, id=rm, label=@sf.t("web-main.rail.remove", args=[("name", rail_label(src, place))]))
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Beside the rail while it is changed (Rail.tsx's Popover): what can be added, by kind, each pressed into the rail;
/// pressing anywhere but the rail (or Esc) ends the change.
fn rail_adder(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let kept = rail_items(src, w.id)
  // beside the rail (its 56: the sidebar reaches over its last 8), 8 past it, clear of the window's buttons' row
  // (Rail.tsx: Popover.Anchor the rail, collisionPadding top 52)
  let p = @kit.popover(
    c,
    "rail/adder",
    wide.editing,
    c.id("rail"),
    side=Right,
    along=Start,
    offset=rail_adder_off,
    at=(0.0, rail_menu_clear, rail_w, 0.0),
    look=fn(c, _, body) {
      @sf.small_panel(c, w=Px(rail_adder_w), fn() { c.box(style=adder_body, body) |> ignore }) |> ignore
    },
    fn() {
      c.box(style=adder_head, fn() {
        c.text(@sf.t("web-main.rail.customize"), style=adder_title) |> ignore
        c.text(@sf.t("web-main.rail.customizeLead"), style=adder_lead) |> ignore
      })
      |> ignore
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
        c.box(style=adder_kind, fn() {
          c.box(style=adder_group, fn() { c.text(k.0, style=adder_label) |> ignore }) |> ignore
          for i in hidden {
            if adder_row(c, i, rail_label(src, i)) {
              let next = kept.copy()
              next.push(i)
              rail_keep(src, w.id, next)
            }
          }
        })
        |> ignore
      }
      if none {
        c.box(style=adder_group, fn() { c.text(@sf.t("web-main.rail.allIn"), style=adder_lead) |> ignore }) |> ignore
      }
    },
  )
  // (pressing in the rail does not end it: its places are moved and taken out there)
  if !p.value {
    let (px, _, _) = c.pointer()
    if px >= rail_w || !wide.editing {
      wide.editing = false
    }
  }
}

///|
/// A place that can be put in the rail, in the adder (parts.tsx PanelRow): its icon (奏 its word), its ＋ at its end.
/// True on the frame after it was pressed.
fn adder_row(c : @ui.Ctx, place : String, label : String) -> Bool {
  @sf.menu_item(
    c,
    label,
    key="rail/add/" + place,
    panel=true,
    icon=rail_icon(place),
    word=if place == "decisions" { "奏" } else { "" },
    end="plus",
  )
}

///|
/// A kind's label and its rows, 2 apart (parts.css.ts panelGroup).
// kept across runs: a value (no field of it changes)
let adder_kind : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// The adder's panel: 248 wide, 8 past the rail (Rail.css.ts adder).
let rail_adder_w : Double = 248.0

///|
let rail_adder_off : Double = 8.0

///|
/// The − 5 out past the place's top left corner, its icon 12 (Rail.css.ts remove).
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
/// A place while the rail is changed: outlined, its corner the editing frame's (Rail.css.ts editing: 12).
// kept across runs: a value (no field of it changes)
let rail_editing : @ui.Style = @ui.css("radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let rail_remove_at : @ui.Style = @ui.css("w=Full")

///|
/// The −: 18 round in the words' colour, the rail's ground round it (Rail.css.ts remove).
// kept across runs: a value (no field of it changes)
let rail_remove : @ui.Style = @ui.css("w=S4_5 h=S4_5 align=ACenter justify=JCenter bg=Fg radius=Full")

///|
// kept across runs: a value (no field of it changes)
let adder_head : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S1 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let adder_group : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S0_5")

///|
/// The adder's head and its kinds 8 apart (Rail.css.ts adder: a grid, gap 8).
// kept across runs: a value (no field of it changes)
let adder_body : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let adder_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let adder_lead : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5)

///|
/// A kind's label in the adder (parts.css.ts panelLabel: 12, muted, on the page's line, 1.55 of it).
// kept across runs: a value (no field of it changes)
let adder_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L4_75)

///|
/// The rail in the closed bar (Rail.css.ts rail, closed): as narrow as the bar, its places 2 from its every edge.
pub let rail_closed_w : Double = 42.0

///|
/// The invitations waiting for any account signed in, with the account each is for.
pub fn invitations_waiting(src : Source) -> Array[(Json?, Json)] {
  let pending : Array[(Json?, Json)] = []
  match (src.topic)("workspaces", {}).value {
    Some(Array(a)) =>
      for e in a {
        for i in items(Some(e), "invitations") {
          pending.push((field(Some(e), "account"), i))
        }
      }
    _ => ()
  }
  pending
}

///|
/// The ＋'s menu, beside it, its foot level with the ＋'s (WorkspaceSwitcher `adder`): 新建 workspace, 添加另一个账号,
/// then the invitations waiting, each joined or ignored.
fn rail_ws_menu(c : @ui.Ctx, src : Source, add : Int) -> Unit {
  let entries : Array[@kit.Entry] = [
    @kit.menu_item("create", label=@sf.t("web-pages.workspace.create")),
    @kit.menu_item("account", label=@sf.t("web-pages.workspace.addAccount")),
  ]
  let icons : Map[String, String] = { "create": "plus", "account": "user-plus" }
  let pending = invitations_waiting(src)
  if pending.length() > 0 {
    entries.push(@kit.menu_separator())
    entries.push(@kit.menu_label(@sf.t("web-pages.workspace.invitations")))
    for p in pending {
      let iv = Some(p.1)
      let id = text(iv, "id")
      let inviter = match text(iv, "inviter") {
        "" => @sf.t("web-pages.cloud.someone")
        x => x
      }
      entries.push(
        @kit.menu_label(@sf.t("web-pages.workspace.invitedYou", args=[("inviter", inviter), ("name", text(iv, "name"))])),
      )
      entries.push(@kit.menu_item("join:" + id, label=@sf.t("web-pages.cloud.join")))
      entries.push(@kit.menu_item("ignore:" + id, label=@sf.t("web-pages.workspace.ignore")))
    }
  }
  // beside it, its foot level with the ＋'s (side right, align end, sideOffset 10)
  let m = @sf.dropdown(c, "rail/ws-menu", wide.add_open, add, entries, icons, rail_ws_menu_w, side=Right, along=End, offset=rail_ws_menu_off)
  wide.add_open = m.open
  match m.chosen {
    Some("create") => open_new_workspace()
    Some("account") => (src.sign_in)()
    Some(v) if v.has_prefix("join:") || v.has_prefix("ignore:") => {
      let join = v.has_prefix("join:")
      let id = v.view(start_offset=if join { 5 } else { 7 }).to_string()
      for p in pending {
        if text(Some(p.1), "id") == id {
          answer_invitation(src, p.0, id, join, text(Some(p.1), "name"))
        }
      }
    }
    _ => ()
  }
}

///|
let rail_ws_menu_off : Double = 10.0

///|
/// What the stations' place says on hover (RailStations): what is wrong with them, else what the core waits on, else
/// how many and who works.
pub fn rail_stations_label(src : Source, ws : String) -> String {
  let chats = (src.topic)("chats", { "scope": Json::string(ws), "mine": Json::boolean(false) }).value
  let status = (src.topic)("status", { "workspace": Json::string(ws) }).value
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

///|
/// The sidebar's edge (Rail.tsx SidebarEdge, Rail.css.ts edge): a strip 12 wide over its right edge, the library's edge
/// in it 3 in (its line on the sidebar's edge, its bar shown only with the pointer on the strip, its line not while the
/// sidebar is folded): dragged, the sidebar's width (180 to 480), while it is open or shown a while; pressed without
/// moving, the sidebar folded to the rail or opened again. Its words follow the pointer along it. `at`: its left
/// (Rail.css.ts edge), moved with the block (side_moves).
fn sidebar_edge(c : @ui.Ctx, at : Double) -> Unit {
  let id = c.id("sidebar-edge")
  // its width dragged open, and shown a while (the same width as open); folded, only pressed (any way it moves)
  let sized = !wide.folded || wide.peeking
  c.cursor(id, if wide.folded { Hand } else { ResizeX })
  let (least, most) = if sized { (side_min, side_max) } else { (wide.side_w, wide.side_w) }
  let said = @sf.handle_drag(c, id, wide.side_w, min=least, max=most)
  match said {
    Dragging(w) => wide.side_w = w
    Dropped(w) if sized => wide.side_w = w
    // (folded: the web's moves go nowhere, so a press that moved is a press)
    Dropped(_) | Pressed | Twice => wide.folded = !wide.folded
    Untouched => ()
  }
  let active = c.pressed(id) || said is Dragging(_)
  wide.edge_held = active
  let words = if wide.folded {
    @sf.t("web-main.sidebar.open")
  } else {
    @sf.t("web-pages.workspace.resizeSidebar") + " · " + @sf.t("web-main.sidebar.close")
  }
  c.layer(fn() {
    let strip = c.box(style=edge_strip, moves="edge", left=at, top=0.0, bottom=0.0, id~, fn() {
      @sf.edge_look(
        c,
        "sidebar-edge",
        over=false,
        on=c.lit(id) || c.focus_shown(id) || active,
        active~,
        line=!wide.folded,
      )
    })
    c.semantics(strip, Button, id~, label=words)
    @sf.edge_tip(c, "sidebar-edge", id, words)
  })
  |> ignore
}

///|
/// The edge's strip: 12 wide, the window's height (placed from its top to its foot), the library's 7-wide edge 3 in
/// (Rail.css.ts edge: its line 6 in, its bar 4 in).
// kept across runs: a value (no field of it changes)
let edge_strip : @ui.Style = @ui.style(w=S3, pl=@sf.edge_in)
