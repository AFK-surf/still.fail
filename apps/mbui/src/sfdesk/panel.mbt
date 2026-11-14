// Beside a chat on the desktop (still.fail web/src/pages/ChatPage.tsx's side panel, ChatSide.tsx useSidePanel, SidePane,
// FilesTab; ChatPage.css.ts sidePanel, sideBar, sideTab): the side panel at the pane's right, a tab each for what is
// opened in it (an agent's execution history, the chat's services and jobs, the stations' files, what its agents and
// other chats' wrote each other), the one in front shown; its edge drags its width (pressed, the panel closes), its
// switch closes it. It slides in and out as its first tab opens and its last closes. Which tabs are open and in front
// is the core's (the chat view's `tabs`), as are the changes (`chat.tabs.*`). Each chat keeps its own tabs.

///|
/// A chat's tabs' key as the core keeps them (the prefs' `chatTabs`: `<station>:<session>`, as its page names it).
fn tabs_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// Whether this panel shows `tab` beside a chat of `v`: one of its agents' histories (by its session's key), 任务, 文件,
/// agent 往来, a web service of its agents' (`service:<job>`), a visualization (`file:[…]`: service_tab.mbt), a file in
/// the viewer (`view:[…]`: sfbase's viewer_tab.mbt).
fn side_shows(v : ChatView, tab : String) -> Bool {
  tab == "jobs" ||
  @sfbase.view_tab_file(tab) is Some(_) ||
  tab == "files" ||
  tab == "letters" ||
  tab == "things" ||
  tab_service(tab) is Some(_) ||
  tab_file(tab) is Some(_) ||
  station_tab(tab) is Some(_) ||
  v.agents.iter().any(fn(a) { a.key == tab })
}

///|
/// The chat's side panel's tabs, in their order, and the one in front: the core's (the chat view's `tabs`: those kept
/// for it on this device that it has, ChatPage.tsx), of those this panel shows.
pub fn side_of(v : ChatView) -> (Array[String], String) {
  let tabs = v.tabs.open.filter(fn(t) { side_shows(v, t) })
  let front = match v.tabs.shown {
    Some(f) if tabs.contains(f) => f
    _ => tabs.get(0).unwrap_or("")
  }
  (tabs, front)
}

///|
/// Chat `r`'s tabs as its view has them now.
pub fn side_now(src : Source, r : ChatRef) -> (Array[String], String) {
  match view_of_chat(src, r).0 {
    Some(v) => side_of(v)
    None => ([], "")
  }
}

///|
/// Chat `r`'s tabs changed by the core, which keeps them on this device: `tab` opened in front (an
/// agent's history after the histories open, any other last), closed (the last left in front, if it was), brought to
/// the front; all of them closed (`clear`). The panel is told first whether any will be open, to slide as they come.
pub fn side_change(src : Source, r : ChatRef, action : String, tab : String?) -> Unit {
  side_change_from(src, r, action, tab, side_now(src, r))
}

///|
/// side_change, chat `r`'s tabs as they are now (side_now's) given, read by the caller where it holds them: what
/// changes them as a page comes on top (beside_follow) reads them in its reaction's read, held as long as that reads
/// them, not by the wide frame's node for as long as it lives (Source::owned_by's raw read: the chat held after it left).
fn side_change_from(src : Source, r : ChatRef, action : String, tab : String?, now : (Array[String], String)) -> Unit {
  let (tabs, front) = now
  let any = match action {
    "open" | "front" => true
    "close" => tabs.iter().any(fn(t) { Some(t) != tab })
    _ => false
  }
  side_changing(chat_key(r), tabs, front, any)
  // a web service's or a visualization's tab closed lets its page go
  match (action, tab) {
    ("close", Some(t)) => tab_let_go(r, t)
    ("clear", _) => for t in tabs { tab_let_go(r, t) }
    ("open", Some(t)) => tab_kept(r, t)
    _ => ()
  }
  side_ask(src, r, action, tab)
}

///|
/// The change asked of the core alone (changeTabs, `chat.tabs.*`), the panel told nothing: as a chat made from the new
/// chat's page starts with what it had beside it.
pub fn side_ask(src : Source, r : ChatRef, action : String, tab : String?) -> Unit {
  let params : Map[String, Json] = { "chat": Json::string(tabs_key(r)) }
  match tab {
    Some(t) => params["tab"] = Json::string(t)
    None => ()
  }
  (src.call)("chat.tabs." + action, Json::object(params), @sfbase.answer_unread)
}

///|
/// File tab `tab` opened beside chat `r` (the shell's `beside`: sfapp's beside_where), in front; a tab of that file open
/// there already (the same file, what it said of itself then aside: view_tab_file's same_file), that one brought to the
/// front, never a second: the tab put in front.
pub fn view_beside(src : Source, r : ChatRef, tab : String) -> String {
  let open = match @sfbase.view_tab_file(tab) {
    Some(f) =>
      side_now(src, r).0
      .iter()
      .find_first(fn(t) {
        match @sfbase.view_tab_file(t) {
          Some(g) => f.same_file(g)
          None => false
        }
      })
    None => None
  }
  let put = open.unwrap_or(tab)
  side_change(src, r, "open", Some(put))
  put
}

///|
/// An agent's history pressed (its mark in the bar), or the chat's files (its info's 文件): in front, closed; else
/// opened in front; an agent's history opened whole, once what it first shows is answered (history_side_open).
pub fn side_toggle(src : Source, r : ChatRef, tab : String) -> Unit {
  let (tabs, front) = side_now(src, r)
  if tabs.contains(tab) && front == tab {
    side_change(src, r, "close", Some(tab))
  } else if side_history_tab(tab) {
    history_side_open(src, r, tab, fn() { side_change(src, r, "open", Some(tab)) })
  } else {
    side_change(src, r, "open", Some(tab))
  }
}

///|
/// How narrow and how wide the panel is dragged (PANEL_MAX).
let panel_min : Double = 320.0

///|
let panel_max : Double = 960.0

///|
/// How wide the panel is (else 38% of the page and at least 360), the
/// chat keeping 360 at least.
pub fn side_width(pane : Double) -> Double {
  let wanted = match panel_own.width.get() {
    Some(w) => w
    None => dmax(360.0, (pane * 0.38).floor())
  }
  dmax(0.0, dmin(wanted, pane - 360.0))
}

///|
/// The chat and the panel side by side.
// kept across runs: a value (no field of it changes)
let panel_row : @ui.Style = @ui.css("row w=Full h=Full")

///|
/// The least the chat and the panel are side by side (ChatSide.tsx panelWidth: the chat 360, the panel 360 at least, the
/// rule between): on a page narrower, the panel over the page.
let side_both_least : Double = 721.0

///|
/// How wide the panel is over the page (ChatPage.css.ts sidePanel on a narrow page: min(460px, 100vw)).
let side_over_w : Double = 460.0

///|
/// Whether the panel being built is a panel of its own on the tape (tape_side): round by the tape's corner.
// kept across runs: said by tape_side round the panel it builds
let side_on_tape : Ref[Bool] = Ref(false)

///|
/// The page under the panel over it: as wide as it is.
// kept across runs: a value (no field of it changes)
let panel_page_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The panel over the page (sidePanel, narrow): the page's ground, its shadow at its side (-12 0 32).
// kept across runs: a value (no field of it changes)
let side_over_box : @ui.Style = @ui.css("bg=Bg shadow=Xl")

///|
/// The panel (sidePanel): its ground the canvas, beside the page with no line between: its edge's own line shows as
/// the pointer comes onto it (@sf.resize_handle; 2026-10-26 用户 of a hairline always there: 「搞坏了宽度调整的样式」).
// kept across runs: a value (no field of it changes)
pub let side_panel_style : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Its bar (sideBar): 45 high, the tabs from 8 in, the panel's switch at its right 12 in (at the window's top right
/// corner, following it where the bar's buttons do: @sf.window_end_in).
pub fn side_bar() -> @ui.Style {
  side_bar_look.then(@ui.style(pr=@sf.room_of(@sf.window_end_in(side_bar_end))))
}

///|
// kept across runs: a value (no field of it changes)
let side_bar_look : @ui.Style = @ui.css("row w=Full h=S11 pl=S2 gap=S2 align=ACenter")

///|
/// Its bar as a panel of its own on the tape (laid out Medium, its corners @sf.pane_round): on the tape's one line, as
/// every bar of the tape is (@sf.tape_line: what it holds in its middle as far under the panel's top as a bar's round
/// buttons' middles, the page's beside it on the same), the first tab in its top left corner and the switch in its top
/// right each as far in as makes them concentric with the corner they are in (@sf.line_end_in); in one too square for
/// that (it follows a round window), clear of it, as in the wide frame at least (side_bar's 8 and 12); its foot as
/// before.
pub fn side_bar_tape() -> @ui.Style {
  let (left, right) = match @sf.pane_radii() {
    Some(k) => (k[0], k[1])
    None => return side_bar()
  }
  // (the switch the tallest in it, the row's top its, the tab's middle on its)
  let side = bar_button_side()
  @ui.style(
    row=true,
    w=Full,
    pt=@sf.room_of(@ui.capsule_in(@sf.tape_corner, side)),
    pb=S1_5,
    pl=@sf.room_of(@sf.line_end_in(left, side_bar_start, side=@sf.side_tab_side)),
    pr=@sf.room_of(@sf.line_end_in(right, side_bar_end, side~)),
    gap=S2,
    align=ACenter,
  )
}

///|
/// The tabs' room at the bar's start in the wide frame (side_bar: pl=S2).
let side_bar_start : Double = 8.0

///|
/// The switch's room at the bar's end in the wide frame (side_bar: pr=S3).
let side_bar_end : Double = 12.0

///|
/// Its tabs (sideTabList), 2 apart.
// kept across runs: a value (no field of it changes)
pub let side_tab_list : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S0_5, align=ACenter, clip=true)

///|
/// A tab (sideTabWrap, sideTab): 30 high, its mark (in a 14 room) and label 6 apart, its close 5 from its end, each in
/// the middle of its end, concentric with it (a service's dot too); a capsule (so in a panel's corner it stands where
/// its shape is concentric with it).
// kept across runs: a value (no field of it changes)
let side_tab_shape : @ui.Style = @ui.style(
  row=true,
  h=@sf.side_tab_h,
  pl=@sf.capsule_end_room(@sf.side_tab_side, side_tab_mark_side),
  pr=S1_25,
  gap=S1_5,
  align=ACenter,
  radius=Full,
)

///|
/// One behind: the pointer's ground on it (and its × a step more, pointed at: mbui ui/hand_moves.mbt).
// kept across runs: a value (no field of it changes)
pub let side_tab : @ui.Style = side_tab_shape.then(@ui.css("hovered{bg=Hover}"))

///|
/// The one in front: the selected ground under it; pressed, it does nothing, so pointed at it stays as it is (its ×
/// lights over it).
// kept across runs: a value (no field of it changes)
pub let side_tab_in_front : @ui.Style = side_tab_shape.then(@ui.css("bg=Selected"))

///|
/// Its mark's room: an icon's, a maker's mark's, a service's dot in its middle.
let side_tab_mark_side : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let side_tab_mark : @ui.Style = @ui.css("w=S3_5 h=S3_5 align=ACenter justify=JCenter")

///|
/// Its label: muted, 13; the one in front in the words' colour and 500. Cut short where the tabs have not the room
/// (sideTab's min-width 0): a tab gives way, never runs past the bar.
// kept across runs: a value (no field of it changes)
pub let side_tab_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// One behind, pointed at: its words in the words' colour.
// kept across runs: a value (no field of it changes)
let side_tab_words_lit : @ui.TextStyle = side_tab_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
pub let side_tab_front : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
/// Its close (sideTabClose): 20 round, concentric in the tab's end; pointed at, the pointer's ground over the tab's.
// kept across runs: a value (no field of it changes)
pub let side_tab_close : @ui.Style = @ui.css("w=S5 h=S5 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// What the tab in front shows, under the bar.
// kept across runs: a value (no field of it changes)
pub let side_pane : @ui.Style = @ui.css("w=Full h=Full clip")

///|
/// What the panel keeps of its own (its tabs are the core's): the width it was dragged to (None: its own), and its
/// slide (useSidePanel), for the page it is beside (a chat's, a workspace's new chat's): what it was last built as
/// (open or not), whether a change asked of the core here opens or closes it (`asked`: it slides then), and while it
/// slides out, what it showed (its tabs and the one in front); a chat's panel's column's way, by its page's key, set off
/// at the change that opens or closes it and read where it is drawn (side_panel_node).
priv struct PanelOwn {
  width : @signals.Signal[Double?]
  was : @sf.LiveMap[String, Bool]
  asked : @signals.Signal[String]
  leaving : @signals.Signal[(String, Array[String], String)?]
  goes : Map[String, @motion.Way]
}

///|
let panel_own : PanelOwn = {
  width: @signals.signal(None, same=fn(a, b) { a == b }),
  was: @sf.LiveMap::new(),
  asked: @signals.signal("", same=fn(a, b) { a == b }),
  leaving: @signals.signal(None, same=fn(a, b) { a == b }),
  goes: {},
}

///|
pub fn side_slide_reset() -> Unit {
  panel_own.width.set(None)
  panel_own.was.clear()
  panel_own.asked.set("")
  panel_own.leaving.set(None)
  panel_own.goes.clear()
}

///|
/// A change of page `key`'s tabs asked of the core, from `tabs` (`front` in front), leaving `any` open (useSidePanel
/// changing): from none to some, the panel slides in once they come; from some to none, out, showing them as it goes.
pub fn side_changing(key : String, tabs : Array[String], front : String, any : Bool) -> Unit {
  let open = tabs.length() > 0
  if any {
    panel_own.leaving.set(None)
  }
  if open != any {
    panel_own.asked.set(key)
    if !any {
      panel_own.leaving.set(Some((key, tabs, front)))
    }
  } else {
    panel_own.asked.set("")
  }
}

///|
/// What page `key`'s panel shows while it slides out, its last tab closed: the tabs it had, the one in front.
fn side_leaving(key : String) -> (Array[String], String)? {
  match panel_own.leaving.get() {
    Some((k, tabs, front)) if k == key => Some((tabs, front))
    _ => None
  }
}

///|
/// Page `key`'s panel gone, as it was sliding out (its tabs shown no more).
fn side_left(key : String) -> Unit {
  if side_leaving(key) is Some(_) {
    panel_own.leaving.set(None)
  }
}

///|
/// Page `key` (`page`) and its side panel (`panel`, `whole` wide at rest) side by side, the panel `open` or not. Opened by
/// a change asked here, the panel's column widens from nothing over 280 ms and the page narrows with it, frame by frame;
/// closed, the other way over 240 ms. The panel keeps its whole width all along and shows
/// through its column as it grows, so it comes in from the right edge without what it holds laid out again; turned back
/// on its way, it goes on from where it is. Open or closed otherwise (a page opened with its tabs as they were left),
/// it is so at once.
pub fn side_beside(c : @ui.Ctx, key : String, open : Bool, whole : Double, page : () -> Unit, panel : () -> Unit) -> Unit {
  // where the page has not the room for the chat and the panel at their least side by side, the panel comes in over
  // the page from its right edge (a shadow at its side), the
  // page as wide as it was, the panel's edge not dragged
  let over = c.width < side_both_least
  let whole = if over { dmin(side_over_w, c.width) } else { whole }
  let name = "--side-panel/" + key
  match panel_own.was.get(key) {
    Some(was) if was != open && panel_own.asked.get() == key => {
      panel_own.asked.set("")
      // (in and out on a Move as long as it is wide)
      c.move_state([("side-panel", [name])])
    }
    _ => ()
  }
  // (each page's own: a panel beside one page and beside another, each as it was last built)
  if panel_own.was.get(key) != Some(open) {
    panel_own.was[key] = open
  }
  // its column (the panel) as wide as it has got
  let col = c.moved(name, if open { whole } else { 0.0 })
  if col <= 0.0 {
    if !open && side_leaving(key) is Some(_) {
      panel_own.leaving.set(None)
    }
    // (the frame it sets off on, its column not open yet: the page on its way from this frame, as on those after it,
    // not from whichever is drawn next)
    if open && !over && whole > 0.0 {
      let (way, to, ends) = (@sfbase.page_way.id, @sfbase.page_way.to, @sfbase.page_way.ends)
      @sfbase.page_way_said(
        way + "/" + name + "/" + open.to_string(),
        (if way != "" { to } else { c.width }) - whole,
        ends=dmax(if way != "" { ends } else { 0.0 }, c.moved_ends(name).unwrap_or(c.moment())),
      )
      page()
      @sfbase.page_way_said(way, to, ends~)
      return
    }
    page()
    return
  }
  if over {
    c.box(style=panel_row, fn() {
      c.box(style=panel_page_whole, fn() { page() }) |> ignore
      c.box(style=side_over_box.then(@ui.style(w=Fixed(whole))), right=0.0, top=0.0, bottom=0.0, tx=whole - col, fn() {
        c.sized(whole, c.height, panel)
      })
      |> ignore
    })
    |> ignore
    return
  }
  let left = c.width - col
  c.box(style=panel_row, fn() {
    // (the page on its way as the panel slides, or as what holds it goes: as wide as that leaves it beside the panel)
    let (way, to, ends) = (@sfbase.page_way.id, @sfbase.page_way.to, @sfbase.page_way.ends)
    let target = if open { whole } else { 0.0 }
    let sliding = col != target
    if sliding || way != "" {
      @sfbase.page_way_said(
        way + "/" + name + "/" + open.to_string(),
        (if way != "" { to } else { c.width }) - target,
        ends=dmax(if way != "" { ends } else { 0.0 }, c.moved_ends(name).unwrap_or(c.moment())),
      )
    }
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() { c.sized(left, c.height, page) }) |> ignore
    @sfbase.page_way_said(way, to, ends~)
    // (cut to its column only while it slides: at rest what it puts past its left edge, its edge's handle half over
    // the page, shows whole, as the web's sidePanel cuts nothing)
    c.box(style=@ui.style(w=Fixed(col), h=Full, clip=col < whole), fn() {
      c.box(style=@ui.style(w=Fixed(whole), h=Full), fn() { c.sized(whole, c.height, panel) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Chat `r`'s page (`chat`) in workspace `w`, its side panel the tree's beside it (side_panel_node; on the tape a panel
/// of its own, tape_side): as the panel's column slides, the page on its way to the width it leaves the page, there as
/// the slide ends: built again in the first frame at or past its end (Ctx::shows_until), whether or not the page's room
/// changes then. (A frame drawn just short of the end has the column as wide as it comes to be already; at 24 frames a
/// second, in a window wide enough for the list to be held at its width on the way (sfpages' laid_w), the next kept the
/// page as on its way, parting from it built anew: view_beside_wbtest, wide_panel_wbtest.)
pub fn with_side(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, chat : () -> Unit) -> Unit {
  if @sf.in_pane() {
    chat()
    return
  }
  let key = chat_key(r)
  let (id, to, ends) = (@sfbase.page_way.id, @sfbase.page_way.to, @sfbase.page_way.ends)
  let open = side_now(src, r).0.length() > 0
  let way_opt = panel_own.goes.get(key)
  let way_goes = match way_opt {
    Some(way) => way.goes_at(c.moment())
    None => false
  }
  if !way_goes && !(id != "" && open) {
    chat()
    return
  }
  let pane = if id != "" {
    to
  } else {
    let ww = c.window_size().0
    ww - fold_target(src, w, ww).1.col
  }
  if pane < side_both_least {
    chat()
    return
  }
  let (side_to, side_ends, side_tag) = match way_opt {
    Some(way) if way_goes => {
      c.shows_until(way.ends_at())
      (way.target(), way.ends_at(), (way.target() > 0.0).to_string())
    }
    _ => (side_width(pane), 0.0, "true")
  }
  @sfbase.page_way_said(
    id + "/--side-panel/" + key + "/" + side_tag,
    pane - side_to,
    ends=dmax(if id != "" { ends } else { 0.0 }, side_ends),
  )
  chat()
  @sfbase.page_way_said(id, to, ends~)
}

///|
/// Whose side panel is open (what the frame puts beside the page on the tape): a chat's, or workspace `ws`'s new
/// chat's (its Station 文件, kept by the same `chatTabs`, by `new:<ws>`).
#derive(Eq)
pub(all) enum SideOf {
  ChatSide(ChatRef)
  NewSide(String)
}

///|
/// The key its panel is kept by (chatTabs).
pub fn SideOf::key(self : SideOf) -> String {
  match self {
    ChatSide(r) => chat_key(r)
    NewSide(ws) => "new:" + ws
  }
}

///|
/// Whose side panel is open on page `p` in workspace `w`: a chat's (or an agent's history asked as a page: its
/// chat's), as its view has it; the new chat's, its 文件 open where the stations lend their files; None with none open.
pub fn side_open_for(src : Source, w : Workspace, p : Page) -> SideOf? {
  match p {
    Chat(r) | History(r, _, _) => if side_now(src, r).0.length() > 0 { Some(ChatSide(r)) } else { None }
    NewChat => if new_files_open(src, w.id) && new_drive_station(src, w) is Some(_) { Some(NewSide(w.id)) } else { None }
    _ => None
  }
}

///|
/// The side panel `side` on the tape, a panel of its own beside the page's: a chat's tabs as its view has them, a new
/// chat's Station 文件; its edge not dragged (its width the tape's: frame.mbt tape_one_beside).
pub fn tape_side(c : @ui.Ctx, src : Source, w : Workspace, side : SideOf, leaving? : Bool = false) -> Unit {
  side_on_tape.val = true
  match side {
    ChatSide(r) =>
      match view_of_chat(src, r).0 {
        Some(view) => {
          // (closed while in use: what it had as the tape moves off it)
          let (tabs, front) = if leaving {
            side_leaving(chat_key(r)).unwrap_or(side_of(view))
          } else {
            side_of(view)
          }
          side_panel(c, src, w, r, view, tabs, front)
        }
        None => ()
      }
    NewSide(_) =>
      match new_drive_station(src, w) {
        Some(address) => new_files_panel(c, src, w, address)
        None => ()
      }
  }
  side_on_tape.val = false
}

///|
/// The panel (sidePanel) of every tab but an agent's history, an old view: its tabs and its switch over what the one in
/// front shows. Its edge is the tree's (side_panel_node's), as an agent's history is (side_body_node).
fn side_panel(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
  v : ChatView,
  tabs : Array[String],
  front : String,
) -> Unit {
  c.box(style=side_panel_style, fn() {
    let (_, screen_alone, own_bar) = side_bars(c, tabs, front)
    if !own_bar {
      side_bar_row(c, src, r, v, tabs, front)
    }
    c.box(style=side_pane, fn() {
      if front == "jobs" {
        // a service up pressed: its own tab, in front (JobsTab onOpen)
        jobs_tab(c, src, r.station, chat_key(r), src.topic("chatJobs", chat_params(r)).get().value, fn(job) {
          c.tell("jobs-open/" + job, fn() { side_change(src, r, "open", Some("service:" + job)) })
        })
      } else if front == "files" {
        // the workspace's stations' files (drive_tab.mbt), what is added from them going into the chat's draft
        files_tab(c, src, w.id, tabs_key(r), r.station)
      } else if front == "letters" {
        match v.thread {
          Some(th) => letters_tab(c, src, r, v, th)
          None => ()
        }
      } else if front == "things" {
        // what was said in it besides words (sfpages things.mbt): 在对话里看 goes to the message beside it
        match v.thread {
          Some(th) => @sfpages.things_body(c, src, r, th, false, fn(seq) { @sfbase.go_to(r, seq) })
          None => ()
        }
      } else if tab_service(front) is Some(job) {
        service_pane(c, src, r, job, close=if own_bar && !column_short.get() {
          Some(fn() { c.tell("side/close", fn() { side_change(src, r, "clear", None) }) })
        } else {
          None
        })
      } else if tab_file(front) is Some((session, path, name)) {
        file_pane(c, src, r, session, path, name)
      } else if station_tab_pane(c, src, w, r, front, own_bar=if screen_alone { Some(side_bar_tape()) } else { None }) {
        ()
      }
      // (an agent's history: the tree's, side_body_node)
    })
    |> ignore
  })
  |> ignore
}

///|
/// How the panel showing `tabs` (`front` in front) is headed: a panel of its own on the tape showing one tab, that tab
/// its title, the panel's close its only ×; the station's screen alone on its side, its tools a rail with no name of
/// their own (the panel's row names it); and whether what is in front has a bar of its own (a service's alone: its
/// address names it; the screen's), that bar the panel's, its × at its end, no row of the panel's over it (the user,
/// 2026-10-28: two rows there too much).
fn side_bars(c : @ui.Ctx, tabs : Array[String], front : String) -> (Bool, Bool, Bool) {
  let alone = side_on_tape.val && tabs.length() == 1
  let (ww, wh) = c.window_size()
  let screen_alone = screen_tab_alone(tabs) && !column_short.get() && ww <= wh
  (alone, screen_alone, (alone && tab_service(front) is Some(_)) || screen_alone)
}

///|
/// The panel's bar (sideBar): its tabs (or the one alone, its title), the station's screen to a window of its own,
/// the panel's switch.
fn side_bar_row(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, tabs : Array[String], front : String) -> Unit {
  // (the desktop app has no title bar: the panel's bar drags the window as the page's does)
  let bar = c.id("side/bar")
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  let (alone, _, _) = side_bars(c, tabs, front)
  c.box(style=if side_on_tape.val { side_bar_tape() } else { side_bar() }, id=bar, fn() {
    if alone {
      side_title(c, src, r, v, tabs[0])
    } else {
      c.box(style=side_tab_list, fn() {
        for tab in tabs {
          side_tab_of(c, src, r, v, tab, tab == front)
        }
      })
      |> ignore
    }
    // the station's screen in front: to a window of its own (a desktop's), its tab closed here (station_tabs.mbt)
    match station_tab_page(r, front) {
      Some(p) if @sfbase.window_opens_for(p) =>
        @sf.icon_button(c, "external", key="side/window", round=true, label=@sf.t("web-pages.screen.window"), on_press=fn() {
          if @sfbase.open_window(p) {
            side_change(src, r, "close", Some(front))
          }
        })
        |> ignore
      _ => ()
    }
    // the panel's switch stays in its top right corner, open or closed; in the short column, the column's
    // (histories_ticked)
    if !column_short.get() {
      @sf.icon_button(c, if alone { "close" } else { "panel-close" }, key="side/close", round=true, linked?=@sf.bar_keys_link(), label=@sf.t("web-pages.chat.closePanel"), shortcut="panel.close", on_press=fn() {
        side_change(src, r, "clear", None)
      }) |> ignore
    }
  })
  |> ignore
}

///|
/// What a tab is called and how its close is said: an agent's by its label, a web service's by its name, a
/// visualization's by its file's name, 任务's, 文件's, agent 往来's by theirs.
fn side_tab_names(src : Source, r : ChatRef, v : ChatView, tab : String) -> (String, String) {
  match station_tab_name(src, tab) {
    Some(label) => return (label, @sf.t("web-pages.chat.close", args=[("name", label)]))
    None => ()
  }
  // a file in the viewer: by its name
  match @sfbase.view_tab_file(tab) {
    Some(f) => return (f.file.name, @sf.t("web-pages.chat.close", args=[("name", f.file.name)]))
    None => ()
  }
  let agent = v.agents.iter().find_first(fn(a) { a.key == tab })
  let service = match tab_service(tab) {
    Some(job) => Some(src.topic("job", { "station": Json::string(r.station), "id": Json::string(job) }).get().value)
    None => None
  }
  let file = tab_file(tab)
  let label = match (agent, service, file) {
    (Some(a), _, _) => a.who
    (_, Some(j), _) => if text(j, "name") == "" { svc("android-chat.preview.service") } else { text(j, "name") }
    (_, _, Some((_, _, name))) => name
    _ =>
      if tab == "jobs" {
        @sf.t("web-pages.chat.jobs")
      } else if tab == "files" {
        @sf.t("web-pages.chat.files")
      } else if tab == "things" {
        @sf.t("web-main.things.title")
      } else {
        @sf.t("web-main.letters.title")
      }
  }
  let closing = match (agent, service, file) {
    (Some(_), _, _) | (_, Some(_), _) | (_, _, Some(_)) => @sf.t("web-pages.chat.close", args=[("name", label)])
    _ =>
      if tab == "jobs" {
        @sf.t("web-pages.chat.closeJobs")
      } else if tab == "files" {
        @sf.t("web-pages.chat.closeFiles")
      } else if tab == "things" {
        @sf.t("web-main.things.close")
      } else {
        @sf.t("web-main.letters.close")
      }
  }
  (label, closing)
}

///|
/// A tab's mark: an agent's maker's, a web service's dot of how it is, else the icon of what it shows (in the words'
/// colour when `front`: in front, or lit by the hand).
fn side_tab_mark_of(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, tab : String, front : Bool) -> Unit {
  let t = @sf.theme()
  match station_tab(tab) {
    Some((kind, _, _)) => {
      @sf.icon(c, match kind { "drive" => "folder"; "adb" => "phone"; _ => "monitor" }, size=14.0, color=if front { t.p.text } else { t.p.muted }) |> ignore
      return
    }
    None => ()
  }
  match v.agents.iter().find_first(fn(a) { a.key == tab }) {
    Some(a) => {
      @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
      return
    }
    None => ()
  }
  match tab_service(tab) {
    Some(job) => {
      let j = src.topic("job", { "station": Json::string(r.station), "id": Json::string(job) }).get().value
      c.box(style=side_tab_mark, fn() { job_dot(c, text(j, "tone")) }) |> ignore
      return
    }
    None => ()
  }
  let icon = if @sfbase.view_tab_file(tab) is Some(f) {
    if @sfbase.preview_kind(f.file.name).0 == Some(@sfbase.KImage) {
      "photo"
    } else {
      "file"
    }
  } else if tab_file(tab) is Some(_) {
    "file"
  } else if tab == "jobs" {
    "boxes"
  } else if tab == "files" {
    "folder"
  } else if tab == "things" {
    "photo"
  } else {
    "chats"
  }
  @sf.icon(c, icon, size=14.0, color=if front { t.p.text } else { t.p.muted }) |> ignore
}

///|
/// A tab (sideTab): its mark and label (all of it in its tip where it is cut); a press brings it in front, its ×
/// closes it.
fn side_tab_of(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, tab : String, front : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/tab/" + tab)
  c.on_press(id, fn() {
    side_change(src, r, "front", Some(tab))
  })
  let close = c.id("side/tab-close/" + tab)
  c.on_press(close, fn() {
    side_change(src, r, "close", Some(tab))
  })
  let (label, closing) = side_tab_names(src, r, v, tab)
  // lit, a tab's muted words and marks come up to the words' colour, as its ground comes (mbui ui/hand_moves.mbt)
  let lit = !front && c.lit(id)
  let b = c.box(style=if front { side_tab_in_front } else { side_tab }, id~, fn() {
    side_tab_mark_of(c, src, r, v, tab, front || lit)
    c.text(label, style=if front {
      side_tab_front
    } else if lit {
      side_tab_words_lit
    } else {
      side_tab_words
    })
    |> ignore
    let x = c.box(style=side_tab_close, id=close, fn() {
      @sf.icon(c, "close", size=12.0, color=if c.lit(close) { t.p.text } else { t.p.muted }) |> ignore
    })
    c.semantics(x, Button, id=close, label=closing)
  })
  c.semantics(b, Tab, id~, label~, selected=front)
  if !(tab == "jobs" || tab == "files" || tab == "letters" || tab == "things") {
    @sf.tip(c, "side/tab-tip/" + tab, id, label, repeats=true)
  }
}

///|
/// The one tab of a panel of its own on the tape, as its title (pengxiao, 2026-10-25: a tab alone in a panel's corner
/// is a capsule against its corner, its × beside the panel's): its mark and its name as the page's bar has its title,
/// what closes the panel at the bar's end the only close.
fn side_title(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, tab : String) -> Unit {
  let (label, _) = side_tab_names(src, r, v, tab)
  let b = c.box(style=side_title_row, fn() {
    side_tab_mark_of(c, src, r, v, tab, true)
    c.text(label, style=side_title_words) |> ignore
  })
  c.semantics(b, Heading, label~)
}

///|
/// The title's row: grown into the bar, its mark over what the tab shows under it (16 more in), its name 8 after it.
// kept across runs: a value (no field of it changes)
let side_title_row : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("row pl=S4 gap=S2 align=ACenter"))

///|
/// The title's words: as the page's bar's title (chat_title_words).
// kept across runs: a value (no field of it changes)
let side_title_words : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, color=Fg, leading=L6, wrap=false, w=Cut)

///|
/// A bar's icon button's side (@sf.icon_button, round: 32 on either hand, @sf.bar_key_side): a circle, so in a panel's
/// corner it stands where it is concentric.
fn bar_button_side() -> Double {
  @sf.bar_key_side
}
