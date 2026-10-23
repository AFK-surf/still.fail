// still.fail at a desktop's width (macOS, Windows): the web app's wide frame (ember web/src/cloud/workspace.tsx
// WorkspaceShell, styles/shell.css.ts), which the desktop app shows too. Above the web's breakpoint (701 wide) the
// rail at the left (Rail.tsx: the places, the workspaces, settings), the sidebar beside it on the same ground (the
// chats' list, or the settings', the files', 奏's: wide_side.mbt), and the page the stack has on top in the rest
// (the chat open, a settings page, a folder…); below it the phone's pages as before. Both are the same stack of pages
// (app.nav) and the same core topics: the window resized across the breakpoint shows the same place either way.

///|
/// From this width on, the wide frame (the web's `(min-width: 701px)`).
pub let wide_from : Double = 701.0

///|
/// The rail's width; the sidebar's own (Rail.tsx SIDEBAR: 240, from 180 to 480).
let rail_w : Double = 56.0

///|
let side_min : Double = 180.0

///|
let side_max : Double = 480.0

///|
/// What the wide frame keeps of its own (the rest is the stack's and the core's).
priv struct Wide {
  /// the sidebar's width, and whether it is folded to the rail (⌘\)
  mut side_w : Double
  mut folded : Bool
  /// the sidebar's edge in hand (pressed or dragged): its width kept, and the block moved, once it is let go
  mut edge_held : Bool
  /// a chat's row's menu open (its right click): its row's key, the item, where
  mut menu : (String, ChatItem, Double, Double)?
  /// a row being renamed in place: its key
  mut renaming : String
  /// the lists' filter menu open, 待处理's panel open
  mut filter_open : Bool
  mut attention_open : Bool
  /// ⌘K's panel open, what is typed in it, the row chosen
  mut switcher : Bool
  mut chosen : Int
  /// 快捷键一览 (⌘/) open
  mut keys_open : Bool
  /// the chat last opened here by the frame (the core's last chat taken once per workspace)
  mut landed : String
  /// beside each chat, by its station and session (wide_panel.mbt): the side panel's tabs, the one in front
  tabs : Map[String, Array[String]]
  front : Map[String, String]
  /// the chat's "…" open (what is done with it), its services' popover open
  mut info_open : Bool
  mut jobs_open : Bool
  /// the job picked in the 任务 tab ("" the first)
  mut job_picked : String
  /// ⌘F's bar (wide_find.mbt): the chat it is open in ("" closed), its field, what is typed, what the core found
  /// (None nothing asked yet), the time the reader is at (which of its messages, which time in it), whether what is
  /// not on the device is being read, the message the chat's window was last moved about for it
  mut find_chat : String
  find_field : @ui.Field
  mut find_query : String
  mut found : Found?
  mut find_at : Int
  mut find_k : Int
  mut bringing : Bool
  mut find_around : Double
  /// a model control's panel open (model_triple.mbt): its station and pick ("" none), its accounts' panel beside it,
  /// its filter's field and words; the borrowing it asks to confirm ("" none)
  mut triple : String
  mut triple_accounts : Bool
  triple_field : @ui.Field
  mut triple_query : String
  mut borrow_asking : String
  /// an agent's history in the side panel (wide_history.mbt): 只看收发, its details folded; where its runtime keeps
  /// each session's transcript (by station and session; "" none), asked once; its context's 管理 menu open, clearing
  /// it asked to confirm (its session's key, "" none)
  mut history_io : Bool
  mut history_shut : Bool
  transcripts : Map[String, String]
  mut context_menu : String
  mut clear_asking : String
  /// the new chat's station chooser open (wide_newchat.mbt)
  mut station_menu : Bool
  /// the rail's menu (Rail.tsx's, from its right click): the place right clicked ("" the rail), where
  mut rail_menu : (String, Double, Double)?
  /// a place of the rail dragged to another place in it: which, where the pointer went down, how far it went
  mut rail_drag : (String, Double, Double)?
  /// the page picked in a place with a list of its own (Station's, Profile's: wide_places.mbt), by place
  place_pick : Map[String, @settings.Route]
  /// the files' page (wide_files.mbt): its way chosen here, the 个人收藏 kept here (by workspace), what is opened in
  /// its sidebar and its tree, each station's places, the folders open in columns (by where the columns start), the
  /// row chosen
  mut files_view : String?
  favs_set : Map[String, String]
  files_open : Map[String, Bool]
  files_places : Map[String, Array[Json]]
  files_cols : Map[String, String]
  mut files_chosen : String
  /// the preview beside the list shown or not, as chosen here until the prefs say (wide_files_pane.mbt)
  mut files_preview : Bool?
  /// the files' tabs kept here (by workspace), until the prefs say
  tabs_set : Map[String, String]
}

///|
let wide : Wide = {
  side_w: 240.0,
  folded: false,
  edge_held: false,
  menu: None,
  renaming: "",
  filter_open: false,
  attention_open: false,
  switcher: false,
  chosen: 0,
  keys_open: false,
  landed: "",
  tabs: {},
  front: {},
  info_open: false,
  jobs_open: false,
  job_picked: "",
  find_chat: "",
  find_field: @ui.Field::new(),
  find_query: "",
  found: None,
  find_at: -1,
  find_k: 0,
  bringing: false,
  find_around: -1.0,
  triple: "",
  triple_accounts: false,
  triple_field: @ui.Field::new(),
  triple_query: "",
  borrow_asking: "",
  history_io: false,
  history_shut: false,
  transcripts: {},
  context_menu: "",
  clear_asking: "",
  station_menu: false,
  rail_menu: None,
  rail_drag: None,
  place_pick: {},
  files_view: None,
  favs_set: {},
  files_open: {},
  files_places: {},
  files_cols: {},
  files_chosen: "",
  files_preview: None,
  tabs_set: {},
}

///|
/// Whether this frame is drawn wide (what the phone's parts read where they differ: the chat's rows' sides, the
/// composer's Enter).
let wide_on : Ref[Bool] = Ref(false)

///|
/// Whether a window this wide is drawn wide: a desktop's (a phone's or a tablet's by what its system says of the
/// window: is_touch_wide).
pub fn is_wide(c : @ui.Ctx) -> Bool {
  c.width >= wide_from && !@sf.touch_system()
}

///|
/// Whether a phone's or a tablet's window is drawn as the wide frame: one the system classes as regular both ways
/// (@ui.system_size_class: an iPhone Duo's inner screen, an iPad's whole screen), unless the device is half open on its
/// back half (tabletop.mbt: a chat's page across the window then, its composer under the fold). Its pages are the
/// frame's, in the phone's theme, a finger dragging the lists; regular in width alone (a phone on its side) is
/// corners.mbt's.
pub fn is_touch_wide() -> Bool {
  @sf.touch_system() &&
  @ui.system_size_class() is Some({ width: Regular, height: Regular }) &&
  @ui.system_tabletop() is None
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
fn wide_reset() -> Unit {
  wide.side_w = 240.0
  wide.folded = false
  wide.edge_held = false
  wide.menu = None
  wide.renaming = ""
  wide.filter_open = false
  wide.attention_open = false
  wide.switcher = false
  sw_reset()
  wide.chosen = 0
  wide.keys_open = false
  wide.landed = ""
  wide.tabs.clear()
  wide.front.clear()
  wide.info_open = false
  wide.jobs_open = false
  wide.job_picked = ""
  find_forget()
  wide.triple = ""
  wide.triple_accounts = false
  wide.triple_field.set("")
  wide.triple_query = ""
  wide.borrow_asking = ""
  wide.history_io = false
  wide.history_shut = false
  wide.transcripts.clear()
  wide.context_menu = ""
  wide.clear_asking = ""
  wide.station_menu = false
  wide.rail_menu = None
  wide.rail_drag = None
  rail_ws_reset()
  wide.place_pick.clear()
  wide.files_view = None
  wide.favs_set.clear()
  wide.files_open.clear()
  wide.files_places.clear()
  wide.files_cols.clear()
  wide.files_chosen = ""
  wide.files_preview = None
  fpane_reset()
  fdrag_reset()
  ftab_reset()
  wide.tabs_set.clear()
  fgo_reset()
  wide_switch_reset()
  wide_on.val = false
  corners_on.val = false
  recent_open.val = false
  recent_over.val = None
}

///|
/// How long the sidebar takes to open, fold, or be shown a while (brand.tsx moveSidebar: motion.ts moveState's 380 ms,
/// its ease out).
let side_move_ms : Double = 380.0

///|
/// What moves as the sidebar opens, folds, is shown a while or goes to another place's width: brand.tsx moveSidebar's
/// list, its selectors the boxes' `moves` names, what of each moves by its CSS names as the web lists them. The column
/// the page starts after (the shell's grid-template-columns: the page is laid out in what it leaves, so a value), the
/// page moved aside (main's left: a margin here, as wide as it was), the edge, the rail as narrow as the closed bar and
/// its top row, the block's margins, corner, ground, shadow and line, the sidebar in it (and whether it is drawn at all),
/// its frosted bands' ground and top row, the lists' marks on the rail, the page bars' room.
// kept across runs: a table, never written
let side_moves : Array[(String, Array[String])] = [
  ("shell", ["--side-col"]),
  ("main", ["margin-left"]),
  ("edge", ["left"]),
  ("rail", ["width", "padding-left", "padding-top", "padding-bottom"]),
  ("rail-top", ["height", "margin-bottom"]),
  (
    "dock",
    [
      "margin-top", "margin-right", "margin-bottom", "margin-left", "border-radius", "background-color", "box-shadow",
      "--dock-line",
    ],
  ),
  ("sidebar", ["margin-inline-start", "width", "--side-shown"]),
  ("nav-band", ["--band"]),
  ("brand", ["--brand"]),
  ("list-mark", ["--mark"]),
  ("page-bar", ["padding-left", "margin-left", "margin-right"]),
  ("page-bar-end", ["width"]),
]

///|
/// The closed bar (shell.css.ts dock, closed): 6 from the window's edges (under the window's buttons' row where they
/// are in the app's top row), 8 from the page.
let closed_bar_in : Double = 6.0

///|
let closed_bar_top : Double = 44.0

///|
/// The rail's column's room between the closed bar and the page (the dock's margin-right closed: 8).
let closed_bar_gap : Double = 8.0

///|
/// The rail's places' ground's corner (Rail.css.ts item: 9), what the closed bar's is concentric with.
let rail_ground_r : Double = 9.0

///|
/// The closed bar's line (shell.css.ts dock::after: inset 1px) and shadows (blur, fall, how much of the shadow's
/// colour): there but clear open (0 8px 24px transparent, so it moves in), faint by the page closed (0 2px 10px, the
/// shadow's colour at 30%), a floating panel's shown a while (0 8px 24px).
let closed_line : Double = 1.0

///|
let open_shadow : (Double, Double, Double) = (24.0, 8.0, 0.0)

///|
let closed_shadow : (Double, Double, Double) = (10.0, 2.0, 0.3)

///|
let closed_peek_shadow : (Double, Double, Double) = (24.0, 8.0, 1.0)

///|
/// Open, the sidebar reaching 8 into the rail's 56, empty there right of its places (Sidebar.css.ts: outsetStart(8)).
let side_into_rail : Double = 8.0

///|
/// How far the page clears the folded sidebar shown a while, and stays from the window's edge (Rail.tsx PEEK_GAP).
let peek_gap : Double = 16.0

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
/// width.
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
) -> Unit {
  let t = @sf.theme()
  // shell.css.ts dock, closed: margin 6px 8px 6px 6px (its top 44 under the window's buttons), its corner calc(9px *
  // scale + 6px); shown a while, margin-right calc(8px - the sidebar's width)
  let (ml, mt, mr, mb, corner) = if bar {
    let above = if @ui.window_inset() { closed_bar_top } else { closed_bar_in }
    let right = if peek { closed_bar_gap - s } else { closed_bar_gap }
    (closed_bar_in, above, right, closed_bar_in, @sf.surface_corner(closed_bar_in, rail_ground_r))
  } else {
    (0.0, 0.0, 0.0, 0.0, 0.0)
  }
  let (blur, shadow_y, shadow_k) = if peek {
    closed_peek_shadow
  } else if bar {
    closed_shadow
  } else {
    open_shadow
  }
  // its line (::after's opacity: --dock-line), and what is in the sidebar drawn while any of it shows: open, shown a
  // while, or still on its way to the bar (the sidebar's box always, so what it was is where a move sets out from)
  let line = c.moved("--dock-line", if bar { 1.0 } else { 0.0 })
  let showing = c.moved("--side-shown", if !bar || peek { 1.0 } else { 0.0 })
  let shown = !bar || peek || showing > 0.0
  // the sidebar beside the rail: open its own width and 8 more, reaching 8 into the rail's; the group's in the bar
  let (side_w, side_ml) = if bar { (s, 0.0) } else { (s + side_into_rail, -side_into_rail) }
  c.layer(fn() {
    c.box(dir=Row, w=Px(col), h=Fill(1.0), pt=top, pb=foot, fn() {
      c.box(
        moves="dock",
        dir=Row,
        w=Fill(1.0),
        h=Fill(1.0),
        ml~,
        mt~,
        mr~,
        mb~,
        radius=corner,
        bg=if bar { closed_ground() } else { t.p.sidebar },
        border=closed_line,
        border_color=@sf.alpha(t.p.line, line),
        shadow=blur,
        shadow_y~,
        shadow_color=@sf.alpha(t.p.shadow, shadow_k),
        clip=true,
        fn() {
          rail(c, src, w, all, bar)
          c.box(moves="sidebar", w=Px(side_w), h=Fill(1.0), ml=side_ml, fn() {
            if shown && s > 0.0 {
              // (in the bar: what the web's sidebar does there, at once, as the bar starts out)
              rail_ws.in_bar = wide.folded
              sidebar(c, src, w, side_w)
              rail_ws.in_bar = false
            }
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

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
/// The wide frame (WorkspaceShell): the rail and the sidebar on the sidebar's ground, the page in the rest; over them
/// the menus and panels that are open.
fn wide_frame(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  let t = @sf.theme()
  // a desktop's page: the wheel and the trackpad scroll, a drag is the pointer's own; a phone's or a tablet's: a
  // finger drags the lists
  let touch = @sf.touch_system()
  c.mouse_drags_lists(touch)
  wide_keys(c, src, w)
  // a device waiting to be confirmed in the workspace's safe mode: beside the rail (the workspaces, settings) only
  // what it waits on, no chats' list (its stations refuse it), unless a settings page is open
  let gated = lit_place() != "settings" && @settings.lock_waiting(settings_core(src, w), w.id)
  // (连接 and 用量: a page across the pane, no sidebar: wide_places.mbt)
  let bare = place_bare(lit_place())
  // the sidebar of this place and workspace, as it was left (wide_rail.mbt)
  side_follow(src, w.id)
  // (on a fold standing upright, the sidebar ends on it while it is not folded away)
  let on_fold = if wide.folded { None } else { side_on_fold() }
  let own = !gated && !bare
  // folded to the rail's bar (and a page with no sidebar of its own: Rail.tsx showSidebar), shown a while beside it as
  // the pointer comes on it: each part built as the web's CSS has it in that state, and moved there from what it showed
  // as the state changes, all together (brand.tsx moveSidebar: 380 ms, ease out); not the width the edge drags, which
  // follows the pointer at once
  let bar = (own && wide.folded) || bare
  let s = if gated { 0.0 } else { on_fold.unwrap_or(wide.side_w) }
  let top = status_top()
  let foot = nav_foot()
  let inset = @ui.window_inset()
  let peek_r = rail_w - closed_bar_gap + (if rail_ws.peeking { s } else { 0.0 })
  side_peek(c, closed_bar_in, top + (if inset { closed_bar_top } else { closed_bar_in }), peek_r, c.height - foot - closed_bar_in)
  let peek = own && wide.folded && rail_ws.peeking
  // what the page shows across as the last frame laid it out (its bars left out): what it moves aside for, shown a
  // while
  let page_id = c.id("main-page")
  let shown = c.shown_across(page_id, but="page-bar")
  let state = (bar, peek, s)
  match rail_ws.moved_as {
    Some(was) if was != state && !wide.edge_held => {
      // shown a while from now: how far the page moves aside, worked out once as it starts (Rail.tsx markPeek)
      if peek && !was.1 {
        rail_ws.peek_shift = peek_shift(c, shown, rail_ws.page_from, s)
      }
      c.move_state(side_moves, duration=side_move_ms)
    }
    _ => ()
  }
  rail_ws.moved_as = Some(state)
  // the column the page starts after (shell.css.ts shell: the rail's 56 and the sidebar open, the rail's folded) where
  // its move has got to: the page laid out as wide as it leaves
  let col = c.moved("--side-col", rail_w + (if bar { 0.0 } else { s }))
  rail_ws.page_from = col
  let main_w = dmax(0.0, c.width - col)
  // shown a while, the page moved aside as wide as it was (shell.css.ts main's left: --peek-shift), its bars from the
  // sidebar's edge to the window's (brand.css.ts); closed, their padding clear of the bar (and of the window's buttons)
  let shift = if peek { rail_ws.peek_shift } else { 0.0 }
  rail_ws.bar_pl = if bar && inset { bar_closed_inset } else { bar_in }
  rail_ws.bar_ml = if peek { dmax(0.0, s - closed_bar_gap - shift) } else { 0.0 }
  rail_ws.bar_mr = shift
  // what the sidebar's parts work out from, where the move has got to: its top row (Sidebar.css.ts brand: none in the
  // closed bar), its frosted bands' ground (the block's), the lists' marks on the rail (Rail.css.ts listMark: in as it
  // folds)
  rail_ws.brand_h = c.moved("--brand", if bar { 0.0 } else if inset { side_top_inset } else { side_top_web })
  rail_ws.band = c.moved("--band", if bar { 1.0 } else { 0.0 })
  rail_ws.mark = c.moved("--mark", if bar { 1.0 } else { 0.0 })
  // the core's chat last open, else a new chat: there is always a page beside the list (workspace.tsx WorkspaceHome)
  land(src, w)
  // what the page or the sidebar takes back for (a sheet, a menu, a step of a page's) goes back before the stack does
  let took = c.took_back(fn() {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
      // the rail's and the sidebar's column (the block over it, below)
      c.box(w=Px(col), h=Fill(1.0), fn() {  }) |> ignore
      // a right click in it: what is picked copied (sfdesk/context_menu.mbt)
      @sfdesk.context_page(c, page_id)
      // (moved aside as wide as it was, the window cutting what goes past its edge)
      c.box(moves="main", dir=Row, w=Px(main_w), h=Fill(1.0), clip=true, ml=shift, pt=top, pb=foot, id=page_id, fn() {
        c.sized(main_w, c.height - top - foot, fn() {
          let page = fn() {
            if gated {
              c.box(w=Px(main_w), h=Px(c.height), bg=t.p.bg, fn() { lock_gate(c, src, w) |> ignore }) |> ignore
            } else {
              // a chat and a new chat switched between: the composer moving, the rest crossfading (wide_switch.mbt)
              wide_switch_frame(c)
              c.nav_flat(app.nav, fn(page) { main_page(c, src, w, all, invited, page) }, bg=t.p.bg)
              |> ignore
            }
          }
          // the page's words are picked with the pointer and copied, as the web's (the sidebar's are not); a finger
          // picks them as on a phone (pick.mbt)
          if touch {
            page()
          } else {
            c.selectable(color=@sf.alpha(t.p.blue, 0.28), page)
          }
        })
      })
      |> ignore
    })
    |> ignore
    dock(c, src, w, all, bar, peek, s, col, top, foot)
  })
  // (the sidebar's edge: on its right edge open, between the bar and the page folded, at the edge of the sidebar shown
  // a while; dragged, unless it is on the fold)
  if !bare && on_fold is None {
    let at = if !bar {
      rail_w + s - edge_half
    } else if peek {
      closed_edge + s
    } else {
      closed_edge
    }
    sidebar_edge(c, at)
  }
  // back (⌘[, a mouse's back button) a page of the stack, where there is one
  if app.nav.depth() > 1 && !took && !app.menu && !sheet_open() {
    c.take_back(fn() { app.nav.pop() |> ignore })
  }
}

///|
/// A page's bar's padding at its left and its right (styles/sidebar.css.ts pageBar: 12; brand.css.ts, railed, closed:
/// 28 in a window with its buttons in the app's top row, which reach 12 past the rail), and its margins while the folded
/// sidebar is shown a while (from its edge to the window's): the box named "page-bar", moved with the block
/// (side_moves).
fn page_bar_room() -> (Double, Double, Double, Double) {
  (rail_ws.bar_pl, bar_in, rail_ws.bar_ml, rail_ws.bar_mr)
}

///|
/// At the end of a page's bar that has no padding of its own there (a new chat's): as wide as its right margin while the
/// folded sidebar is shown a while (page_bar_room), its end by the window's; moved with the block.
fn page_bar_end(c : @ui.Ctx) -> Unit {
  c.box(moves="page-bar-end", w=Px(rail_ws.bar_mr), fn() {  }) |> ignore
}

///|
let bar_in : Double = 12.0

///|
let bar_closed_inset : Double = 28.0

///|
/// The sidebar's edge's strip: 12 wide, its middle on the edge (6 each side); folded, from 46 (its bar between the
/// closed bar at 48 and the page at 56: Rail.css.ts edge, closed).
let edge_half : Double = 6.0

///|
let closed_edge : Double = 46.0

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
/// The page in the wide frame's pane: the chat (wide_chat.mbt), else the phone's page of the same (its own bar at its
/// top), the stack's top as it is.
fn main_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
  page : Page,
) -> Unit {
  match page {
    Chat(r) => {
      wide_chat_page(c, src, w, r)
      new_chat_leaving_wide(c, src, w, r)
      // (come to from a new chat by the sidebar: the new chat fading over it)
      switch_new_out(c, src, w)
    }
    // the chats' list is the sidebar's: nothing open (yet), the page's ground
    Home => ()
    // settings' own home is its first page (the web goes to 外观)
    Settings => setting_page(c, src, w, @settings.Route::Appearance)
    // a place of the rail's other than the chats': its page, under its title
    Place("stations" | "profiles" as p) => place_page_wide(c, src, w, p)
    Place(p) => wide_place(c, src, w, p)
    // 文件: a folder under its bar, as the web's (wide_files.mbt)
    Files => files_landing(c, src, w)
    Drive(at) => wide_folder(c, src, w, at)
    // a station's screen, a drive's text read, a film played are over the whole window (app.mbt signed_in), not in
    // the pane
    Screen(_) | DriveRead(_) | DrivePlay(_) => ()
    // 已归档, none of its chats open beside the list: what it is (wide_lists.mbt)
    Archived => archive_main(c, src, w)
    _ => page_view(c, src, w, all, invited, page)
  }
}

// ── the rail (Rail.tsx) ─────────────────────────────────────────────────

///|
/// The rail's places when none were chosen (Rail.tsx RAIL_DEFAULT).
// kept across runs: a table, never written
let rail_default : Array[String] = [
  "attention", "chats", "files", "stations", "profiles", "connects", "usage",
]

///|
/// The rail's places in workspace `ws`, as kept (the prefs' `rails`), those this app has.
fn rail_items(src : Source, ws : String) -> Array[String] {
  let prefs = (src.topic)("prefs", {}).value
  let kept = match field(field(prefs, "rails"), ws) {
    Some(Array(a)) => a.map(fn(x) { text(Some(x), "") })
    _ =>
      match field(prefs, "rail") {
        Some(Array(a)) => a.map(fn(x) { text(Some(x), "") })
        _ => []
      }
  }
  let known = [
    "chats", "mine", "watching", "archive", "decisions", "attention", "files", "stations",
    "profiles", "connects", "usage",
  ]
  let items = kept.filter(fn(k) { known.contains(k) })
  if items.length() == 0 {
    rail_default
  } else {
    items
  }
}

///|
/// The place lit in the rail: what the stack's root is, settings while a settings page is open.
fn lit_place() -> String {
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
      // 已归档: one of the chats' lists (wide_lists.mbt)
      Home | Chat(_) | NewChat | Archived => return "chats"
      _ => ()
    }
    k = k - 1
  }
  "chats"
}

///|
/// The rail: its top (in a window with its buttons in the app's top row, their row, dragging the window), the places,
/// then the workspaces and settings at its foot.
fn rail(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace], bar : Bool) -> Unit {
  let t = @sf.theme()
  let lit = lit_place()
  // Rail.css.ts rail, top: 56 wide, its places in its middle (9 from its edge; the sidebar reaches over its last 8),
  // 9 under the last; its top row (41 under the window's buttons, else 5) 6 over its first place. In the closed bar
  // (`bar`) as narrow as it (42), its places 2 from its every edge (their grounds 6), no top row: the bar starts under
  // it, its margin taken back
  let rail_id = c.id("rail")
  match c.right_clicked(rail_id) {
    Some((x, y)) if wide.rail_menu is None => wide.rail_menu = Some(("", x, y))
    _ => ()
  }
  let inset = @ui.window_inset()
  let (rw, pl, pt, pb) = if bar {
    (rail_closed_w, rail_closed_in, rail_closed_in, rail_closed_in)
  } else {
    (rail_w, rail_in, 0.0, rail_in)
  }
  let (top_h, top_mb) = if bar {
    (0.0, -rail_gap)
  } else if inset {
    (rail_top_inset, 0.0)
  } else {
    (rail_top_web, 0.0)
  }
  c.box(moves="rail", w=Px(rw), h=Fill(1.0), pl~, pt~, pb~, gap=rail_gap, align=AStart, id=rail_id, fn() {
    // its top row drags the window (the macOS app's buttons in it), not in the closed bar
    let top = c.id("rail/top")
    if inset && !bar {
      c.window_drag(top)
    }
    c.box(moves="rail-top", w=Fill(1.0), h=Px(top_h), mb=top_mb, id=top, fn() {  }) |> ignore
    let places = rail_items(src, w.id)
    // a list's place lit while its list is the one shown (Rail.tsx `on`): 我参与的, 监控中 by the filter when they are
    // in the rail, else 对话; 已归档 while the archive is open
    // the list shown (Rail.tsx shownList): its place where it is in the rail, else 对话's
    let list = match list_mode(src, w) {
      1 => "mine"
      2 => "watching"
      3 => "decisions"
      4 => "archive"
      _ => "chats"
    }
    let listy = lit == "chats" || lit == "decisions"
    // a place left out of the rail but in view: at the foot of its places, lit, while it is
    let in_view = rail_in_view(src, w)
    let shown = places.copy()
    if in_view != "" && !places.contains(in_view) && !rail_ws.editing {
      shown.push(in_view)
    }
    let shown_list = if shown.contains(list) { list } else { "chats" }
    for place in shown {
      let on = match place {
        "chats" | "mine" | "watching" | "decisions" | "archive" => listy && shown_list == place
        _ => lit == place
      }
      rail_place(c, src, w, place, on, places)
    }
    c.spacer()
    rail_workspaces(c, src, w, all)
    // settings
    let gear = c.id("rail/settings")
    c.cursor(gear, Hand)
    if c.clicked(gear) {
      // lit (in the settings): back out of them, to the chat last open (Rail.tsx: the settings' NavLink, in them)
      if lit == "settings" {
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        wide.landed = ""
      } else {
        open_settings()
      }
    }
    rail_ground(c, gear, lit == "settings", fn(color) {
      @sf.icon(c, "settings", size=20.0, color~) |> ignore
    })
  })
  |> ignore
}

///|
/// The rail's places 9 from its edges open (in its 56's middle), 2 in the closed bar; 6 apart; its top row 41 under the
/// window's buttons, else 5.
let rail_in : Double = 9.0

///|
let rail_closed_in : Double = 2.0

///|
let rail_gap : Double = 6.0

///|
let rail_top_inset : Double = 41.0

///|
let rail_top_web : Double = 5.0

///|
/// A place's 38 to press, its ground (hovered, lit) 30 square under the icon (Rail.css.ts item).
fn rail_ground(c : @ui.Ctx, id : Int, on : Bool, body : (Int64) -> Unit, label? : String = "") -> Unit {
  let t = @sf.theme()
  let hover = c.hovered(id)
  // its ground and its icon's colour moved over 140 ms (Rail.css.ts item: transition background, color)
  let key = "rail/ground/" + id.to_string()
  let ink = @kit.animate(c, key + "/ink", if on || hover { 1.0 } else { 0.0 }, transition=nav_fade)
  let b = c.box(w=Px(38.0), h=Px(38.0), align=ACenter, justify=JCenter, id~, fn() {
    rail_square(c, nav_ground(c, key, hover, on), fn() { body(@sf.mix(t.p.text, ink, t.p.muted)) })
    |> ignore
  })
  // named for a screen reader (Rail.tsx's aria-label), and on hover beside it (its Tip, side right)
  if label != "" {
    c.semantics(b, Button, id~, label~)
    @sf.tip(c, "rail/tip/" + id.to_string(), id, label, side=Right)
  }
}

///|
/// A square of the rail (Rail.css.ts item's ground, workspaceItem, workspaceAdd): 30, its corner 9, on `ground`; `id`
/// to press it; its node.
fn rail_square(c : @ui.Ctx, ground : Int64, body : () -> Unit, id? : Int) -> Int {
  c.box(w=Px(30.0), h=Px(30.0), radius=9.0, bg=ground, align=ACenter, justify=JCenter, id?, body)
}

///|
/// A dot at a square's top right corner, `out` past it (4: Rail.css.ts mark, a workspace's; 1: listMark, a list's,
/// 3 in from its place's 38), cut out of the rail's ground: what waits in another workspace or a list (its tone), an
/// invitation.
fn rail_corner_mark(c : @ui.Ctx, tone : String, out? : Double = 4.0, shown? : Double = 1.0) -> Unit {
  let t = @sf.theme()
  c.layer(align=AEnd, fn() {
    let i = c.box(tx=out, ty=-out, radius=6.0, bg=if rail_ws.in_bar || wide.folded { closed_ground() } else { t.p.sidebar }, pad=2.0, fn() {
      chat_mark(c, tone)
    })
    // a list's, `shown` of the way in as the sidebar folds (listMark: from clear at 40%, moved with it)
    if shown < 1.0 {
      c.look(i, @ui.look(alpha=shown, scale=fold_at(mark_folded_from, 1.0, shown)))
    }
  })
  |> ignore
}

///|
let mark_folded_from : Double = 0.4

///|
/// The closed bar's ground (a floating panel's: the canvas, raised in the dark).
fn closed_ground() -> Int64 {
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
/// the pointer; the one in view a short bar at its left; another with what waits in it (the core's marks' tone) a dot
/// at its corner. Over them the ＋ (making one, another account, invitations: wide_rail.mbt), seen as the pointer comes
/// over them or while an invitation waits. Pressed, that workspace.
fn rail_workspaces(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  let t = @sf.theme()
  let marks = field((src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value, "workspaces")
  let area = c.id("rail/workspaces")
  let add = c.id("rail/ws-add")
  let open = rail_ws.add_open
  let over = open ||
    c.hovered(area) ||
    c.hovered(add) ||
    all.iter().any(fn(x) { c.hovered(c.id("rail/ws/" + x.id)) })
  let waiting = invitations_waiting(src).length() > 0
  // ⌃1 … ⌃9 on a Mac (Alt elsewhere): the workspace at that place, as the web's keys (keymap.ts workspaceIndexOf)
  let held = if @ui.platform() == 0 { @ui.mod_ctrl } else { @ui.mod_alt }
  for k in 0..<dmin(9.0, all.length().to_double()).to_int() {
    if c.key_pressed(@ui.key_of_char((49 + k).unsafe_to_char()), mods=held, in_field=true) && all[k].id != w.id {
      app.picked = all[k].id
      (src.call)("prefs.set", Json::object({ "workspace": Json::string(all[k].id) }), fn(_) {  })
      home()
    }
  }
  c.box(style=rail_ws_list, id=area, fn() {
    // the ＋
    c.cursor(add, Hand)
    if c.clicked(add) {
      rail_ws.add_open = !open
    }
    let hot = c.hovered(add) || open
    let plus = rail_square(
      c,
      if hot { t.p.hover } else { 0L },
      fn() {
        if over || waiting {
          @sf.icon(c, "plus", size=16.0, color=if hot { t.p.text } else { t.p.muted }) |> ignore
        }
        if waiting {
          rail_corner_mark(c, "accent")
        }
      },
      id=add,
    )
    c.semantics(plus, Button, id=add, label=tr("web-main.rail.addWorkspace"))
    @sf.tip(c, "rail/ws-add-tip", add, tr("web-main.rail.addWorkspace"), side=Right)
    for x in all {
      let id = c.id("rail/ws/" + x.id)
      c.cursor(id, Hand)
      if c.clicked(id) && x.id != w.id {
        app.picked = x.id
        (src.call)("prefs.set", Json::object({ "workspace": Json::string(x.id) }), fn(_) {  })
        home()
      }
      let on = x.id == w.id
      let hot = c.hovered(id)
      let marked = @sf.has_station_mark(x.emoji, x.icon)
      let square = rail_square(c, if !marked || hot { t.p.hover } else { 0L }, fn() {
        if marked {
          @sf.station_mark(c, x.emoji, x.icon, 18.0, t.p.text)
        } else {
          c.text(
            @sf.initial(x.name),
            size=13.0,
            weight=600,
            color=if on || hot { t.p.text } else { t.p.muted },
            wrap=false,
          )
          |> ignore
        }
        // the one in view: a short bar in the margin at its left
        if on {
          c.layer(fn() {
            c.box(style=rail_bar_at, fn() {
              c.box(w=Px(3.0), h=Px(14.0), tx=-6.0, radius=2.0, bg=t.p.text, fn() {  }) |> ignore
            })
            |> ignore
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
/// The workspaces' column: 4 in from the rail's 38 (its squares where the places' grounds are), 4 above and under, 6
/// between.
// kept across runs: a value (no field of it changes)
let rail_ws_list : @ui.Style = @ui.style(pl=S1, pt=S1, pb=S1, gap=S1_5)

///|
/// The bar at the left of the workspace in view: 8 down its square.
// kept across runs: a value (no field of it changes)
let rail_bar_at : @ui.Style = @ui.style(pt=S2)

///|
/// What waits on a place: its dot 4 in from its 38's top right (Rail.css.ts count: 6 from the 38's corner, 2 of it the
/// ring cut out of the rail's ground).
// kept across runs: a value (no field of it changes)
let rail_dot_at : @ui.Style = @ui.style(pt=S1, pr=S1)

///|
/// One place of the rail: its icon (奏 its word), what waits on it a dot at its corner; pressed, its page.
fn rail_place(c : @ui.Ctx, src : Source, w : Workspace, place : String, on : Bool, places : Array[String]) -> Unit {
  let t = @sf.theme()
  let id = c.id("rail/" + place)
  c.cursor(id, Hand)
  match c.right_clicked(id) {
    Some((x, y)) => wide.rail_menu = Some((place, x, y))
    None => ()
  }
  // dragged up or down (past a few points): to another place in the rail, the others as they were until let go
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
    None if c.pressed(id) => {
      wide.rail_drag = Some((place, py, 0.0))
      false
    }
    _ => false
  }
  let moved = match wide.rail_drag {
    Some((p, _, dy)) if p == place && dy.abs() > rail_slop => dy
    _ => 0.0
  }
  if c.clicked(id) && !dragged && !rail_ws.editing {
    // the lit place pressed again (not 待处理, a panel): its sidebar folded or opened, not gone to; folded so with the
    // pointer on the rail, it is shown a while (Rail.tsx's rail onClickCapture)
    if on && place != "attention" && !place_bare(lit_place()) {
      wide.folded = !wide.folded
      rail_ws.peeking = wide.folded
    } else {
      rail_go(c, src, w, place)
    }
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let dot = match place {
    "attention" => bell_lit(src, w)
    "decisions" => count(field(field(marks.value, "workspaces"), w.id), "decisions") > 0
    _ => false
  }
  rail_edit_frame(c, src, w, place, moved, fn() {
    rail_ground(c, id, on || (place == "attention" && wide.attention_open), fn(color) {
      if place == "decisions" {
        c.text("奏", size=16.0, weight=600, color~, wrap=false, line=20.0) |> ignore
      } else if place == "stations" {
        // the stations at a glance (Sidebar.tsx RailStations: StationGlyph, 20)
        @sf.station_glyph(c, stations_at_glance(src, w.id).0, 20.0, color, t.p.red) |> ignore
      } else {
        @sf.icon(c, rail_icon(place), size=20.0, color~) |> ignore
      }
    }, label=if place == "stations" { "Station：" + rail_stations_label(src, w.id) } else { rail_label(place) })
    // what wants the person in a list, as its rows' marks: on its icon's corner while the sidebar is folded (open,
    // the rows show it; Rail.css.ts listMark)
    let tone = match place {
      "chats" => text(field(field(marks.value, "workspaces"), w.id), "tone")
      "mine" => text(field(field(marks.value, "workspaces"), w.id), "mineTone")
      "watching" => text(field(field(marks.value, "workspaces"), w.id), "watchingTone")
      _ => ""
    }
    if tone != "" && rail_ws.mark > 0.0 {
      rail_corner_mark(c, tone, out=1.0, shown=rail_ws.mark)
    }
    if dot {
      c.layer(align=AEnd, fn() {
        c.box(style=rail_dot_at, fn() {
          c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.sidebar, pad=2.0, fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), radius=4.0, bg=t.p.red, fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
}

///|
///|
/// A place gone to, from the rail or its menu (Rail.tsx `drawn`'s presses and `go`): 待处理 its panel; a list of chats
/// its list in the sidebar, the chat last open beside it; 已归档 the archive; the others their page.
fn rail_go(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  match place {
    "attention" => {
      wide.attention_open = !wide.attention_open
      wide.menu = None
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
        go_place(c, "chats", [], -1)
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
    p => go_place(c, p, [], -1)
  }
}

///|
/// A place's name (Rail.tsx railLabel).
fn rail_label(place : String) -> String {
  match place {
    "chats" => tr("web-main.rail.chats")
    "mine" => tr("web-main.filter.chats.mine")
    "watching" => tr("web-main.filter.watching")
    "archive" => tr("web-main.filter.archived")
    "decisions" => tr("web-main.rail.decisions")
    "attention" => tr("web-main.attention.entry")
    "files" => tr("web-pages.drive.title")
    "stations" => "Station"
    "profiles" => "Profile"
    "connects" => tr("web-pages.settings.nav.connects")
    "usage" => tr("web-pages.settings.nav.usage")
    _ => place
  }
}

///|
/// The places the rail can hold (Rail.tsx RAIL_ITEMS), in its order.
// kept across runs: a table, never written
let rail_known : Array[String] = [
  "chats", "mine", "watching", "archive", "decisions", "attention", "files", "stations",
  "profiles", "connects", "usage",
]

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
    match list_mode(src, w) {
      1 => "mine"
      2 => "watching"
      3 => "decisions"
      4 => "archive"
      _ => "chats"
    }
  } else if rail_known.contains(lit) {
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
/// The rail's menu (Rail.tsx's DropdownMenu, from a right click on it), beside the place right clicked (else its
/// first), 8 past it, clear of the window's buttons' row: the places not in it (pressed, their page; their ＋, shown on
/// the row pointed at, puts one in it and the rail is changed from there), 从侧边条移除 the place right clicked,
/// 自定义侧边条, 侧边条恢复默认 when it was changed.
fn rail_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (place, _, _) = match wide.rail_menu {
    Some(m) => m
    None => {
      @sf.menu(c, "rail-menu", false, 0, [], {}, @sf.menu_w) |> ignore
      return
    }
  }
  let items = rail_items(src, w.id)
  // (提醒 is no page, nor the one in view at the rail's foot: put in from 自定义侧边条)
  let extra = rail_in_view(src, w)
  let away = rail_known.filter(fn(i) { !items.contains(i) && i != "attention" && i != extra })
  let entries : Array[@kit.Entry] = []
  let icons : Map[String, String] = {}
  if away.length() > 0 {
    entries.push(@kit.menu_label(tr("web-main.rail.away")))
    for i in away {
      entries.push(@kit.menu_item("go:" + i, label=rail_label(i)))
      icons["go:" + i] = if i == "decisions" { "zou" } else { rail_icon(i) }
    }
    entries.push(@kit.menu_separator())
  }
  if place != "" && items.contains(place) && items.length() > 1 {
    entries.push(@kit.menu_item("remove", label=fill("web-main.rail.remove", [("name", rail_label(place))])))
    icons["remove"] = "minus"
  }
  entries.push(@kit.menu_item("customize", label=tr("web-main.rail.customize")))
  icons["customize"] = "sliders"
  if items != rail_default {
    entries.push(@kit.menu_item("reset", label=tr("web-main.rail.reset")))
    icons["reset"] = "refresh"
  }
  let by = c.rect_of(c.id("rail/" + (if place != "" { place } else { items.get(0).unwrap_or("") })))
  let (ax, ay, aw, ah) = by.unwrap_or((0.0, rail_menu_clear, rail_w - 8.0, 0.0))
  // a place's ＋: put in, the rail changed from there (once the menu has gone)
  let added : Ref[String] = Ref("")
  let m = @sf.menu(
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
        if rail_menu_add(c, i, s.hot) {
          added.val = i
        }
      }
    },
  )
  if !m.open || added.val != "" {
    wide.rail_menu = None
  }
  if added.val != "" {
    let next = items.copy()
    next.push(added.val)
    rail_keep(src, w.id, next)
    rail_ws.editing = true
    return
  }
  match m.chosen {
    Some("remove") => rail_keep(src, w.id, items.filter(fn(i) { i != place }))
    Some("reset") => rail_keep(src, w.id, rail_default)
    Some("customize") => rail_ws.editing = true
    Some(v) if v.has_prefix("go:") => rail_go(c, src, w, v.view(start_offset=3).to_string())
    _ => ()
  }
}

///|
/// A place's ＋ at the end of its row in the rail's menu (Rail.css.ts menuAdd): 24 round, shown on the row pointed at,
/// in the pointer's ground pointed at itself; true on the frame after it was pressed.
fn rail_menu_add(c : @ui.Ctx, place : String, hot : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("rail-menu/add/" + place)
  c.cursor(id, Hand)
  let over = c.hovered(id)
  // in on its row pointed at (Rail.css.ts menuAdd: transition opacity 140 ms)
  let shown = @kit.animate(c, "rail-menu/add-shown/" + place, if hot || over { 1.0 } else { 0.0 }, transition=nav_fade)
  let b = c.box(style=if over { rail_menu_plus_on } else { rail_menu_plus }, id~, fn() {
    if shown > 0.0 {
      @sf.icon(c, "plus", size=14.0, color=@sf.alpha(if over { t.p.text } else { t.p.muted }, shown)) |> ignore
    }
  })
  c.semantics(b, Button, id~, label=fill("web-main.rail.add", [("name", rail_label(place))]))
  c.clicked(id)
}

///|
/// A ＋ in the rail's menu: 24 round, at its row's end.
// kept across runs: a value (no field of it changes)
let rail_menu_plus : @ui.Style = @ui.style(w=S6, h=S6, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let rail_menu_plus_on : @ui.Style = @ui.style(w=S6, h=S6, radius=Full, align=ACenter, justify=JCenter, bg=Hover)

///|
/// The rail's menu 8 past its place, and no higher than the window's buttons' row (Rail.tsx: collisionPadding top 52).
let rail_menu_off : Double = 8.0

///|
let rail_menu_clear : Double = 52.0

///|
/// The rail's ＋'s menu (workspace.tsx accountMenu): 260 at least.
let rail_menu_w : Double = 260.0

///|
/// A rail's place to the next (its 38 and the 6 between), and how far a press goes before it is a drag.
let rail_pitch : Double = 44.0

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
fn open_settings() -> Unit {
  open_settings_at(@settings.Route::Appearance)
}

///|
/// Settings at one of its pages (快捷键 from the shortcuts' dialog), the sidebar its list.
fn open_settings_at(route : @settings.Route) -> Unit {
  lower_sheet()
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Setting(route))
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
  let sized = !wide.folded || rail_ws.peeking
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
    tr("web-main.sidebar.open")
  } else {
    tr("web-pages.workspace.resizeSidebar") + " · " + tr("web-main.sidebar.close")
  }
  c.layer(fn() {
    let strip = c.box(style=edge_strip, pl=edge_look_in, moves="edge", left=at, top=0.0, bottom=0.0, id~, fn() {
      @sf.edge_look(
        c,
        "sidebar-edge",
        over=false,
        on=c.hovered(id) || c.focus_shown(id) || active,
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
let edge_strip : @ui.Style = @ui.style(w=S3)

///|
let edge_look_in : Double = 3.0

///|
/// A new chat (新建对话, ⌘N): its page beside the list.
fn new_chat_wide() -> Unit {
  match app.nav.top() {
    NewChat => ()
    _ => {
      lower_sheet()
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      if app.nav.top() != Home {
        app.nav.replace(Home)
      }
      app.nav.push(NewChat)
    }
  }
}

///|
/// A chat's row pressed: its chat the page beside the list (in place of what was open), the list's place kept.
fn open_row(item : ChatItem) -> Unit {
  let r : ChatRef = {
    station: item.station,
    session: item.session,
    title: item.title,
    station_name: item.station_name,
  }
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => return
    _ => ()
  }
  lower_sheet()
  wide.menu = None
  // the chats' place under it: settings or another place left for the chat
  if lit_place() != "chats" {
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    app.nav.replace(Home)
    app.nav.push(Chat(r))
    return
  }
  if app.nav.depth() > 1 {
    app.nav.replace(Chat(r))
  } else {
    app.nav.push(Chat(r))
  }
}

///|
/// A place of the rail's (Station, Profile, 连接, 用量) in the pane: its title as a page's head (pages.css.ts), what
/// the settings' page of it shows under it.
fn wide_place(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let t = @sf.theme()
  let side = dmax(24.0, (c.width - 792.0) / 2.0) + 16.0
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let head = c.id("place-head")
    if @ui.window_inset() {
      c.window_drag(head)
    }
    // (a place across the pane has its page's own head, its title and what it does: settings' place_page)
    if !place_bare(place) {
      c.box(w=Fill(1.0), pl=side, pr=side, pt=40.0, pb=12.0, id=head, fn() {
        c.text(place_label(place), size=22.0, weight=600, color=t.p.text, wrap=false, line=34.0) |> ignore
      })
      |> ignore
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      match @settings.route_of(place) {
        Some(r) => {
          let core = settings_core(src, w)
          @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
        }
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The system's side of still.fail (before @ui.run). The desktop's window: 1280 by 820 at first, as still.fail's
/// desktop app opens (apps/desktop main.ts), its size not kept (the desktop app keeps none either); at least 360 by
/// 560, a phone's page below the breakpoint; on macOS its title bar the app's (its buttons in its top row, as the
/// desktop app's hiddenInset: the rail's and the sidebar's tops, a phone's page under their band), on Windows the
/// system's. On a phone the app is
/// Android's whatever the phone: on iOS too its lists fling, give at their edges and show no scroll bar as Android's,
/// its fields take a tap, draw their caret and handles and pick words as Android's (@ui.feel_as).
pub fn host_setup() -> Unit {
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0, inset=true)
  if @ui.platform() == 1 {
    @ui.feel_as(2)
  }
}
