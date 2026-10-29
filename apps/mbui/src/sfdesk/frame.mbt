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
// them, on the sidebar's ground, each on the ground its pages have on a phone): the sidebar in use its own width (a
// list's: the user, 2026-10-26, the chats' list needs no more), the page beside it showing what the window leaves; the
// side panel in use as wide as the window leaves past a strip of the page, the page in use past a strip of each beside
// it, as wide as the rail at the window's edge (tape_shows: the user, 2026-10-26, what shows of those not in use
// smaller); the edge between the sidebar or the side panel in use and the page dragged, its width (tape_edge: the
// user, 2026-10-26, its width to be set), the page showing what it leaves; as screens beside it,
// untinted (the user, 2026-10-25: the page's ground as a phone's). What shows of another is not used where it is: a press on it, a tap or a click, only brings it
// over (the tape moving, 380 ms), and what it holds answers from then on; dragged across, it comes with the finger and,
// let go, over or back (the user, 2026-10-25: only there; a drag on the one in use is its own). Something shown in
// the page while the sidebar is in use (a row of the sidebar, a search's, ⌘K's, a link's) shows beside it, the sidebar
// still in use (show_page; the user, 2026-10-27); with the side panel in use the page comes over to show it; 新建对话
// brings it over, opened to be written in (bring_page); nothing else puts the sidebar away (no ⌘\, no lit place pressed again: asked,
// 2026-10-24); the sidebar at first. The side panel comes over as it opens (the page again as it closes). What is
// opened from the page in use (or its side panel) goes over it as on a phone, sliding in (page_goes_on); chosen in the
// sidebar, in its place. Back goes from the side panel to the page, takes what was opened over the page off one at a
// time (sliding as a phone's page does), then from the page to the sidebar, from the sidebar of another place to the
// chats'; each following the system's back gesture as it goes (the page's stack, Ctx::nav_flat's; the tape, tape_back).

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
  peeking : @signals.Signal[Bool]
  /// folded for the page's room whatever was chosen (page_beside_least), this frame; shown a while from the next as a
  /// place is pressed into; the page shown as the last build began (a row chosen while shown: another page, folded)
  mut crowded : Bool
  mut peek_next : Bool
  mut peek_top : Page?
  /// the place whose sidebar the block holds as it was last built (side_place: kept through a place with none)
  mut side_place : String
  /// the sidebar shown (its workspace and group) and how it was kept (prefs `sidebars`)
  mut side_key : String
  mut kept_w : Double
  mut kept_folded : Bool
  /// the sidebar being drawn in the closed bar (what the web's sidebar does there, at once)
  mut in_bar : Bool
  /// the block closed to the bar this frame (the web's data-sidebar="closed"): what is drawn in it as there
  mut closed : Bool
  /// what the block last moved for, as it was last built (brand.tsx moveSidebar's callers: folded or opened as chosen,
  /// shown a while, a place with no sidebar of its own, another sidebar at its own width: side_key): a move sets out as
  /// it changes
  mut moved_as : (Bool, Bool, Bool, String, Bool)?
  /// where the move has got to this frame: the sidebar's top row's height, its frosted bands' ground (0 the sidebar's,
  /// 1 the closed bar's), the lists' marks on the rail (0 gone, 1 in)
  mut brand_h : Double
  mut band : Double
  mut mark : Double
  /// the page's bars' padding at its left (clear of the closed bar) and their margins while the folded sidebar is shown
  /// a while: from its edge (the sidebar less 8 less how far the page moved) to the window's (how far it moved); where
  /// the block's move has got to, as the page beside them
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
  /// the side panel last built on the tape (its key) and in which frame: brought over once a frame before has built it
  mut tape_built : (String, Int)
  /// the side panel last open on the tape: closed while in use, built as it was as the tape moves off it (side_leaving)
  mut tape_last_side : SideOf?
  /// the one not in use being pulled over by what shows of it (tape_covers), and how far the finger has moved the tape
  /// since it took it
  mut tape_pull : TapePane?
  mut tape_drag : Double
  /// the pull the system's back gesture's (tape_back): where it began across (from the edge it came from), where and when
  /// it was last and how fast it went there (px/s); how it ended, for the frame to settle (let go, called off, gone
  /// through)
  mut tape_backing : Bool
  mut tape_back_x0 : Double
  mut tape_back_last : (Double, Double)
  mut tape_back_v : Double
  mut tape_back_end : @ui.BackStep?
  /// the passage picked last frame (its message and the frame it was taken), a new one bringing the page over
  mut tape_pick : String
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
  peeking: @signals.signal(false, same=fn(a, b) { a == b }),
  crowded: false,
  peek_next: false,
  peek_top: None,
  side_place: "chats",
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
  tape_built: ("", -1),
  tape_last_side: None,
  tape_pull: None,
  tape_drag: 0.0,
  tape_backing: false,
  tape_back_x0: 0.0,
  tape_back_last: (0.0, 0.0),
  tape_back_v: 0.0,
  tape_back_end: None,
  tape_pick: "",
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
  wide.peeking.set(false)
  wide.crowded = false
  wide.peek_next = false
  wide.peek_top = None
  wide.side_place = "chats"
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
  wide.tape_built = ("", -1)
  wide.tape_pull = None
  wide.tape_drag = 0.0
  wide.tape_backing = false
  wide.tape_back_x0 = 0.0
  wide.tape_back_last = (0.0, 0.0)
  wide.tape_back_v = 0.0
  wide.tape_back_end = None
  wide.tape_pick = ""
}

///|
/// Whether the window is drawn as this frame: laid out Medium or Large (@sf.layout), by the window's width (not the
/// box being built's: asked from within the sidebar too).
pub fn is_wide(c : @ui.Ctx) -> Bool {
  // (or where the system lays out its tabs in every pose, the cards across on each screen: an iPhone Duo's outer one too,
  // rail_native.mbt)
  !(@sf.layout(c.window_size().0) is Small) || @sf.native_able()
}

///|
/// Something chosen to be shown in the page (a row of the sidebar's lists, a search's, ⌘K's, a link's, a
/// notification's, what the bell's panel or the services' open). On the tape with the sidebar in use the page beside it
/// shows it and the tape stays: what shows of the page is a screen beside it, pressed when it is to be used (the user,
/// 2026-10-24: 当需要操作某个视窗的时候，应该先点击，然后视窗会过来; 2026-10-27: 为啥现在中屏侧边栏点击就直接切到 chat 页面了),
/// as nothing else puts the sidebar away; with the side panel in use, where the page is a strip, the page comes over
/// to show it. Off the tape nothing comes of it (tape_frame lets the ask go): the page is beside the list. What a place
/// is gone to with (the rail, its list's own page) is not one: its list is the sidebar's.
pub fn show_page() -> Unit {
  if wide.tape_at != Side {
    wide.tape_ask = Some(Page)
  }
}

///|
/// The page brought over whatever is in use: what is opened to be written in at once (新建对话, ⌘N: pengxiao,
/// 2026-10-25, opened from the sidebar in use it showed beside it), a fixture's page as the app begins (a picture's).
pub fn bring_page() -> Unit {
  wide.tape_ask = Some(Page)
}

///|
/// Whether page `p`, opened, is shown in the page pane (show_page): not a place's own page, whose list is the
/// sidebar's (the chats', the settings', 文件's, 奏's, the archive's, a rail's place's), nor what is over the whole
/// window (a screen, a file read or played).
pub fn shown_in_page(p : Page) -> Bool {
  !(p is (Home | Settings | Place(_) | Files | Decisions | Archived | Screen(_) | DriveRead(_) | DrivePlay(_)))
}

///|
/// The sidebar folded or opened (⌘\, the lit place pressed again, ⌘K's command); nothing on the tape, where the
/// sidebar is never put away but by a press on the page beside it or what is chosen to be shown in the page
/// (show_page; asked, 2026-10-24: it went away unasked).
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
  if @sf.native_input() is Mouse {
    return None
  }
  for d in @ui.system_fold().divisions {
    let (x, _, w, h) = d
    if h > w {
      return Some(dmax(side_min, dmin(side_max, x + w / 2.0 - rail_left())))
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
/// What moves as the sidebar opens, folds, is shown a while or goes to another place's width: brand.tsx moveSidebar's
/// list, its selectors the boxes' `moves` names, what of each moves by its CSS names as the web lists them. The column
/// the page starts after (the shell's grid-template-columns: the page is laid out in what it leaves, so a value), how
/// far the page is moved aside (main's left: drawn moved, as wide as it was), the edge, the rail as narrow as the closed bar and its top row, the
/// block's margins (values: it is placed by them), corner, ground, shadow and line, the sidebar in it (and whether it
/// is drawn at all), its frosted bands' ground and top row, the lists' marks on the rail, the page bars' room.
// kept across runs: a table, never written
let side_moves : Array[(String, Array[String])] = [
  ("shell", ["--side-col"]),
  ("main", ["--peek-shift"]),
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
  ("page-bar", ["--bar-pl", "--bar-ml", "--bar-mr"]),
  ("side-update", ["left", "transform"]),
]

///|
/// The closed bar (shell.css.ts dock, closed): 6 from the window's edges (44 from its top under the window's buttons'
/// row where they are in the app's top row), 8 from the page.
pub let closed_bar_in : Double = @sf.window_in

///|
let closed_bar_top : Double = 44.0

///|
/// In a window with its buttons in the app's top row (macOS's: no title bar of the system's), a row `h` high at the top
/// of what it is built in, under what is built there after it, which is the window's title bar (shell.css.ts main's and
/// gate's ::before): a press on it that nothing over it takes drags the window, a double click does what the system's
/// title bar does (Ctx::window_drag). The system takes none of the app's presses there itself (mbui's mac host).
fn title_row(c : @ui.Ctx, name : String, h : Double) -> Unit {
  let id = c.id(name)
  c.window_drag(id)
  c.box(style=@ui.style(h=Fixed(h)), left=0.0, top=0.0, right=0.0, id~, fn() {  }) |> ignore
}

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
  // (under the window's buttons where they are the system's, at its left: macOS's)
  let above = if @ui.window_keys_left() { closed_bar_top } else { bar_in_now() }
  let ml = c.moved("--dock-ml", if bar || apart { bar_in_now() } else { 0.0 })
  let mt = c.moved("--dock-mt", if bar { above } else if apart { bar_in_now() } else { 0.0 })
  let mr = c.moved("--dock-mr", if apart {
    bar_gap_now()
  } else if !bar {
    0.0
  } else if peek {
    bar_gap_now() - s
  } else {
    bar_gap_now()
  })
  let mb = c.moved("--dock-mb", if bar || apart { bar_in_now() } else { 0.0 })
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
  let side_w = if bar || @sf.native_on() { s } else { s + side_into_rail }
  // (a panel's corners the tape's sidebar's, the closed bar's its own: each in the window's the window's less its 6 from
  // it where it follows it)
  let look = if apart {
    dock_look.then(@ui.style(radius=@sf.corners_radius(tape_pane_corners(Side, false))))
  } else if bar {
    dock_look.then(@ui.style(radius=@sf.closed_bar_corner(rail_closed_ground_in)))
  } else {
    dock_look
  }
  let look = look.then(@ui.style(bg=Data(dock_ground(bar))))
  let dock_w = dmax(0.0, col - ml - mr)
  // (open beside the system's tabs, its ground to the window's foot as the system's own sidebars are, its list under the
  // home indicator: rail_native.mbt)
  let foot = if side_full_height(bar) { 0.0 } else { foot }
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
        // (along a screen whose corners it follows, an iPhone Duo's, none of the block's moves: its corners as they are)
        moves=if @sf.native_card_corner() > 0.0 { "" } else { "dock" },
        left=ml,
        top=top + mt,
        fn() {
          if !@sf.native_on() {
            rail(c, src, w, all, bar)
          }
          c.box(style=dock_side.then(@ui.style(w=Fixed(side_w))), moves="sidebar", fn() {
            if shown && s > 0.0 {
              // (in the bar: what the web's sidebar does there, at once, as the bar starts out; the bar's as long as it
              // is drawn as the bar, its filter in the bar's corner)
              wide.in_bar = bar
              // (what is in it as wide as it: a part that asks how wide its box is is told the sidebar's)
              c.sized(side_w, c.height, fn() { sidebar(c, src, w, side_w) })
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
/// The block open (its line and shadow there but clear) and closed to the bar or on the tape (a floating panel's, its
/// corner concentric with the places' grounds 6 in: shell.css.ts dock, closed; on the tape the page's panel's, all the
/// tape's panels alike, asked 2026-10-24); both cut what goes past their edges. On its ground (dock_ground).
// kept across runs: a value (no field of it changes)
let dock_look : @ui.Style = @ui.css("row border=B1 clip")

///|
/// What the block stands on: open, the sidebar's ground; a panel of its own (the closed bar, or on the tape) the
/// ground it floats on (apart_ground), as the lists' bands on it are: one ground under all of it, whatever the theme's
/// surface is on this system. The rail's marks are on discs of it (rail_hung).
fn dock_ground(bar : Bool) -> Int64 {
  if bar || wide.tape {
    apart_ground()
  } else {
    @sf.theme().p.sidebar
  }
}

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
      let moved = (rail_left() - from) / 2.0
      let reach = bar_in_now() + rail_closed_w + s + peek_gap
      let room = c.width - 2.0 * peek_gap - dmin(right + moved, c.width)
      dmax(0.0, dmin(s, dmin(room, reach - dmax(left + moved, rail_left())))).round()
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
  // (连接 and 用量: a page across the pane, no sidebar; the block closes holding the one it had: side_place)
  let bare = place_bare(lit_place())
  wide.side_place = side_place()
  // the sidebar of this place and workspace, as it was left
  side_follow(c, src, w.id)
  let own = !gated && !bare
  // laid out Medium, with a sidebar to show: the rail and the sidebar beside the page on the tape
  // (the cards across, whatever the window's width, beside the column of the system's glass the rail's places are in:
  // rail_native.mbt)
  // (beside the system's tab bar, the cards across whatever the window's width: one design upright and on its side,
  // rail_native.mbt)
  wide.tape = own && (@sf.layout(c.width) is Medium || @sf.native_on() || @sf.native_able())
  // the rail's places the system's tabs where it has its own bars (an iPhone Duo's: rail_native.mbt), what was chosen
  // there gone to
  native_frame(c, src, w, all)
  // (off the tape, a phone's or a tablet's screen with less than a phone's width for the page beside it: folded
  // whatever was chosen)
  wide.crowded = own &&
    !wide.tape &&
    (@sf.native_input() is Finger) &&
    c.width - rail_left() - side_on_fold().unwrap_or(wide.side_w) < page_beside_least
  side_crowded()
  // (on a fold standing upright, the sidebar ends on it while it is not folded away, but on the tape)
  let on_fold = if side_folded() || wide.tape { None } else { side_on_fold() }
  // folded to the rail's bar (and a page with no sidebar of its own: Rail.tsx showSidebar), shown a while beside it as
  // the pointer comes on it: each part built as the web's CSS has it in that state, and moved there from what it showed
  // as the state changes, all together (brand.tsx moveSidebar: 380 ms, ease out); not the width the edge drags, which
  // follows the pointer at once
  let bar = (own && side_folded()) || bare
  // (on the tape its own, the page beside it what the window leaves: tape_side_w)
  // (on the tape, what the window leaves beside the column of the system's glass at its right, its glass over the
  // window's ground alone: @sf.side_clear)
  let tw = c.width - @sf.native_clear()
  let s = if gated {
    0.0
  } else if wide.tape {
    tape_side_w(tw, wide.side_w)
  } else {
    on_fold.unwrap_or(wide.side_w)
  }
  let bars = @ui.system_bars()
  let top = bars.top
  // (the cards beside the column of the system's glass to the window's foot but the home indicator's own line: what
  // is in them keeps its padding over it; rail_native.mbt)
  // (down the side, the cards to the column's own foot, the home indicator's line under their ground: cards_foot; the
  // soft keyboard up, the window ends where it starts plus the bars' foot: the cards end on it as it rises past that)
  // (a touch device's the same: its navigation bar over the app, edge to edge (Android's gesture line, iOS's home
  // indicator), the cards' ground under it to the window's foot, what is in them clear of it; not a window's on a
  // computer, whose foot is its own; nor an iPhone Duo's upright, the system's tabs across its foot in that room: the
  // cards over them, what is in them not under the tabs: the user, 2026-10-28)
  let edge = @sf.native_side() || (@sf.native_input() is Finger && wide.tape && !@sf.native_on())
  let foot = if edge { dmin(bars.bottom, cards_foot + c.ime_inset()) } else { bars.bottom }
  let inset = @ui.window_inset()
  let peek_r = rail_left() - bar_gap_now() + (if wide.peeking.get() { s } else { 0.0 })
  // (under the window's buttons where they are the system's, at its left: macOS's)
  let peek_top = if @ui.window_keys_left() { closed_bar_top } else { bar_in_now() }
  side_peek(c, bar_in_now(), top + peek_top, peek_r, c.height - foot - bar_in_now())
  let peek = own && side_folded() && wide.peeking.get()
  // what the page shows across as the last frame laid it out (its bars left out): what it moves aside for, shown a
  // while
  let page_id = c.id("main-page")
  let shown = c.shown_across(page_id, but="page-bar")
  // it moves for what it is asked (brand.tsx moveSidebar's callers): folded or opened as chosen (⌘\, its place pressed
  // again), shown a while or no longer, a place with no sidebar of its own come to or left, another place's or
  // workspace's sidebar at its own width (side_key, not the width: a width is no cause); not for the window's room
  // folding it (crowded), a fold's place or the tape coming or going, which put it as they have it at once, nor for its
  // edge, whose width it follows at once, held or let go (let go a little past where the last frame drew it, the rest
  // of the way is the hand's too, not a move after it); nor for the system's bars taking the app's places or giving
  // them back (an iPhone Duo's, told as the app starts: its sidebar one width beside the system's tabs, side_follow),
  // which put it as they have it at once
  let cause = (wide.folded, wide.peeking.get(), gated || bare, wide.side_key, @sf.native_on())
  match wide.moved_as {
    Some(was) if was != cause && was.4 == cause.4 && !wide.edge_held => {
      // shown a while from now: how far the page moves aside, worked out once as it starts (Rail.tsx markPeek)
      if peek && !was.1 {
        wide.peek_shift = peek_shift(c, shown, wide.page_from, s)
      }
      c.move_state(side_moves)
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
    rail_left() + (if bar { 0.0 } else { s }) + (if wide.tape { bar_in_now() + bar_gap_now() + rail_more() } else { 0.0 }),
  )
  wide.page_from = col
  // on the tape: a chat's side panel open beside it, a panel of its own after the page's; each as wide as the window
  // leaves in use past what shows of those beside it (tape_shows, 8 from it) and 6 from the window's edge where none
  // is; which is in use and how far the tape is moved
  let panel_of = if wide.tape { side_open_for(src, w, app.nav.top()) } else { None }
  // (one closed while in use: what it showed, as it goes, while the tape moves off it to the page: let go once there,
  // as a panel beside a page goes out showing its tabs: side_beside)
  let leaving = match (panel_of, wide.tape_last_side) {
    (None, Some(s)) if wide.tape && side_leaving(s.key()) is Some(_) => Some(s)
    _ => None
  }
  wide.tape_last_side = match panel_of {
    Some(_) => panel_of
    None => leaving
  }
  let shown_side = match panel_of {
    Some(_) => panel_of
    None => leaving
  }
  let panel_w = match shown_side {
    Some(_) => tape_panel_w(tw)
    None => 0.0
  }
  // (the page beside the side panel once a frame before has built it, as its move over starts: tape_frame)
  let laid = match panel_of {
    Some(side) => wide.tape_built.0 == side.key() && wide.tape_built.1 < c.frame_number()
    None => false
  }
  let main_to = if !wide.tape {
    dmax(0.0, c.width - col)
  } else if laid && !@sf.native_side() {
    dmax(0.0, tw - tape_shows_left() - tape_shows_right() - 2.0 * bar_gap_now())
  } else {
    // The system's trailing column already separates the active pane from what
    // peeks beside it. Do not reserve a second strip of chat width for details.
    tape_one_beside(tw, tape_shows_left())
  }
  let at = tape_at(tw, col, main_to, panel_w)
  // (the chat shown has its view: what its side panel shows is known)
  let known = match app.nav.top() {
    Chat(r) | History(r, _, _) => (src.topic)("chat", chat_params(r)).value is Some(_)
    _ => true
  }
  let tape_x = tape_frame(c, panel_of, at, known)
  // (the panel closed gone once the tape is at the page)
  match leaving {
    Some(s) if (tape_x - at.1).abs() < 0.5 => side_left(s.key())
    _ => ()
  }
  // (on the tape the page as wide as its move has got: the side panel opening beside it, it narrows as the tape moves
  // to it, one move, not at once before it: tape_moves)
  let main_w = if wide.tape { c.moved("--tape-page-w", main_to) } else { main_to }
  // shown a while, the page moved aside as wide as it was (shell.css.ts main's left: --peek-shift), drawn moved
  // (page_in); closed, its bars' padding clear of the bar (and of the window's buttons)
  let shift = if peek { wide.peek_shift } else { 0.0 }
  let aside = c.moved("--peek-shift", shift)
  // shown a while, where the window's buttons are in the app's top row, the sidebar is under that row as the closed bar
  // is (dock: closed_bar_top), the row the page's bars are in: they stay as folded, from the rail, their words beside the
  // window's buttons, not moved aside with the page (their margin at their start the page's move back). Else it reaches
  // over them: they start past its edge (brand.css.ts), their own padding past it as open (what the closed padding
  // clears is left of it then), their words as far from its edge as open. Either way their end by the window's.
  let over_bars = peek && !inset
  // (closed, with 更新 over their start: clear of it too, brand.css.ts)
  wide.closed = bar
  let updating = !gated && update_shown()
  // (where the move has got to, as the page beside them: every bar builds its room from these)
  // (clear of the window's buttons at its left where they are the system's, macOS's: brand.css.ts's inset frame)
  let keys_left = @ui.window_keys_left()
  wide.bar_pl = c.moved("--bar-pl", if !bar || over_bars {
    bar_in
  } else if updating {
    if keys_left {
      bar_update_inset
    } else {
      bar_update_in
    }
  } else if keys_left {
    bar_closed_inset
  } else {
    bar_in
  })
  wide.bar_ml = c.moved("--bar-ml", if over_bars {
    dmax(0.0, s - bar_gap_now() - shift)
  } else if peek {
    -shift
  } else {
    0.0
  })
  wide.bar_mr = c.moved("--bar-mr", shift)
  // what the sidebar's parts work out from, where the move has got to: its top row (Sidebar.css.ts brand: none in the
  // closed bar), its frosted bands' ground (the block's), the lists' marks on the rail (Rail.css.ts listMark: in as it
  // folds)
  // (更新 is in the first row, before the filter: update_in_row, no row of its own)
  wide.brand_h = c.moved("--brand", if bar {
    0.0
  } else if keys_left {
    side_top_inset
  } else if side_full_height(bar) {
    side_top_web + top
  } else {
    side_top_web
  })
  // (on the tape the sidebar in a panel of its own: its bands on a floating panel's ground, as in the closed bar)
  wide.band = c.moved("--band", if bar || wide.tape { 1.0 } else { 0.0 })
  wide.mark = c.moved("--mark", if bar { 1.0 } else { 0.0 })
  // the core's chat last open, else a new chat: there is always a page beside the list (workspace.tsx WorkspaceHome)
  land(src, w)
  let page_h = dmax(0.0, c.height - top - foot)
  // on the tape the page's panel 6 in from the bars' edges too
  let panel_top = top + bar_in_now()
  let panel_h = dmax(0.0, page_h - 2.0 * bar_in_now())
  // (beside the system's action at the column's foot, the cards' foot corners the one the composer stands concentric
  // in on its line: said before any of them is built; another than the last frame's, what was kept of them, cut by
  // their corners as they were, drawn anew, as for the screen's corner: rail_native.mbt native_frame)
  if @sf.native_foot_set(panel_top + panel_h) {
    c.forget_parts()
  }
  // the page in its pane, `ph` high
  // (its top row, a bar's height, the window's title bar under the page, whether the page has a bar there or not: a
  // new chat, settings, 奏: title_row)
  let page_in = fn(ph : Double) {
    if inset {
      title_row(c, "page-title-row", @sf.wide_bar_h + (if wide.tape { @sf.tape_bar_over() } else { 0.0 }))
    }
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
          // (moved aside for the sidebar shown a while within what cuts the page at its edges, so a bar of it that
          // stays as folded is not cut there: page_bar_row; what moves in it of its own takes its place from its foot,
          // the move aside moving none of it)
          // (on the tape the page a phone's screen: what is opened from it pushed over it, slid in and taken off by
          // back as a phone's are, down to the page chosen to be shown in it: page_goes_on)
          c.nav_flat(
            app.nav,
            fn(page) {
              let moved = c.box(style=page_aside, tx=aside, fn() {
                // (the page drawn: one on its way out, a stack's move, hands no actions to the system's bars)
                drawn_page.val = Some(page)
                main_page(c, src, w, all, invited, page)
                drawn_page.val = None
              })
              @motion.scope(c, moved, bottom=true)
            },
            bg=@sf.theme().p.bg,
            stacks=wide.tape,
            // (back its while the page is in use: the side panel's, the sidebar's first)
            takes_back=!wide.tape || wide.tape_at == Page,
          )
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
  // (the window's buttons' row under all of the frame, where nothing of it is: over the closed bar, title_row)
  if inset {
    title_row(c, "window-title-row", closed_bar_top)
  }
  // what the page or the sidebar takes back for (a sheet, a menu, a step of a page's) goes back before the stack does
  let took = c.took_back(fn() {
    if wide.tape {
      // on the tape, on the ground its panels stand on, each put where it is on the tape and drawn moved as far as the
      // tape has got (tx: moved as a whole, nothing in it laid out again frame by frame as the tape moves): the page's a
      // panel of its own, apart from the sidebar's (6 in from the bars, its corner the sidebar's panel's, a line round
      // it), and a chat's side panel open after it, 8 from it, as high
      // (the last panel on to the window's edge under the column of the system's glass, its ground under the glass,
      // what is in it as wide as beside it: @sf.side_clear, the user 2026-10-26)
      let under = @sf.native_clear()
      c.box(style=frame_tape, fn() {
        // a right click in it: what is picked copied (context_menu.mbt)
        context_page(c, page_id)
        let page_corners = tape_pane_corners(Page, panel_of is Some(_))
        let page_w = if panel_of is None { main_w + under } else { main_w }
        let pane = tape_behind(c, Page, fn() { c.box(
          style=page_apart.then(
            @ui.style(
              w=Fixed(page_w),
              h=Fixed(panel_h),
              radius=@sf.corners_radius(page_corners),
            ),
          ),
          left=col,
          top=panel_top,
          tx=tape_x,
          id=page_id,
          fn() {
            // (what is in it as wide as beside the system's column: `under` its ground alone, its right corners none
            // of what is in it, which ends where the column begins: beside_column)
            @sf.pane_round.val = Some(beside_column(page_corners, page_w - main_w))
            c.box(style=@ui.style(w=Fixed(main_w), h=Full), fn() {
              tape_part(c, Page, "\{col} \{panel_top} \{main_w} \{panel_h} \{tape_x} \{wide.bar_pl} \{wide.bar_ml} \{wide.bar_mr}", fn() {
                page_in(panel_h)
              })
            })
            |> ignore
            @sf.pane_round.val = None
          },
        ) })
        // what moves in the page of its own (the composer) takes its place from the page's foot: the tape moving the
        // page, a keyboard making it shorter, move none of it (it goes with the page, at once)
        @motion.scope(c, pane, bottom=true)
        match shown_side {
          Some(side) =>
            tape_behind(c, Panel, fn() { c.box(
              style=page_apart.then(
                @ui.style(
                  w=Fixed(panel_w + under),
                  h=Fixed(panel_h),
                  radius=@sf.corners_radius(tape_pane_corners(Panel, true)),
                ),
              ),
              left=col + main_w + bar_gap_now(),
              top=panel_top,
              tx=tape_x,
              fn() {
                @sf.pane_round.val = Some(beside_column(tape_pane_corners(Panel, true), under))
                c.box(style=@ui.style(w=Fixed(panel_w), h=Full), fn() {
                  tape_part(c, Panel, "\{col} \{main_w} \{panel_top} \{panel_w} \{panel_h} \{tape_x} \{side.key()}", fn() {
                    c.sized(panel_w, panel_h, fn() { tape_side(c, src, w, side, leaving=leaving is Some(_)) })
                  })
                })
                |> ignore
                // (the frame it was first built in, kept while it stays open)
                if leaving is None && wide.tape_built.0 != side.key() {
                  wide.tape_built = (side.key(), c.frame_number())
                }
                @sf.pane_round.val = None
              },
            ) })
            |> ignore
          None => wide.tape_built = ("", -1)
        }
      })
      |> ignore
    } else {
      c.box(style=frame_row, fn() {
        // the rail's and the sidebar's column (the block over it, below); the page beside it, moved aside in it
        c.box(style=frame_col.then(@ui.style(w=Fixed(col))), fn() {  }) |> ignore
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
    tape_behind(c, Side, fn() {
      tape_part(c, Side, "\{s} \{col} \{top} \{foot} \{tape_x} \{c.width} \{c.height} \{wide.brand_h} \{wide.band} \{@sf.native_bars.corners}", fn() {
        // (open beside the system's tabs off the tape, its ground from the window's top as the system's own sidebars'
        // are, what is in it under the bars there: brand_h; rail_native.mbt)
        dock(c, src, w, all, bar, peek, s, col, if side_full_height(bar) { 0.0 } else { top }, foot, tape_x)
      })
    })
    // (with the sidebar closed, where its first row is not shown: 更新 where the bar's start leaves room for it)
    if updating && bar && !peek && !wide.tape {
      update_button(c, src, inset, top)
    }
    if wide.tape {
      let panels = [(Side, bar_in_now(), col - bar_in_now() - bar_gap_now()), (Page, col, main_w)]
      if panel_of is Some(_) {
        panels.push((Panel, col + main_w + bar_gap_now(), panel_w))
      }
      tape_covers(c, tape_x, at, panels, panel_top, panel_h)
      // the edge between the sidebar or the side panel in use and the page beside it: dragged, its width (the
      // sidebar's kept as the wide frame's is: side_follow), the page beside it showing what it leaves
      let side_edge = c.id("tape/side-edge")
      match wide.tape_at {
        Side if !gated => {
          let said = tape_edge(
            c,
            "tape/side-edge",
            @sf.t("web-pages.workspace.resizeSidebar"),
            col - bar_gap_now(),
            tape_x,
            panel_top,
            panel_h,
            tape_side_w(tw, wide.side_w),
            side_min,
            tape_side_most(tw),
            Right,
          )
          match said {
            Dragging(x) | Dropped(x) => wide.side_w = x
            Twice => wide.side_w = side_default(side_group(src, w.id))
            Pressed | Untouched => ()
          }
          wide.edge_held = c.pressed(side_edge) || said is Dragging(_)
        }
        Panel if panel_of is Some(_) => {
          wide.edge_held = false
          match
            tape_edge(
              c,
              "tape/panel-edge",
              @sf.t("web-pages.chat.resizePanel"),
              col + main_w,
              tape_x,
              panel_top,
              panel_h,
              panel_w,
              dmin(panel_min, tape_one_beside(tw, tape_shows_left())),
              tape_one_beside(tw, tape_shows_left()),
              Left,
            ) {
            Dragging(x) | Dropped(x) => panel_own.width = Some(x)
            Twice => panel_own.width = None
            Pressed | Untouched => ()
          }
        }
        _ => wide.edge_held = false
      }
    }
  })
  // (the sidebar's edge: on its right edge open, between the bar and the page folded, at the edge of the sidebar shown
  // a while; dragged, unless it is on the fold, folded for the page's room or on the tape)
  if !bare && on_fold is None && !wide.crowded && !wide.tape {
    let at = if !bar {
      rail_left() + s - edge_half
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
    match tape_back_to() {
      // (on the tape the panel back brings over follows the system's back gesture as it goes: tape_back)
      Some(p) => c.follow_back(fn(step) { tape_back(p, step) })
      None =>
        match @sfbase.back_step() {
          Some(f) => c.take_back(f)
          None => ()
        }
    }
  }
  // the pages of web services' and visualizations' tabs closed, no longer drawn, let go (service_tab.mbt)
  sv_sweep(c, src)
}

///|
/// Back on the wide frame (docs/architecture.md, the tiers' table): what is over the whole window (a screen, a file
/// read or played) put away first, a page of the stack popped. On the tape, with a chat's side panel in use, the page
/// brought over; with the page in use, what was opened over it from there taken off (Nav::push_over), else the
/// sidebar brought over (the page it chose: the chats' place's chat, a settings page); with the sidebar in use, the chats' from another place's (or the
/// archive), as a phone's place goes back to them; nothing with the chats' in use (the system's: as from a phone's
/// list). Laid out Large, the stack's top popped, but for the new chat beside the chats alone: the page there is never
/// empty (land: popped, a new chat would come again), so nothing to go back to.
pub fn wide_back() -> (() -> Unit)? {
  let over_all = app.nav.top() is (Screen(_) | DriveRead(_) | DrivePlay(_))
  if wide.tape && !over_all {
    match tape_back_to() {
      Some(p) => Some(fn() { wide.tape_ask = Some(p) })
      None =>
        match wide.tape_at {
          // (the sidebar of another place, or the archive: the chats', as a phone's place goes back to them)
          Side =>
            if lit_place() != "chats" || app.nav.pages().contains(Archived) {
              Some(fn() {
                @sfbase.go_place("chats") |> ignore
                wide.landed = ""
              })
            } else {
              None
            }
          _ => Some(@sfbase.back_pop)
        }
    }
  } else if app.nav.pages() is [Home, Chat(open)] && @sfbase.chat_back(open) is Some(_) {
    // a chat alone beside the sidebar: the chat shown before it (the web's history), else what is under it
    @sfbase.chat_back(open)
  } else if app.nav.depth() > 2 || (app.nav.depth() == 2 && !(app.nav.pages() == [Home, NewChat])) {
    Some(@sfbase.back_pop)
  } else {
    None
  }
}

///|
/// How much shows on the tape of each panel beside the one in use, at the window's edge: a strip as wide as the rail
/// (the user, 2026-10-26: what shows of those not in use smaller), a finger's width past the edge a phone's system takes
/// for its back gesture, to be tapped or dragged over. The page or the side panel in use, those beside it show as much;
/// the sidebar in use, the page beside it shows what the sidebar's own width leaves (tape_side_w).
pub let tape_shows : Double = 56.0

///|
/// What shows at the window's left of the panel beside the one in use (the sidebar's, the page in use; the page's, the
/// side panel in use): tape_shows; where the window's buttons are in the app's top row there (a Mac's, not full
/// screen), as wide as holds them with as much room past them as before them from the window's edge (the strip's own
/// edge is off it), so they stand on what is at the window's left, in use or a strip, never over the panel beside it
/// (the user, 2026-10-26: 红绿灯没有一个空位可以放).
pub fn tape_shows_left() -> Double {
  if @ui.window_keys_left() {
    dmax(tape_shows, window_buttons_in + window_buttons_w + window_buttons_in)
  } else {
    tape_shows
  }
}

///|
/// What shows at the window's right of the panel beside the one in use (the page's, the sidebar in use; the side
/// panel's, the page in use): tape_shows; where the window's buttons are the app's, at its right (Windows'), as wide
/// as holds them (@sf.window_keys_room_tape: from the window's side to before their rule) with the panels' 6 past
/// them, so they stand on what is at the window's right, in use or a strip, never over the panel beside it, as a Mac's
/// at its left (tape_shows_left).
pub fn tape_shows_right() -> Double {
  if @ui.window_keys_own() {
    dmax(tape_shows, @sf.window_keys_room_tape() + @sf.window_in)
  } else {
    tape_shows
  }
}

///|
/// The window's buttons in the app's top row (mbui's mac_app.m: 16 from the window's left, centred on its 44, as far
/// apart as the system has them): from 16, the three 54 across (each 14, 20 apart).
let window_buttons_in : Double = 16.0

///|
let window_buttons_w : Double = 54.0

///|
/// How wide a panel is on the tape with one beside it, a window `width` wide: what the window leaves in use past what
/// shows of the other (`shows`: at the window's left tape_shows_left, at its right tape_shows; 8 from it) and 6 from the
/// window's other edge. The page's without a side panel and the side panel's (a strip at the window's left beside
/// them), the sidebar's at most (the page's at the window's right).
fn tape_one_beside(width : Double, shows : Double) -> Double {
  dmax(0.0, width - shows - bar_gap_now() - bar_in_now())
}

///|
/// How wide the sidebar is on the tape, a window `width` wide: its own, as the person left it (a list as wide as a list
/// needs: the user, 2026-10-26, the chats' list stretched across the window had no need to be), the page beside it
/// showing what the window leaves; at most tape_side_max, and as wide as a panel with one beside it (tape_one_beside),
/// less the rail's.
fn tape_side_w(width : Double, own : Double) -> Double {
  dmax(0.0, dmin(dmin(own, tape_side_max), tape_one_beside(width, tape_shows_right()) - rail_left() - rail_more()))
}

///|
/// The widest the sidebar is on the tape, whatever width the person left it at on a larger screen (theirs, the same on
/// every screen: a sidebar dragged to the wide frame's most opened on a phone on its side, a small tablet or a fold
/// nearly to the window's edge; the user, 2026-10-28: opened there, it is not to be so wide). The width kept stays
/// theirs; a larger screen shows it again.
pub let tape_side_max : Double = 320.0

///|
/// What moves as the other comes over on the tape: the tape (how far it is moved), as the sidebar moves (380 ms, its
/// ease out).
// kept across runs: a table, never written
let tape_moves : Array[(String, Array[String])] = [
  ("tape", ["--tape-x", "--tape-page-w", "--behind-side", "--behind-page", "--behind-panel"]),
]

///|
/// Where the tape is with each of its panels in use, a window `width` wide (`d`: where the page's panel starts on it,
/// `page_w`, `panel_w`: the page's panel's width and the side panel's): the sidebar 6 in from the window's left (0); the
/// page 8 past what shows of the sidebar (tape_shows_left); the side panel 6 in from the window's right, the page beside
/// it showing what it leaves (all of the window but that strip, as it is at first: tape_panel_w).
fn tape_at(width : Double, d : Double, page_w : Double, panel_w : Double) -> (Double, Double, Double) {
  (0.0, tape_shows_left() + bar_gap_now() - d, width - bar_in_now() - (d + page_w + bar_gap_now() + panel_w))
}

///|
/// How wide a chat's side panel is on the tape, a window `width` wide: as wide as it was dragged (tape_edge, the wide
/// frame's edge too: panel_own, kept while the app runs), the page beside it showing what it leaves; else as wide as
/// the window leaves past a strip of the page (tape_one_beside). From panel_min to that.
fn tape_panel_w(width : Double) -> Double {
  let most = tape_one_beside(width, tape_shows_left())
  match panel_own.width {
    Some(w) => dmax(dmin(panel_min, most), dmin(w, most))
    None => most
  }
}

///|
/// The widest the sidebar is dragged to on the tape, a window `width` wide: a panel with a strip of the page beside it,
/// less the rail's, and the tape's most (tape_side_w).
fn tape_side_most(width : Double) -> Double {
  dmax(side_min, dmin(tape_side_max, tape_one_beside(width, tape_shows_right()) - rail_left() - rail_more()))
}

///|
/// The edge between the sidebar or the side panel in use on the tape and the page beside it, in the gap between the two
/// (`gap`: the gap's left on the tape, `x`: how far the tape is moved; `top`, `h`: the panels'), the library's (its bar
/// and its line, @sf.edge_look, in the gap's middle; always shown to touch, which points at nothing, else while the
/// pointer is on it), over the gap and as far into each panel as @sf.edge_reach says (over what shows of the page
/// there: drawn after tape_covers, the drags across that land on it are its own, @sf.handle_drag): dragged, the width
/// of the one in use, from `width` between `least` and `most` (its `edge`: the sidebar's right, the side panel's left),
/// the page beside it showing what it leaves; what was done with it said (the second of two presses: its own width
/// again; a press on the page's part is the page's, tape_frame).
fn tape_edge(
  c : @ui.Ctx,
  key : String,
  label : String,
  gap : Double,
  x : Double,
  top : Double,
  h : Double,
  width : Double,
  least : Double,
  most : Double,
  edge : @ui.Side,
) -> @sf.Resized {
  let id = c.id(key)
  c.cursor(id, ResizeX)
  let said = @sf.handle_drag(c, id, width, min=least, max=most, edge~)
  let held = c.pressed(id) || said is Dragging(_)
  // (the gap `before` from its left and `after` from its right, the look in its middle)
  let (into_in, into_page) = @sf.edge_reach(bar_gap_now())
  let (before, after) = if edge is Left { (into_page, into_in) } else { (into_in, into_page) }
  c.layer(fn() {
    let strip = c.box(
      style=@ui.style(
        row=true,
        w=Fixed(before + bar_gap_now() + after),
        h=Fixed(h),
        pl=@sf.room_of(before),
        pr=@sf.room_of(after),
        justify=JCenter,
      ),
      left=gap - before,
      top~,
      tx=x,
      id~,
      fn() {
        @sf.edge_look(
          c,
          key,
          over=@sf.pointed_or_finger(c, false),
          on=c.lit(id) || c.focus_shown(id) || held,
          active=held,
        )
      },
    )
    c.semantics(strip, Separator, id~, label~)
    @sf.edge_tip(c, key, id, label, side=if edge is Left { Left } else { Right })
  })
  |> ignore
  said
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
fn tape_frame(c : @ui.Ctx, panel : SideOf?, at : (Double, Double, Double), known : Bool) -> Double {
  if !wide.tape {
    wide.tape_ask = None
    wide.tape_chat = ""
    wide.tape_panel = ""
  wide.tape_built = ("", -1)
    wide.tape_pull = None
    wide.tape_drag = 0.0
    wide.tape_backing = false
    wide.tape_back_end = None
    return 0.0
  }
  // a press on what shows of another (tape_covers), a right click there as well (no menu of what it holds); or what
  // shows of it dragged across: the tape in the hand from there, let go brought over or back (tape_let_go)
  for p in [Side, Page, Panel] {
    let id = c.id("tape/" + p.to_string())
    if c.clicked(id) || c.right_clicked(id) is Some(_) {
      wide.tape_ask = Some(p)
    }
    match c.drag_of(id) {
      Some(d) => {
        let (dx, _) = d.take_move()
        if d.down && d.moving && p != wide.tape_at && wide.tape_pull is None {
          wide.tape_pull = Some(p)
          wide.tape_drag = 0.0
        }
        if wide.tape_pull == Some(p) && !wide.tape_backing {
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
  // a press on the edge beside the page (tape_edge) where it lies over what shows of the page: the page's, as a press
  // there would be without it (the edge takes that much of it for a finger's drag); in the gap the edge's own
  for key in ["tape/side-edge", "tape/panel-edge"] {
    let id = c.id(key)
    match (c.drag_of(id), c.rect_of(c.id("tape/Page"))) {
      (Some(d), Some((px, py, pw, ph))) if c.clicked(id) && d.x >= px && d.x < px + pw && d.y >= py && d.y < py + ph =>
        wide.tape_ask = Some(Page)
      _ => ()
    }
  }
  // the back gesture's pull ended (tape_back): gone through, the one it pulled brought over from where it got to;
  // let go (a swipe of mbui's own), over or back as a finger's is; called off, back where it was
  match wide.tape_back_end {
    Some(end) => {
      wide.tape_back_end = None
      wide.tape_backing = false
      match wide.tape_pull {
        Some(p) =>
          match end {
            Back => {
              wide.tape_pull = None
              wide.tape_drag = 0.0
              wide.tape_ask = Some(p)
            }
            LetGo(_, _) => tape_let_go(c, at, p, wide.tape_back_v)
            _ => {
              wide.tape_pull = None
              wide.tape_drag = 0.0
              c.move_state(tape_moves)
            }
          }
        None => ()
      }
    }
    None => ()
  }
  // the chat's side panel opened beside it (the same chat as before, its panel closed then, its view come): the panel
  // comes over; closed while in use, the page. Another chat shown while a panel was in use: its page, not the panel
  // open in it (pengxiao, 2026-10-25: the chat in the middle is what one comes to; a panel shown as its view comes is
  // not one opened). What is chosen to be shown in the page with the side panel in use brings it over (show_page);
  // nothing else moves the tape by itself
  // a passage of a message picked while the page is not in use (held where it shows beside the sidebar): the page
  // comes over with it, its bar there to be pressed (pengxiao, 2026-10-25: 引用 pressed there went to what showed of
  // the page and brought it over, quoting nothing). As it is picked, once: a passage left picked keeps nothing from
  // being brought over after (pengxiao, 2026-10-25: the sidebar pressed or pulled over went straight back)
  let pick = if @sfbase.pk.ts == "" { "" } else { "\{@sfbase.pk.ts}\u{1}\{@sfbase.pk.taken_at}" }
  if pick != "" && pick != wide.tape_pick && wide.tape_at != Page && wide.tape_ask is None && wide.tape_pull is None {
    wide.tape_ask = Some(Page)
  }
  wide.tape_pick = pick
  let chat = match app.nav.top() {
    Chat(r) | History(r, _, _) => chat_key(r)
    // a chat's detail asked as a page, on its way to its chat's side panel (main_page): still that chat, not another
    // come (its panel, opening, comes over)
    p if laid_beside(p) => wide.tape_chat
    _ => ""
  }
  let open = match panel {
    Some(side) => side.key()
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
    // the page brought over for what was put on it once it shows it (the core's answer waited for, LOCAL_MS at most:
    // Nav::shows_when), as a phone's page slides in once it has what it shows: not sliding over with the page before
    // on it, swapped mid-way and built for the first time as it moves; asked still till then
    Some(Page) if wide.tape_at != Page && !app.nav.top_shows() => ()
    // the side panel brought over once a frame before this has built it where it waits past the window's edge, as the
    // page is once it shows what is put on it: what it holds made then (a service's page, its native view made as it is
    // first drawn: a frame held the while), not as it moves, its first steps skipped over that while
    Some(Panel) if open != "" && (wide.tape_built.0 != open || wide.tape_built.1 >= c.frame_number()) => ()
    Some(p) => {
      wide.tape_ask = None
      if p != wide.tape_at && !(p == Panel && open == "") {
        wide.tape_at = p
        // the page no more in use: its field lets go of the keyboard (what shows of it takes nothing)
        if p != Page {
          c.blur()
        }
        c.move_state(tape_moves)
      }
    }
    None => ()
  }
  // (another brought over while one was pulled, by back or a press: the pull is over)
  if wide.tape_pull == Some(wide.tape_at) {
    wide.tape_pull = None
    wide.tape_drag = 0.0
    wide.tape_backing = false
  }
  let pulled = match wide.tape_pull {
    Some(p) => tape_pull_clamp(at, p, wide.tape_drag)
    None => 0.0
  }
  c.moved("--tape-x", tape_x_of(at, wide.tape_at) + pulled)
}

///|
/// What the frame knew of the shown chat's side panel while its view had not come (tape_frame): neither open nor not.
let tape_unknown : String = "?"

///|
/// What panel `p` holds (`body`), kept as it was drawn while nothing it shows can have changed (Ctx::kept_part), in use
/// or not, as GPUI keeps every view it was not told changed: a list scrolled in one builds none of the others, a mark
/// stepping in one builds nothing. In use (and off the tape), read out and taking the hand (built while a finger is on
/// it, and the frame after); behind the one in use, only drawn (a press there brings it over: tape_covers). `at`: where
/// it is and how big, and what else of the frame's it is built from (its ground said with it).
fn tape_part(c : @ui.Ctx, p : TapePane, at : String, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  let in_use = !wide.tape || wide.tape_at == p
  c.kept_part(c.id("tape/kept/" + p.to_string()), "\{at} \{t.p.bg} \{t.dark}", body, read_out=in_use)
}

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
  let k = if span == 0.0 { 0.0 } else { tape_pull_clamp(at, p, wide.tape_drag) / span }
  let fling = v.abs() > tape_fling
  let toward = fling && (v > 0.0) == (span > 0.0)
  let away = fling && !toward
  wide.tape_pull = None
  wide.tape_drag = 0.0
  if toward || (k > tape_pull_over && !away) {
    wide.tape_ask = Some(p)
  } else {
    c.move_state(tape_moves)
  }
}

///|
/// Back on the tape bringing `p` over (the one before the one in use: tape_back_to), step by step as the system's back
/// gesture goes (Ctx::follow_back): the tape in its hand from where it began, as a finger pulling `p` over has it
/// (tape_pull), moved as far as the gesture has come from the edge it came from (either: as a phone's page follows it,
/// Ctx::nav); gone through, `p` brought over from there; called off, back where it was (settled as the frame is built:
/// tape_frame). A back with no gesture (a back key, ⌘[) brings `p` over at once.
fn tape_back(p : TapePane, step : @ui.BackStep) -> Unit {
  match step {
    Began(x, t) =>
      if wide.tape_pull is None {
        wide.tape_pull = Some(p)
        wide.tape_drag = 0.0
        wide.tape_backing = true
        wide.tape_back_x0 = x
        wide.tape_back_last = (x, t)
        wide.tape_back_v = 0.0
        wide.tape_back_end = None
      }
    Moved(x, t) | LetGo(x, t) =>
      if wide.tape_backing {
        let (x1, t1) = wide.tape_back_last
        if t > t1 {
          wide.tape_back_v = (x - x1) / (t - t1) * 1000.0
        }
        wide.tape_back_last = (x, t)
        wide.tape_drag = x - wide.tape_back_x0
        if step is LetGo(_, _) {
          wide.tape_back_end = Some(step)
        }
      }
    CalledOff => if wide.tape_backing { wide.tape_back_end = Some(step) }
    Back =>
      if wide.tape_backing {
        wide.tape_back_end = Some(step)
      } else {
        wide.tape_ask = Some(p)
      }
  }
}

///|
/// Which panel back brings over on the tape: the page from the side panel, the sidebar from the page chosen to be shown
/// with nothing of the pane's under it (page_back_pops); None where back is not the tape's (a page opened over that one
/// taken off, as a phone's are: the page's stack, Ctx::nav_flat's; what is over the whole window put away, the
/// sidebar's own: wide_back).
fn tape_back_to() -> TapePane? {
  if !wide.tape || app.nav.top() is (Screen(_) | DriveRead(_) | DrivePlay(_)) {
    return None
  }
  match wide.tape_at {
    Panel => Some(Page)
    Page => if page_back_pops() { None } else { Some(Side) }
    Side => None
  }
}

///|
/// Whether back with the page in use on the tape goes back in the page: what was opened over it taken off (Nav::push_over,
/// sliding as a phone's), or a page of the pane's own under it come back to (a settings page under the one it opened:
/// its bar's back there too, setting_page). Not where under it is a place's own (the chats', the settings', 文件's…:
/// what the pane shows before anything is chosen, the sidebar its list): the sidebar comes over instead.
fn page_back_pops() -> Bool {
  let pages = app.nav.pages()
  let n = pages.length()
  app.nav.top_over() || (n >= 2 && !(pages[n - 2] is (Home | Settings | Place(_) | Files | Decisions | Archived)))
}

///|
/// Whether what is opened now goes over the page shown (laid out on the tape, the page or its side panel in use: what
/// it opens from there, as a phone's page does, pushed over it, Nav::push_over, back coming to it again) rather than in
/// its place (the sidebar in use, choosing what the page shows; laid out Large, the web's pane).
pub fn page_goes_on() -> Bool {
  wide.tape && wide.tape_at != Side
}

///|
/// Whether page `p`, opened now, goes over the page shown (page_goes_on): one that is a page of the pane's own
/// (shown_in_page), not a chat's detail asked as a page (its history, a service, a file: the frame lays it beside its
/// chat, in the chat's place).
pub fn goes_over(p : Page) -> Bool {
  page_goes_on() && shown_in_page(p) && !laid_beside(p)
}

///|
/// Whether page `p` is a chat's detail asked as a page, which the frame lays beside its chat in its side panel
/// (main_page): its history, a service, a file. Opened on the tape, the panel comes over with it (tape_frame: a panel
/// opened), not the page, which keeps the chat.
pub fn laid_beside(p : Page) -> Bool {
  p is (History(_, _, _) | Service(_, _) | PreviewFile(_, _, _, _))
}

///|
/// How much of the way a panel pulled over must have come to be brought over when let go, and how fast a finger
/// leaving it (px/s) flings it over or back whatever the way it came (the 奏 deck's swipe's fling, decisions.mbt).
let tape_pull_over : Double = 0.3

///|
let tape_fling : Double = 900.0

///|
/// What shows of the panels not in use on the tape, each under a cover of its shape that takes what is done there, drawn
/// nothing (the panel as it is, its pages' ground a phone's): a press there, a tap, a click or a right click, brings it
/// over (tape_frame) and goes to nothing it holds; dragged across, it comes with the finger (the tape in the hand) and, let go,
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
        // (a finger held on it picks the words under it, as it brings it over: tape_frame)
        c.holds_through(id)
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
        c.semantics(b, Button, id~, label=tape_words(p))
      }
    }
  })
  |> ignore
}

///|
/// The corners of panel `p` on the tape (@sf.tape_corners): on the side it stands at the window's edge in use the
/// window's less its 6 from it where they follow it, the others the tape's corner. The sidebar's at the window's
/// left, the side panel's at its right, the page's at its right with no side panel open after it (`panel`).
fn tape_pane_corners(p : TapePane, panel : Bool) -> FixedArray[@ui.CornerOf] {
  match p {
    Side => @sf.tape_side_corners()
    Page => @sf.tape_corners(left=false, right=!panel)
    Panel => @sf.tape_corners(left=false, right=true)
  }
}

///|
/// The corners what is in a tape's panel `k` round stands in, the panel going `under` past it on under the system's
/// column (an iPhone Duo's): its right ones none where it does (square, what is at its foot or top there in no corner:
/// the panel's are under the column, past what is in it), so a composer at its foot is concentric with its left foot
/// corner alone, as the tape's panels' are with none beside them (the user, 2026-10-28: its corners did not match).
fn beside_column(k : FixedArray[@ui.CornerOf], under : Double) -> FixedArray[@ui.CornerOf] {
  if under > 0.0 {
    [k[0], Own(0.0), Own(0.0), k[3]]
  } else {
    k
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
/// it (the closed bar's: bar_in_now(), bar_gap_now()).
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
/// The page in it, drawn moved aside while the sidebar is shown a while.
// kept across runs: a value (no field of it changes)
let page_aside : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let frame_gate : @ui.Style = @ui.css("bg=Bg")

///|
/// A page's bar's padding at its left and its right (styles/sidebar.css.ts pageBar: 12, at its right where the window's
/// corner has its last button in a window's whole: @sf.window_end_in; brand.css.ts, railed, closed: 28 in a window with
/// its buttons in the app's top row, which reach 12 past the rail; 12 again while the folded sidebar shown a while
/// reaches over the bar, which starts past it), and its margins while it is shown a while (from its edge to the
/// window's; under the window's buttons' row, from the rail as folded: less than none at its start, the page's move
/// aside taken back): where the block's move has got to (side_moves' page-bar), so a bar built of them moves with the
/// page it is on, its words not jumping ahead of it.
pub fn page_bar_room() -> (Double, Double, Double, Double) {
  (wide.bar_pl, if wide.tape { @sf.tape_bar_end(bar_in) } else { @sf.window_end_in(bar_in) }, wide.bar_ml, wide.bar_mr)
}

///|
/// A page's bar's row (`style`: as wide as the page, its height) with its room (page_bar_room) round what `bar` builds
/// (told its padding at its left and its right): its margins as spaces at its ends, one less than none taken back by
/// drawing the row moved back as far (the page drawn moved aside within what cuts it: frame's page_in). Named
/// "page-bar" (what the page shows across leaves it out: peek_shift).
pub fn page_bar_row(c : @ui.Ctx, style : @ui.Style, bar : (Double, Double) -> Unit) -> Int {
  let (pl, pr, ml, mr) = page_bar_room()
  let room = fn(x : Double) { c.box(style=@ui.style(w=Fixed(x), h=Full), fn() {  }) |> ignore }
  let back = dmin(0.0, ml)
  c.box(style~, moves="page-bar", tx=back, fn() {
    room(dmax(0.0, ml))
    bar(pl, pr)
    room(mr + back)
  })
}

///|
/// At the end of a page's bar that has no padding of its own there (a new chat's): as wide as its right margin while the
/// folded sidebar is shown a while (page_bar_room), its end by the window's; moved with the block as that is.
pub fn page_bar_end(c : @ui.Ctx) -> Unit {
  c.box(style=@ui.style(w=Fixed(wide.bar_mr)), fn() {  }) |> ignore
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
/// Whether the chats' place of workspace `w` has nothing open yet and is still to land on its chat (land: the core's
/// mark of it not come): what is beside the list is not known till then.
pub fn landing(w : Workspace) -> Bool {
  app.nav.depth() == 1 && app.nav.top() == Home && wide.landed != w.id
}

///|
/// The chats' place with nothing open: the chat the core says was open last in this workspace, else a new chat
/// (workspace.tsx WorkspaceHome; once per workspace, so closing the chat goes back to the list on a phone).
fn land(src : Source, w : Workspace) -> Unit {
  if app.nav.depth() != 1 || app.nav.top() != Home {
    return
  }
  // come back to the chats (a chat closed, settings left): a new chat, as the web's empty place is
  if wide.landed == w.id {
    // (come back by back: forward puts back what it took in the new chat's place)
    @sfbase.forward_landed()
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
    // the settings come to beside their list: its first row's page (settings_frame.mbt settings_landing)
    Settings => setting_page(c, src, w, settings_landing)
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
/// Which sidebar the block holds (Rail.tsx SidebarGroup), each its own width and folded or not: the files', the
/// profiles' and the stations' when in the rail, the chats' for the chats' places and the others in the rail, else the
/// settings'; in a place with none of its own, the one it had (side_place: it closes as wide as it was).
fn side_group(src : Source, ws : String) -> String {
  let place = side_place()
  let railed = rail_items(src, ws)
  match place {
    "files" => "files"
    "profiles" if railed.contains("profiles") => "profiles"
    "stations" if railed.contains("stations") => "stations"
    "chats" | "decisions" | "archive" => "chats"
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
/// The sidebar shown follows the place and the workspace as it was left on this device (prefs `sidebars`): its width
/// the person's, the same in every workspace, by `\n<group>` (no workspace before the line); folded or not each
/// workspace's own, by `<workspace>\n<group>` (`closed`; Rail.tsx widthFor, folded). A width kept before by a
/// workspace (`<width>` or `<width>,closed` there) is read where none is kept across them. What changes of it is
/// kept, once a drag of its edge is over. (The user, 2026-10-27: a sidebar's width is the person's, not the
/// workspace's.)
fn side_follow(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  // (not read yet: as it is until it is)
  if prefs is None {
    return
  }
  // (beside the system's tabs one width whatever the tab, so the cards stay where they are as one is chosen: the user,
  // 2026-10-27, the sidebar jumping from tab to tab)
  let group = if @sf.native_on() { "tabs" } else { side_group(src, ws) }
  let key = ws + "\n" + group
  let width_key = "\n" + group
  if wide.side_key != key {
    let kept = field(prefs, "sidebars")
    let parts = text(kept, key).split(",").map(fn(p) { p.to_string() }).collect()
    let closed = parts.contains("closed")
    let own = if parts.length() > 0 && parts[0] != "closed" { parts[0] } else { "" }
    let width = match text(kept, width_key) {
      "" => own
      w => w
    }
    wide.side_w = match whole_of(width) {
      Some(n) if n > 0 => dmax(side_min, dmin(side_max, n.to_double()))
      _ => side_default(group)
    }
    wide.folded = closed
    wide.side_key = key
    wide.kept_w = wide.side_w
    wide.kept_folded = wide.folded
    wide.peeking.set(false)
    return
  }
  if wide.edge_held || (wide.side_w == wide.kept_w && wide.folded == wide.kept_folded) {
    return
  }
  let (kept_w, kept_folded) = (wide.side_w, wide.folded)
  let w = if wide.side_w == side_default(group) { "" } else { wide.side_w.round().to_int().to_string() }
  // (the workspace's says only whether it is folded from now on: a width it kept before is the one across them now)
  let said = Map::from_array([
    (width_key, if w == "" { Json::null() } else { Json::string(w) }),
    (key, if wide.folded { Json::string("closed") } else { Json::null() }),
  ])
  // (kept once the frame's builds are over, as the last saw it)
  c.after_build("side-kept", fn() {
    wide.kept_w = kept_w
    wide.kept_folded = kept_folded
    (src.call)("prefs.set", Json::object({ "sidebars": Json::object(said) }), fn(_) {  })
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
    wide.peeking.set(false)
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
      wide.peeking.set(true)
    }
    match c.tapped_anywhere() {
      Some((x, y)) if wide.peeking.get() && !held && !on_bar(x, y) && x >= bar_in_now() + rail_closed_w + wide.side_w =>
        wide.peeking.set(false)
      _ => ()
    }
    return
  }
  // on it, or on its edge at its right (Rail.tsx PEEK_ON: the dock, the edge, what pops up from it)
  let over = (px >= bar_x && px < bar_r && py >= bar_y && py < bar_b) ||
    (wide.peeking.get() && px >= bar_r - 2.0 && px < bar_r + 10.0)
  if over && !wide.peeking.get() && px < bar_x + rail_closed_w {
    wide.peeking.set(true)
  }
  if @kit.after(c, "side/peek-away", wide.peeking.get() && !over && !held, peek_leave_ms) {
    wide.peeking.set(false)
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
  if wide.peeking.get() && wide.peek_top is Some(was) && was != top {
    wide.peeking.set(false)
  }
  if wide.peek_next {
    wide.peek_next = false
    wide.peeking.set(true)
  }
  wide.peek_top = Some(top)
}

///|
/// How long the pointer is off the sidebar shown a while before it folds again (Rail.tsx PEEK_LEAVE).
pub let peek_leave_ms : Double = 400.0
