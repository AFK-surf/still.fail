// A chat on the desktop (ember web/src/pages/ChatPage.tsx, ChatPage.css.ts; styles/sidebar.css.ts pageBar,
// conversation.css.ts pageBarTitle): its side panel beside it (panel.mbt), its bar over its messages: its title (while a
// new one goes, that one with a turning ring), its station's update, the station while no agent is in it, its people,
// its agents (each its history beside the chat, its card on hover); at its end 归档 while nothing is left in it, its
// services and jobs (a popover: jobs.mbt), 对话信息 (a popover), the panel's switch while the panel is closed; ⌘F's bar
// in place of those while it is open (find.mbt). Its messages are chat_list.mbt's, its composer composer.mbt's.

///|
/// What the chat's page keeps of its own (the rest is the core's): its info's popover open, its services' popover
/// open. The popovers' as signals: opened or
/// closed from another island than the page's (an item of the system's bars chosen as the frame under the tape is
/// built, after the page was: rail_native.mbt), the page's is told and built again, not kept as it was till the hand
/// comes to it (an iPhone Duo's ⓘ, 2026-11-01: the popover only once a finger moved).
priv struct ChatOwn {
  info_open : @signals.Signal[Bool]
  jobs_open : @signals.Signal[Bool]
}

///|
// kept across runs: put back by chat_page_reset
let chat_own : ChatOwn = {
  info_open: @signals.signal(false, same=fn(a, b) { a == b }),
  jobs_open: @signals.signal(false, same=fn(a, b) { a == b }),
}

///|
fn chat_page_reset() -> Unit {
  chat_own.info_open.set(false)
  chat_own.jobs_open.set(false)
}

///|
/// The chat's services' popover opened or closed (its keys, ⌘K's 服务和后台任务).
pub fn toggle_jobs_pop() -> Unit {
  chat_own.jobs_open.set(!@signals.untracked(fn() { chat_own.jobs_open.get() }))
}

///|
pub fn open_jobs_pop() -> Unit {
  chat_own.jobs_open.set(true)
}

///|
/// Its info's popover open (a screen's fixture).
pub fn open_info_pop() -> Unit {
  chat_own.info_open.set(true)
}

///|
/// Whether its info's popover is open, and its services' (tests).
pub fn chat_pops_open() -> (Bool, Bool) {
  (chat_own.info_open.get(), chat_own.jobs_open.get())
}

///|
/// ⌘F's bar opened in chat `r`: what opens under the bar closed.
pub fn chat_find_open(c : @ui.Ctx, r : ChatRef) -> Unit {
  chat_own.info_open.set(false)
  chat_own.jobs_open.set(false)
  find_open(c, chat_key(r))
}

///|
/// ⌘F's bar opened in chat `r` at the key's moment, its popovers shut (chat_find_open's, its bar a node's).
fn chat_find_open_now(r : ChatRef) -> Unit {
  chat_own.info_open.set(false)
  chat_own.jobs_open.set(false)
  @sfpages.find_open_now(chat_key(r))
}

///|
/// The chat's own keys (keymap.ts, ChatPage.tsx useShortcut) on its page `talk` (its view `view`, the list to its end
/// `latest`), each done at its moment while the page takes input (@settings.actions_node), and as chosen from the menu
/// bar: ⌘F its find (a chat with a thread); ⌘↓ its list to its end, following it again, or short of the chat's end its
/// latest page (chat.latest); ⌘⇧E into the archive while nothing is left in it, ⌘⇧H its first agent's history beside it
/// (one in front: the panel closed), ⌘. its agents at work stopped, its services and jobs (chat.jobs), its station's own
/// display (chat.screen); ⌘U the system's file picker for its draft (composer.file); Space with no field focused, the
/// composer's field (composer.focus).
fn chat_actions_node(talk : @view.View, src : Source, w : Workspace, r : ChatRef, view : () -> ChatView?, latest : () -> Unit) -> Unit {
  let draft = r.station + ":" + r.session
  let with_view = fn(f : (ChatView) -> Bool) { fn() { match view() { Some(v) => f(v); None => false } } }
  @settings.actions_node(talk, fn() { (src.topic)("prefs", {}).value }, [
    ("chat.find", with_view(fn(v) { if v.thread is Some(_) { chat_find_open_now(r); true } else { false } })),
    ("chat.latest", with_view(fn(v) {
      match (v.newer, v.thread) {
        (false, _) => { latest(); true }
        (true, Some(th)) => {
          (src.call)("chat.latest", { "station": Json::string(r.station), "thread": Json::number(th) }, fn(_) {  })
          true
        }
        _ => false
      }
    })),
    ("chat.jobs", with_view(fn(_) { toggle_jobs_pop(); true })),
    ("chat.screen", with_view(fn(v) { chat_screen_first(r, v.screens); true })),
    ("composer.focus", with_view(fn(_) {
      if switcher_open() || @ui.current().field_focused() { return false }
      writing(src, draft).field.focus()
      true
    })),
    ("chat.archive", with_view(fn(v) {
      if v.archived || v.offline { return false }
      archive_asked(src, w, r, v, (src.topic)("chat", chat_params(r)).value)
      true
    })),
    ("chat.history", with_view(fn(v) { if v.agents.length() > 0 { history_toggle(src, r, v); true } else { false } })),
    ("chat.stop", with_view(fn(v) { stop_agents(src, r, v); true })),
    ("composer.file", with_view(fn(v) { if v.offline { false } else { @sfpages.pick_files(writing(src, draft)); true } })),
  ])
}

///|
/// ⌘⇧H: an agent's history in front, the panel closed; else the first agent's open, or the first agent's opened.
fn history_toggle(src : Source, r : ChatRef, v : ChatView) -> Unit {
  let (tabs, front) = side_of(v)
  let agent = fn(t : String) { v.agents.iter().any(fn(a) { a.key == t }) }
  if agent(front) {
    side_change(src, r, "clear", None)
  } else {
    side_change(src, r, "open", Some(tabs.iter().find_first(agent).unwrap_or(v.agents[0].key)))
  }
}

///|
/// Whether one of the chat's agents is at work (or waiting to be): what ⌘. stops.
fn agents_working(v : ChatView) -> Bool {
  v.agents.iter().any(fn(a) { a.status == "running" || a.status == "queued" })
}

///|
/// ⌘.: the chat's agents at work stopped.
fn stop_agents(src : Source, r : ChatRef, v : ChatView) -> Unit {
  for a in v.agents {
    if a.status == "running" || a.status == "queued" {
      act(
        src,
        @sf.t("web-pages.chat.stop"),
        "",
        "session.stop",
        { "station": Json::string(r.station), "key": Json::string(a.key) },
        done=@sf.t("web-pages.chat.stopAsked"),
      )
    }
  }
}

///|
/// Into the archive, asked first where the chat keeps watch (in the core's words).
fn archive_asked(src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?) -> Unit {
  if field(chat, "watch") is Some(Object(_)) {
    @sf.confirm(
      @sf.t("web-pages.chat.archiveConfirm", args=[("title", v.title)]),
      text(field(chat, "watch"), "ask"),
      @sf.t("web-pages.chat.archive"),
      fn() { archive(src, w, r, v) },
      danger=true,
    )
  } else {
    archive(src, w, r, v)
  }
}

///|
/// The chat into the archive (ChatPage.tsx archive): on to the chat below it in the list (or above, at the end), so
/// the keys go on working, the list if none; said at once, or why not.
fn archive(src : Source, w : Workspace, r : ChatRef, v : ChatView) -> Unit {
  let here = fn() {
    match app.nav.top() {
      Chat(t) => t.station == r.station && t.session == r.session
      _ => false
    }
  }
  neighbour(src, w, 1)
  if here() {
    neighbour(src, w, -1)
  }
  if here() {
    @sfbase.close_page(Chat(r)) |> ignore
    wide.landed.set("")
  }
  let p : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(r.session),
    "archived": Json::boolean(true),
  }
  match v.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  // said at once, by its title (the core's list has it gone); why not, when not
  toast_later(
    @sf.t("web-main.chat.archivedNamed", args=[("title", v.title)]),
    action=@sf.t("android-chat.archived.undo"),
    run=@sfbase.archive_undo(src, p),
  )
  (src.call)("chat.archive", Json::object(p), fn(res) {
    match res {
      Ok(_) => ()
      Err(e) => toast_later(@sf.t("web-pages.chat.archiveFailed", args=[("error", error_words(e))]))
    }
  })
}

///|
/// People overlapping a little (components.tsx PeopleStack): `most` of them at most, each a 16 circle (their picture, or
/// their initial), each 4 over the one before; more than that, +n after them; their names in its tip.
fn people_stack(c : @ui.Ctx, src : Source, key : String, people : Array[Person], most : Int) -> Unit {
  let shown = if people.length() > most { people[:most].to_array() } else { people }
  let id = c.id(key)
  let t = @sf.theme()
  let ring = people_ring.then(@ui.style(bg=Data(t.p.sidebar)))
  let letter = people_letter_box.then(@ui.style(bg=Data(t.p.paper)))
  c.box(style=people_row, id~, fn() {
    for i, p in shown {
      // each ringed 1.5 in the sidebar's ground, 4 over the one before (later.css.ts peopleStack)
      c.box(style=if i == 0 { ring.then(person_first) } else { ring.then(person_next) }, fn() {
        if p.picture != "" {
          // (the picture as the core gives it: Source.picture)
          @sf.avatar(c, p.id, p.display, (src.picture)(p.picture, c.page_stint()), person_side)
        } else {
          // its initial on the paper, 600 (cloud.css.ts personLetter)
          c.box(style=letter, fn() { c.text(person_initial(p.display), style=people_letter) |> ignore }) |> ignore
        }
      })
      |> ignore
    }
    if people.length() > most {
      c.box(style=people_more_box, fn() { c.text("+\{people.length() - most}", style=people_more) |> ignore }) |> ignore
    }
  })
  |> ignore
  @sf.tip(c, key, id, @sf.t("web-main.people.in", args=[
    ("names", people.map(fn(p) { p.display }).join(@sf.t("web-main.list.separator"))),
  ]))
}

///|
/// The screens' button's dot while an agent drives one: as the services' (jobs_alarm_room), in the tone of an agent at
/// work.
// kept across runs: a value (no field of it changes)
let screen_driven_dot : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Warn border=B2 border_color=Bg")

///|
/// How wide the info's popover and the services' are (ChatPage.css.ts chatInfo, jobsPanel).
let chat_info_w : Double = 320.0

///|
let jobs_pop_w : Double = 360.0

///|
/// What the chat's info says (ChatInfoBody), in two groups apart: what it is (where it came from if not here, who
/// started it, who else takes part, when it was made and last written in) and who works in it (its agents,
/// AgentLine); what is in it (its pull requests, what else was said, the stations' files beside it, what its agents
/// and other chats' wrote each other). What is done with it is the "…"'s menu, a row of the sidebar's.
fn chat_info(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?) -> Unit {
  let thread = field(chat, "thread")
  // (a chat of a Slack or Feishu thread alone has none here: where it is, its agents and the way there, no more)
  let th = opt_number(thread, "id")
  // (its labels in a column 80 wide, or as wide as the widest of them in this language: words of a length known,
  // whole)
  let labels = ["from", "started", "people", "created", "lastMessage"].map(fn(k) { @sf.t("web-pages.chat.info." + k) })
  let label_w = labels.fold(init=info_label_w, fn(m, l) { dmax(m, c.words_across(l, info_muted).ceil()) })
  let fact = fn(label : String, value : () -> Unit) {
    c.box(style=info_fact, fn() {
      c.box(style=@ui.style(w=Fixed(label_w)), fn() { c.text(label, style=info_muted) |> ignore }) |> ignore
      value()
    })
    |> ignore
  }
  // (its first fact's words as far under the panel's top as a menu's first item's: the fact's row taller than its
  // line, centred in it)
  let over = @sf.menu_row_over - (info_fact_h - @sf.theme().t.ui_line) / 2.0
  c.box(style=info_facts.then(@ui.style(pt=@sf.room_of(over))), fn() {
    // (where it came from only when that is not here: a still.fail chat's says nothing)
    match text(chat, "place") {
      "" => ()
      place =>
        fact(@sf.t("web-pages.chat.info.from"), fn() {
          let feishu = text(thread, "surface").has_prefix("feishu:") || text(chat, "feishuUrl") != ""
          c.box(style=info_inline, fn() {
            if feishu {
              @sf.feishu_mark(c, 13.0) |> ignore
            } else {
              @sf.slack_mark(c, 13.0) |> ignore
            }
            let through = if feishu { @sf.t("web-pages.connect.feishu.name") } else { "Slack" }
            c.text(through + " · " + place, style=info_words) |> ignore
          })
          |> ignore
        })
    }
    guard th is Some(_) else { return }
    let creator = match text(field(field(thread, "creator"), "shown"), "display") {
      "" => text(field(thread, "creator"), "name")
      d => d
    }
    fact(@sf.t("web-pages.chat.info.started"), fn() {
      // made by another chat's agent: that chat, its mark before its title (已归档 after one in the archive); pressed,
      // it opens
      match v.opener {
        Some(o) => {
          let id = c.id("info-opener")
          if c.clicked(id) {
            chat_own.info_open.set(false)
            open_page(Chat(o.chat))
          }
          let p = @sf.theme().p
          let b = c.box(style=info_inline, id~, fn() {
            @sf.icon(c, "spawned", size=14.0, color=if c.lit(id) { p.text } else { p.muted }) |> ignore
            c.text(o.chat.title, style=if c.lit(id) { info_words_hot } else { info_words }) |> ignore
            if o.archived {
              c.text(o.note, style=info_quiet) |> ignore
            }
          })
          c.semantics(b, Link, id~, label=o.text)
          @sf.tip(c, "info-opener", id, o.text, repeats=true)
          return
        }
        None => ()
      }
      if creator == "" {
        c.text(@sf.t("web-pages.chat.info.unknown"), style=info_muted) |> ignore
      } else {
        // their face before their name, as the people's are
        c.box(style=info_inline, fn() {
          match field(thread, "creator") {
            Some(Object(_) as p) => people_stack(c, src, "info-creator", [@sfbase.person_of(p)], 1)
            _ => ()
          }
          c.text(creator, style=info_words) |> ignore
        })
        |> ignore
      }
    })
    // (who takes part only when that is more than who started it)
    let creator_id = text(field(thread, "creator"), "id")
    let only_starter = v.people.length() == 0 ||
      (v.people.length() == 1 && creator_id != "" && v.people[0].id == creator_id)
    if !only_starter {
      fact(@sf.t("web-pages.chat.info.people"), fn() {
        // (beside the system's tabs, no pointer to rest on them for their names: each its face and its name, the people
        // out of the chat's bar there, rail_native.mbt; the user 2026-10-27)
        if @sf.native_on() && v.people.length() > 0 {
          c.box(style=info_people_list, fn() {
            for i, p in v.people {
              c.box(style=info_inline, fn() {
                people_stack(c, src, "info-person/\{i}", [p], 1)
                c.text(p.display, style=info_words) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
          return
        }
        c.box(style=info_inline, fn() {
          if v.people.length() > 0 {
            people_stack(c, src, "info-people", v.people, 8)
          }
          c.text(@sf.t("web-pages.workspace.people", args=[("n", v.people.length().to_string())]), style=info_words)
          |> ignore
        })
        |> ignore
      })
    }
    fact(@sf.t("web-pages.chat.info.created"), fn() {
      info_time(c, "info-created", field(field(thread, "time"), "createdAt"))
    })
    let last = field(field(field(thread, "lastMessage"), "time"), "createdAt")
    if last is Some(Object(_)) {
      fact(@sf.t("web-pages.chat.info.lastMessage"), fn() { info_time(c, "info-last", last) })
    }
  })
  |> ignore
  // who works in it, under who and when (the user, 2026-10-30: 信息和排布不是很合理): its agents
  let agents = items(chat, "agents")
  if agents.length() > 0 {
    c.box(style=info_agents, fn() {
      for a in agents {
        let av = Some(a)
        let s = field(av, "session")
        let connect = field(av, "connect")
        c.box(style=info_agent, fn() {
          c.box(style=info_agent_head, fn() {
            agent_mark(
              c,
              text(field(s, "maker"), "id"),
              text(s, "runtime"),
              text(av, "badge"),
              side=info_mark_side,
              ground=@sf.panel_ground(),
            )
            c.text(text(s, "agentText"), style=info_words) |> ignore
          })
          |> ignore
          let parts = []
          if connect is Some(Object(_)) {
            parts.push(text(connect, "name"))
          }
          parts.push(text(s, "processText"))
          parts.push(@sf.t("web-pages.chat.lastActive", args=[("time", text(field(field(s, "time"), "lastActiveAt"), "ago"))]))
          c.box(style=info_agent_line, fn() { c.text(parts.join(" · "), style=info_quiet) |> ignore }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  // the chats its agent made (after who works in it): one row, 创建了 N 个对话, each of them in the menu beside the
  // panel it opens
  if v.opened.length() > 0 {
    c.box(style=info_tools(false), fn() {
      // (beside the panel, to its left: the panel stands at the window's end; pointed at, it opens)
      @sf.submenu_row(
        c,
        "info-pop/opened/" + chat_key(r),
        v.opened_text,
        @sfpages.opened_items(v.opened, then=fn() { chat_own.info_open.set(false) }),
        icon="spawned",
        side=Left,
      )
    })
    |> ignore
  }
  // what is in it: the pull requests linked in it, the latest 3 (the user, 2026-10-29: most chats have one or two,
  // seen at a look), 全部 N 个 to the rest beside the chat, pressed, one opens in the browser; what else was said in it
  // besides words, the stations' files beside it, what its agents and other chats' wrote each other, it in Slack or
  // Feishu
  let (said, pulls) = match th {
    Some(id) => @sfpages.things_now(src, r.station, id)
    None => (0, [])
  }
  // the stations' files beside the chat, where they lend them (ChatPage.tsx onFiles: useStationDrive)
  let files = dv_stations(src, scope_of(r.station)).0.unwrap_or([]).iter().any(fn(s) { s.drive })
  if pulls.length() > 0 || said > 0 || files || v.letters > 0 {
    c.box(style=info_tools(true), fn() {
      // (beside the system's tabs, a phone's room: none of them by itself, 全部 N 个 alone, the user 2026-11-01)
      let named = if @sf.native_on() { 0 } else { info_pulls_most }
      for i, p in pulls {
        if i == named {
          break
        }
        let pv = Some(p)
        if info_pull_row(c, src, r, "info-pop/pull/" + text(pv, "key"), pv) {
          chat_own.info_open.set(false)
          let url = text(pv, "url")
          c.tell("info-pop/pull", fn() { @sfbase.open_link_in(src, url) })
        }
      }
      if pulls.length() > named &&
        info_row(c, "info-pop/pulls", "list", @sf.t("web-main.things.pullsAll", args=[("n", pulls.length().to_string())]), "") {
        chat_own.info_open.set(false)
        @sfpages.things_choose(r, "pulls")
        side_change(src, r, "open", Some("things"))
      }
      // (sfpages things.mbt)
      if said > 0 && info_row(c, "info-pop/things", "photo", @sf.t("web-main.things.title"), said.to_string()) {
        chat_own.info_open.set(false)
        side_change(src, r, "open", Some("things"))
      }
      if files && info_row(c, "info-pop/files", "folder", @sf.t("web-pages.chat.files"), "") {
        chat_own.info_open.set(false)
        side_toggle(src, r, "files")
      }
      if v.letters > 0 &&
        info_row(
          c,
          "info-pop/letters",
          "chats",
          @sf.t("web-main.letters.title"),
          @sf.t("web-main.letters.count", args=[("n", v.letters.to_string())]),
        ) {
        chat_own.info_open.set(false)
        letters_to_list(r)
        side_toggle(src, r, "letters")
      }
    })
    |> ignore
  }
  ignore(w)
}

///|
/// A time as the core says it (ui.tsx Time): how long ago, the date in its tip.
fn info_time(c : @ui.Ctx, key : String, stamp : Json?) -> Unit {
  let id = c.id(key)
  c.box(id~, taps=false, points=true, fn() { c.text(text(stamp, "ago"), style=info_words) |> ignore }) |> ignore
  @sf.tip(c, key, id, text(stamp, "full"))
}

///|
/// A row of the info (ui.tsx PanelRow): its icon (14, muted) at the panel's words' inset, as the facts' words and the
/// agents' marks over it, and words 10 apart, what is at its end muted; round with the panel, the pointer's ground on
/// it. True on the frame after a press.
fn info_row(c : @ui.Ctx, key : String, icon : String, label : String, end : String) -> Bool {
  let id = c.id(key)
  let b = c.box(style=info_tool(), id~, fn() {
    c.box(style=info_tool_icon, fn() { @sf.icon(c, icon, size=14.0, color=@sf.theme().p.muted) |> ignore }) |> ignore
    // (what it says of it at the line's end, under its words where the line has not the room: its words whole)
    c.box(style=info_label_flow, flow=true, line_gap=0.0, fn() {
      c.text(label, style=info_words) |> ignore
      if end != "" {
        c.text(end, style=info_end) |> ignore
      }
    })
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// A pull request in the info (as info_row): its mark where a row's icon is, its title cut to the line, its number at
/// the line's end, muted; pointed at, its card (as a message's link to it); held or right clicked, its menu (在对话中查看,
/// its link copied). True on the frame after a press.
fn info_pull_row(c : @ui.Ctx, src : Source, r : ChatRef, key : String, pull : Json?) -> Bool {
  let id = c.id(key)
  let title = @sfpages.pull_title(pull)
  let b = c.box(style=info_tool(), id~, fn() {
    c.box(style=info_tool_icon, fn() { @sfpages.pull_mark(c, pull, 14.0) }) |> ignore
    c.box(style=info_pull_words, fn() { c.text(title, style=info_pull_title) |> ignore }) |> ignore
    c.text("#" + count(pull, "number").to_string(), style=info_end) |> ignore
  })
  c.semantics(b, Link, id~, label=title)
  let url = text(pull, "url")
  // (at the info's left: under it, it would cover the info's rows after it; the user, 2026-10-29: 显示到左边)
  @sfpages.web_peek(c, src, r.station, url, title, id, side=Left, peek=text(pull, "peek"))
  @sfpages.thing_menu(c, id, number(pull, "seq"), url, fn(seq) {
    chat_own.info_open.set(false)
    @sfbase.go_to(r, seq)
  })
  c.clicked(id)
}

///|
/// How many pull requests the info names itself (the rest: 全部 N 个).
let info_pulls_most : Int = 3

///|
// kept across runs: a value (no field of it changes)
let info_pull_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let info_pull_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// A tool's words and what it says of it, at the line's two ends, 12 apart (one under the other where the line has
/// not the room).
// kept across runs: a value (no field of it changes)
let info_label_flow : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S3, align=ACenter, justify=JBetween)

///|
/// The bar (pageBar): 45 high, its line under it, its title's row and its buttons 16 apart.
// kept across runs: a value (no field of it changes)
let chat_bar_box : @ui.Style = @ui.style(row=true, w=@sf.grow, h=@sf.wide_bar_h_size, pb=SPx, align=ACenter, bg=Bg)

///|
/// What is in it between its rooms at its ends (page_bar_room): its title's row and its buttons 16 apart.
// kept across runs: a value (no field of it changes)
let chat_bar_inner : @ui.Style = @ui.style(row=true, w=@sf.grow, h=Full, gap=S4, align=ACenter)

///|
/// The bar with its room while the folded sidebar is shown a while (page_bar_row), moved with the block.
// kept across runs: a value (no field of it changes)
let chat_bar_row : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wide_bar_h_size)

///|
/// The same in a panel of the tape: its buttons in the panel's top right corner concentric with it (@sf.tape_bar_over,
/// as round as the panel is this frame).
fn chat_bar_box_tape() -> @ui.Style {
  chat_bar_box.then(@ui.style(h=Fixed(@sf.wide_bar_h + @sf.tape_bar_over()), pt=@sf.tape_bar_over_room()))
}

///|
fn chat_bar_row_tape() -> @ui.Style {
  chat_bar_row.then(@ui.style(h=Fixed(@sf.wide_bar_h + @sf.tape_bar_over())))
}

///|
/// Its title, its people and agents 10 apart, 8 in (pageBarTitle), 4 kept past its last for the reach of the badge at
/// an agent's corner (agent_mark.mbt: 3 past it); never narrower than what is left in it needs (Ctx::box keep), ⌘F's
/// field beside it giving way first, down to its least.
// kept across runs: a value (no field of it changes)
let chat_bar_title_row : @ui.Style = @ui.style(row=true, w=@sf.grow, pl=S2, pr=S1, gap=S2_5, align=ACenter)

///|
/// How far its title stands in from where its row starts (chat_bar_title_row's pl=S2).
let chat_bar_title_in : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let chat_title_room : @ui.Style = @ui.css("row")

///|
/// What leaves the bar's title row first, short of room: its people, then its agents but the
/// first (the last of them first).
let chat_bar_drop_people : Int = 1

///|
let chat_bar_drop_agents : Int = 2

///|
/// How wide the title may be: 42% of the bar, 80 at least.
let chat_title_least : Double = 80.0

///|
let chat_title_part : Double = 0.42

///|
/// A page's title in its bar (sidebar.css.ts pageBar h1: 14 in 600, on 20).
// kept across runs: a value (no field of it changes)
let chat_title_words : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, leading=L6, wrap=false, w=Cut)

///|
/// The station's tag (chatStation): 1 by 7 in, a line round it, round as a pill, its dot, mark and name 4 apart, 12,
/// muted (the words' ink and the strong line on hover); 160 wide at most.
// kept across runs: a value (no field of it changes)
let chat_station_tag : @ui.Style = @ui.style(
  row=true,
  max_w=@sf.chat_station_most,
  py=SPx,
  px=@sf.chat_station_in,
  gap=S1,
  align=ACenter,
  radius=Full,
  border=B1,
  border_color=Line,
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let chat_station_hot : @ui.Style = chat_station_tag.then(@ui.css("border_color=Border"))

///|
/// The tag's height (its words' 18 line, 1 over and under) and its dot's side (via_direct's S2): its dot in its round
/// end (chat_station).
let chat_station_h : Double = 20.0

///|
let via_dot_side : Double = 8.0

///|
/// How far in from the tag's edge its dot stands: concentric with its round end (@sf.capsule_in; the line round it is
/// drawn over its padding, not in it).
let chat_station_dot_in : Double = @sf.capsule_in(chat_station_h / 2.0, via_dot_side, room=chat_station_h / 2.0)

///|
// kept across runs: a value (no field of it changes)
let chat_station_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let chat_station_words_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// A station's mark in the bar (12).
let chat_station_mark : Double = 12.0

///|
/// How a station is reached, a dot 7 across (StationLink.css.ts dot): green, amber, red, grey.
// kept across runs: a value (no field of it changes)
let via_direct : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Positive")

///|
// kept across runs: a value (no field of it changes)
let via_relay : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
// kept across runs: a value (no field of it changes)
let via_offline : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Danger")

///|
// kept across runs: a value (no field of it changes)
let via_waiting : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Muted")

///|
/// The same on a tile's corner (cornerDot): 10 across, ringed 2 in the page's ground, 3 past its edges.
fn corner_dot_of(via : String) -> @ui.Style {
  match via {
    "direct" => corner_direct
    "relay" => corner_relay
    "offline" => corner_offline
    _ => corner_waiting
  }
}

///|
// kept across runs: a value (no field of it changes)
let corner_direct : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Positive border=B2 border_color=Bg")

///|
// kept across runs: a value (no field of it changes)
let corner_relay : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Warn border=B2 border_color=Bg")

///|
// kept across runs: a value (no field of it changes)
let corner_offline : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Danger border=B2 border_color=Bg")

///|
// kept across runs: a value (no field of it changes)
let corner_waiting : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Muted border=B2 border_color=Bg")

///|
/// People in a stack (peopleStack): each 16 across, each 4 over the one before; +n after them, 11 muted.
let person_side : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let people_row : @ui.Style = @ui.css("row align=ACenter")

///|
/// Each 16, ringed 1.5 (a 19 circle), the first's face where the stack starts, each 4 over the one before.
// kept across runs: a value (no field of it changes)
let people_ring : @ui.Style = @ui.style(w=@sf.person_ringed, h=@sf.person_ringed, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let person_first : @ui.Style = @sf.outset_start(1.5)

///|
// kept across runs: a value (no field of it changes)
let person_next : @ui.Style = @sf.overlap(7.0)

///|
// kept across runs: a value (no field of it changes)
let people_letter_box : @ui.Style = @ui.css("w=S4 h=S4 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let people_letter : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false, leading=L3)

///|
/// Their initial, upper case.
fn person_initial(name : String) -> String {
  match name.iter().next() {
    Some(ch) => ch.to_string().to_upper()
    None => "?"
  }
}

///|
// kept across runs: a value (no field of it changes)
let people_more : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let people_more_box : @ui.Style = @ui.css("pl=S1_5")

///|
/// An agent's mark in the bar (agentMarkBtn), round 6; an accent ring 2 round it while its history shows (among
/// several); with its station one tile (agentStation): the maker's square (the pointer's ground on hover) and the
/// station's part (its mark, or its name 140 at most, in by .19 of the tile and 1), the dot on the tile's corner.
// kept across runs: a value (no field of it changes)
let agent_mark_btn : @ui.Style = @ui.css("radius=Md")

///|
// kept across runs: a value (no field of it changes)
let agent_mark_btn_on : @ui.Style = @ui.css("radius=Md border=B2 border_color=Accent")

///|
// kept across runs: a value (no field of it changes)
let agent_station : @ui.Style = @ui.css("row h=S5 radius=Md bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let agent_station_on : @ui.Style = agent_station.then(@ui.css("border=B2 border_color=Accent"))

///|
/// The tile's corner (radius=Md's, 6): the two parts' outer ends are round by it, where they meet square (ui.css.ts
/// agentMarkJoined: the hover's ground meets the other part at a straight edge, not a notch).
let agent_station_round : Double = 6.0

///|
let agent_station_seam : Double = 0.0

///|
// kept across runs: a value (no field of it changes)
let agent_station_agent : @ui.Style = @ui.style(
  w=S5,
  h=S5,
  // det-ok(corners-each): one tile of two parts; only its outer ends are round, where they meet square (the user, 2026-10-27)
  radius=Corners(
    agent_station_round, agent_station_seam, agent_station_seam, agent_station_round,
  ),
)

///|
// kept across runs: a value (no field of it changes)
let agent_station_agent_hot : @ui.Style = agent_station_agent.then(
  @ui.css("bg=Hover"),
)

///|
// kept across runs: a value (no field of it changes)
let agent_station_part : @ui.Style = @ui.style(
  row=true,
  h=S5,
  max_w=@sf.agent_station_most,
  px=@sf.agent_station_in,
  align=ACenter,
  // det-ok(corners-each): the tile's other part, square where it meets the agent's (agent_station_agent)
  radius=Corners(
    agent_station_seam, agent_station_round, agent_station_round, agent_station_seam,
  ),
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let agent_station_part_hot : @ui.Style = agent_station_part.then(@ui.css("bg=Hover"))

///|
/// The agent's card in the tile's whole (with touch, held): as a card of its own holds it, 10 in from the panel's
/// padding (the hover's padded), the station's card under it at the padding, its rows there.
// kept across runs: a value (no field of it changes)
let tile_card_agent : @ui.Style = @ui.css("w=Full p=S2_5")

///|
/// The dot on the tile's bottom right corner, 3 past it.
// kept across runs: a value (no field of it changes)
let agent_station_dot_room : @ui.Style = @ui.css("w=Full h=Full align=AEnd justify=JEnd").then(@sf.oversize(3.0))

///|
/// The services' button's dot (jobsTrigger ::after): 7 across, 6 in from its top right, ringed 2 in the page's ground.
// kept across runs: a value (no field of it changes)
let jobs_alarm_room : @ui.Style = @ui.css("w=S8 h=S8 pt=S1 pr=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let jobs_alarm_fail : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Danger border=B2 border_color=Bg")

///|
// kept across runs: a value (no field of it changes)
let jobs_alarm_restart : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full bg=Warn border=B2 border_color=Bg")

///|
/// The info's facts (detailRow): what it is muted in a 6em column, 12 apart; 13; at the panel's words' inset. A fact
/// 28 high and 6 apart, as far from the next as the rows under them are (32 and 2: pengxiao, 2026-10-25, the panel's
/// rows unevenly apart).
// kept across runs: a value (no field of it changes)
let info_facts : @ui.Style = @ui.css("w=Full px=S2_5 gap=S1_5")

///|
let info_fact_h : Double = 28.0

///|
// kept across runs: a value (no field of it changes)
let info_fact : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(info_fact_h), gap=S3, align=ACenter)

///|
/// Its labels' column at least (the web's 80).
let info_label_w : Double = 80.0

///|
// kept across runs: a value (no field of it changes)
let info_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// A chat named in the info (the one whose agent made it) pointed at: its words in the accent.
// kept across runs: a value (no field of it changes)
let info_words_hot : @ui.TextStyle = @ui.text_style(size=Ui, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_muted : @ui.TextStyle = @ui.text_style(size=Ui, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_quiet : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_end : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_inline : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its agents (detailsList): 8 under the facts, each its mark and label over its line, 2 apart.
// kept across runs: a value (no field of it changes)
let info_agents : @ui.Style = @ui.css("w=Full px=S2_5 pt=S2 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let info_agent : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// An agent's mark and label: the mark where the rows' icons stand under it, its label where their words do (14 and
/// 10 apart: info_row), its line under its label (pengxiao, 2026-10-25: their edges out of line).
// kept across runs: a value (no field of it changes)
let info_agent_head : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// (the mark as wide as the rows' icons' column, its line as far in as its label: info_agent_line)
let info_mark_side : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let info_agent_line : @ui.Style = @ui.css("w=Full pl=S6")

///|
/// A group of its rows (infoTools, PanelRow): 16 under what is over it, as far as sets the groups apart without a
/// line, its rows 2 apart; a row a small panel's (@sf.pick_high: in its foot corners concentric with them, as a menu's
/// item is), its icon's 14 column and words 10 apart, 10 in, round with the panel, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let info_tools_base : @ui.Style = @ui.css("w=Full pt=S4 gap=S0_5")

///|
/// (`last` in the panel: its last row, a capsule with keyboard and mouse, in the panel's foot corners as far in as
/// makes it concentric with them, @sf.pick_reach)
fn info_tools(last : Bool) -> @ui.Style {
  // (beside the system's tabs, a phone's room: the groups nearer, the user 2026-11-01, 收紧内容)
  let base = if @sf.native_on() { info_tools_near } else { info_tools_base }
  if last {
    base.then(@ui.style(mb=@sf.room_of(-@sf.menu_row_reach(@sf.theme().rows.pick))))
  } else {
    base
  }
}

///|
/// A group of its rows beside the system's tabs (info_tools): 4 under what is over it, its rows as tall as a finger's
/// keeping them apart enough.
// kept across runs: a value (no field of it changes)
let info_tools_near : @ui.Style = @ui.css("w=Full pt=S1 gap=S0_5")

///|
fn info_tool() -> @ui.Style {
  info_tool_base.then(@sf.pick_high()).then(@sf.pick_reach())
}

///|
// kept across runs: a value (no field of it changes)
let info_tool_base : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2_5 align=ACenter radius=Inner hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let info_tool_icon : @ui.Style = @ui.css("w=S3_5 align=ACenter")


///|
/// A chat's people each on a line of their own in its info (beside the system's tabs: chat_info).
// kept across runs: a value (no field of it changes)
let info_people_list : @ui.Style = @ui.css("gap=S1_5")

///|
/// The window's width as the chat's bar's popovers were last drawn (bar_popovers: a turn closes them).
