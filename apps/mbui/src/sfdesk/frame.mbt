// still.fail laid out Medium or Large (@sf.layout: a desktop's window from 600 wide, a tablet's, an opened foldable's,
// a phone on its side): the web app's wide frame (ember web/src/cloud/workspace.tsx WorkspaceShell,
// styles/shell.css.ts), which the desktop app shows too. The rail at the left (Rail.tsx: the places, the workspaces,
// settings: rail.mbt), the sidebar beside it on the same ground (the chats' lists, or the settings', the files', a
// place's), and the page the stack has on top in the rest (the chat open, a settings page, a folder…); laid out Small,
// the phone's pages. Both are the same stack of pages (app.nav) and the same core topics: the window resized across
// the breakpoint shows the same place either way.
//
// Medium, the rail and the sidebar, the page, and a chat's side panel while it is open are as they are Large, side by
// side on a tape wider than the window, each a panel apart (the closed bar's: 6 from the window's edges, 8 between
// them, on the sidebar's ground, each on the ground its pages have on a phone): the one in use whole, those beside it
// showing past its edges, as screens beside it, untinted (the user, 2026-10-25: the page's ground as a phone's). What shows of another is not used where it is: a press on it, a tap or a click, only brings it over (the
// tape moving, 380 ms), and what it holds answers from then on; dragged across, it comes with the finger and, let go,
// over or back (the user, 2026-10-25: only there; a drag on the one in use is its own). Nothing puts the sidebar away
// but a press on the page beside it (a chat chosen in it shows in the page, the sidebar still in use; no ⌘\, no lit
// place pressed again: asked, 2026-10-24); the sidebar at first. The side panel comes over as it opens (the page
// again as it closes); back goes from the side panel to the page, from the page to the sidebar.

///|
/// What the settings' pages read and call, and how they move, as the desktop has them (sfbase's settings_core_of): its
/// way home the stack's, a station's login its own card (login_card.mbt).
fn settings_core(src : Source, w : Workspace) -> Core {
  settings_core_of(src, w, home=nav_home, login_card=fn(c, station, id, marked) {
    login_card(c, settings_core(src, w), station, id, marked~)
  })
}

///|
/// What the frame keeps of its own (the rest is the stack's and the core's): the sidebar's width and how it was left,
/// how the block is moving, what is open from the rail and the lists.
pub(all) struct Wide {
  /// the sidebar's width, whether it is folded to the rail (⌘\), its edge in hand (pressed or dragged: its width kept,
  /// and the block moved, once it is let go)
  mut side_w : Double
  mut folded : Bool
  mut edge_held : Bool
  /// folded, whether it is shown a while over the page (Rail.tsx peekSidebar)
  mut peeking : Bool
  /// folded for the page's room whatever was chosen (page_beside_least), this frame; shown a while from the next as a
  /// place is pressed into; the page shown as the last build began (a row chosen while shown: another page, folded)
  mut crowded : Bool
  mut peek_next : Bool
  mut peek_top : Page?
  /// the sidebar shown (its workspace and group) and how it was kept (prefs `sidebars`)
  mut side_key : String
  mut kept_w : Double
  mut kept_folded : Bool
  /// the sidebar being drawn in the closed bar (what the web's sidebar does there, at once)
  mut in_bar : Bool
  /// the block closed to the bar this frame (the web's data-sidebar="closed"): what is drawn in it as there
  mut closed : Bool
  /// what the block last moved for, as it was last built (brand.tsx moveSidebar's callers: folded or opened as chosen,
  /// shown a while, a place with no sidebar of its own, a place's own width): a move sets out as it changes
  mut moved_as : (Bool, Bool, Bool, Double)?
  /// where the move has got to this frame: the sidebar's top row's height, its frosted bands' ground (0 the sidebar's,
  /// 1 the closed bar's), the lists' marks on the rail (0 gone, 1 in)
  mut brand_h : Double
  mut band : Double
  mut mark : Double
  /// the page's bars' padding at its left (clear of the closed bar) and their margins while the folded sidebar is shown
  /// a while: from its edge (the sidebar less 8 less how far the page moved) to the window's (how far it moved)
  mut bar_pl : Double
  mut bar_ml : Double
  mut bar_mr : Double
  /// how far the page moves aside while the folded sidebar is shown a while (worked out as it is shown: peek_shift),
  /// and where the page started as the last frame laid it out
  mut peek_shift : Double
  mut page_from : Double
  /// the chat last opened here by the frame (the core's last chat taken once per workspace)
  mut landed : String
  /// the rail's menu (from its right click): the place right clicked ("" the rail), where; a place dragged to another
  /// place in it: which, where the pointer went down, how far it went; the rail being changed (自定义侧边条); the ＋'s
  /// menu over the workspaces open
  mut rail_menu : (String, Double, Double)?
  mut rail_drag : (String, Double, Double)?
  mut editing : Bool
  /// 待处理's panel, the services' panel from the lists' foot, ⌘/'s shortcuts open
  mut attention_open : Bool
  mut jobs_open : Bool
  mut keys_open : Bool
  /// laid out Medium this frame (the rail and the sidebar beside the page on a tape: @sf.layout), with a sidebar to
  /// show; which of its panels is in use (kept while the frame is off the tape: a place with no sidebar, another
  /// layout; the sidebar at first); one asked over where no frame was being built (back); the chat shown last frame and
  /// the one whose side panel was open then (its panel opening brings it over)
  mut tape : Bool
  mut tape_at : TapePane
  mut tape_ask : TapePane?
  mut tape_chat : String
  mut tape_panel : String
  /// the one not in use being pulled over by what shows of it (tape_covers), and how far the finger has moved the tape
  /// since it took it
  mut tape_pull : TapePane?
  mut tape_drag : Double
}

///|
/// The panels on the tape (laid out Medium), from its start: the rail and the sidebar, the page, a chat's side panel
/// while it is open.
pub(all) enum TapePane {
  Side
  Page
  Panel
} derive(Eq, Show, Debug)

///|
pub let wide : Wide = {
  side_w: side_own,
  folded: false,
  edge_held: false,
  peeking: false,
  crowded: false,
  peek_next: false,
  peek_top: None,
  side_key: "",
  kept_w: 0.0,
  kept_folded: false,
  in_bar: false,
  closed: false,
  moved_as: None,
  brand_h: 0.0,
  band: 0.0,
  mark: 0.0,
  bar_pl: 0.0,
  bar_ml: 0.0,
  bar_mr: 0.0,
  peek_shift: 0.0,
  page_from: 0.0,
  landed: "",
  rail_menu: None,
  rail_drag: None,
  editing: false,
  attention_open: false,
  jobs_open: false,
  keys_open: false,
  tape: false,
  tape_at: Side,
  tape_ask: None,
  tape_chat: "",
  tape_panel: "",
  tape_pull: None,
  tape_drag: 0.0,
}

///|
/// The archive's list as it is looked at: the words looked for, how many asked for, the last read (shown while
/// another is asked for); whether the newest was opened beside it since the archive was opened.
pub(all) struct ArchiveSide {
  mut q : String
  mut limit : Int
  mut last : Json?
  mut landed : Bool
}

///|
pub let archive_side : ArchiveSide = { q: "", limit: archive_side_page, last: None, landed: false }

///|
/// How many the archive's list shows at first, and how many more each time it is scrolled near its end (Archive.tsx
/// ARCHIVE_PAGE).
pub let archive_side_page : Int = 60

///|
fn wide_reset() -> Unit {
  archive_side.q = ""
  archive_side.limit = archive_side_page
  archive_side.last = None
  archive_side.landed = false
  wide.side_w = side_own
  wide.folded = false
  wide.edge_held = false
  wide.peeking = false
  wide.crowded = false
  wide.peek_next = false
  wide.peek_top = None
  wide.side_key = ""
  wide.kept_w = 0.0
  wide.kept_folded = false
  wide.in_bar = false
  wide.closed = false
  wide.moved_as = None
  wide.brand_h = 0.0
  wide.band = 0.0
  wide.mark = 0.0
  wide.bar_pl = 0.0
  wide.bar_ml = 0.0
  wide.bar_mr = 0.0
  wide.peek_shift = 0.0
  wide.page_from = 0.0
  wide.landed = ""
  wide.rail_menu = None
  wide.rail_drag = None
  wide.editing = false
  wide.attention_open = false
  wide.jobs_open = false
  wide.keys_open = false
  wide.tape = false
  wide.tape_at = Side
  wide.tape_ask = None
  wide.tape_chat = ""
  wide.tape_panel = ""
  wide.tape_pull = None
  wide.tape_drag = 0.0
}

///|
/// Whether a window this wide is drawn as this frame: laid out Medium or Large (@sf.layout).
pub fn is_wide(c : @ui.Ctx) -> Bool {
  !(@sf.layout(c.width) is Small)
}

///|
/// The sidebar folded or opened (⌘\, the lit place pressed again, ⌘K's command); nothing on the tape, where the
/// sidebar is never put away but by a press on the page beside it (asked, 2026-10-24: it went away unasked).
pub fn sidebar_toggle() -> Unit {
  if !wide.tape {
    wide.folded = !wide.folded
  }
}

///|
/// Where the sidebar ends on a phone's or a tablet's screen whose fold stands upright between two halves (an iPhone Duo
/// opened as a book: @ui.system_fold's division): on the fold, the chats' list on one half and the page on the other
/// (within the sidebar's least and most). None without one.
fn side_on_fold() -> Double? {
  if !@sf.touch_system() {
    return None
  }
  for d in @ui.system_fold().divisions {
    let (x, _, w, h) = d
    if h > w {
      return Some(dmax(side_min, dmin(side_max, x + w / 2.0 - rail_w)))
    }
  }
  None
}

///|
/// The rail's width; the sidebar's own, its least and most (Rail.tsx SIDEBAR: 240, from 180 to 480; the stations' 280).
pub let rail_w : Double = 56.0

///|
/// On a phone's or a tablet's screen, the least a page is laid out at beside the sidebar: a phone's (360, the width
/// every page is made for); with less beside it (a small tablet held upright), the sidebar stays folded to the rail
/// whatever was chosen, its place's mark there saying what waits in it, shown over the page as the place is pressed
/// and folded again as what it shows is chosen or the page is tapped. Not on the tape (laid out Medium), where the page
/// in use has the window less what shows of the sidebar; a desktop's window keeps the page beside the sidebar as the
/// person sizes them.
pub let page_beside_least : Double = 360.0

///|
/// Whether the sidebar is folded to the rail now: as it was left (⌘\, its place pressed again, its edge), but never on
/// the tape (laid out Medium: the sidebar always whole there, the page beside it brought over instead); or kept so for
/// the page's room (page_beside_least).
pub fn side_folded() -> Bool {
  (wide.folded && !wide.tape) || wide.crowded
}

///|
let side_own : Double = 240.0

///|
let side_stations : Double = 280.0

///|
pub let side_min : Double = 180.0

///|
pub let side_max : Double = 480.0

///|
/// How long the sidebar takes to open, fold, or be shown a while (brand.tsx moveSidebar: motion.ts moveState's 380 ms,
/// its ease out).
pub let side_move_ms : Double = @sf.move_state_ms

///|
/// What moves as the sidebar opens, folds, is shown a while or goes to another place's width: brand.tsx moveSidebar's
/// list, its selectors the boxes' `moves` names, what of each moves by its CSS names as the web lists them. The column
/// the page starts after (the shell's grid-template-columns: the page is laid out in what it leaves, so a value), the
/// page moved aside (main's left, as wide as it was), the edge, the rail as narrow as the closed bar and its top row, the
/// block's margins (values: it is placed by them), corner, ground, shadow and line, the sidebar in it (and whether it
/// is drawn at all), its frosted bands' ground and top row, the lists' marks on the rail, the page bars' room.
// kept across runs: a table, never written
let side_moves : Array[(String, Array[String])] = [
  ("shell", ["--side-col"]),
  ("main-shift", ["width"]),
  ("edge", ["left"]),
  ("rail", ["width", "padding-left", "padding-top", "padding-bottom"]),
  ("rail-top", ["height"]),
  (
    "dock",
    [
      "border-radius", "background-color", "box-shadow", "--dock-ml", "--dock-mt", "--dock-mr", "--dock-mb", "--dock-line",
    ],
  ),
  ("sidebar", ["width", "--side-shown"]),
  ("nav-band", ["--band"]),
  ("brand", ["--brand"]),
  ("list-mark", ["--mark"]),
  ("page-bar", ["padding-left", "margin-left", "margin-right"]),
  ("page-bar-end", ["width"]),
  ("side-update", ["left", "transform"]),
]

///|
/// The closed bar (shell.css.ts dock, closed): 6 from the window's edges (44 from its top under the window's buttons'
/// row where they are in the app's top row), 8 from the page.
pub let closed_bar_in : Double = @sf.window_in

///|
let closed_bar_top : Double = 44.0

///|
let closed_bar_gap : Double = 8.0

///|
/// The closed bar's shadows (blur, fall, how much of the shadow's colour): there but clear open (0 8px 24px
/// transparent, so it moves in), faint by the page closed (0 2px 10px, the shadow's colour at 30%), a floating panel's
/// shown a while (0 8px 24px).
let open_shadow : (Double, Double, Double) = (24.0, 8.0, 0.0)

///|
let closed_shadow : (Double, Double, Double) = (10.0, 2.0, 0.3)

///|
let closed_peek_shadow : (Double, Double, Double) = (24.0, 8.0, 1.0)

///|
/// Open, the sidebar reaching 8 into the rail's 56, empty there right of its places (Sidebar.css.ts: outsetStart(8)):
/// the rail as wide as what it shows of itself, the sidebar 8 wider.
let side_into_rail : Double = 8.0

///|
/// How far the page clears the folded sidebar shown a while, and stays from the window's edge (Rail.tsx PEEK_GAP).
pub let peek_gap : Double = 16.0

///|
/// `open` at `e` of the way to `closed`.
fn fold_at(open : Double, closed : Double, e : Double) -> Double {
  open + (closed - open) * e
}

///|
/// The rail and the sidebar as one block (shell.css.ts dock) in its column `col` (the shell's grid's first, a phone's or
/// a tablet's bars `top` and `foot` clear), as the web's CSS has it: open, the column's whole, the sidebar's ground;
/// closed (`bar`), the closed bar: 6 from the window's edges (under its buttons' row where they are in the app's top
/// row), 8 from the page, as wide as the rail, a floating panel's ground, its line and a faint shadow, its corner
/// concentric with the places' grounds 6 in; shown a while (`peek`), reaching over the page as wide as the rail and the
/// sidebar (its margin past the column), a floating panel's shadow. Moved from what it was to that together with every
/// part of it (side_moves), the sidebar in it not moved across: the block's edges close round it. `s`: the sidebar's
/// width; `x`: how far the tape is moved (laid out Medium: tape_frame).
fn dock(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  bar : Bool,
  peek : Bool,
  s : Double,
  col : Double,
  top : Double,
  foot : Double,
  x : Double,
) -> Unit {
  let t = @sf.theme()
  // shell.css.ts dock, closed: margin 6px 8px 6px 6px (its top 44 under the window's buttons); shown a while,
  // margin-right calc(8px - the sidebar's width): where their move has got to, the block placed and sized by them
  // on the tape (open, apart from the page), a panel of its own as the closed bar is: 6 from the window's edges (its
  // buttons in its top row), 8 from the page's panel
  let apart = wide.tape && !bar
  let above = if @ui.window_inset() { closed_bar_top } else { closed_bar_in }
  let ml = c.moved("--dock-ml", if bar || apart { closed_bar_in } else { 0.0 })
  let mt = c.moved("--dock-mt", if bar { above } else if apart { closed_bar_in } else { 0.0 })
  let mr = c.moved("--dock-mr", if apart {
    closed_bar_gap
  } else if !bar {
    0.0
  } else if peek {
    closed_bar_gap - s
  } else {
    closed_bar_gap
  })
  let mb = c.moved("--dock-mb", if bar || apart { closed_bar_in } else { 0.0 })
  let (blur, shadow_y, shadow_k) = if peek {
    closed_peek_shadow
  } else if bar || apart {
    closed_shadow
  } else {
    open_shadow
  }
  // its line (::after's opacity: --dock-line), and what is in the sidebar drawn while any of it shows: open, shown a
  // while, or still on its way to the bar (the sidebar's box always, so what it was is where a move sets out from)
  let line = c.moved("--dock-line", if bar || apart { 1.0 } else { 0.0 })
  let showing = c.moved("--side-shown", if !bar || peek { 1.0 } else { 0.0 })
  let shown = !bar || peek || showing > 0.0
  // the sidebar beside the rail: open its own width and 8 more, reaching 8 into the rail's; the group's in the bar
  let side_w = if bar { s } else { s + side_into_rail }
  // (a panel's corners the tape's sidebar's, the closed bar's its own: each in the window's the window's less its 6 from
  // it where it follows it)
  let look = if apart {
    dock_apart.then(@ui.style(radius=@sf.corners_radius(tape_pane_corners(Side, false))))
  } else if bar {
    dock_closed.then(@ui.style(radius=@sf.closed_bar_corner(rail_closed_ground_in)))
  } else {
    dock_open
  }
  // (a panel of its own, the closed bar or on the tape: on its ground (apart_ground), as the lists' bands on it are: one
  // ground under all of it, whatever the theme's surface is on this system)
  let look = if bar || apart { look.then(@ui.style(bg=Data(apart_ground()))) } else { look }
  let dock_w = dmax(0.0, col - ml - mr)
  let dock_h = dmax(0.0, c.height - top - foot - mt - mb)
  c.layer(fn() {
    c.box(style=dock_column.then(@ui.style(w=Fixed(col))), tx=x, fn() {
      let b = c.box(
        style=look.then(
          @ui.style(
            w=Fixed(dock_w),
            h=Fixed(dock_h),
            border_color=Data(@sf.alpha(t.p.line, line)),
            shadow=Cast(blur, shadow_y, @sf.alpha(t.p.shadow, shadow_k)),
          ),
        ),
        moves="dock",
        left=ml,
        top=top + mt,
        fn() {
          rail(c, src, w, all, bar)
          c.box(style=dock_side.then(@ui.style(w=Fixed(side_w))), moves="sidebar", fn() {
            if shown && s > 0.0 {
              // (in the bar: what the web's sidebar does there, at once, as the bar starts out)
              wide.in_bar = side_folded()
              sidebar(c, src, w, side_w)
              wide.in_bar = false
            }
          })
          |> ignore
        },
      )
      ignore(b)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The block's column, the window's height.
// kept across runs: a value (no field of it changes)
let dock_column : @ui.Style = @ui.css("h=Full")

///|
/// The block open (the sidebar's ground, its line and shadow there but clear) and closed to the bar (a floating
/// panel's ground, its corner concentric with the places' grounds 6 in: shell.css.ts dock, closed); both cut what goes
/// past their edges.
// kept across runs: a value (no field of it changes)
let dock_open : @ui.Style = @ui.css("row bg=Sidebar border=B1 clip")

///|
// kept across runs: a value (no field of it changes)
let dock_closed : @ui.Style = @ui.css("row bg=Surface border=B1 clip")

///|
/// On the tape, a panel of its own as the closed bar is, its corner the page's panel's: all the tape's panels alike
/// (asked, 2026-10-24).
// kept across runs: a value (no field of it changes)
let dock_apart : @ui.Style = @ui.css("row bg=Surface border=B1 clip")

///|
/// The sidebar in the block: its width, the block's height.
// kept across runs: a value (no field of it changes)
let dock_side : @ui.Style = @ui.css("h=Full")

///|
/// How far the page moves aside for the folded sidebar shown a while (Rail.tsx peekShift, shell.css.ts main's
/// --peek-shift), worked out once as it is shown, from the page folded: as far as what it shows (`shown`, across, its
/// bars left out) is from clearing the sidebar 16 past its edge, but no further than the room on its right allows (16
/// from the window's edge, the same from what it shows) nor than the sidebar is wide; moved, not laid out anew. What it
/// shows as the last frame laid it out, the page then `from` across: from open, laid out wider than folded, what it
/// shows taken as centred in it (the pages that move aside, a chat's column, a new chat's), the folded page not laid
/// out yet.
fn peek_shift(c : @ui.Ctx, shown : (Double, Double)?, from : Double, s : Double) -> Double {
  match shown {
    Some((left, right)) => {
      // (the folded page's middle where the page then had its own)
      let moved = (rail_w - from) / 2.0
      let reach = closed_bar_in + rail_closed_w + s + peek_gap
      let room = c.width - 2.0 * peek_gap - dmin(right + moved, c.width)
      dmax(0.0, dmin(s, dmin(room, reach - dmax(left + moved, rail_w)))).round()
    }
    None => 0.0
  }
}

///|
/// The wide frame (WorkspaceShell): the rail and the sidebar on the sidebar's ground, the page in the rest. What opens
/// over them is drawn after it (overlays).
pub fn frame(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  // pointed at with a mouse: the wheel and the trackpad scroll, a drag is the pointer's own; with a finger (a tablet's
  // screen, whatever the frame): it drags the lists
  let finger = @ui.pointing() is Finger
  c.mouse_drags_lists(finger)
  // a device waiting to be confirmed in the workspace's safe mode: beside the rail (the workspaces, settings) only
  // what it waits on, no chats' list (its stations refuse it), unless a settings page is open
  let gated = lit_place() != "settings" && @settings.lock_waiting(settings_core(src, w), w.id)
  // (连接 and 用量: a page across the pane, no sidebar)
  let bare = place_bare(lit_place())
  // the sidebar of this place and workspace, as it was left
  side_follow(c, src, w.id)
  let own = !gated && !bare
  // laid out Medium, with a sidebar to show: the rail and the sidebar beside the page on the tape
  wide.tape = own && @sf.layout(c.width) is Medium
  // (off the tape, a phone's or a tablet's screen with less than a phone's width for the page beside it: folded
  // whatever was chosen)
  wide.crowded = own &&
    !wide.tape &&
    @sf.touch_system() &&
    c.width - rail_w - side_on_fold().unwrap_or(wide.side_w) < page_beside_least
  side_crowded()
  // (on a fold standing upright, the sidebar ends on it while it is not folded away, but on the tape)
  let on_fold = if side_folded() || wide.tape { None } else { side_on_fold() }
  // folded to the rail's bar (and a page with no sidebar of its own: Rail.tsx showSidebar), shown a while beside it as
  // the pointer comes on it: each part built as the web's CSS has it in that state, and moved there from what it showed
  // as the state changes, all together (brand.tsx moveSidebar: 380 ms, ease out); not the width the edge drags, which
  // follows the pointer at once
  let bar = (own && side_folded()) || bare
  let s = if gated { 0.0 } else { on_fold.unwrap_or(wide.side_w) }
  let bars = @ui.system_bars()
  let top = bars.top
  let foot = bars.bottom
  let inset = @ui.window_inset()
  let peek_r = rail_w - closed_bar_gap + (if wide.peeking { s } else { 0.0 })
  side_peek(c, closed_bar_in, top + (if inset { closed_bar_top } else { closed_bar_in }), peek_r, c.height - foot - closed_bar_in)
  let peek = own && side_folded() && wide.peeking
  // what the page shows across as the last frame laid it out (its bars left out): what it moves aside for, shown a
  // while
  let page_id = c.id("main-page")
  let shown = c.shown_across(page_id, but="page-bar")
  // it moves for what it is asked (brand.tsx moveSidebar's callers): folded or opened as chosen (⌘\, its place pressed
  // again), shown a while or no longer, a place with no sidebar of its own come to or left, another place's own width;
  // not for the window's room folding it (crowded), a fold's place or the tape coming or going, which put it as they
  // have it at once, nor for its edge in hand, which it follows at once
  let cause = (wide.folded, wide.peeking, gated || bare, wide.side_w)
  match wide.moved_as {
    Some(was) if was != cause && !wide.edge_held => {
      // shown a while from now: how far the page moves aside, worked out once as it starts (Rail.tsx markPeek)
      if peek && !was.1 {
        wide.peek_shift = peek_shift(c, shown, wide.page_from, s)
      }
      c.move_state(side_moves, duration=side_move_ms)
    }
    _ => ()
  }
  wide.moved_as = Some(cause)
  // the column the page starts after (shell.css.ts shell: the rail's 56 and the sidebar open, the rail's folded) where
  // its move has got to: the page laid out as wide as it leaves
  // (on the tape apart from the page: its panel 6 in from the window's edge, 8 from the page's: tape_apart; as much
  // wider as its rail shows more there, its places in the panel's corners concentric with it: rail_open_tape)
  let col = c.moved(
    "--side-col",
    rail_w + (if bar { 0.0 } else { s }) + (if wide.tape { tape_apart + rail_tape_more() } else { 0.0 }),
  )
  wide.page_from = col
  // on the tape: a chat's side panel open beside it, a panel of its own after the page's; the page's panel as wide as
  // the window leaves past what shows of the sidebar with the page in use and of the side panel after it, else 6 in
  // from the window's edge; which is in use and how far the tape is moved
  let peek_w = tape_peek(c.width)
  let panel_of = if wide.tape { side_open_for(src, app.nav.top()) } else { None }
  let panel_w = match panel_of {
    Some(_) => tape_side_width(c.width, peek_w, closed_bar_in + closed_bar_gap)
    None => 0.0
  }
  let main_w = if !wide.tape {
    dmax(0.0, c.width - col)
  } else if panel_of is Some(_) {
    dmax(0.0, c.width - 2.0 * peek_w)
  } else {
    dmax(0.0, c.width - peek_w - closed_bar_in)
  }
  let at = tape_at(c.width, col, peek_w, main_w, panel_w)
  // (the chat shown has its view: what its side panel shows is known)
  let known = match app.nav.top() {
    Chat(r) | History(r, _, _) => (src.topic)("chat", chat_params(r)).value is Some(_)
    _ => true
  }
  let tape_x = tape_frame(c, panel_of, at, known)
  // shown a while, the page moved aside as wide as it was (shell.css.ts main's left: --peek-shift), its bars from the
  // sidebar's edge to the window's (brand.css.ts); closed, their padding clear of the bar (and of the window's buttons)
  let shift = if peek { wide.peek_shift } else { 0.0 }
  // (closed, with 更新 over their start: clear of it too, brand.css.ts)
  wide.closed = bar
  let updating = !gated && update_shown()
  wide.bar_pl = if !bar {
    bar_in
  } else if updating {
    if inset {
      bar_update_inset
    } else {
      bar_update_in
    }
  } else if inset {
    bar_closed_inset
  } else {
    bar_in
  }
  wide.bar_ml = if peek { dmax(0.0, s - closed_bar_gap - shift) } else { 0.0 }
  wide.bar_mr = shift
  // what the sidebar's parts work out from, where the move has got to: its top row (Sidebar.css.ts brand: none in the
  // closed bar), its frosted bands' ground (the block's), the lists' marks on the rail (Rail.css.ts listMark: in as it
  // folds)
  // (with 更新 over it and no window's buttons, as on a phone's wide screen: their row, its room, not over the first row)
  wide.brand_h = c.moved("--brand", if bar { 0.0 } else if inset || updating { side_top_inset } else { side_top_web })
  // (on the tape the sidebar in a panel of its own: its bands on a floating panel's ground, as in the closed bar)
  wide.band = c.moved("--band", if bar || wide.tape { 1.0 } else { 0.0 })
  wide.mark = c.moved("--mark", if bar { 1.0 } else { 0.0 })
  // the core's chat last open, else a new chat: there is always a page beside the list (workspace.tsx WorkspaceHome)
  land(src, w)
  let page_h = dmax(0.0, c.height - top - foot)
  // on the tape the page's panel 6 in from the bars' edges too
  let panel_top = top + closed_bar_in
  let panel_h = dmax(0.0, page_h - 2.0 * closed_bar_in)
  // the page in its pane, `ph` high
  let page_in = fn(ph : Double) {
    c.sized(main_w, ph, fn() {
      let page = fn() {
        if gated {
          c.box(style=frame_gate.then(@ui.style(w=Fixed(main_w), h=Fixed(c.height))), fn() {
            let core = settings_core(src, w)
            @sfpages.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
          })
          |> ignore
        } else {
          // a chat and a new chat switched between: the composer moving, the rest crossfading (switch.mbt)
          page_switch_frame(c)
          c.nav_flat(app.nav, fn(page) { main_page(c, src, w, all, invited, page) }, bg=@sf.theme().p.bg)
          |> ignore
        }
      }
      // the page's words are picked with the pointer and copied, as the web's (the sidebar's are not); a finger
      // picks them as on a phone (pick.mbt)
      if finger {
        page()
      } else {
        c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), page)
      }
    })
  }
  // what the page or the sidebar takes back for (a sheet, a menu, a step of a page's) goes back before the stack does
  let took = c.took_back(fn() {
    if wide.tape {
      // on the tape, on the ground its panels stand on, each put where it is on the tape and drawn moved as far as the
      // tape has got (tx: moved as a whole, nothing in it laid out again frame by frame as the tape moves): the page's a
      // panel of its own, apart from the sidebar's (6 in from the bars, its corner the sidebar's panel's, a line round
      // it), and a chat's side panel open after it, 8 from it, as high
      c.box(style=frame_tape, fn() {
        // a right click in it: what is picked copied (context_menu.mbt)
        context_page(c, page_id)
        let page_corners = tape_pane_corners(Page, panel_of is Some(_))
        let pane = tape_behind(c, Page, fn() { c.box(
          style=page_apart.then(
            @ui.style(w=Fixed(main_w), h=Fixed(panel_h), radius=@sf.corners_radius(page_corners)),
          ),
          left=col,
          top=panel_top,
          tx=tape_x,
          id=page_id,
          fn() {
            @sf.pane_round.val = Some(@sf.corner_radii(page_corners))
            page_in(panel_h)
            @sf.pane_round.val = None
          },
        ) })
        // what moves in the page of its own (the composer) takes its place from the page's foot: the tape moving the
        // page, a keyboard making it shorter, move none of it (it goes with the page, at once)
        @motion.scope(c, pane, bottom=true)
        match panel_of {
          Some(r) =>
            tape_behind(c, Panel, fn() { c.box(
              style=page_apart.then(
                @ui.style(
                  w=Fixed(panel_w),
                  h=Fixed(panel_h),
                  radius=@sf.corners_radius(tape_pane_corners(Panel, true)),
                ),
              ),
              left=col + main_w + closed_bar_gap,
              top=panel_top,
              tx=tape_x,
              fn() {
                @sf.pane_round.val = Some(@sf.corner_radii(tape_pane_corners(Panel, true)))
                c.sized(panel_w, panel_h, fn() { tape_side(c, src, w, r) })
                @sf.pane_round.val = None
              },
            ) })
            |> ignore
          None => ()
        }
      })
      |> ignore
    } else {
      c.box(style=frame_row, fn() {
        // the rail's and the sidebar's column (the block over it, below), and the page moved aside by as much as it is
        c.box(style=frame_col.then(@ui.style(w=Fixed(col))), fn() {  }) |> ignore
        c.box(style=frame_col.then(@ui.style(w=Fixed(shift))), moves="main-shift", fn() {  }) |> ignore
        // a right click in it: what is picked copied (context_menu.mbt)
        context_page(c, page_id)
        // (the window cutting what goes past its edge)
        let pane = c.box(style=frame_main.then(@ui.style(w=Fixed(main_w))), id=page_id, fn() {
          if top > 0.0 {
            c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
          }
          page_in(page_h)
        })
        // (what moves in the page of its own takes its place from the page's foot: a keyboard, the sidebar moving the
        // page aside, move none of it)
        @motion.scope(c, pane, bottom=true)
      })
      |> ignore
    }
    tape_behind(c, Side, fn() { dock(c, src, w, all, bar, peek, s, col, top, foot, tape_x) })
    if updating {
      update_button(c, src, bar, s, inset, top, tape_x)
    }
    if wide.tape {
      let panels = [(Side, closed_bar_in, col - tape_apart), (Page, col, main_w)]
      if panel_of is Some(_) {
        panels.push((Panel, col + main_w + closed_bar_gap, panel_w))
      }
      tape_covers(c, tape_x, at, panels, panel_top, panel_h)
    }
  })
  // (the sidebar's edge: on its right edge open, between the bar and the page folded, at the edge of the sidebar shown
  // a while; dragged, unless it is on the fold, folded for the page's room or on the tape)
  if !bare && on_fold is None && !wide.crowded && !wide.tape {
    let at = if !bar {
      rail_w + s - edge_half
    } else if peek {
      closed_edge + s
    } else {
      closed_edge
    }
    sidebar_edge(c, at)
  }
  // back (⌘[, a mouse's back button), the shell's one way (sfbase's go_back: wide_back here), after what the page or
  // the sidebar takes it for
  if !took && !app.menu {
    match @sfbase.back_step() {
      Some(f) => c.take_back(f)
      None => ()
    }
  }
  // the pages of web services' and visualizations' tabs closed, no longer drawn, let go (service_tab.mbt)
  sv_sweep(c, src)
}

///|
/// Back on the wide frame (docs/architecture.md, the tiers' table): what is over the whole window (a screen, a file
/// read or played) put away first, a page of the stack popped. On the tape, with a chat's side panel in use, the page
/// brought over; with the page in use, the sidebar brought over from the page the sidebar opened (the chats' place's
/// chat, a settings page), else the page popped; nothing with the sidebar in use (the system's: as from a phone's
/// list). Laid out Large, the stack's top popped, but for the new chat beside the chats alone: the page there is never
/// empty (land: popped, a new chat would come again), so nothing to go back to.
pub fn wide_back() -> (() -> Unit)? {
  let over_all = app.nav.top() is (Screen(_) | DriveRead(_) | DrivePlay(_))
  if wide.tape && !over_all {
    match wide.tape_at {
      Side => None
      Panel => Some(fn() { wide.tape_ask = Some(Page) })
      Page =>
        if app.nav.depth() <= 2 {
          Some(fn() { wide.tape_ask = Some(Side) })
        } else {
          Some(fn() { app.nav.pop() |> ignore })
        }
    }
  } else if app.nav.depth() > 2 || (app.nav.depth() == 2 && !(app.nav.pages() == [Home, NewChat])) {
    Some(fn() { app.nav.pop() |> ignore })
  } else {
    None
  }
}

///|
/// How much of the one not in use shows on the tape: of the sidebar past the page's edge, the page in use; the page
/// beside the sidebar shows what the sidebar leaves of the window. A fifth of the window, 72 at least.
fn tape_peek(width : Double) -> Double {
  dmax(72.0, (width / 5.0).round())
}

///|
/// What moves as the other comes over on the tape: the tape (how far it is moved), as the sidebar moves (380 ms, its
/// ease out).
// kept across runs: a table, never written
let tape_moves : Array[(String, Array[String])] = [
  ("tape", ["--tape-x", "--behind-side", "--behind-page", "--behind-panel"]),
]

///|
/// Where the tape is with each of its panels in use, a window `width` wide (`d`: where the page's panel starts on it,
/// `peek`: what shows of the one before or after the page, `page_w`, `panel_w`: the page's panel's width and the side
/// panel's, 0 closed): the sidebar's left at the window's (0); the page's left `peek` in; the side panel's right 6 in
/// from the window's.
fn tape_at(width : Double, d : Double, peek : Double, page_w : Double, panel_w : Double) -> (Double, Double, Double) {
  let panel = width - closed_bar_in - (d + page_w + closed_bar_gap + panel_w)
  (0.0, peek - d, panel)
}

///|
/// Where the tape is with `p` in use (`at`: tape_at's).
fn tape_x_of(at : (Double, Double, Double), p : TapePane) -> Double {
  match p {
    Side => at.0
    Page => at.1
    Panel => at.2
  }
}

///|
/// The tape this frame: which of its panels is in use — asked over (back, a press on what shows of another), or brought
/// over: the side panel as it opens beside the chat it was closed for, the page again as it closes — and how far the
/// tape is moved where its move has got to. 0 off the tape. `panel`: the chat whose side panel is open (tape_side);
/// `at`: tape_at's.
fn tape_frame(c : @ui.Ctx, panel : ChatRef?, at : (Double, Double, Double), known : Bool) -> Double {
  if !wide.tape {
    wide.tape_ask = None
    wide.tape_chat = ""
    wide.tape_panel = ""
    wide.tape_pull = None
    wide.tape_drag = 0.0
    return 0.0
  }
  // a press on what shows of another (tape_covers); or what shows of it dragged across: the tape in the hand from there,
  // let go brought over or back (tape_let_go)
  for p in [Side, Page, Panel] {
    let id = c.id("tape/" + p.to_string())
    if c.clicked(id) {
      wide.tape_ask = Some(p)
    }
    match c.drag_of(id) {
      Some(d) => {
        let (dx, _) = d.take_move()
        if d.down && d.moving && p != wide.tape_at && wide.tape_pull is None {
          wide.tape_pull = Some(p)
          wide.tape_drag = 0.0
        }
        if wide.tape_pull == Some(p) {
          if d.down {
            wide.tape_drag = tape_pull_clamp(at, p, wide.tape_drag + dx)
          } else {
            d.take_end() |> ignore
            tape_let_go(c, at, p, d.vx * 1000.0)
          }
        }
      }
      None => ()
    }
  }
  // the chat's side panel opened beside it (the same chat as before, its panel closed then, its view come): the panel
  // comes over; closed while in use, the page. Another chat shown while a panel was in use: its page, not the panel
  // open in it (pengxiao, 2026-10-25: the chat in the middle is what one comes to; a panel shown as its view comes is
  // not one opened). Nothing else moves the tape by itself: a chat opened from the sidebar shows in the page beside
  // it, the sidebar still in use (a new chat asks for its page: new_chat)
  // a passage of a message picked while the page is not in use (held where it shows beside the sidebar): the page
  // comes over with it, its bar there to be pressed (pengxiao, 2026-10-25: 引用 pressed there went to what showed of
  // the page and brought it over, quoting nothing)
  if @sfbase.pk.ts != "" && wide.tape_at != Page && wide.tape_ask is None && wide.tape_pull is None {
    wide.tape_ask = Some(Page)
  }
  let chat = match app.nav.top() {
    Chat(r) | History(r, _, _) => chat_key(r)
    _ => ""
  }
  let open = match panel {
    Some(r) => chat_key(r)
    None => ""
  }
  if wide.tape_ask is None {
    if chat != wide.tape_chat {
      if wide.tape_at == Panel {
        wide.tape_ask = Some(Page)
      }
    } else if open != "" && open != wide.tape_panel && wide.tape_panel != tape_unknown && known {
      wide.tape_ask = Some(Panel)
    } else if open == "" && known && wide.tape_at == Panel {
      wide.tape_ask = Some(Page)
    }
  }
  wide.tape_chat = chat
  wide.tape_panel = if known { open } else { tape_unknown }
  match wide.tape_ask {
    Some(p) => {
      wide.tape_ask = None
      if p != wide.tape_at && !(p == Panel && open == "") {
        wide.tape_at = p
        // the page no more in use: its field lets go of the keyboard (what shows of it takes nothing)
        if p != Page {
          c.blur()
        }
        c.move_state(tape_moves, duration=side_move_ms)
      }
    }
    None => ()
  }
  // (another brought over while one was pulled, by back or a press: the pull is over)
  if wide.tape_pull == Some(wide.tape_at) {
    wide.tape_pull = None
    wide.tape_drag = 0.0
  }
  let pulled = if wide.tape_pull is Some(_) { wide.tape_drag } else { 0.0 }
  c.moved("--tape-x", tape_x_of(at, wide.tape_at) + pulled)
}

///|
/// What the frame knew of the shown chat's side panel while its view had not come (tape_frame): neither open nor not.
let tape_unknown : String = "?"

///|
/// What `body` draws of panel `p` (its answer): on the tape behind the one in use, on the ground a step darker
/// (@sf.behind_ground), what is on it as it is; in use, or off the tape, on its own.
fn[T] tape_behind(c : @ui.Ctx, p : TapePane, body : () -> T) -> T {
  // (how far behind it is: as far as the tape's move has got, the tape and its grounds one move: tape_moves)
  let k = if wide.tape { c.moved(tape_behind_var(p), if wide.tape_at == p { 0.0 } else { 1.0 }) } else { 0.0 }
  if k <= 0.0 {
    return body()
  }
  let mut out : T? = None
  @sf.with_ground(c, @sf.behind_ground(k~), fn() { out = Some(body()) })
  out.unwrap()
}

///|
/// The move's name for how far panel `p` is behind (tape_moves).
fn tape_behind_var(p : TapePane) -> String {
  match p {
    Side => "--behind-side"
    Page => "--behind-page"
    Panel => "--behind-panel"
  }
}

///|
/// How far the finger may move the tape pulling `p` over: from where it is with the one in use to where it has `p` in
/// use, no further either way (`at`: tape_at's).
fn tape_pull_clamp(at : (Double, Double, Double), p : TapePane, drag : Double) -> Double {
  let span = tape_x_of(at, p) - tape_x_of(at, wide.tape_at)
  if span < 0.0 {
    dmax(span, dmin(0.0, drag))
  } else {
    dmax(0.0, dmin(span, drag))
  }
}

///|
/// The one pulled over let go (`v`: the finger's speed across as it left, px/s): brought over when pulled a third of
/// the way or flung toward it, else back to the one in use; on from where the finger left the tape, as the tape moves.
fn tape_let_go(c : @ui.Ctx, at : (Double, Double, Double), p : TapePane, v : Double) -> Unit {
  let span = tape_x_of(at, p) - tape_x_of(at, wide.tape_at)
  let k = if span == 0.0 { 0.0 } else { wide.tape_drag / span }
  let fling = v.abs() > tape_fling
  let toward = fling && (v > 0.0) == (span > 0.0)
  let away = fling && !toward
  wide.tape_pull = None
  wide.tape_drag = 0.0
  if toward || (k > tape_pull_over && !away) {
    wide.tape_ask = Some(p)
  } else {
    c.move_state(tape_moves, duration=side_move_ms)
  }
}

///|
/// How much of the way a panel pulled over must have come to be brought over when let go, and how fast a finger
/// leaving it (px/s) flings it over or back whatever the way it came (the 奏 deck's swipe's fling, decisions.mbt).
let tape_pull_over : Double = 0.3

///|
let tape_fling : Double = 900.0

///|
/// What shows of the panels not in use on the tape, each under a cover of its shape that takes what is done there, drawn
/// nothing (the panel as it is, its pages' ground a phone's): a press there, a tap or a click, brings it over
/// (tape_frame) and goes to nothing it holds; dragged across, it comes with the finger (the tape in the hand) and, let go,
/// over or back. Drags on the one in use are its own (a row swiped, words scrolled across). `x`: how far the tape is
/// moved; `at`: tape_at's; `panels`: each panel, its left on the tape and its width; `top`, `h`: theirs.
fn tape_covers(
  c : @ui.Ctx,
  x : Double,
  at : (Double, Double, Double),
  panels : Array[(TapePane, Double, Double)],
  top : Double,
  h : Double,
) -> Unit {
  // whether the tape has it in use: moved exactly where it has it
  let in_use = fn(p : TapePane) { x == tape_x_of(at, p) }
  let side_open = panels.iter().any(fn(q) { q.0 == Panel })
  c.layer(fn() {
    for panel in panels {
      let (p, left, width) = panel
      // (the one pulled over still the finger's as it comes whole)
      if width <= 0.0 || (in_use(p) && wide.tape_pull != Some(p)) {
        continue
      }
      // (only one not in use takes presses and drags across: the one in use lets them through)
      let id = if p == wide.tape_at { 0 } else { c.id("tape/" + p.to_string()) }
      if id != 0 {
        c.drag_on(id, axis=Horizontal)
      }
      let b = c.box(
        style=@ui.style(
          w=Fixed(width),
          h=Fixed(h),
          radius=@sf.corners_radius(tape_pane_corners(p, side_open)),
        ),
        left~,
        top~,
        tx=x,
        id~,
        fn() {  },
      )
      if id != 0 {
        c.cursor(id, Hand)
        c.semantics(b, Button, id~, label=tape_words(p))
      }
    }
  })
  |> ignore
}

///|
/// The corners of panel `p` on the tape (@sf.tape_corners): on the side it stands at the window's edge in use the
/// window's less its 6 from it where they follow it, the others the ladder's pane corner. The sidebar's at the window's
/// left, the side panel's at its right, the page's at its right with no side panel open after it (`panel`).
fn tape_pane_corners(p : TapePane, panel : Bool) -> FixedArray[@ui.CornerOf] {
  match p {
    Side => @sf.tape_side_corners()
    Page => @sf.tape_corners(left=false, right=!panel)
    Panel => @sf.tape_corners(left=false, right=true)
  }
}

///|
/// What a covered panel is called to a screen reader: what pressing it does.
fn tape_words(p : TapePane) -> String {
  match p {
    Side => @sf.t("web-main.sidebar.open")
    Page => @sf.t("web-main.sidebar.close")
    Panel => @sf.t("web-pages.chat.openPanel")
  }
}



///|
/// On the tape what keeps the sidebar's panel apart: 6 from the window's edge before it, 8 from the page's panel after
/// it (the closed bar's: closed_bar_in, closed_bar_gap).
let tape_apart : Double = closed_bar_in + closed_bar_gap

///|
/// The ground the panels stand on, on the tape: the window's.
// kept across runs: a value (no field of it changes)
let frame_tape : @ui.Style = @ui.css("w=Full h=Full bg=Sidebar")

///|
/// The page's panel on the tape: the page's ground, its corners the tape's (tape_pane_corners), a line round it,
/// what goes past its edges cut.
// kept across runs: a value (no field of it changes)
let page_apart : @ui.Style = @ui.css("bg=Bg border=B1 border_color=Line clip")

///|
/// The frame's row: the page's ground under all of it.
// kept across runs: a value (no field of it changes)
let frame_row : @ui.Style = @ui.css("row w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let frame_col : @ui.Style = @ui.css("h=Full")

///|
/// The pane: its page laid out as wide as the column leaves, what goes past the window cut.
// kept across runs: a value (no field of it changes)
let frame_main : @ui.Style = @ui.css("h=Full clip")

///|
// kept across runs: a value (no field of it changes)
let frame_gate : @ui.Style = @ui.css("bg=Bg")

///|
/// A page's bar's padding at its left and its right (styles/sidebar.css.ts pageBar: 12; brand.css.ts, railed, closed:
/// 28 in a window with its buttons in the app's top row, which reach 12 past the rail), and its margins while the folded
/// sidebar is shown a while (from its edge to the window's): the box named "page-bar", moved with the block
/// (side_moves).
pub fn page_bar_room() -> (Double, Double, Double, Double) {
  (wide.bar_pl, if wide.tape { @sf.tape_bar_end(bar_in) } else { bar_in }, wide.bar_ml, wide.bar_mr)
}

///|
/// At the end of a page's bar that has no padding of its own there (a new chat's): as wide as its right margin while the
/// folded sidebar is shown a while (page_bar_room), its end by the window's; moved with the block.
pub fn page_bar_end(c : @ui.Ctx) -> Unit {
  c.box(style=@ui.style(w=Fixed(wide.bar_mr)), moves="page-bar-end", fn() {  }) |> ignore
}

///|
/// A page's bars' padding (12), closed past the rail and the window's buttons (28), and past 更新 over their start then
/// (72; 84 with the window's buttons in the app's top row: brand.css.ts).
pub let bar_in : Double = 12.0

///|
let bar_closed_inset : Double = 28.0

///|
pub let bar_update_in : Double = 72.0

///|
pub let bar_update_inset : Double = 84.0

///|
/// The sidebar's edge's strip: 12 wide, its middle on the edge (6 each side); folded, from 46 (its bar between the
/// closed bar at 48 and the page at 56: Rail.css.ts edge, closed).
pub let edge_half : Double = 6.0

///|
pub let closed_edge : Double = 46.0

///|
/// The chats' place with nothing open: the chat the core says was open last in this workspace, else a new chat
/// (workspace.tsx WorkspaceHome; once per workspace, so closing the chat goes back to the list on a phone).
fn land(src : Source, w : Workspace) -> Unit {
  if app.nav.depth() != 1 || app.nav.top() != Home {
    return
  }
  // come back to the chats (a chat closed, settings left): a new chat, as the web's empty place is
  if wide.landed == w.id {
    app.nav.push(NewChat)
    return
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  guard marks.value is Some(_) else { return }
  wide.landed = w.id
  let chat = field(field(field(marks.value, "workspaces"), w.id), "chat")
  let station = text(chat, "station")
  let key = text(chat, "key")
  if station != "" && key != "" {
    app.nav.push(Chat({ station, session: key, title: "", station_name: "" }))
  } else {
    app.nav.push(NewChat)
  }
}

///|
/// The page in the wide frame's pane: the stack's top as the app's pages draw it.
fn main_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
  page : Page,
) -> Unit {
  match page {
    Chat(r) => chat_page(c, src, w, r)
    // an agent's history, asked as a page (a link's `?history=…&entry=…`): on the desktop its chat with the history
    // open beside it at the entry asked (ChatPage.tsx's `history`), the page the chat's
    History(r, key, entry) => {
      c.tell("history-page/" + key, fn() { history_beside(src, r, key, entry) })
      chat_page(c, src, w, r)
    }
    // the chats' list is the sidebar's: nothing open (yet), the page's ground
    Home => ()
    // settings' own home is its first page (the web goes to 外观)
    Settings => setting_page(c, src, w, Route::Appearance)
    Setting(r) => setting_page(c, src, w, r)
    // a place of the rail's other than the chats': its page, under its title
    Place(p) => place_page(c, src, w, p)
    // 文件: a folder under its bar, as the web's
    Files => files_home(c, src, w, settings_core(src, w), files_room(c))
    Drive(at) => files_station(c, src, w, settings_core(src, w), at, files_room(c))
    // a new chat (newchat.mbt)
    NewChat => new_chat_page(c, src, w)
    // a station's screen, a drive's text read, a film played are over the whole window (sfapp's signed_in), not in
    // the pane
    Screen(_) | DriveRead(_) | DrivePlay(_) => ()
    // 已归档, none of its chats open beside the list: what it is
    Archived => archive_main(c)
    // 奏: the decision picked in the sidebar's 奏 (decision_page.mbt)
    Decisions => decision_page(c, src, w)
    // a web service, a visualization opened aside: its chat with it beside it (service_tab.mbt)
    Service(station, job) => service_beside(c, src, w, station, job)
    PreviewFile(station, key, path, name) => tab_beside(c, src, w, station, key, file_tab(key, path, name))
    // the plain text a phone's history opens: the phone's own
    Words(_, _) => ()
  }
}

///|
/// Which sidebar the place shows (Rail.tsx SidebarGroup), each its own width and folded or not: the files', the
/// profiles' and the stations' when in the rail, the chats' for the chats' places and the others in the rail, else the
/// settings'.
fn side_group(src : Source, ws : String) -> String {
  let place = lit_place()
  let railed = rail_items(src, ws)
  match place {
    "files" => "files"
    "profiles" if railed.contains("profiles") => "profiles"
    "stations" if railed.contains("stations") => "stations"
    "chats" | "decisions" => "chats"
    p if railed.contains(p) => "chats"
    _ => "settings"
  }
}

///|
/// A sidebar's own width where none was kept (the stations' a little wider: a line of meters on each row).
fn side_default(group : String) -> Double {
  if group == "stations" {
    side_stations
  } else {
    side_own
  }
}

///|
/// The sidebar shown follows the place and the workspace, each as it was left on this device (prefs `sidebars`, by
/// `<workspace>\n<group>`: its width, `,closed` folded; Rail.tsx widthFor, folded); what changes of it is kept, once a
/// drag of its edge is over.
fn side_follow(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  // (not read yet: as it is until it is)
  if prefs is None {
    return
  }
  let group = side_group(src, ws)
  let key = ws + "\n" + group
  if wide.side_key != key {
    let said = text(field(field(prefs, "sidebars"), key), "")
    let parts = said.split(",").map(fn(p) { p.to_string() }).collect()
    let closed = parts.contains("closed")
    let width = if parts.length() > 0 && parts[0] != "closed" { parts[0] } else { "" }
    wide.side_w = match whole_of(width) {
      Some(n) if n > 0 => dmax(side_min, dmin(side_max, n.to_double()))
      _ => side_default(group)
    }
    wide.folded = closed
    wide.side_key = key
    wide.kept_w = wide.side_w
    wide.kept_folded = wide.folded
    wide.peeking = false
    return
  }
  if wide.edge_held || (wide.side_w == wide.kept_w && wide.folded == wide.kept_folded) {
    return
  }
  let (kept_w, kept_folded) = (wide.side_w, wide.folded)
  let w = if wide.side_w == side_default(group) { "" } else { wide.side_w.round().to_int().to_string() }
  let v = match (w, wide.folded) {
    ("", false) => Json::null()
    ("", true) => Json::string("closed")
    (w, true) => Json::string(w + ",closed")
    (w, false) => Json::string(w)
  }
  // (kept once the frame's builds are over, as the last saw it)
  c.after_build("side-kept", fn() {
    wide.kept_w = kept_w
    wide.kept_folded = kept_folded
    (src.call)("prefs.set", Json::object({ "sidebars": Json::object(Map::from_array([(key, v)])) }), fn(_) {  })
  })
}

///|
/// A whole number written in decimal digits alone ("" or anything else: None).
fn whole_of(s : String) -> Int? {
  if s == "" {
    return None
  }
  let mut n = 0
  for ch in s {
    if ch < '0' || ch > '9' {
      return None
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Folded, the sidebar shown a while over the page as the pointer comes onto the rail's closed bar (Rail.tsx
/// peekSidebar), until the pointer has been off it a moment (PEEK_LEAVE, 400 ms) and nothing from it is open (a row's
/// menu, the filter's, a row renamed in place, the workspaces' ＋); to a finger, from its press on the bar until a tap
/// off them.
fn side_peek(c : @ui.Ctx, bar_x : Double, bar_y : Double, bar_r : Double, bar_b : Double) -> Unit {
  if !side_folded() {
    wide.peeking = false
    return
  }
  let (px, py, _) = c.pointer()
  // (something from it open: a row's menu, the filter's, a row renamed in place, the workspaces' ＋)
  let held = @sf.presenting() || @sfpages.renaming() || @sfpages.workspace_menu_open()
  // a finger, which rests on nothing: shown as it presses the bar (folded for the room: as its place is pressed,
  // rail.mbt), until a tap off the bar and the sidebar shown with nothing from it open
  if @ui.pointing() is Finger {
    let on_bar = fn(x : Double, y : Double) { x >= bar_x && x < bar_r && y >= bar_y && y < bar_b }
    if !wide.crowded && on_bar(px, py) && px < bar_x + rail_closed_w {
      wide.peeking = true
    }
    match c.tapped_anywhere() {
      Some((x, y)) if wide.peeking && !held && !on_bar(x, y) && x >= closed_bar_in + rail_closed_w + wide.side_w =>
        wide.peeking = false
      _ => ()
    }
    return
  }
  // on it, or on its edge at its right (Rail.tsx PEEK_ON: the dock, the edge, what pops up from it)
  let over = (px >= bar_x && px < bar_r && py >= bar_y && py < bar_b) ||
    (wide.peeking && px >= bar_r - 2.0 && px < bar_r + 10.0)
  if over && !wide.peeking && px < bar_x + rail_closed_w {
    wide.peeking = true
  }
  if @kit.after(c, "side/peek-away", wide.peeking && !over && !held, peek_leave_ms) {
    wide.peeking = false
  }
}

///|
/// Folded for the page's room (page_beside_least): shown a while from the start where a place was pressed into, and
/// folded again as a row of it is chosen (the page another); else nothing kept of it.
fn side_crowded() -> Unit {
  let top = app.nav.top()
  if !wide.crowded {
    wide.peek_next = false
    wide.peek_top = None
    return
  }
  if wide.peeking && wide.peek_top is Some(was) && was != top {
    wide.peeking = false
  }
  if wide.peek_next {
    wide.peek_next = false
    wide.peeking = true
  }
  wide.peek_top = Some(top)
}

///|
/// How long the pointer is off the sidebar shown a while before it folds again (Rail.tsx PEEK_LEAVE).
pub let peek_leave_ms : Double = 400.0
