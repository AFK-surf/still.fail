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
/// The chat's side panel's tabs, in their order: `history/<session>` an agent's, `jobs`, `letters`.
fn side_tabs(r : ChatRef) -> Array[String] {
  let k = side_key(r)
  match wide.tabs.get(k) {
    Some(tabs) => tabs
    None => {
      // as the core kept them for the chat on this device (prefs `chatTabs`, the web's keepTabs), the first time asked
      let (tabs, front) = kept_tabs(r)
      if tabs.length() > 0 {
        wide.tabs[k] = tabs
        if front != "" {
          wide.front[k] = front
        }
      }
      tabs
    }
  }
}

///|
/// The tabs the core keeps for chat `r` (prefs `chatTabs` by `station:session`: an agent's history by its session's
/// key, `jobs`, `letters`), as this panel names them, and the one in front.
fn kept_tabs(r : ChatRef) -> (Array[String], String) {
  let prefs = match link_src.val {
    Some(src) => (src.topic)("prefs", {}).value
    None => return ([], "")
  }
  let kept = field(field(prefs, "chatTabs"), r.station + ":" + r.session)
  let own = fn(t : String) -> String? {
    match t {
      "jobs" | "letters" | "files" => Some(t)
      // (the web's other tabs, its services and visualizations, this panel has not)
      _ if t.has_prefix("service:") || t.contains("/") => None
      _ => Some("history/" + t)
    }
  }
  let tabs : Array[String] = []
  match field(kept, "tabs") {
    Some(Array(a)) =>
      for x in a {
        match x {
          String(t) =>
            match own(t) {
              Some(o) => tabs.push(o)
              None => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  let front = match own(text(kept, "active")) {
    Some(f) if tabs.contains(f) => f
    _ => ""
  }
  (tabs, front)
}

///|
/// Chat `r`'s tabs as they are now, kept by the core for it on this device (prefs `chatTabs`), as the web keeps them.
fn keep_tabs(r : ChatRef) -> Unit {
  match link_src.val {
    Some(src) => {
      let k = side_key(r)
      let web = fn(t : String) { if t.has_prefix("history/") { t.view(start_offset=8).to_string() } else { t } }
      let tabs = wide.tabs.get(k).unwrap_or([]).map(fn(t) { Json::string(web(t)) })
      let entry : Map[String, Json] = { "tabs": Json::array(tabs) }
      match wide.front.get(k) {
        Some(f) if f != "" => entry["active"] = Json::string(web(f))
        _ => ()
      }
      let chat : Map[String, Json] = {}
      chat[r.station + ":" + r.session] = Json::object(entry)
      (src.call)("prefs.set", { "chatTabs": Json::object(chat) }, fn(_) {  })
    }
    None => ()
  }
}

///|
/// The tab in front (the last opened while none is said).
fn side_front(r : ChatRef) -> String {
  let tabs = side_tabs(r)
  match wide.front.get(side_key(r)) {
    Some(f) if tabs.contains(f) => f
    _ =>
      match tabs.last() {
        Some(l) => l
        None => ""
      }
  }
}

///|
/// `tab` opened in front: an agent's history after the histories open, before the other tabs (ChatPage.tsx openTab).
fn side_open(r : ChatRef, tab : String) -> Unit {
  let k = side_key(r)
  let tabs = side_tabs(r).copy()
  if !tabs.contains(tab) {
    if tab.has_prefix("history/") {
      let mut at = 0
      for i, x in tabs {
        if x.has_prefix("history/") {
          at = i + 1
        }
      }
      tabs.insert(at, tab)
    } else {
      tabs.push(tab)
    }
  }
  wide.tabs[k] = tabs
  wide.front[k] = tab
  keep_tabs(r)
}

///|
/// `tab` closed: the last left comes to the front if it was.
fn side_close(r : ChatRef, tab : String) -> Unit {
  let k = side_key(r)
  let tabs = side_tabs(r).filter(fn(x) { x != tab })
  if tabs.length() == 0 {
    // (none left: kept so, not read back from what the core had)
    wide.tabs[k] = []
    wide.front.remove(k)
    keep_tabs(r)
    return
  }
  wide.tabs[k] = tabs
  if side_front(r) == tab || !tabs.contains(side_front(r)) {
    wide.front[k] = tabs[tabs.length() - 1]
  }
  keep_tabs(r)
}

///|
/// An agent's history pressed (its mark in the bar), or the chat's files (its info's 文件): in front, closed; else
/// opened in front.
fn side_toggle(r : ChatRef, tab : String) -> Unit {
  if side_front(r) == tab {
    side_close(r, tab)
  } else {
    side_open(r, tab)
  }
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
/// The chat's page with its side panel beside it while something is open in it: the chat `pane` wide less the panel's.
fn with_side(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?, chat : () -> Unit) -> Unit {
  let tabs = side_tabs(r)
  let panel = if tabs.length() > 0 && v is Some(_) { side_width(c.width) } else { 0.0 }
  if panel <= 0.0 {
    chat()
    return
  }
  let left = c.width - panel - 1.0
  c.box(style=side_row, fn() {
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() { c.sized(left, c.height, chat) }) |> ignore
    c.box(style=side_rule, fn() {  }) |> ignore
    c.box(style=@ui.style(w=Fixed(panel), h=Full), fn() {
      c.sized(panel, c.height, fn() {
        match v {
          Some(view) => side_panel(c, src, w, r, view)
          None => ()
        }
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The panel: its tabs and its switch over what the one in front shows.
fn side_panel(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView) -> Unit {
  let tabs = side_tabs(r)
  let front = side_front(r)
  c.box(style=side_panel_style, fn() {
    c.box(style=side_bar, fn() {
      c.box(style=side_tab_list, fn() {
        for tab in tabs {
          side_tab_of(c, r, v, tab, tab == front)
        }
      })
      |> ignore
      if icon_button(c, "side/close", "panel-close", label=tr("web-pages.chat.closePanel")) {
        wide.tabs.remove(side_key(r))
        wide.front.remove(side_key(r))
      }
    })
    |> ignore
    c.box(style=side_pane, fn() {
      if front.has_prefix("history/") {
        let key = front.view(start_offset=8).to_string()
        history_body(c, src, r, key, None, (src.topic)("chat", chat_params(r)))
      } else if front == "jobs" {
        side_jobs(c, src, r)
      } else if front == "files" {
        // the workspace's stations' files (wide_files_tab.mbt), what is added from them going into the chat's draft
        files_tab(c, src, w, draft_key(r), r.station)
      } else if front == "letters" {
        match v.thread {
          Some(th) => letters_body(c, src, r, th)
          None => ()
        }
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
    wide.front[side_key(r)] = tab
    keep_tabs(r)
  }
  let close = c.id("side/tab-close/" + tab)
  c.cursor(close, Hand)
  if c.clicked(close) {
    side_close(r, tab)
  }
  c.box(style=side_tab, selected=front, id~, fn() {
    if tab.has_prefix("history/") {
      let key = tab.view(start_offset=8).to_string()
      match v.agents.iter().find_first(fn(a) { a.key == key }) {
        Some(a) => {
          @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
          c.text(a.who, style=if front { side_tab_front } else { side_tab_words }) |> ignore
        }
        None => ()
      }
    } else {
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
    look=fn(c, _, body) { wide_panel(c, 320.0, body) },
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
    look=fn(c, _, body) { wide_panel(c, 360.0, body) },
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
          people_stack(c, src, people, 16.0, ring=panel_ground())
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
          side_open(r, "letters")
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
        side_open(r, "jobs")
      }),
    )
  })
  |> ignore
  c.box(style=info_tools, fn() {
    if info_tool_row(c, "jobs-pop/all", "panel-open", text(view, "allText"), "") {
      wide.jobs_open = false
      side_open(r, "jobs")
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

