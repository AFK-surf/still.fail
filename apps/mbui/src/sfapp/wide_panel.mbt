// Beside a chat in the wide frame (ember web/src/pages/ChatPage.tsx, ChatSide.tsx, ChatPage.css.ts sidePanel and
// sideTab, Jobs.tsx JobsPopover and JobsTab): the side panel at the pane's right, a tab each for what is opened in it
// (an agent's execution history, the chat's services and jobs, what its agents and other chats' wrote each other), the
// one in front shown, the panel closed with its switch; and what opens under the chat's bar as the web's does, not as
// a phone's sheets: its "…" (what is done with the chat) and its services' popover. Each chat keeps its own tabs.

///|
/// A chat's key among the frame's own: its station and session.
fn side_key(r : ChatRef) -> String {
  r.station + "\u{1}" + r.session
}

///|
/// A chat's tabs' key as the core keeps them (the prefs' `chatTabs`: `<station>:<session>`, as its page names it).
fn tabs_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// Whether this panel shows `tab` beside a chat of `v`: one of its agents' histories (by its session's key), 任务, 文件,
/// agent 往来 (not yet the web's services and visualizations).
fn side_shows(v : ChatView, tab : String) -> Bool {
  tab == "jobs" || tab == "files" || tab == "letters" || v.agents.iter().any(fn(a) { a.key == tab })
}

///|
/// The chat's side panel's tabs, in their order, and the one in front: the core's (the chat view's `tabs`: those kept
/// for it on this device that it has, ChatPage.tsx), of those this panel shows.
fn side_of(v : ChatView) -> (Array[String], String) {
  let tabs = v.tabs.open.filter(fn(t) { side_shows(v, t) })
  let front = match v.tabs.shown {
    Some(f) if tabs.contains(f) => f
    _ => tabs.get(0).unwrap_or("")
  }
  (tabs, front)
}

///|
/// Chat `r`'s tabs as its view has them now.
fn side_now(r : ChatRef) -> (Array[String], String) {
  match link_src.val {
    Some(src) =>
      match (src.topic)("chat", chat_params(r)).value {
        Some(v) => side_of(chat_view(v))
        None => ([], "")
      }
    None => ([], "")
  }
}

///|
/// Chat `r`'s tabs changed by the core, which keeps them on this device (ChatPage.tsx change): `tab` opened in front (an
/// agent's history after the histories open, any other last), closed (the last left in front, if it was), brought to
/// the front; all of them closed (`clear`). The panel is told first whether any will be open, to slide as they come.
fn side_change(r : ChatRef, action : String, tab : String?) -> Unit {
  let (tabs, front) = side_now(r)
  let any = match action {
    "open" | "front" => true
    "close" => tabs.iter().any(fn(t) { Some(t) != tab })
    _ => false
  }
  side_changing(side_key(r), tabs, front, any)
  side_ask(r, action, tab)
}

///|
/// The change asked of the core alone (changeTabs, `chat.tabs.*`), the panel told nothing: as a chat made from the new
/// chat's page starts with what it had beside it.
fn side_ask(r : ChatRef, action : String, tab : String?) -> Unit {
  match link_src.val {
    Some(src) => {
      let params : Map[String, Json] = { "chat": Json::string(tabs_key(r)) }
      match tab {
        Some(t) => params["tab"] = Json::string(t)
        None => ()
      }
      (src.call)("chat.tabs." + action, Json::object(params), fn(_) {  })
    }
    None => ()
  }
}

///|
/// An agent's history pressed (its mark in the bar), or the chat's files (its info's 文件): in front, closed; else
/// opened in front.
fn side_toggle(r : ChatRef, tab : String) -> Unit {
  let (tabs, front) = side_now(r)
  side_change(r, if tabs.contains(tab) && front == tab { "close" } else { "open" }, Some(tab))
}

///|
/// How wide the panel is (ChatSide.tsx: 38% of the page, at least 360; between PANEL_MIN 320 and PANEL_MAX 960), the
/// chat keeping 360 at least.
fn side_width(pane : Double) -> Double {
  let wanted = dmin(960.0, dmax(320.0, dmax(360.0, (pane * 0.38).floor())))
  dmax(0.0, dmin(wanted, pane - 360.0))
}

///|
/// The chat and the panel side by side.
// kept across runs: a value (no field of it changes)
let side_row : @ui.Style = @ui.style(row=true, w=Full, h=Full)

///|
/// The panel: its ground the canvas, a hairline at its left.
// kept across runs: a value (no field of it changes)
let side_panel_style : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let side_rule : @ui.Style = @ui.style(w=SPx, h=Full, bg=Line)

///|
/// How wide that hairline is (its SPx), the panel's column being it and the panel.
let side_rule_w : Double = 1.0

///|
/// Its bar (sideBar): 45 high, the tabs from 8 in, the panel's switch at its right 12 in.
// kept across runs: a value (no field of it changes)
let side_bar : @ui.Style = @ui.style(row=true, w=Full, h=S11, pl=S2, pr=S3, gap=S2, align=ACenter)

///|
/// Its tabs (sideTabList), 2 apart.
// kept across runs: a value (no field of it changes)
let side_tab_list : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S0_5, align=ACenter, clip=true)

///|
/// A tab (sideTabWrap, sideTab): its icon and label 6 apart, 12 in (8 before its close), the pointer's ground on it, the
/// selected ground under the one in front.
// kept across runs: a value (no field of it changes)
let side_tab : @ui.Style = @ui.style(
  row=true,
  h=S8,
  pl=S3,
  pr=S1,
  gap=S1_5,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
)

///|
/// Its label: muted, 13; the one in front in the words' colour and 500.
// kept across runs: a value (no field of it changes)
let side_tab_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let side_tab_front : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// Its close (sideTabClose): 20 square, round 6 (a small mark of its own), the line's ground on it.
// kept across runs: a value (no field of it changes)
let side_tab_close : @ui.Style = @ui.style(w=S5, h=S5, radius=Md, align=ACenter, justify=JCenter, hovered=@ui.patch(bg=Line))

///|
/// What the tab in front shows, under the bar.
// kept across runs: a value (no field of it changes)
let side_pane : @ui.Style = @ui.style(w=Full, h=Full, clip=true)

///|
/// How long the side panel takes to slide in and out (ChatSide.tsx useSidePanel: 0.28 s and 0.24 s, the page's ease-out).
pub let side_in_ms : Double = 280.0

///|
pub let side_out_ms : Double = 240.0

///|
/// The side panel's slide (ChatSide.tsx useSidePanel), for the page it is beside (a chat's, a workspace's new chat's):
/// what it was last built as (open or not), whether a change asked of the core here opens or closes it (`opening`,
/// `leaving`: it slides then), and while it slides out, what it showed (its tabs and the one in front).
priv struct SideSlide {
  mut was : (String, Bool)?
  mut asked : String
  mut leaving : (String, Array[String], String)?
}

///|
let side_slide_of : SideSlide = { was: None, asked: "", leaving: None }

///|
fn side_slide_reset() -> Unit {
  side_slide_of.was = None
  side_slide_of.asked = ""
  side_slide_of.leaving = None
}

///|
/// A change of page `key`'s tabs asked of the core, from `tabs` (`front` in front), leaving `any` open (useSidePanel
/// changing): from none to some, the panel slides in once they come; from some to none, out, showing them as it goes.
fn side_changing(key : String, tabs : Array[String], front : String, any : Bool) -> Unit {
  let open = tabs.length() > 0
  if any {
    side_slide_of.leaving = None
  }
  if open != any {
    side_slide_of.asked = key
    if !any {
      side_slide_of.leaving = Some((key, tabs, front))
    }
  } else {
    side_slide_of.asked = ""
  }
}

///|
/// What page `key`'s panel shows while it slides out, its last tab closed: the tabs it had, the one in front.
fn side_leaving(key : String) -> (Array[String], String)? {
  match side_slide_of.leaving {
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
fn side_beside(c : @ui.Ctx, key : String, open : Bool, whole : Double, page : () -> Unit, panel : () -> Unit) -> Unit {
  let name = "--side-panel/" + key
  match side_slide_of.was {
    Some((k, was)) if k == key && was != open && side_slide_of.asked == key => {
      side_slide_of.asked = ""
      c.move_state([("side-panel", [name])], duration=if open { side_in_ms } else { side_out_ms })
    }
    _ => ()
  }
  side_slide_of.was = Some((key, open))
  // its column (the rule, then the panel) as wide as it has got
  let col = c.moved(name, if open { whole + side_rule_w } else { 0.0 })
  if col <= 0.0 {
    if !open && side_leaving(key) is Some(_) {
      side_slide_of.leaving = None
    }
    page()
    return
  }
  let left = c.width - col
  c.box(style=side_row, fn() {
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
/// The chat's page with its side panel beside it: its tabs, or while the panel slides out the ones it had.
fn with_side(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?, chat : () -> Unit) -> Unit {
  let key = side_key(r)
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
/// The panel: its tabs and its switch over what the one in front shows.
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
    c.box(style=side_bar, fn() {
      c.box(style=side_tab_list, fn() {
        for tab in tabs {
          side_tab_of(c, r, v, tab, tab == front)
        }
      })
      |> ignore
      if icon_button(c, "side/close", "panel-close", label=tr("web-pages.chat.closePanel")) {
        side_change(r, "clear", None)
      }
    })
    |> ignore
    c.box(style=side_pane, fn() {
      if front == "jobs" {
        side_jobs(c, src, r)
      } else if front == "files" {
        // the workspace's stations' files (src/sfdesk/drive_tab.mbt), what is added from them going into the chat's draft
        @sfdesk.files_tab(c, src, w.id, draft_key(r), r.station)
      } else if front == "letters" {
        match v.thread {
          Some(th) => letters_body(c, src, r, th)
          None => ()
        }
      } else if front != "" {
        // one of its agents' execution histories
        history_body(c, src, r, front, None, (src.topic)("chat", chat_params(r)))
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A tab: an agent's by its maker's mark and label, 任务's, agent 往来's; a press brings it in front, its × closes it.
fn side_tab_of(c : @ui.Ctx, r : ChatRef, v : ChatView, tab : String, front : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/tab/" + tab)
  c.cursor(id, Hand)
  if c.clicked(id) {
    side_change(r, "front", Some(tab))
  }
  let close = c.id("side/tab-close/" + tab)
  c.cursor(close, Hand)
  if c.clicked(close) {
    side_change(r, "close", Some(tab))
  }
  c.box(style=side_tab, selected=front, id~, fn() {
    match v.agents.iter().find_first(fn(a) { a.key == tab }) {
      Some(a) => {
        @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
        c.text(a.who, style=if front { side_tab_front } else { side_tab_words }) |> ignore
      }
      None => {
        let (icon, label) = if tab == "jobs" {
          ("boxes", tr("web-pages.chat.jobs"))
        } else if tab == "files" {
          ("folder", tr("web-pages.chat.files"))
        } else {
          ("chats", tr("web-main.letters.title"))
        }
        @sf.icon(c, icon, size=14.0, color=if front { t.p.text } else { t.p.muted }) |> ignore
        c.text(label, style=if front { side_tab_front } else { side_tab_words }) |> ignore
      }
    }
    c.box(style=side_tab_close, id=close, fn() { @sf.icon(c, "close", size=12.0, color=t.p.muted) |> ignore })
    |> ignore
  })
  |> ignore
}

///|
/// The 任务 tab (Jobs.tsx JobsTab): every service and job of the chat's, those that matter first, the one picked (the
/// first job while none is) shown under them.
fn side_jobs(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let topic = (src.topic)("chatJobs", chat_params(r))
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => {
      waiting_rows(c, 3, topic.error)
      return
    }
  }
  let jobs = items(view, "jobs")
  if jobs.length() == 0 {
    c.box(style=letters_none_box, fn() { c.text(tr("android-misc.jobs.none"), style=letters_none) |> ignore }) |> ignore
    return
  }
  let picked = match jobs.iter().find_first(fn(j) { text(Some(j), "id") == wide.job_picked }) {
    Some(j) => Some(j)
    None => jobs.iter().find_first(fn(j) { !flag(Some(j), "service") })
  }
  c.list(
    "side-jobs/" + r.station + "/" + r.session,
    2,
    120.0,
    fn(i) {
      if i == 0 {
        c.box(style=side_jobs_list, fn() { job_groups(c, r, view, jobs, pick=Some(fn(id) { wide.job_picked = id })) })
        |> ignore
      } else {
        match picked {
          Some(j) => job_detail(c, src, r, text(Some(j), "id"), Some(j))
          None => ()
        }
      }
    },
  )
  |> ignore
}

///|
/// The 任务 tab's list, at the panel's sides.
// kept across runs: a value (no field of it changes)
let side_jobs_list : @ui.Style = @ui.style(w=Full, px=S4, pb=S3)

///|
/// What opens under the chat's bar (wide_chat.mbt): its "…" and its services' popover, each by its button.
fn bar_popovers(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let info = @kit.popover(
    c,
    "chat-info-pop",
    wide.info_open,
    c.id("chat-more"),
    side=Bottom,
    along=End,
    look=fn(c, _, body) { @sf.panel(c, w=Px(320.0), body) |> ignore },
    fn() { chat_info_rows(c, src, r, v) },
  )
  // (closed by what was pressed in it, or as a popover closes: Escape, a press outside)
  wide.info_open = wide.info_open && info.value
  let jobs = @kit.popover(
    c,
    "chat-jobs-pop",
    wide.jobs_open,
    c.id("chat-jobs"),
    side=Bottom,
    along=End,
    look=fn(c, _, body) { @sf.panel(c, w=Px(360.0), body) |> ignore },
    fn() { jobs_rows(c, src, r) },
  )
  wide.jobs_open = wide.jobs_open && jobs.value
}

///|
/// A line of the chat's facts (ChatPage.tsx detailRow): what it is in muted words 80 wide, then what there is of it.
// kept across runs: a value (no field of it changes)
let info_fact : @ui.Style = @ui.style(row=true, w=Full, min_h=S6, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let info_fact_label : @ui.Style = @ui.style(w=S20)

///|
/// Its facts and its agents, at the panel's words' inset (TEXT_IN 10).
// kept across runs: a value (no field of it changes)
let info_facts : @ui.Style = @ui.style(w=Full, px=S2_5, pt=S2_5, pb=S2, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let info_words_sm : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_muted_sm : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_muted_xs : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// An agent of it (AgentLine): its mark and label, its line under them.
// kept across runs: a value (no field of it changes)
let info_agent : @ui.Style = @ui.style(w=Full, pt=S1, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let info_inline : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
/// A row of what is done with it (ui.tsx PanelRow): 34 high at least, its icon (20 wide, muted) and words 10 apart, what
/// is at its end muted; round with the panel, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let info_tool : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=S8,
  px=S2_5,
  gap=S2_5,
  align=ACenter,
  radius=Inner,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let info_tool_icon : @ui.Style = @ui.style(w=S5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let info_tools : @ui.Style = @ui.style(w=Full, pt=S2, gap=S0_5)

///|
/// A row of the popover: true on the frame after a press.
fn info_tool_row(c : @ui.Ctx, key : String, icon : String, label : String, end : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  c.box(style=info_tool, id~, fn() {
    c.box(style=info_tool_icon, fn() { @sf.icon(c, icon, size=14.0, color=t.p.muted) |> ignore }) |> ignore
    c.box(style=letters_grow, fn() { c.text(label, style=info_words_sm) |> ignore }) |> ignore
    if end != "" {
      c.text(end, style=info_muted_xs) |> ignore
    }
  })
  |> ignore
  c.clicked(id)
}

///|
/// What the chat's "…" holds (ChatPage.tsx ChatInfoBody): where it came from, who started it, who takes part, when it
/// was made and last written in; its agents; then what is done with it: what its agents and other chats' wrote each
/// other (in the side panel), relaying it, it in Slack or Feishu, sharing it, publishing it.
fn chat_info_rows(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let chat = (src.topic)("chat", chat_params(r)).value
  let thread = field(chat, "thread")
  let fact = fn(label : String, value : () -> Unit) {
    c.box(style=info_fact, fn() {
      c.box(style=info_fact_label, fn() { c.text(label, style=info_muted_sm) |> ignore }) |> ignore
      value()
    })
    |> ignore
  }
  c.box(style=info_facts, fn() {
    fact(tr("web-pages.chat.info.from"), fn() {
      let words = match text(chat, "place") {
        "" => fill("web-pages.chat.info.native", [("name", "still.fail")])
        p => "Slack · " + p
      }
      c.text(words, style=info_words_sm) |> ignore
    })
    let creator = match text(field(field(thread, "creator"), "shown"), "display") {
      "" => text(field(thread, "creator"), "name")
      d => d
    }
    fact(tr("web-pages.chat.info.started"), fn() {
      c.text(if creator == "" { tr("web-pages.chat.info.unknown") } else { creator }, style=if creator == "" {
        info_muted_sm
      } else {
        info_words_sm
      })
      |> ignore
    })
    fact(tr("web-pages.chat.info.people"), fn() {
      c.box(style=info_inline, fn() {
        let people = if v.people.length() > 8 { v.people[:8].to_array() } else { v.people }
        if people.length() > 0 {
          people_stack(c, src, people, 16.0, ring=@sf.panel_ground())
        }
        c.text(fill("android-chat.info.people.count", [("n", v.people.length().to_string())]), style=info_words_sm)
        |> ignore
      })
      |> ignore
    })
    fact(tr("web-pages.chat.info.created"), fn() {
      c.text(text(field(field(thread, "time"), "createdAt"), "ago"), style=info_words_sm) |> ignore
    })
    match text(field(field(field(thread, "lastMessage"), "time"), "createdAt"), "ago") {
      "" => ()
      ago => fact(tr("web-pages.chat.info.lastMessage"), fn() { c.text(ago, style=info_words_sm) |> ignore })
    }
    for a in items(chat, "agents") {
      let av = Some(a)
      let s = field(av, "session")
      c.box(style=info_agent, fn() {
        c.box(style=info_inline, fn() {
          @sf.maker_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), 14.0) |> ignore
          c.text(text(s, "agentText"), style=info_words_sm) |> ignore
        })
        |> ignore
        c.text(text(s, "statusText"), style=info_muted_xs) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  let th = opt_number(thread, "id")
  c.box(style=info_tools, fn() {
    // the stations' files beside the chat, where they lend them (ChatPage.tsx onFiles)
    if drive_in(src, workspace_of(r.station)) &&
      info_tool_row(c, "info-pop/files", "folder", tr("web-pages.chat.files"), "") {
      wide.info_open = false
      side_toggle(r, "files")
    }
    match th {
      Some(id) if v.letters > 0 =>
        if info_tool_row(
            c,
            "info-pop/letters",
            "chats",
            tr("web-main.letters.title"),
            fill("web-main.letters.count", [("n", v.letters.to_string())]),
          ) {
          wide.info_open = false
          dui.letters_open = ""
          dui.letters_held[side_key(r)] = id
          side_change(r, "open", Some("letters"))
        }
      _ => ()
    }
    match th {
      Some(id) if !v.archived && !v.offline && v.agents.length() > 0 =>
        if info_tool_row(c, "info-pop/relay", "arrow-up-right", tr("web-main.relay.action"), "") {
          wide.info_open = false
          open_relay(c, src, r, id)
        }
      _ => ()
    }
    match text(chat, "slackUrl") {
      "" => ()
      url =>
        if info_tool_row(c, "info-pop/slack", "external", tr("android-chat.info.slack.open"), "") {
          wide.info_open = false
          @ui.open_url(url) |> ignore
        }
    }
    match text(chat, "feishuUrl") {
      "" => ()
      url =>
        if info_tool_row(c, "info-pop/feishu", "external", tr("web-mobile.chat.openFeishu"), "") {
          wide.info_open = false
          @ui.open_url(url) |> ignore
        }
    }
    if field(chat, "xshare") is Some(Object(_)) &&
      info_tool_row(c, "info-pop/xshare", "users", tr("web-pages.chat.xshare"), "") {
      wide.info_open = false
      open_sheet(c, XShare(r, th))
    }
    match (shown_publish(chat), th) {
      (Some(_), Some(id)) =>
        if info_tool_row(c, "info-pop/publish", "web", tr("web-pages.chat.publish"), "") {
          wide.info_open = false
          open_sheet(c, Publish(r.station, id))
        }
      _ => ()
    }
  })
  |> ignore
}

///|
/// What matters now of the chat's services and jobs, from the bar's button (Jobs.tsx JobsPopover): those that matter now,
/// a job pressed opened in the 任务 tab; at its foot all of them there, and clearing what ended.
fn jobs_rows(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let topic = (src.topic)("chatJobs", chat_params(r))
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => return
  }
  let jobs = items(view, "jobs")
  let shown = jobs.filter(fn(j) { flag(Some(j), "current") })
  c.box(style=side_jobs_pop, fn() {
    job_groups(
      c,
      r,
      view,
      shown,
      pick=Some(fn(id) {
        wide.jobs_open = false
        wide.job_picked = id
        side_change(r, "open", Some("jobs"))
      }),
    )
  })
  |> ignore
  c.box(style=info_tools, fn() {
    if info_tool_row(c, "jobs-pop/all", "panel-open", text(view, "allText"), "") {
      wide.jobs_open = false
      side_change(r, "open", Some("jobs"))
    }
    if number(view, "ended") > 0.0 {
      let clear_key = "clear/" + r.station
      if info_tool_row(c, "jobs-pop/clear", "trash", text(view, "clearText"), "") && !doing(clear_key) {
        for session in items(view, "clear") {
          match session {
            String(s) =>
              act(
                src,
                tr("android-misc.jobs.clearWhat"),
                clear_key,
                "job.clearEnded",
                { "station": Json::string(r.station), "session": Json::string(s) },
              )
            _ => ()
          }
        }
      }
    }
  })
  |> ignore
}

///|
/// The services' popover's groups, at the panel's words' inset.
// kept across runs: a value (no field of it changes)
let side_jobs_pop : @ui.Style = @ui.style(w=Full, px=S1)

