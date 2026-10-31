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
  side_w : @signals.Signal[Double]
  folded : @signals.Signal[Bool]
  edge_held : @signals.Signal[Bool]
  /// folded, whether it is shown a while over the page (Rail.tsx peekSidebar)
  peeking : @signals.Signal[Bool]
  /// folded for the page's room whatever was chosen (page_beside_least), this frame; shown a while from the next as a
  /// place is pressed into; the page shown as the last build began (a row chosen while shown: another page, folded)
  mut crowded : Bool
  peek_next : @signals.Signal[Bool]
  peek_top : @signals.Signal[Page?]
  /// the place whose sidebar the block holds as it was last built (side_place: kept through a place with none)
  mut side_place : String
  /// the sidebar shown (its workspace and group) and how it was kept (prefs `sidebars`)
  mut side_key : String
  kept_w : @signals.Signal[Double]
  kept_folded : @signals.Signal[Bool]
  /// the sidebar being drawn in the closed bar (what the web's sidebar does there, at once)
  mut in_bar : Bool
  /// the block closed to the bar this frame (the web's data-sidebar="closed"): what is drawn in it as there
  closed : @signals.Signal[Bool]
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
  /// where the page starts (the column the block takes, where its move has got)
  mut page_from : Double
  /// the chat last opened here by the frame (the core's last chat taken once per workspace)
  landed : @signals.Signal[String]
  /// the rail's menu (from its right click): the place right clicked ("" the rail), where; a place dragged to another
  /// place in it: which, where the pointer went down, how far it went; the rail being changed (自定义侧边条); the ＋'s
  /// menu over the workspaces open
  rail_menu : @signals.Signal[(String, Double, Double)?]
  rail_drag : @signals.Signal[(String, Double, Double)?]
  editing : @signals.Signal[Bool]
  /// 待处理's panel, the services' panel from the lists' foot, ⌘/'s shortcuts open
  attention_open : @signals.Signal[Bool]
  jobs_open : @signals.Signal[Bool]
  keys_open : @signals.Signal[Bool]
  /// laid out Medium this frame (the rail and the sidebar beside the page on a tape: @sf.layout), with a sidebar to
  /// show; which of its panels is in use (kept while the frame is off the tape: a place with no sidebar, another
  /// layout; the sidebar at first); one asked over where no frame was being built (back); the chat shown last frame and
  /// the one whose side panel was open then (its panel opening brings it over)
  mut tape : Bool
  tape_at : @signals.Signal[TapePane]
  tape_ask : @signals.Signal[TapePane?]
  tape_chat : @signals.Signal[String]
  tape_panel : @signals.Signal[String]
  /// the side panel last open on the tape off it (the frame's: nothing kept of it there, tape_off)
  mut tape_last_side : SideOf?
  /// the one not in use being pulled over by what shows of it (tape_covers), and how far the finger has moved the tape
  /// since it took it
  tape_pull : @signals.Signal[TapePane?]
  tape_drag : @signals.Signal[Double]
  /// the pull the system's back gesture's (tape_view.mbt tape_back): where it began across (from the edge it came from),
  /// where and when it was last and how fast it went there (px/s)
  mut tape_backing : Bool
  mut tape_back_x0 : Double
  mut tape_back_last : (Double, Double)
  mut tape_back_v : Double
  /// the passage picked last frame (its message and the frame it was taken), a new one bringing the page over
  tape_pick : @signals.Signal[String]
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
  side_w: @signals.signal(side_own, same=fn(a, b) { a == b }),
  folded: @signals.signal(false, same=fn(a, b) { a == b }),
  edge_held: @signals.signal(false, same=fn(a, b) { a == b }),
  peeking: @signals.signal(false, same=fn(a, b) { a == b }),
  crowded: false,
  peek_next: @signals.signal(false, same=fn(a, b) { a == b }),
  peek_top: @signals.signal(None, same=fn(a, b) { a == b }),
  side_place: "chats",
  side_key: "",
  kept_w: @signals.signal(0.0, same=fn(a, b) { a == b }),
  kept_folded: @signals.signal(false, same=fn(a, b) { a == b }),
  in_bar: false,
  closed: @signals.signal(false, same=fn(a, b) { a == b }),
  brand_h: 0.0,
  band: 0.0,
  mark: 0.0,
  bar_pl: 0.0,
  bar_ml: 0.0,
  bar_mr: 0.0,
  page_from: 0.0,
  landed: @signals.signal("", same=fn(a, b) { a == b }),
  rail_menu: @signals.signal(None, same=fn(a, b) { a == b }),
  rail_drag: @signals.signal(None, same=fn(a, b) { a == b }),
  editing: @signals.signal(false, same=fn(a, b) { a == b }),
  attention_open: @signals.signal(false, same=fn(a, b) { a == b }),
  jobs_open: @signals.signal(false, same=fn(a, b) { a == b }),
  keys_open: @signals.signal(false, same=fn(a, b) { a == b }),
  tape: false,
  tape_at: @signals.signal(Side, same=fn(a, b) { a == b }),
  tape_ask: @signals.signal(None, same=fn(a, b) { a == b }),
  tape_chat: @signals.signal("", same=fn(a, b) { a == b }),
  tape_panel: @signals.signal("", same=fn(a, b) { a == b }),
  tape_last_side: None,
  tape_pull: @signals.signal(None, same=fn(a, b) { a == b }),
  tape_drag: @signals.signal(0.0, same=fn(a, b) { a == b }),
  tape_backing: false,
  tape_back_x0: 0.0,
  tape_back_last: (0.0, 0.0),
  tape_back_v: 0.0,
  tape_pick: @signals.signal("", same=fn(a, b) { a == b }),
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
  wide.side_w.set(side_own)
  wide.folded.set(false)
  wide.edge_held.set(false)
  wide.peeking.set(false)
  wide.crowded = false
  wide.peek_next.set(false)
  wide.peek_top.set(None)
  wide.side_place = "chats"
  wide.side_key = ""
  wide.kept_w.set(0.0)
  wide.kept_folded.set(false)
  wide.in_bar = false
  wide.closed.set(false)
  wide.brand_h = 0.0
  wide.band = 0.0
  wide.mark = 0.0
  wide.bar_pl = 0.0
  wide.bar_ml = 0.0
  wide.bar_mr = 0.0
  wide.page_from = 0.0
  wide.landed.set("")
  wide.rail_menu.set(None)
  wide.rail_drag.set(None)
  wide.editing.set(false)
  wide.attention_open.set(false)
  wide.jobs_open.set(false)
  wide.keys_open.set(false)
  wide.tape = false
  wide.tape_at.set(Side)
  wide.tape_ask.set(None)
  wide.tape_chat.set("")
  wide.tape_panel.set("")
  wide.tape_last_side = None
  wide.tape_pull.set(None)
  wide.tape_drag.set(0.0)
  wide.tape_backing = false
  wide.tape_back_x0 = 0.0
  wide.tape_back_last = (0.0, 0.0)
  wide.tape_back_v = 0.0
  wide.tape_pick.set("")
  tape_goes_reset()
  fold_goes_reset()
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
  if wide.tape_at.get() != Side {
    wide.tape_ask.set(Some(Page))
  }
}

///|
/// The page brought over whatever is in use: what is opened to be written in at once (新建对话, ⌘N: pengxiao,
/// 2026-10-25, opened from the sidebar in use it showed beside it), a fixture's page as the app begins (a picture's).
pub fn bring_page() -> Unit {
  wide.tape_ask.set(Some(Page))
}

///|
/// Whether page `p`, opened, is shown in the page pane (show_page): not a place's own page, whose list is the
/// sidebar's (the chats', the settings', 文件's, the archive's, a rail's place's), nor what is over the whole
/// window (a screen, a file read or played).
pub fn shown_in_page(p : Page) -> Bool {
  !(p is (Home | Settings | Place(_) | Files | Archived | Screen(_) | DriveRead(_) | DrivePlay(_)))
}

///|
/// The sidebar folded or opened (⌘\, the lit place pressed again, ⌘K's command); nothing on the tape, where the
/// sidebar is never put away but by a press on the page beside it or what is chosen to be shown in the page
/// (show_page; asked, 2026-10-24: it went away unasked).
pub fn sidebar_toggle() -> Unit {
  if !wide.tape {
    wide.folded.set(!wide.folded.get())
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
  (wide.folded.get() && !wide.tape) || wide.crowded
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
/// The rail and the sidebar as one block (shell.css.ts dock) in its column `col` (the shell's grid's first, a phone's or
/// a tablet's bars `top` and `foot` clear), as the web's CSS has it: open, the column's whole, the sidebar's ground;
/// closed (`bar`), the closed bar: 6 from the window's edges (under its buttons' row where they are in the app's top
/// row), 8 from the page, as wide as the rail, a floating panel's ground, its line and a faint shadow, its corner
/// concentric with the places' grounds 6 in; shown a while (`peek`), reaching over the page as wide as the rail and the
/// sidebar (its margin past the column), a floating panel's shadow; on the tape a panel of its own, apart from the
/// page. Off the tape `fold` says where the block's move has got (pane_view.mbt's FoldLook) and whether it goes: its
/// margins, line, shadow, corner and ground, the sidebar's width, the rail's, from there; at rest the corner its own
/// (linked to the window's). `s`: the sidebar's width; `x`: how far it is drawn moved across.
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
  held? : Bool = false,
  fold? : (FoldLook, Bool)? = None,
) -> Unit {
  let t = @sf.theme()
  // on the tape (open, apart from the page), a panel of its own as the closed bar is: 6 from the window's edges, 8 from
  // the page's panel
  let apart = wide.tape && !bar
  let f = match fold {
    Some((f, _)) => f
    None => fold_look_tape(s, col, top, foot)
  }
  let moving = fold is Some((_, true))
  let (ml, mt, mr, mb) = (f.ml, f.mt, f.mr, f.mb)
  // its line (::after's opacity), and what is in the sidebar drawn while any of it shows: open, shown a while, or
  // still on its way to the bar
  let line = f.line
  let shown = !bar || peek || f.showing > 0.0
  // the sidebar beside the rail: open its own width and 8 more, reaching 8 into the rail's; the group's in the bar
  let side_w = f.side_w
  // (a panel's corners the tape's sidebar's, the closed bar's its own: each in the window's the window's less its 6 from
  // it where it follows it; on its way between, as round as its move has it)
  let look = if apart {
    dock_look.then(@ui.style(radius=@sf.corners_radius(tape_pane_corners(Side, false))))
  } else if moving && @sf.native_card_corner() <= 0.0 {
    dock_look.then(@ui.style(radius=@sf.radius_between(f.corner)))
  } else if bar {
    dock_look.then(@ui.style(radius=@sf.closed_bar_corner(rail_closed_ground_in)))
  } else {
    dock_look
  }
  let look = look.then(@ui.style(bg=Data(if apart { dock_ground(bar) } else { f.ground })))
  let dock_w = dmax(0.0, col - ml - mr)
  // (open beside the system's tabs, its ground to the window's foot as the system's own sidebars are, its list under the
  // home indicator: rail_native.mbt)
  let foot = if side_full_height(bar) { 0.0 } else { foot }
  let dock_h = dmax(0.0, c.height - top - foot - mt - mb)
  // (over the page, as the web's block is; `held`, in an island of its own: tape_view.mbt, pane_view.mbt)
  let column = fn() {
    c.box(style=dock_column.then(@ui.style(w=Fixed(col))), tx=x + f.x, fn() {
      let b = c.box(
        style=look.then(
          @ui.style(
            w=Fixed(dock_w),
            h=Fixed(dock_h),
            border_color=Data(@sf.alpha(t.p.line, line)),
            shadow=Cast(f.blur, f.fall, @sf.alpha(t.p.shadow, f.shade)),
          ),
        ),
        // (named as the web's block is: what finds it, layout.sh and the tests, by it; along a screen whose corners it
        // follows, an iPhone Duo's, none)
        moves=if @sf.native_card_corner() > 0.0 { "" } else { "dock" },
        left=ml,
        top=top + mt,
        fn() {
          if !@sf.native_on() {
            rail(c, src, w, all, bar, moving=if moving { Some(f) } else { None })
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
  }
  if held {
    column()
  } else {
    c.layer(column) |> ignore
  }
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
/// Whether a finger has the pointer now (the frame's panes: a finger drags their lists and holds to pick words, a mouse
/// scrolls them by the wheel and drags to pick).
fn pane_finger() -> Bool {
  @ui.pointing() is Finger
}

///|
/// The sidebar's top row's height (Sidebar.css.ts brand: none in the closed bar), the bars `top` high: beside the
/// window's buttons where they are the system's at its left (macOS's), from the window's top where it is as high as the
/// window beside the system's tabs (rail_native.mbt).
fn side_brand_h(bar : Bool, top : Double) -> Double {
  if bar {
    0.0
  } else if @ui.window_keys_left() {
    side_top_inset
  } else if side_full_height(bar) {
    side_top_web + top
  } else {
    side_top_web
  }
}

///|
/// The page in its pane, `main_w` wide and `ph` high, in workspace `w`: its top row a bar's height, the window's title
/// bar under the page, whether the page has a bar there or not (a new chat, settings: title_row); what waits to be
/// confirmed in the workspace's safe mode (`gated`), else the stack's top drawn flat, moved `aside` (the folded sidebar
/// shown a while). On the tape the page a phone's screen: what is opened from it pushed over it, slid in and taken off
/// by back as a phone's are, down to the page chosen to be shown in it (page_goes_on).
fn page_in(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  gated : Bool,
  main_w : Double,
  ph : Double,
  aside : Double,
  finger : Bool,
) -> Unit {
  if @ui.window_inset() {
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
        c.nav_flat(
          app.nav,
          fn(page) {
            let moved = c.box(style=page_aside, tx=aside, fn() {
              // (the page drawn: one on its way out, a stack's move, hands no actions to the system's bars)
              drawn_page.val = Some(page)
              if page == app.nav.top() {
                top_drawn.val = true
              }
              // (the workspaces as read here: what the page is built from, read by it)
              let (now, all, _, invited) = @sfbase.workspace_in_view(src)
              main_page(c, src, now.unwrap_or(w), all, invited, page)
              drawn_page.val = None
            })
            @motion.scope(c, moved, bottom=true)
          },
          bg=@sf.theme().p.bg,
          stacks=wide.tape,
          // (back its while the page is in use: the side panel's, the sidebar's first)
          takes_back=!wide.tape || wide.tape_at.get() == Page,
        )
        |> ignore
      }
    }
    // the page's words are picked with the pointer and copied, as the web's (the sidebar's are not); a finger picks
    // them as on a phone (pick.mbt)
    if finger {
      page()
    } else {
      c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), page)
    }
  })
}

///|
/// Back on the wide frame (docs/architecture.md, the tiers' table): what is over the whole window (a screen, a file
/// read or played) put away first, a page of the stack popped. On the tape, with a chat's side panel in use, the page
/// brought over; with the page in use, what was opened over it from there taken off (Nav::push_over), else the
/// sidebar brought over (the page it chose: the chats' place's chat, a settings page); with the sidebar in use, the chats' from another place's (or the
/// archive), as a phone's place goes back to them; nothing with the chats' in use (the system's: as from a phone's
/// list). Laid out Large, the spot before this one in the app's history (sfbase's app_history.mbt: another chat, another
/// workspace's, a page under it), else the stack's top popped, but for the new chat beside the chats alone: the page
/// there is never empty (land: popped, a new chat would come again), so nothing to go back to.
pub fn wide_back(src : Source) -> (() -> Unit)? {
  let over_all = app.nav.top() is (Screen(_) | DriveRead(_) | DrivePlay(_))
  if wide.tape && !over_all {
    match tape_back_to() {
      Some(p) => Some(fn() { wide.tape_ask.set(Some(p)) })
      None =>
        match wide.tape_at.get() {
          // (the sidebar of another place, or the archive: the chats', as a phone's place goes back to them)
          Side =>
            if lit_place() != "chats" || app.nav.pages().contains(Archived) {
              Some(fn() {
                @sfbase.go_place("chats") |> ignore
                wide.landed.set("")
              })
            } else {
              None
            }
          _ => Some(@sfbase.back_pop)
        }
    }
  } else if @sfbase.history_back_step(src) is Some(f) {
    // the spot before this one (the web's history: a chat chosen before, another workspace's, a page under it)
    Some(f)
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
  match panel_own.width.get() {
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
/// Where the tape is with `p` in use (`at`: tape_at's).
fn tape_x_of(at : (Double, Double, Double), p : TapePane) -> Double {
  match p {
    Side => at.0
    Page => at.1
    Panel => at.2
  }
}

///|
/// What the frame knew of the shown chat's side panel while its view had not come (tape_frame): neither open nor not.
let tape_unknown : String = "?"

///|
/// How far the finger may move the tape pulling `p` over: from where it is with the one in use to where it has `p` in
/// use, no further either way (`at`: tape_at's).
fn tape_pull_clamp(at : (Double, Double, Double), p : TapePane, drag : Double) -> Double {
  let span = tape_x_of(at, p) - tape_x_of(at, wide.tape_at.get())
  if span < 0.0 {
    dmax(span, dmin(0.0, drag))
  } else {
    dmax(0.0, dmin(span, drag))
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
  match wide.tape_at.get() {
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
  app.nav.top_over() || (n >= 2 && !(pages[n - 2] is (Home | Settings | Place(_) | Files | Archived)))
}

///|
/// Whether what is opened now goes over the page shown (laid out on the tape, the page or its side panel in use: what
/// it opens from there, as a phone's page does, pushed over it, Nav::push_over, back coming to it again) rather than in
/// its place (the sidebar in use, choosing what the page shows; laid out Large, the web's pane).
pub fn page_goes_on() -> Bool {
  wide.tape && wide.tape_at.get() != Side
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
/// leaving it (px/s) flings it over or back whatever the way it came.
let tape_pull_over : Double = 0.3

///|
let tape_fling : Double = 900.0

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
  app.nav.depth() == 1 && app.nav.top() == Home && wide.landed.get() != w.id
}

///|
/// The chats' place with nothing open: the chat the core says was open last in this workspace, else a new chat
/// (workspace.tsx WorkspaceHome; once per workspace, so closing the chat goes back to the list on a phone).
fn land(src : Source, w : Workspace) -> Unit {
  if app.nav.depth() != 1 || app.nav.top() != Home {
    return
  }
  // come back to the chats (a chat closed, settings left): a new chat, as the web's empty place is
  if wide.landed.get() == w.id {
    app.nav.push(NewChat)
    return
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  guard marks.value is Some(_) else { return }
  wide.landed.set(w.id)
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
    "chats" | "archive" => "chats"
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
  if side_take(src, ws) {
    return
  }
  let prefs = (src.topic)("prefs", {}).value
  if prefs is None {
    return
  }
  let group = if @sf.native_on() { "tabs" } else { side_group(src, ws) }
  let key = ws + "\n" + group
  let width_key = "\n" + group
  if wide.edge_held.get() || (wide.side_w.get() == wide.kept_w.get() && wide.folded.get() == wide.kept_folded.get()) {
    return
  }
  let (kept_w, kept_folded) = (wide.side_w.get(), wide.folded.get())
  let w = if wide.side_w.get() == side_default(group) { "" } else { wide.side_w.get().round().to_int().to_string() }
  // (the workspace's says only whether it is folded from now on: a width it kept before is the one across them now)
  let said = Map::from_array([
    (width_key, if w == "" { Json::null() } else { Json::string(w) }),
    (key, if wide.folded.get() { Json::string("closed") } else { Json::null() }),
  ])
  // (kept once the frame's builds are over, as the last saw it)
  c.after_build("side-kept", fn() {
    wide.kept_w.set(kept_w)
    wide.kept_folded.set(kept_folded)
    (src.call)("prefs.set", Json::object({ "sidebars": Json::object(said) }), fn(_) {  })
  })
}

///|
/// The sidebar of this place and workspace `ws` taken as it was left (side_follow), where it is another than the one
/// shown: its width, whether it is folded; true then. As the place or the workspace changes (at that cause, on the
/// tape: tape_view.mbt), or as the frame is built.
fn side_take(src : Source, ws : String) -> Bool {
  let prefs = (src.topic)("prefs", {}).value
  // (not read yet: as it is until it is)
  if prefs is None {
    return false
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
    wide.side_w.set(
      match whole_of(width) {
        Some(n) if n > 0 => dmax(side_min, dmin(side_max, n.to_double()))
        _ => side_default(group)
      },
    )
    wide.folded.set(closed)
    wide.side_key = key
    wide.kept_w.set(wide.side_w.get())
    wide.kept_folded.set(wide.folded.get())
    wide.peeking.set(false)
    return true
  }
  false
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
      Some((x, y)) if wide.peeking.get() && !held && !on_bar(x, y) && x >= bar_in_now() + rail_closed_w + wide.side_w.get() =>
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
    wide.peek_next.set(false)
    wide.peek_top.set(None)
    return
  }
  if wide.peeking.get() && wide.peek_top.get() is Some(was) && was != top {
    wide.peeking.set(false)
  }
  if wide.peek_next.get() {
    wide.peek_next.set(false)
    wide.peeking.set(true)
  }
  wide.peek_top.set(Some(top))
}

///|
/// How long the pointer is off the sidebar shown a while before it folds again (Rail.tsx PEEK_LEAVE).
pub let peek_leave_ms : Double = 400.0

///|
/// `open` at `e` of the way to `closed`.
fn fold_at(open : Double, closed : Double, e : Double) -> Double {
  open + (closed - open) * e
}
