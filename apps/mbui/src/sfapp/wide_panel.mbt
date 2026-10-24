// What opens under a chat's bar in the wide frame (ember web/src/pages/ChatPage.tsx ChatInfo, JobsPanel), as the
// web's does, not as a phone's sheets: its "…" (what is done with the chat) and its services' popover (sfdesk/jobs.mbt).
// The side panel beside the chat is sfdesk's (panel.mbt); what this package asks of it goes through the names below.

///|
/// A chat's key among the frame's own: its station and session.
fn side_key(r : ChatRef) -> String {
  @sfdesk.chat_key(r)
}

///|
/// The chat's side panel's tabs, in their order, and the one in front (sfdesk/panel.mbt).
fn side_of(v : ChatView) -> (Array[String], String) {
  @sfdesk.side_of(v)
}

///|
/// Chat `r`'s tabs as its view has them now.
fn side_now(r : ChatRef) -> (Array[String], String) {
  match link_src.val {
    Some(src) => @sfdesk.side_now(src, r)
    None => ([], "")
  }
}

///|
/// Chat `r`'s tabs changed by the core, the panel told first whether any will be open (sfdesk's side_change).
fn side_change(r : ChatRef, action : String, tab : String?) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_change(src, r, action, tab)
    None => ()
  }
}

///|
/// The change asked of the core alone, the panel told nothing (sfdesk's side_ask).
fn side_ask(r : ChatRef, action : String, tab : String?) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_ask(src, r, action, tab)
    None => ()
  }
}

///|
/// An agent's history pressed, or the chat's files: in front, closed; else opened in front (sfdesk's side_toggle).
fn side_toggle(r : ChatRef, tab : String) -> Unit {
  match link_src.val {
    Some(src) => @sfdesk.side_toggle(src, r, tab)
    None => ()
  }
}

///|
/// What the side panel shows of this package's beside chat `r`: an agent's history's steps (history.mbt), a letter as
/// the chat draws a message, a link opened as the chat opens one.
fn panel_parts(c : @ui.Ctx, src : Source, r : ChatRef) -> @sfdesk.PanelParts {
  {
    steps: fn(key) { history_steps(c, src, r, key, None) },
    message: fn(m) {
      match view_of_chat(src, r) {
        (Some(v), _, _) =>
          said(c, src, { station: r.station, session: r.session, view: v }, message_of(m), [], decide=false)
        _ => ()
      }
    },
    link: fn(href) { open_link(href) },
  }
}

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
    fn() {
      let open = fn(id : String) {
        wide.jobs_open = false
        if id != "" {
          @sfdesk.pick_job(id)
        }
        side_change(r, "open", Some("jobs"))
      }
      // (a service's own tab is not here yet: it opens in 任务 too)
      @sfdesk.jobs_popover(c, src, r.station, (src.topic)("chatJobs", chat_params(r)).value, open, open)
    },
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
          @sfdesk.letters_to_list(r)
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



