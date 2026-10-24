// A chat on the desktop (ember web/src/pages/ChatPage.tsx, ChatPage.css.ts; styles/sidebar.css.ts pageBar,
// conversation.css.ts pageBarTitle): its side panel beside it (panel.mbt), its bar over its messages: its title (while a
// new one goes, that one with a turning ring), its station's update, the station while no agent is in it, its people,
// its agents (each its history beside the chat, its card on hover); at its end 归档 while nothing is left in it, its
// services and jobs (a popover: jobs.mbt), 对话信息 (a popover), the panel's switch while the panel is closed; ⌘F's bar
// in place of those while it is open (find.mbt). Its messages and its composer are still sfapp's (Pages.talk).

///|
/// What the chat's page keeps of its own (the rest is the core's): its info's popover open, its services' popover
/// open, archiving it asked to confirm (its key, "" none: one keeping watch).
priv struct ChatOwn {
  mut info_open : Bool
  mut jobs_open : Bool
  mut archive_asking : String
}

///|
let chat_own : ChatOwn = { info_open: false, jobs_open: false, archive_asking: "" }

///|
fn chat_page_reset() -> Unit {
  chat_own.info_open = false
  chat_own.jobs_open = false
  chat_own.archive_asking = ""
}

///|
/// The chat's services' popover opened or closed (its keys, ⌘K's 服务和后台任务).
pub fn toggle_jobs_pop() -> Unit {
  chat_own.jobs_open = !chat_own.jobs_open
}

///|
pub fn open_jobs_pop() -> Unit {
  chat_own.jobs_open = true
}

///|
/// Its info's popover open (a screen's fixture).
pub fn open_info_pop() -> Unit {
  chat_own.info_open = true
}

///|
/// ⌘F's bar opened in chat `r`: what opens under the bar closed.
pub fn chat_find_open(c : @ui.Ctx, r : ChatRef) -> Unit {
  chat_own.info_open = false
  chat_own.jobs_open = false
  find_open(c, chat_key(r))
}

///|
/// The chat `r` in the pane (ChatPage.tsx ChatScreen).
fn chat_page(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, pages : Pages) -> Unit {
  let chat = (src.topic)("chat", chat_params(r)).value
  let view = match chat {
    Some(v) => Some(chat_view(v))
    None => None
  }
  let key = chat_key(r)
  let list = (pages.find_list)(r)
  // ⌘F: the chat's own find; another chat's let go
  if find_chat() != "" && find_chat() != key {
    (list.forget)()
  }
  let prefs = (src.topic)("prefs", {}).value
  match view {
    Some(v) => {
      if @settings.action_pressed(c, prefs, "chat.find") && v.thread is Some(_) {
        chat_find_open(c, r)
      }
      chat_keys(c, src, w, r, v, chat, pages)
    }
    None => ()
  }
  c.box(style=chat_ground, fn() {
    with_side(c, src, w, r, view, fn() {
      c.box(style=side_panel_style, id=c.id("chat/pane"), fn() {
        (pages.talk)(c, src, w, r, fn() {
          c.layer(fn() { chat_bar(c, src, w, r, view, chat, list, pages) }) |> ignore
          match view {
            Some(v) => bar_popovers(c, src, w, r, v, chat, pages)
            None => ()
          }
        })
      })
      |> ignore
    })
  })
  |> ignore
  // the new chat it became leaving over it, or one left for it fading over it (newchat.mbt)
  new_chat_after(c, src, w, pages, r)
}

///|
/// The pane's ground under a chat.
// kept across runs: a value (no field of it changes)
let chat_ground : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// The chat's own keys (keymap.ts, ChatPage.tsx useShortcut): ⌘⇧E into the archive while nothing is left in it, ⌘⇧H
/// its first agent's history beside it (one in front: the panel closed), ⌘. its agents at work stopped.
fn chat_keys(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?, pages : Pages) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  if @settings.action_pressed(c, prefs, "chat.archive", in_field=true) && !v.archived && !v.offline {
    c.tell("chat/archive", fn() { archive_asked(src, w, r, v, chat, pages) })
  }
  // an agent's history in front: the panel closed; else the first agent's open, or the first agent's opened
  if @settings.action_pressed(c, prefs, "chat.history", in_field=true) && v.agents.length() > 0 {
    let (tabs, front) = side_of(v)
    let agent = fn(t : String) { v.agents.iter().any(fn(a) { a.key == t }) }
    if agent(front) {
      side_change(src, r, "clear", None)
    } else {
      side_change(src, r, "open", Some(tabs.iter().find_first(agent).unwrap_or(v.agents[0].key)))
    }
  }
  if @settings.action_pressed(c, prefs, "chat.stop", in_field=true) {
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
}

///|
/// Into the archive, asked first where the chat keeps watch (its watch runs on in the archive: the core's words).
fn archive_asked(src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?, pages : Pages) -> Unit {
  if field(chat, "watch") is Some(Object(_)) {
    chat_own.archive_asking = chat_key(r)
  } else {
    archive(src, w, r, v, pages)
  }
}

///|
/// The chat into the archive (ChatPage.tsx archive): on to the chat below it in the list (or above, at the end), so
/// the keys go on working, the list if none; said once it is done, or why not.
fn archive(src : Source, w : Workspace, r : ChatRef, v : ChatView, pages : Pages) -> Unit {
  let here = fn() {
    match app.nav.top() {
      Chat(t) => t.station == r.station && t.session == r.session
      _ => false
    }
  }
  neighbour(src, w, pages, 1)
  if here() {
    neighbour(src, w, pages, -1)
  }
  if here() {
    app.nav.pop() |> ignore
    wide.landed = ""
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
  (src.call)("chat.archive", Json::object(p), fn(res) {
    match res {
      Ok(_) => toast_later(@sf.t("web-pages.chat.archived"))
      Err(e) => toast_later(@sf.t("web-pages.chat.archiveFailed", args=[("error", error_words(e))]))
    }
  })
}

///|
/// The chat's bar (ChatPage.tsx header, sidebar.css.ts pageBar: 45 high, its line at its foot): the title, its station's
/// update, its station while no agent is in it, its people, its agents; at its end what is done with it, or ⌘F's bar.
fn chat_bar(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
  v : ChatView?,
  chat : Json?,
  list : FindList,
  pages : Pages,
) -> Unit {
  // the workspace's stations, as the bar shows the chat's (its tag, its first agent's tile)
  let station = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
    .iter()
    .find_first(fn(x) { x.address == r.station })
  let bar = c.id("chat-bar")
  // the bar's empty part drags the window (in one with its buttons in the app's top row)
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  // (beside the rail its room as the block moves: page_bar_room)
  let (room_l, room_r, ml, mr) = page_bar_room()
  let room = fn(x : Double) { c.box(style=@ui.style(w=Fixed(x), h=Full), fn() {  }) |> ignore }
  c.box(style=chat_bar_row, moves="page-bar", fn() {
  room(ml)
  c.box(style=chat_bar_box, id=bar, fn() {
      room(room_l)
      // the title, its people and agents 10 apart, 8 in from the bar's padding (conversation.css.ts pageBarTitle)
      c.box(style=chat_bar_title_row, fn() {
        chat_title(c, src, r, v)
        match v {
          Some(view) => {
            station_update(c, src, r.station, view.station_update)
            if view.agents.length() == 0 {
              chat_station(c, r.station, station)
            }
            if view.people.length() > 0 {
              people_stack(c, src, "bar-people", view.people, 5)
            }
            let (_, front) = side_of(view)
            for i, a in view.agents {
              agent_tile(c, src, r, a, view.agents.length() > 1 && front == a.key, if i == 0 { station } else { None })
            }
          }
          None => ()
        }
      })
      |> ignore
      match v {
        // ⌘F's bar, in place of the buttons while it is open: it covers none of the chat
        Some(view) if find_chat() == chat_key(r) && view.thread is Some(th) => find_bar(c, src, r, th, list)
        Some(view) =>
          c.box(style=chat_bar_buttons, fn() {
            // nothing left in it (the core's `archivable`): archived with one press
            if view.archivable && !view.archived {
              if icon_button(c, "chat-archive", "archive", label=@sf.t("web-pages.chat.archive"), action="chat.archive") {
                c.tell("chat/archive", fn() { archive_asked(src, w, r, view, chat, pages) })
              }
            }
            jobs_trigger(c, src, r)
            if view.thread is Some(_) && icon_button(c, "chat-more", "more", label=@sf.t("web-pages.chat.info")) {
              chat_own.info_open = !chat_own.info_open
            }
            // the side panel's switch while it is closed: the first agent's history in it
            if side_of(view).0.length() == 0 &&
              view.agents.length() > 0 &&
              icon_button(c, "chat-panel", "panel-open", label=@sf.t("web-pages.chat.openPanel"), action="chat.history") {
              side_change(src, r, "open", Some(view.agents[0].key))
            }
          })
          |> ignore
        None => ()
      }
      room(room_r)
  })
  |> ignore
  room(mr)
  })
  |> ignore
  // a chat keeping watch, archived once asked (the core's words)
  let asked = @sf.confirm(
    c,
    "archive-confirm/" + chat_key(r),
    chat_own.archive_asking == chat_key(r),
    @sf.t("web-pages.chat.archiveConfirm", args=[("title", match v { Some(view) => view.title; None => r.title })]),
    text(field(chat, "watch"), "ask"),
    @sf.t("web-pages.chat.archive"),
    cancel=@sf.t("common.cancel"),
  )
  if asked.confirmed {
    chat_own.archive_asking = ""
    match v {
      // (once the frame's builds are over)
      Some(view) => c.tell("chat/archive", fn() { archive(src, w, r, view, pages) })
      None => ()
    }
  } else if chat_own.archive_asking == chat_key(r) && !asked.open {
    chat_own.archive_asking = ""
  }
}

///|
/// The chat's name in its bar (ChatTitle): while a new one goes (`chat.rename`), that one, a turning ring beside it; its
/// own again if it did not, a red mark there a few seconds saying why.
fn chat_title(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView?) -> Unit {
  let on = [("station", r.station), ("session", r.session)]
  let mut renaming = ""
  for d in items((src.topic)("doing", {}).value, "doing") {
    let dv = Some(d)
    if text(dv, "call") == "chat.rename" &&
      text(dv, "stage") != "failed" &&
      on.iter().all(fn(kv) { text(field(dv, "params"), kv.0) == kv.1 }) {
      renaming = text(field(dv, "params"), "title")
    }
  }
  let title = if renaming != "" {
    renaming
  } else {
    match v {
      Some(view) => view.title
      None => r.title
    }
  }
  // (42% of the bar at most, 80 at least)
  let most = dmax(chat_title_least, c.width * chat_title_part)
  c.box(style=chat_title_room.then(@ui.style(max_w=Fixed(most))), fn() {
    c.text(title, style=chat_title_words) |> ignore
  })
  |> ignore
  let failed = core_failed(src, ["chat.rename"], on)
  if renaming != "" || failed is Some(_) {
    let id = c.id("chat-title/doing")
    c.box(id~, taps=false, fn() { @settings.doing_mark(c, renaming != "", failed) }) |> ignore
    @sf.tip(c, "chat-title/doing", id, match failed {
      Some(why) => why
      None => @sf.t("web-pages.settings.stations.renaming")
    })
  }
}

///|
/// The machine the chat runs on, beside its title while it has no agent to share a tile with (ChatStation): how it is
/// reached a dot before it, its mark, its name, a quiet tag; pressed, its card.
fn chat_station(c : @ui.Ctx, station : String, s : Station?) -> Unit {
  guard s is Some(s) else { return }
  let id = c.id("bar-station")
  c.cursor(id, Hand)
  if c.clicked(id) {
    @settings.open_station_peek(station)
  }
  let hot = c.lit(id)
  c.box(style=if hot { chat_station_hot } else { chat_station_tag }, id~, label=s.name, fn() {
    if s.via != "" {
      via_dot(c, s.via)
    }
    if @sf.has_station_mark(s.emoji, s.icon) {
      @sf.station_mark(c, s.emoji, s.icon, chat_station_mark, if hot { @sf.theme().p.text } else { @sf.theme().p.muted })
    }
    c.text(s.name, style=if hot { chat_station_words_hot } else { chat_station_words }) |> ignore
  })
  |> ignore
}

///|
/// How a station is reached, as a dot (StationLink.css.ts dot): straight there green, through a relay amber, away red,
/// else a grey ring.
fn via_dot(c : @ui.Ctx, via : String) -> Unit {
  c.box(
    style=match via {
      "direct" => via_direct
      "relay" => via_relay
      "offline" => via_offline
      _ => via_waiting
    },
    fn() {  },
  )
  |> ignore
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
/// One of the chat's agents in the bar (AgentTile): its mark (20), pressed its history's tab opens (in front, closes);
/// its card on hover; marked among several while its history shows. The chat's first, one tile with the station it runs
/// on (its mark, or its name kept short), how the station is reached a dot on the tile's corner.
fn agent_tile(c : @ui.Ctx, src : Source, r : ChatRef, a : Agent, marked : Bool, station : Station?) -> Unit {
  let id = c.id("bar-agent/" + a.key)
  c.cursor(id, Hand)
  if c.clicked(id) {
    side_toggle(src, r, a.key)
  }
  let chat = (src.topic)("chat", chat_params(r)).value
  let aj = agent_json(chat, a.key)
  let said = @sf.t("web-pages.chat.historyOf", args=[("agent", a.who)])
  let hot = c.lit(id)
  match station {
    Some(s) =>
      c.box(style=if marked { agent_station_on } else { agent_station }, fn() {
        let b = c.box(style=if hot { agent_station_agent_hot } else { agent_station_agent }, id~, fn() {
          agent_mark(c, a.maker, a.runtime, a.badge, said=text(field(aj, "session"), "badgeText"))
        })
        c.semantics(b, Button, id~, label=said)
        let part = c.id("bar-agent-station/" + a.key)
        let part_hot = c.lit(part)
        c.box(style=if part_hot { agent_station_part_hot } else { agent_station_part }, id=part, label=s.name, fn() {
          if @sf.has_station_mark(s.emoji, s.icon) {
            @sf.station_mark(c, s.emoji, s.icon, chat_station_mark, if part_hot {
              @sf.theme().p.text
            } else {
              @sf.theme().p.muted
            })
          } else {
            c.text(s.name, style=if part_hot { chat_station_words_hot } else { chat_station_words }) |> ignore
          }
        })
        |> ignore
        @sf.tip(c, "bar-agent-station/" + a.key, part, s.name)
        if s.via != "" {
          c.layer(fn() {
            c.box(style=agent_station_dot_room, fn() { c.box(style=corner_dot_of(s.via), fn() {  }) |> ignore })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    None => {
      let b = c.box(style=if marked { agent_mark_btn_on } else { agent_mark_btn }, id~, fn() {
        agent_mark(c, a.maker, a.runtime, a.badge, said=text(field(aj, "session"), "badgeText"))
      })
      c.semantics(b, Button, id~, label=said)
    }
  }
  // the pointer resting on it: its card (AgentCard.tsx)
  hover(c, "agent-hover/" + a.key, id, tile=true, fn() {
    match aj {
      Some(j) => agent_card(c, src, r.station, j)
      None => ()
    }
  })
  |> ignore
}

///|
/// The chat's services and jobs' button (JobsPanel): none, nothing in the bar; a dot on it red while one died lately,
/// amber while a service restarts.
fn jobs_trigger(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let view = (src.topic)("chatJobs", chat_params(r)).value
  if items(view, "jobs").length() == 0 {
    return
  }
  if icon_button(c, "chat-jobs", "web", label=@sf.t("web-pages.chat.services"), action="chat.jobs") {
    chat_own.jobs_open = !chat_own.jobs_open
  }
  match text(view, "alarm") {
    "" => ()
    alarm =>
      c.layer(fn() {
        c.box(style=jobs_alarm_room, fn() {
          c.box(style=if alarm == "fail" { jobs_alarm_fail } else { jobs_alarm_restart }, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// What opens under the chat's bar: its info's popover (ChatInfo) and its services' (JobsPanel), each by its button.
fn bar_popovers(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?, pages : Pages) -> Unit {
  let info = @kit.popover(
    c,
    "chat-info-pop",
    chat_own.info_open,
    c.id("chat-more"),
    side=Bottom,
    along=End,
    look=fn(c, _, body) { @sf.panel(c, w=@ui.Size::Px(chat_info_w), body) |> ignore },
    fn() { chat_info(c, src, w, r, v, chat, pages) },
  )
  // (closed by what was pressed in it, or as a popover closes: Escape, a press outside)
  chat_own.info_open = chat_own.info_open && info.value
  let jobs = @kit.popover(
    c,
    "chat-jobs-pop",
    chat_own.jobs_open,
    c.id("chat-jobs"),
    side=Bottom,
    along=End,
    look=fn(c, _, body) { @sf.panel(c, w=@ui.Size::Px(jobs_pop_w), body) |> ignore },
    fn() {
      let open = fn(id : String) {
        chat_own.jobs_open = false
        if id != "" {
          pick_job(id)
        }
        side_change(src, r, "open", Some("jobs"))
      }
      // (a service's own tab is not here yet: it opens in 任务 too)
      jobs_popover(c, src, r.station, (src.topic)("chatJobs", chat_params(r)).value, open, open)
    },
  )
  chat_own.jobs_open = chat_own.jobs_open && jobs.value
}

///|
/// How wide the info's popover and the services' are (ChatPage.css.ts chatInfo, jobsPanel).
let chat_info_w : Double = 320.0

///|
let jobs_pop_w : Double = 360.0

///|
/// What the chat's info says (ChatInfoBody): where it came from, who started it, who takes part, when it was made and
/// last written in; its agents (AgentLine); then what is done with it: the stations' files beside it, what its agents
/// and other chats' wrote each other, relaying it, it in Slack or Feishu; sharing it, publishing it.
fn chat_info(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView, chat : Json?, pages : Pages) -> Unit {
  let thread = field(chat, "thread")
  let th = opt_number(thread, "id")
  guard th is Some(id) else { return }
  let fact = fn(label : String, value : () -> Unit) {
    c.box(style=info_fact, fn() {
      c.box(style=info_fact_label, fn() { c.text(label, style=info_muted) |> ignore }) |> ignore
      value()
    })
    |> ignore
  }
  c.box(style=info_facts, fn() {
    fact(@sf.t("web-pages.chat.info.from"), fn() {
      match text(chat, "place") {
        "" => c.text(@sf.t("web-pages.chat.info.native", args=[("name", "still.fail")]), style=info_words) |> ignore
        place => {
          let feishu = text(thread, "surface").has_prefix("feishu:")
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
        }
      }
    })
    let creator = match text(field(field(thread, "creator"), "shown"), "display") {
      "" => text(field(thread, "creator"), "name")
      d => d
    }
    fact(@sf.t("web-pages.chat.info.started"), fn() {
      if creator == "" {
        c.text(@sf.t("web-pages.chat.info.unknown"), style=info_muted) |> ignore
      } else {
        c.text(creator, style=info_words) |> ignore
      }
    })
    fact(@sf.t("web-pages.chat.info.people"), fn() {
      c.box(style=info_inline, fn() {
        if v.people.length() > 0 {
          people_stack(c, src, "info-people", v.people, 8)
        }
        c.text(@sf.t("web-pages.workspace.people", args=[("n", v.people.length().to_string())]), style=info_words)
        |> ignore
      })
      |> ignore
    })
    fact(@sf.t("web-pages.chat.info.created"), fn() {
      info_time(c, "info-created", field(field(thread, "time"), "createdAt"))
    })
    let last = field(field(field(thread, "lastMessage"), "time"), "createdAt")
    if last is Some(Object(_)) {
      fact(@sf.t("web-pages.chat.info.lastMessage"), fn() { info_time(c, "info-last", last) })
    }
  })
  |> ignore
  let agents = items(chat, "agents")
  if agents.length() > 0 {
    c.box(style=info_agents, fn() {
      for a in agents {
        let av = Some(a)
        let s = field(av, "session")
        let connect = field(av, "connect")
        c.box(style=info_agent, fn() {
          c.box(style=info_inline, fn() {
            agent_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), text(av, "badge"), side=14.0)
            c.text(text(s, "agentText"), style=info_words) |> ignore
          })
          |> ignore
          let parts = []
          if connect is Some(Object(_)) {
            parts.push(text(connect, "name"))
          }
          parts.push(text(s, "processText"))
          parts.push(@sf.t("web-pages.chat.lastActive", args=[("time", text(field(field(s, "time"), "lastActiveAt"), "ago"))]))
          c.text(parts.join(" · "), style=info_quiet) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  // the stations' files beside the chat, where they lend them (ChatPage.tsx onFiles: useStationDrive)
  let files = dv_stations(src, scope_of(r.station)).0.unwrap_or([]).iter().any(fn(s) { s.drive })
  let relayable = !v.archived && !v.offline && v.agents.length() > 0
  let slack = text(chat, "slackUrl")
  let feishu = text(chat, "feishuUrl")
  if files || v.letters > 0 || relayable || slack != "" || feishu != "" {
    c.box(style=info_tools, fn() {
      if files && info_row(c, "info-pop/files", "folder", @sf.t("web-pages.chat.files"), "") {
        chat_own.info_open = false
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
        chat_own.info_open = false
        letters_to_list(r)
        side_toggle(src, r, "letters")
      }
      if relayable && info_row(c, "info-pop/relay", "arrow-up-right", @sf.t("web-main.relay.action"), "") {
        chat_own.info_open = false
        (pages.relay)(c, src, r, id)
      }
      if slack != "" && info_row(c, "info-pop/slack", "external", @sf.t("web-pages.chat.openInSlack"), "") {
        chat_own.info_open = false
        @ui.open_url(slack) |> ignore
      }
      if feishu != "" && info_row(c, "info-pop/feishu", "external", @sf.t("web-pages.chat.openInFeishu"), "") {
        chat_own.info_open = false
        @ui.open_url(feishu) |> ignore
      }
    })
    |> ignore
  }
  let share = field(chat, "xshare")
  let publish = match field(chat, "publish") {
    Some(Object(_)) as p if flag(p, "may") || items(p, "links").length() > 0 => p
    _ => None
  }
  if share is Some(Object(_)) || publish is Some(_) {
    c.box(style=info_tools, fn() {
      if share is Some(Object(_)) &&
        info_row(c, "info-pop/xshare", "users", @sf.t("web-pages.chat.xshare"), text(share, "text")) &&
        flag(share, "may") {
        chat_own.info_open = false
        (pages.share)(c, r, Some(id))
      }
      if publish is Some(_) && info_row(c, "info-pop/publish", "web", @sf.t("web-pages.chat.publish"), "") && flag(publish, "may") {
        chat_own.info_open = false
        (pages.publish)(c, r.station, id)
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
  c.box(id~, taps=false, fn() { c.text(text(stamp, "ago"), style=info_words) |> ignore }) |> ignore
  @sf.tip(c, key, id, text(stamp, "full"))
}

///|
/// A row of the info (ui.tsx PanelRow): its icon in a 20 column (14, muted) and words 10 apart, what is at its end
/// muted; round with the panel, the pointer's ground on it. True on the frame after a press.
fn info_row(c : @ui.Ctx, key : String, icon : String, label : String, end : String) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=info_tool, id~, fn() {
    c.box(style=info_tool_icon, fn() { @sf.icon(c, icon, size=14.0, color=@sf.theme().p.muted) |> ignore }) |> ignore
    c.box(style=info_grow, fn() { c.text(label, style=info_words) |> ignore }) |> ignore
    if end != "" {
      c.text(end, style=info_end) |> ignore
    }
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// The bar (pageBar): 45 high, its line under it, its title's row and its buttons 16 apart.
// kept across runs: a value (no field of it changes)
let chat_bar_box : @ui.Style = @ui.style(row=true, w=@sf.grow, h=@sf.wide_bar_h_size, pb=SPx, gap=S4, align=ACenter, bg=Bg)

///|
/// The bar with its margins while the folded sidebar is shown a while (page_bar_room), moved with the block.
// kept across runs: a value (no field of it changes)
let chat_bar_row : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wide_bar_h_size)

///|
/// Its title, its people and agents 10 apart, 8 in (pageBarTitle).
// kept across runs: a value (no field of it changes)
let chat_bar_title_row : @ui.Style = @ui.style(row=true, w=@sf.grow, pl=S2, gap=S2_5, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let chat_title_room : @ui.Style = @ui.css("row")

///|
/// How wide the title may be: 42% of the bar, 80 at least.
let chat_title_least : Double = 80.0

///|
let chat_title_part : Double = 0.42

///|
/// A page's title in its bar (sidebar.css.ts pageBar h1: 14 in 600, on 20).
// kept across runs: a value (no field of it changes)
let chat_title_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, leading=L6, wrap=false, w=Cut)

///|
/// What is done in its bar, at its end, 2 apart (pageBarActions).
// kept across runs: a value (no field of it changes)
let chat_bar_buttons : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

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
// kept across runs: a value (no field of it changes)
let chat_station_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let chat_station_words_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// A station's mark in the bar (12).
let chat_station_mark : Double = 12.0

///|
/// How a station is reached, a dot 7 across (StationLink.css.ts dot): green, amber, red, a grey ring.
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
let via_waiting : @ui.Style = @ui.css("w=S2 h=S2 radius=Full border=B1 border_color=Muted")

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
let people_letter : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=Fg, wrap=false, leading=L3)

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
let people_more : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

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
// kept across runs: a value (no field of it changes)
let agent_station_agent : @ui.Style = @ui.css("w=S5 h=S5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let agent_station_agent_hot : @ui.Style = @ui.css("w=S5 h=S5 radius=Md bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let agent_station_part : @ui.Style = @ui.style(
  row=true,
  h=S5,
  max_w=@sf.agent_station_most,
  px=@sf.agent_station_in,
  align=ACenter,
  radius=Md,
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let agent_station_part_hot : @ui.Style = agent_station_part.then(@ui.css("bg=Hover"))

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
/// The info's facts (detailRow): what it is muted in a 6em column, 12 apart; 13; at the panel's words' inset.
// kept across runs: a value (no field of it changes)
let info_facts : @ui.Style = @ui.css("w=Full px=S2_5 pt=S2_5 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let info_fact : @ui.Style = @ui.css("row w=Full min_h=S6 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let info_fact_label : @ui.Style = @ui.css("w=S20")

///|
// kept across runs: a value (no field of it changes)
let info_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_muted : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let info_end : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

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
/// What is done with it (infoTools, PanelRow): 8 under what is over it, 2 apart; a row 32 high at least, its icon's
/// 20 column and words 10 apart, 10 in, round with the panel, the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let info_tools : @ui.Style = @ui.css("w=Full pt=S2 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let info_tool : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2_5 align=ACenter radius=Inner hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let info_tool_icon : @ui.Style = @ui.css("w=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let info_grow : @ui.Style = @ui.style(w=@sf.grow)
