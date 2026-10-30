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
/// Which of the lists is shown (the sidebar's mode, station.tsx useSidebarMode): 全部 0, 我参与的 1, 监控中 2 (the
/// filter), 已归档 3.
pub fn list_mode(src : Source, w : Workspace) -> Int {
  match side_place() {
    "archive" => 3
    _ =>
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
    3 => "archive"
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
  // (under the window's buttons where they are the system's, at its left: macOS's; where they are the app's, at its
  // right, Windows', a rail's top row as a browser's: Rail.css.ts, the custom frame's only drags)
  let inset = @ui.window_keys_left()
  // Rail.css.ts rail, top: 56 wide, its places in its middle (9 from its edge; the sidebar reaches over its last 8, so
  // the rail is as wide as the rest), 9 under the last; its top row (41 under the window's buttons, else 5) 6 over its
  // first place; in the bar none, its first place 2 from the bar's top
  // its grounds' corner, all one, linked to the corner they stand in: the closed bar's; the tape's sidebar panel's;
  // open, the window's, its places where the bar's are (12 in: through the bar, the same corner), as round as the
  // bar's would have them where the window has none to follow
  let in_bar : @ui.CornerOf = Follow(@sf.closed_bar_of(rail_closed_ground_in), rail_closed_ground_in, @sf.small_corner)
  rail_round.val = if bar {
    @sf.rail_ground_radius(@sf.closed_bar_of(rail_closed_ground_in), rail_closed_ground_in)
  } else if wide.tape {
    @sf.rail_ground_radius(@sf.tape_side_corners()[3], @sf.rail_in_tape() + rail_ground_in)
  } else {
    @sf.rail_ground_radius(Window, closed_bar_in + rail_closed_ground_in, alone=in_bar.radius())
  }
  // (what it stands on: the marks hung on its grounds' corners on discs of it)
  rail_under.val = dock_ground(bar)
  let look = if bar {
    rail_closed
  } else if wide.tape {
    rail_open_tape()
  } else {
    rail_open
  }
  // (in a panel of the tape its first place as far under its top as its places are in from its side)
  let top_h = if bar {
    0.0
  } else if inset {
    rail_top_inset + rail_gap
  } else if wide.tape {
    // (and its first place's middle on the line of the sidebar's first row beside it, 新建对话's: pengxiao, 2026-10-25)
    dmax(@sf.rail_in_tape(), tape_first_row_mid() - rail_item_side / 2.0)
  } else {
    rail_top_web + rail_gap
  }
  c.box(style=look, moves="rail", id=rail_id, fn() {
    // its top row the window's title bar (the macOS app's buttons in it) across all of it, its padding too; not in the
    // closed bar
    if @ui.window_inset() && !bar {
      // (the window's top row across it at least, where its first place is higher than that: Windows', a browser's;
      // what is pressed there its places')
      title_row(c, "rail/top", dmax(top_h, closed_bar_top))
    }
    c.box(style=rail_head, fn() {
      c.box(style=rail_top.then(@ui.style(h=Fixed(top_h))), moves="rail-top", fn() {  }) |> ignore
      let places = rail_items(src, w.id)
      // a list's place lit while its list is the one shown (Rail.tsx `on`): 我参与的, 监控中 by the filter when they
      // are in the rail, else 对话; 已归档 while the archive is open (shownList)
      let list = list_place(list_mode(src, w))
      let listy = lit == "chats"
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
            "chats" | "mine" | "watching" | "archive" => listy && shown_list == place
            _ => lit == place
          }
          rail_place(c, src, w, place, on, places)
        }
      })
      |> ignore
    })
    |> ignore
    c.spacer()
    // what comes and goes (transfers.mbt), over the workspaces
    rail_transfers(c, src, w.id)
    // the workspaces (sfpages' workspace.mbt), on the rail's squares and with its corner's marks
    @sfpages.workspace_squares(c, src, w, all, {
      square: fn(ground, body, id) { rail_square(c, ground, body, id~) },
      corner: fn(tone) { rail_tone_mark(c, tone) },
    })
    // settings
    let gear = c.id("rail/settings")
    if c.clicked(gear) {
      // lit (in the settings): back out of them, to the chat last open (Rail.tsx: the settings' NavLink, in them); their
      // list folded for the page's room: shown over the page, or folded again (返回会话 at its top goes back)
      if lit == "settings" && wide.crowded {
        wide.peeking.set(!wide.peeking.get())
      } else if lit == "settings" {
        @sfbase.history_push()
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
    )
  })
  |> ignore
}

///|
/// The rail open and in the closed bar (Rail.css.ts rail): its places 8 in and 8 under the last (@sf.rail_in: where they
/// stand in the closed bar), 6 apart (open, as wide as the rail less the 8 the sidebar reaches over); as narrow as the
/// bar, 2 from its every edge.
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
/// How far in from the closed bar's edges its places' grounds stand: its 2 (rail_closed), a place's 38 less its 30.
let rail_closed_ground_in : Double = 2.0 + rail_ground_in

///|
/// How far in from a place's edges its ground stands (its 38 less its 30).
let rail_ground_in : Double = (rail_item_side - rail_sq_side) / 2.0

///|
/// The rail open in a panel of the tape (laid out Medium): its places in the panel's corners concentric with it
/// (@sf.rail_in_tape, as round as the panel is this frame), what it shows beside the sidebar as much wider.
fn rail_open_tape() -> @ui.Style {
  rail_open.then(@ui.style(w=Fixed(rail_shown_w + rail_tape_more()), pl=@sf.rail_in_tape_room(), pb=@sf.rail_in_tape_room()))
}

///|
/// The rail's inset open (rail_in: 8).
let rail_in_px : Double = 8.0

///|
/// How much more of the rail shows on the tape (its places further in: rail_open_tape), the sidebar as much narrower.
fn rail_tape_more() -> Double {
  @sf.rail_in_tape() - rail_in_px
}

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
/// A place's icon (20).
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
  // named for a screen reader (Rail.tsx's aria-label), and on hover beside it (its Tip, side right)
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
/// A ground of the rail (Rail.css.ts item's ground, workspaceItem, workspaceAdd): 30 round, on `ground`; `id` to press
/// it; its node.
fn rail_square(c : @ui.Ctx, ground : Int64, body : () -> Unit, id? : Int) -> Int {
  c.box(style=rail_sq.then(@ui.style(bg=Data(ground), radius=rail_round.val)), id?, body)
}

///|
// kept across runs: a value (no field of it changes)
let rail_sq : @ui.Style = @ui.style(w=Fixed(rail_sq_side), h=Fixed(rail_sq_side), align=ACenter, justify=JCenter)

///|
/// Its grounds' corner this frame, all one (@sf.rail_ground_radius): concentric with the closed bar's corner (open or
/// folded: its places stand where they do in the bar), or on the tape the sidebar's panel's. Said by the rail as it
/// is built.
// kept across runs: said by the rail each build
let rail_round : Ref[@ui.Radius] = Ref(Full)

///|
let rail_sq_side : Double = 30.0

///|
/// What the rail stands on this frame (dock_ground: the sidebar's ground, or the closed bar's or the tape's panel's).
/// Said by the rail as it is built.
// kept across runs: said by the rail each build
let rail_under : Ref[Int64] = Ref(0L)

///|
/// A mark hung on the top right corner of one of the rail's grounds (a place's, a workspace's square: drawn in it,
/// after what is on it): on the corner, not in it (docs/ui-panels.md, the user, 2026-10-17: @sf.on_corner), its middle
/// on the ground's curve where it turns 45° (its corner this frame: rail_round), on a disc of what the rail stands on
/// 2 round it (rail_under), which the ground, lit, shows cut out of it. `shown` of the way in (a list's as the sidebar
/// folds: Rail.css.ts listMark, from clear at 40%, moved with it).
fn rail_hung(c : @ui.Ctx, mark : () -> Unit, shown? : Double = 1.0) -> Unit {
  let reach = @sf.on_corner(c.theme().corner(rail_round.val), rail_hung_side, room=rail_sq_side / 2.0)
  c.layer(fn() {
    c.box(style=corner_end, fn() {
      c.box(style=rail_hung_room, tx=reach, ty=-reach, fn() {
        let i = c.box(style=rail_hung_ring.then(@ui.style(bg=Data(rail_under.val))), mark)
        if shown < 1.0 {
          c.look(i, @ui.look(alpha=shown, scale=fold_at(mark_folded_from, 1.0, shown)))
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What waits in a list of chats or another workspace (Rail.css.ts listMark, mark), hung on its ground's corner
/// (rail_hung): its rows' mark (ChatMark.css.ts chatMarkInline), or an invitation's dot.
fn rail_tone_mark(c : @ui.Ctx, tone : String, shown? : Double = 1.0) -> Unit {
  rail_hung(c, shown~, fn() {
    if tone == "invite" {
      @sfpages.invite_dot(c, "")
    } else {
      chat_mark(c, tone) |> ignore
    }
  })
}

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
/// What stands at a square's top right (a layer's whole, its end).
// kept across runs: a value (no field of it changes)
let corner_end : @ui.Style = @ui.css("w=Full align=AEnd")

///|
let mark_folded_from : Double = 0.4

///|
/// The sidebar's ground where it is a panel of its own: the closed bar's, floating over the page (closed_ground); on
/// the tape, a panel beside the page's as it is, the page's ground, which a phone's lists and pages share (the user,
/// 2026-10-25: the medium screen's grounds the phone's, no other colours).
pub fn apart_ground() -> Int64 {
  if wide.tape {
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
/// What waits on a place: a red dot 8 across hung on its ground's corner (Rail.css.ts count: rail_hung).
// kept across runs: a value (no field of it changes)
let rail_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Danger")

///|
/// One place of the rail: its icon, what waits on it a dot at its corner; pressed, its page.
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
  match c.menu_asked(id) {
    Some((x, y)) => wide.rail_menu = Some((place, x, y))
    None => ()
  }
  // dragged up or down (past a few points) while the rail is changed or with ⌘ held as it was pressed: to another place
  // in the rail, the others as they were until let go (where the pointer is read only by the place it drags)
  let py = fn() { c.pointer().1 }
  let dragged = match wide.rail_drag {
    Some((p, y0, _)) if p == place =>
      if c.pressed(id) {
        wide.rail_drag = Some((p, y0, py() - y0))
        true
      } else {
        // let go: its place by how far it went
        let dy = py() - y0
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
      wide.rail_drag = Some((place, py(), 0.0))
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
        wide.peeking.set(!wide.peeking.get())
      } else {
        sidebar_toggle()
        wide.peeking.set(side_folded())
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
    _ => false
  }
  let label = match place {
    "stations" => "Station：" + rail_stations_label(src, w.id)
    _ => rail_label(src, place)
  }
  // what wants the person in a list, as its rows' marks: while the sidebar is folded (open, the rows show it;
  // Rail.css.ts listMark)
  let tone = match place {
    "chats" => text(here, "tone")
    "mine" => text(here, "mineTone")
    "watching" => text(here, "watchingTone")
    _ => ""
  }
  rail_edit_frame(c, src, w, place, moved, fn() {
    rail_ground(c, id, on || (place == "attention" && wide.attention_open), fn(color) {
      if place == "stations" {
        // the stations at a glance (Sidebar.tsx RailStations: StationGlyph, 20)
        @sf.station_glyph(c, stations_at_glance(src, w.id).0, rail_icon_size, color, t.p.red) |> ignore
      } else {
        @sf.icon(c, rail_icon(place), size=rail_icon_size, color~) |> ignore
      }
      // hung on its ground's corner
      if tone != "" && wide.mark > 0.0 {
        rail_tone_mark(c, tone, shown=wide.mark)
      }
      if dot {
        rail_hung(c, fn() { c.box(style=rail_dot, fn() {  }) |> ignore })
      }
    }, label~, tipped=!rail_carded(place))
    // 对话's, 用量's: what the place is about at a glance, beside it as the pointer rests on it (in place of its tip: what
    // it said is in the card; 用量's with the card to share of the agents' week)
    if rail_carded(place) && !wide.editing {
      @sfpages.hover(c, "rail/card/" + place, id, side=Right, along=Start, fn() { @sfpages.rail_card(c, src, w, place) })
      |> ignore
    }
  })
}

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
/// A place gone to, from the rail or its menu (Rail.tsx `drawn`'s presses and `go`): 待处理 its panel; a list of chats
/// its list in the sidebar, the chat last open beside it; 已归档 the archive; the others their page.
pub fn rail_go(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  match place {
    "attention" => {
      wide.attention_open = !wide.attention_open
    }
    "chats" | "mine" | "watching" => {
      // its list in the sidebar (Rail.tsx toList): 对话 all of them, the others theirs
      let f = if place == "chats" { "all" } else { place }
      if filter_of(src, w.id) != f {
        app.filters[w.id] = f
        // (kept once, whichever build asked: Ctx::tell)
        c.tell("rail/list-filter", fn() {
          (src.call)("prefs.set", Json::object({ "listFilter": Json::object(Map::from_array([(w.id, Json::string(f))])) }), fn(_) {  })
        })
      }
      // the chats again: the chat last open stays open beside the list
      if app.nav.pages()[0] == Home && lit_place() == "chats" && !app.nav.pages().contains(Archived) {
        ()
      } else {
        @sfbase.go_place("chats") |> ignore
        wide.landed = ""
      }
    }
    "archive" => {
      @sfbase.history_push()
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      archive_side.landed = false
      app.nav.push(Archived)
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
/// when 对话 is out), the files, a place picked from the rail's menu (Rail.tsx inView, setExtra); "" none.
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
/// while it is changed, what can be added beside it.
pub fn rail_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  rail_menu(c, src, w)
  rail_adder(c, src, w)
}

///|
/// The rail's menu opened as a right click on `place` opens it (sffix's rail-menu).
pub fn open_rail_menu(place : String) -> Unit {
  wide.rail_menu = Some((place, 0.0, 0.0))
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
  let over = c.lit(id)
  // in on its row pointed at (Rail.css.ts menuAdd: transition opacity 140 ms); always to a finger, which hovers over
  // nothing
  let shown = @kit.animate(
    c,
    "rail-menu/add-shown/" + place,
    if @sf.pointed_or_finger(c, hot || over) { 1.0 } else { 0.0 },
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
/// A ＋ in the rail's menu: 24 round, in its row's end (@sf.menu_row_end), its icon 14.
// kept across runs: a value (no field of it changes)
let rail_menu_plus : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter").then(@sf.menu_row_end)

///|
// kept across runs: a value (no field of it changes)
let rail_menu_plus_on : @ui.Style = rail_menu_plus.then(@ui.css("bg=Hover"))

///|
let rail_menu_plus_icon : Double = 14.0

///|
/// The rail's menu 8 past its place, and no higher than the window's buttons' row (Rail.tsx: collisionPadding top 52).
let rail_menu_off : Double = 8.0

///|
let rail_menu_clear : Double = 52.0


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
  let items = rail_items(src, w.id)
  if items.length() > 1 && c.clicked(rm) {
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
            if adder_row(c, i, rail_label(src, i)) {
              let next = kept.copy()
              next.push(i)
              rail_keep(src, w.id, next)
            }
          }
        })
      }
      if none {
        @sf.panel_note(c, @sf.t("web-main.rail.allIn"))
      }
    },
  )
  // (pressing in the rail does not end it: its places are moved and taken out there)
  if !p.value && wide.editing {
    let (px, _, _) = c.pointer()
    if px >= rail_w {
      wide.editing = false
    }
  }
}

///|
/// A place that can be put in the rail, in the adder (parts.tsx PanelRow): its icon, its ＋ at its end.
/// True on the frame after it was pressed.
fn adder_row(c : @ui.Ctx, place : String, label : String) -> Bool {
  @sf.menu_item(
    c,
    label,
    key="rail/add/" + place,
    panel=true,
    icon=rail_icon(place),
    end="plus",
  )
}

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
/// The adder's head and its kinds 8 apart (Rail.css.ts adder: a grid, gap 8).
// kept across runs: a value (no field of it changes)
let adder_body : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// The rail in the closed bar (Rail.css.ts rail, closed): as narrow as the bar, its places 2 from its every edge.
pub let rail_closed_w : Double = 42.0

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
  let sized = !wide.folded || wide.peeking.get()
  // (folded, it is pressed alone: the hand, as what takes presses)
  if !wide.folded {
    c.cursor(id, ResizeX)
  }
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
    c.box(style=edge_strip, moves="edge", left=at, top=0.0, bottom=0.0, fn() {
      @sf.edge_look(
        c,
        "sidebar-edge",
        over=false,
        on=c.lit(id) || c.focus_shown(id) || active,
        active~,
        line=!wide.folded,
      )
      // (the whole strip, its line in its middle, as the web's: the list's bar's thumb, shown, takes the pointer where
      // it is over it, @ui's hit test; the user, 2026-10-28: 以 divider 为中心，左右各 6px)
      let strip = c.box(left=0.0, right=0.0, top=0.0, bottom=0.0, id~, fn() { })
      c.semantics(strip, Button, id~, label=words)
    })
    |> ignore
    @sf.edge_tip(c, "sidebar-edge", id, words)
  })
  |> ignore
}

///|
/// The edge's strip: 12 wide, the window's height (placed from its top to its foot), the library's 7-wide edge 3 in
/// (Rail.css.ts edge: its line 6 in, its bar 4 in).
// kept across runs: a value (no field of it changes)
let edge_strip : @ui.Style = @ui.style(w=S3, pl=@sf.edge_in)
