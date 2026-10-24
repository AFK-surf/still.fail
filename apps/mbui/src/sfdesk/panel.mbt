// Beside a chat on the desktop (ember web/src/pages/ChatPage.tsx's side panel, ChatSide.tsx useSidePanel, SidePane,
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
/// agent 往来, a web service of its agents' (`service:<job>`), a visualization (`file:[…]`: service_tab.mbt).
fn side_shows(v : ChatView, tab : String) -> Bool {
  tab == "jobs" ||
  tab == "files" ||
  tab == "letters" ||
  tab_service(tab) is Some(_) ||
  tab_file(tab) is Some(_) ||
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
  match (src.topic)("chat", chat_params(r)).value {
    Some(v) => side_of(chat_view(v))
    None => ([], "")
  }
}

///|
/// Chat `r`'s tabs changed by the core, which keeps them on this device (ChatPage.tsx change): `tab` opened in front (an
/// agent's history after the histories open, any other last), closed (the last left in front, if it was), brought to
/// the front; all of them closed (`clear`). The panel is told first whether any will be open, to slide as they come.
pub fn side_change(src : Source, r : ChatRef, action : String, tab : String?) -> Unit {
  let (tabs, front) = side_now(src, r)
  let any = match action {
    "open" | "front" => true
    "close" => tabs.iter().any(fn(t) { Some(t) != tab })
    _ => false
  }
  side_changing(chat_key(r), tabs, front, any)
  // a web service's or a visualization's tab closed lets its page go (ChatPage.tsx endPreview)
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
  (src.call)("chat.tabs." + action, Json::object(params), fn(_) {  })
}

///|
/// An agent's history pressed (its mark in the bar), or the chat's files (its info's 文件): in front, closed; else
/// opened in front.
pub fn side_toggle(src : Source, r : ChatRef, tab : String) -> Unit {
  let (tabs, front) = side_now(src, r)
  side_change(src, r, if tabs.contains(tab) && front == tab { "close" } else { "open" }, Some(tab))
}

///|
/// How narrow and how wide the panel is dragged (ChatSide.tsx PANEL_MIN, PANEL_MAX).
let panel_min : Double = 320.0

///|
let panel_max : Double = 960.0

///|
/// How wide the panel is (ChatSide.tsx panelWidth: the width dragged, else 38% of the page and at least 360), the
/// chat keeping 360 at least.
pub fn side_width(pane : Double) -> Double {
  let wanted = match panel_own.width {
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
/// Whether the panel being built is over the page (side_beside), its edge not dragged then.
// kept across runs: said by side_beside as each panel is built, before it is read
let side_over : Ref[Bool] = Ref(false)

///|
/// The page under the panel over it: as wide as it is.
// kept across runs: a value (no field of it changes)
let panel_page_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The panel over the page (sidePanel, narrow): the page's ground, its shadow at its side (-12 0 32).
// kept across runs: a value (no field of it changes)
let side_over_box : @ui.Style = @ui.css("bg=Bg shadow=Xl")

///|
/// The panel (sidePanel): its ground the canvas, a hairline at its left.
// kept across runs: a value (no field of it changes)
pub let side_panel_style : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let side_rule : @ui.Style = @ui.css("w=SPx h=Full bg=Line")

///|
/// How wide that hairline is (its SPx), the panel's column being it and the panel.
let side_rule_w : Double = 1.0

///|
/// Its bar (sideBar): 45 high, the tabs from 8 in, the panel's switch at its right 12 in.
// kept across runs: a value (no field of it changes)
pub let side_bar : @ui.Style = @ui.css("row w=Full h=S11 pl=S2 pr=S3 gap=S2 align=ACenter")

///|
/// Its tabs (sideTabList), 2 apart.
// kept across runs: a value (no field of it changes)
pub let side_tab_list : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S0_5, align=ACenter, clip=true)

///|
/// A tab (sideTabWrap, sideTab): 30 high, its icon and label 6 apart, 12 in, its close 5 from its end; round 10, the
/// pointer's ground on it, the selected ground under the one in front.
// kept across runs: a value (no field of it changes)
pub let side_tab : @ui.Style = @ui.style(
  row=true,
  h=@sf.side_tab_h,
  pl=S3,
  pr=S1_25,
  gap=S1_5,
  align=ACenter,
  radius=@sf.custom_field_r,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
)

///|
/// Its label: muted, 13; the one in front in the words' colour and 500.
// kept across runs: a value (no field of it changes)
pub let side_tab_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
pub let side_tab_front : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// Its close (sideTabClose): 20 square, round 6 (a small mark of its own), the line's ground on it.
// kept across runs: a value (no field of it changes)
pub let side_tab_close : @ui.Style = @ui.css("w=S5 h=S5 radius=Md align=ACenter justify=JCenter hovered{bg=Line}")

///|
/// What the tab in front shows, under the bar.
// kept across runs: a value (no field of it changes)
pub let side_pane : @ui.Style = @ui.css("w=Full h=Full clip")

///|
/// How long the side panel takes to slide in and out (ChatSide.tsx useSidePanel: 0.28 s and 0.24 s, the page's ease-out).
pub let side_in_ms : Double = 280.0

///|
pub let side_out_ms : Double = 240.0

///|
/// What the panel keeps of its own (its tabs are the core's): the width it was dragged to (None: its own), and its
/// slide (useSidePanel), for the page it is beside (a chat's, a workspace's new chat's): what it was last built as
/// (open or not), whether a change asked of the core here opens or closes it (`asked`: it slides then), and while it
/// slides out, what it showed (its tabs and the one in front).
priv struct PanelOwn {
  mut width : Double?
  mut was : (String, Bool)?
  mut asked : String
  mut leaving : (String, Array[String], String)?
}

///|
let panel_own : PanelOwn = { width: None, was: None, asked: "", leaving: None }

///|
pub fn side_slide_reset() -> Unit {
  panel_own.width = None
  panel_own.was = None
  panel_own.asked = ""
  panel_own.leaving = None
}

///|
/// A change of page `key`'s tabs asked of the core, from `tabs` (`front` in front), leaving `any` open (useSidePanel
/// changing): from none to some, the panel slides in once they come; from some to none, out, showing them as it goes.
pub fn side_changing(key : String, tabs : Array[String], front : String, any : Bool) -> Unit {
  let open = tabs.length() > 0
  if any {
    panel_own.leaving = None
  }
  if open != any {
    panel_own.asked = key
    if !any {
      panel_own.leaving = Some((key, tabs, front))
    }
  } else {
    panel_own.asked = ""
  }
}

///|
/// What page `key`'s panel shows while it slides out, its last tab closed: the tabs it had, the one in front.
fn side_leaving(key : String) -> (Array[String], String)? {
  match panel_own.leaving {
    Some((k, tabs, front)) if k == key => Some((tabs, front))
    _ => None
  }
}

///|
/// Page `key` (`page`) and its side panel (`panel`, `whole` wide at rest) side by side, the panel `open` or not. Opened by
/// a change asked here, the panel's column widens from nothing over 280 ms and the page narrows with it, frame by frame;
/// closed, the other way over 240 ms (ChatSide.tsx useSidePanel). The panel keeps its whole width all along and shows
/// through its column as it grows, so it comes in from the right edge without what it holds laid out again; turned back
/// on its way, it goes on from where it is. Open or closed otherwise (a page opened with its tabs as they were left),
/// it is so at once.
pub fn side_beside(c : @ui.Ctx, key : String, open : Bool, whole : Double, page : () -> Unit, panel : () -> Unit) -> Unit {
  // where the page has not the room for the chat and the panel at their least side by side, the panel comes in over
  // the page from its right edge (ChatPage.css.ts sidePanel on a narrow page: 460 at most, a shadow at its side), the
  // page as wide as it was, the panel's edge not dragged
  let over = c.width < side_both_least
  side_over.val = over
  let whole = if over { dmin(side_over_w, c.width) } else { whole }
  let name = "--side-panel/" + key
  match panel_own.was {
    Some((k, was)) if k == key && was != open && panel_own.asked == key => {
      panel_own.asked = ""
      c.move_state([("side-panel", [name])], duration=if open { side_in_ms } else { side_out_ms })
    }
    _ => ()
  }
  panel_own.was = Some((key, open))
  // its column (the rule, then the panel) as wide as it has got
  let col = c.moved(name, if open { whole + (if over { 0.0 } else { side_rule_w }) } else { 0.0 })
  if col <= 0.0 {
    if !open && side_leaving(key) is Some(_) {
      panel_own.leaving = None
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
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() { c.sized(left, c.height, page) }) |> ignore
    c.box(style=@ui.style(w=Fixed(col), h=Full, clip=true), fn() {
      c.box(style=@ui.style(row=true, w=Fixed(whole + side_rule_w), h=Full), fn() {
        c.box(style=side_rule, fn() {  }) |> ignore
        c.box(style=@ui.style(w=Fixed(whole), h=Full), fn() { c.sized(whole, c.height, panel) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Chat `r`'s page (`chat`) with its side panel beside it (in workspace `w`): its tabs, or while the panel slides out
/// the ones it had.
pub fn with_side(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
  v : ChatView?,
  chat : () -> Unit,
) -> Unit {
  // (on the tape, laid out Medium, the panel is a panel of its own beside the page's: the frame's, tape_side)
  if wide.tape {
    chat()
    return
  }
  let key = chat_key(r)
  let (tabs, front) = match v {
    Some(view) => side_of(view)
    None => ([], "")
  }
  let open = tabs.length() > 0
  side_beside(c, key, open, side_width(c.width), chat, fn() {
    match v {
      Some(view) => {
        let (tabs, front) = if open { (tabs, front) } else { side_leaving(key).unwrap_or(([], "")) }
        side_panel(c, src, w, r, view, tabs, front)
      }
      None => ()
    }
  })
}

///|
/// The chat whose side panel is open on page `p` (a chat's, or an agent's history asked as a page: its chat's), as its
/// view has it; None with none open.
pub fn side_open_for(src : Source, p : Page) -> ChatRef? {
  let r = match p {
    Chat(r) => r
    History(r, _, _) => r
    _ => return None
  }
  if side_now(src, r).0.length() > 0 {
    Some(r)
  } else {
    None
  }
}

///|
/// How wide a chat's side panel is on the tape (laid out Medium), a window `window` wide: its own (the width dragged,
/// else 38% of the window and 360 at least, as side_width's), at most what the window leaves past what shows of the
/// page beside it (`peek`) and the gaps round it (`apart`).
pub fn tape_side_width(window : Double, peek : Double, apart : Double) -> Double {
  let wanted = match panel_own.width {
    Some(w) => w
    None => dmax(360.0, (window * 0.38).floor())
  }
  dmax(0.0, dmin(wanted, window - peek - apart))
}

///|
/// Chat `r`'s side panel on the tape, a panel of its own beside the page's: its tabs as its view has them, its edge not
/// dragged (its width the tape's: tape_side_width).
pub fn tape_side(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  match (src.topic)("chat", chat_params(r)).value {
    Some(v) => {
      let view = chat_view(v)
      let (tabs, front) = side_of(view)
      side_over.val = true
      side_panel(c, src, w, r, view, tabs, front)
    }
    None => ()
  }
}

///|
/// The panel (sidePanel): its edge, its tabs and its switch over what the one in front shows.
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
    // (the desktop app has no title bar: the panel's bar drags the window as the page's does)
    let bar = c.id("side/bar")
    if @ui.window_inset() {
      c.window_drag(bar)
    }
    c.box(style=side_bar, id=bar, fn() {
      c.box(style=side_tab_list, fn() {
        for tab in tabs {
          side_tab_of(c, src, r, v, tab, tab == front)
        }
      })
      |> ignore
      // the panel's switch stays in its top right corner, open or closed
      if icon_button(c, "side/close", "panel-close", label=@sf.t("web-pages.chat.closePanel"), action="panel.close") {
        side_change(src, r, "clear", None)
      }
    })
    |> ignore
    c.box(style=side_pane, fn() {
      if front == "jobs" {
        // a service up pressed: its own tab, in front (JobsTab onOpen)
        jobs_tab(c, src, r.station, chat_key(r), (src.topic)("chatJobs", chat_params(r)).value, fn(job) {
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
      } else if tab_service(front) is Some(job) {
        service_pane(c, src, r, job)
      } else if tab_file(front) is Some((session, path, name)) {
        file_pane(c, src, r, session, path, name)
      } else if front != "" {
        // one of its agents' execution histories
        agent_history(c, src, r.station, front, agent_json((src.topic)("chat", chat_params(r)).value, front))
      }
    })
    |> ignore
    // its edge (ResizeHandle): dragged, its width (kept while the app runs); pressed, the panel closed; pressed
    // twice, its own width again; over the page, none
    if side_over.val {
      return
    }
    match
      @sf.resize_handle(
        c,
        "side/edge",
        c.width,
        min=panel_min,
        max=panel_max,
        label=@sf.t("web-pages.chat.resizePanel"),
        edge=Left,
        press=@sf.t("web-pages.chat.closePanel"),
      ) {
      Dragging(x) | Dropped(x) => panel_own.width = Some(x)
      Pressed => side_change(src, r, "clear", None)
      Twice => panel_own.width = None
      Untouched => ()
    }
  })
  |> ignore
}

///|
/// A tab (sideTab): an agent's by its maker's mark and label (all of it in its tip where it is cut), 任务's, 文件's,
/// agent 往来's; a press brings it in front, its × closes it.
fn side_tab_of(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, tab : String, front : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/tab/" + tab)
  c.cursor(id, Hand)
  if c.clicked(id) {
    side_change(src, r, "front", Some(tab))
  }
  let close = c.id("side/tab-close/" + tab)
  c.cursor(close, Hand)
  if c.clicked(close) {
    side_change(src, r, "close", Some(tab))
  }
  let agent = v.agents.iter().find_first(fn(a) { a.key == tab })
  // a web service's by its name and a dot of how it is; a visualization's by its file's name
  let service = match tab_service(tab) {
    Some(job) => Some((src.topic)("job", { "station": Json::string(r.station), "id": Json::string(job) }).value)
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
      } else {
        @sf.t("web-main.letters.close")
      }
  }
  let b = c.box(style=side_tab, selected=front, id~, fn() {
    match (agent, service) {
      (Some(a), _) => @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
      (_, Some(j)) => job_dot(c, text(j, "tone"))
      _ => {
        let icon = if file is Some(_) {
          "file"
        } else if tab == "jobs" {
          "boxes"
        } else if tab == "files" {
          "folder"
        } else {
          "chats"
        }
        @sf.icon(c, icon, size=14.0, color=if front { t.p.text } else { t.p.muted }) |> ignore
      }
    }
    c.text(label, style=if front { side_tab_front } else { side_tab_words }) |> ignore
    let x = c.box(style=side_tab_close, id=close, fn() {
      @sf.icon(c, "close", size=12.0, color=t.p.muted) |> ignore
    })
    c.semantics(x, Button, id=close, label=closing)
  })
  c.semantics(b, Tab, id~, label~, selected=front)
  if agent is Some(_) || service is Some(_) || file is Some(_) {
    @sf.tip(c, "side/tab-tip/" + tab, id, label)
  }
}

///|
/// An icon button of a page's bar (page.css.ts iconBtn): 32 square, the nav's corner, the pointer's ground and ink
/// on hover; named for a screen reader, and said under it on hover with its keys (`action`'s: the web's IconButton).
/// True on the frame after a press.
pub fn icon_button(c : @ui.Ctx, key : String, icon : String, label? : String = "", action? : String = "") -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.lit(id) || c.pressed(id)
  let b = c.box(style=bar_icon_button, id~, fn() {
    @sf.icon(c, icon, size=16.0, color=if hot { t.p.text } else { t.p.muted }) |> ignore
  })
  if label != "" {
    c.semantics(b, Button, id~, label~)
    @sf.tip(c, key, id, label, shortcut=action)
  }
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let bar_icon_button : @ui.Style = @ui.css(
  #|w=S8 h=S8 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover} pressed{bg=Hover}
)
