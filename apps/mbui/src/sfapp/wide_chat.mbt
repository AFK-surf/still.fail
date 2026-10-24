// A chat in the wide frame's pane (ember web/src/pages/ChatPage.tsx, styles/sidebar.css.ts pageBar, session.css.ts,
// dock.css.ts): its bar (45 high, the title 14 in 600, who is in it, its agents; at its end 归档 while nothing is left
// in it, its services and jobs, its info), the messages in a column 760 wide at most in the middle of the pane (the
// phone's rows: chat.mbt), the composer at its foot, 804 at most. What the phone's chat page does (reading, following
// its end, the way to the newest, telling the core what shows) is the same page's.

///|
/// The column the messages keep to (later.css.ts: 760), and the least room at its sides (session.css.ts: 40).
let column_w : Double = 760.0

///|
/// A page's bar in the wide frame (styles/sidebar.css.ts pageBar: 45, its 1 at the foot).
let wide_bar_h : Double = 45.0

///|
/// What a chat's rows stand in from the pane's sides: 14 on a phone; in the wide frame, the column in the middle.
fn row_side(c : @ui.Ctx) -> Double {
  if wide_on.val {
    dmax(40.0, (c.width - column_w) / 2.0)
  } else {
    14.0
  }
}

///|
/// The chat's page in the pane.
fn wide_chat_page(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  let t = @sf.theme()
  let (view, list, error) = view_of_chat(src, r)
  if focus_composer.val {
    focus_composer.val = false
    c.focus_editor(field_key)
  }
  // ⌘F: the chat's own find (wide_find.mbt); another chat, its own
  if wide.find_chat != "" && wide.find_chat != side_key(r) {
    find_forget()
  }
  if @settings.action_pressed(c, (src.topic)("prefs", {}).value, "chat.find") && view is Some(v) && v.thread is Some(_) {
    find_open(c, r)
  }
  match view {
    Some(v) => chat_keys(c, src, r, v)
    None => ()
  }
  ignore(t)
  c.box(style=wide_pane_ground, fn() {
    // what is opened beside it, at its right (wide_panel.mbt)
    with_side(c, src, w, r, view, fn() { wide_chat_pane(c, src, w, r, view, list, error) })
  })
  |> ignore
  // a row of the 文件 tab let go over the chat: into its message (once the tab has said so, this frame)
  chat_drop(c, src, draft_key(r), c.id("chat/pane"))
}

///|
/// A row of the 文件 tab let go over the chat (box `pane`): into draft `key` (ChatSide.tsx useChatDrop).
fn chat_drop(c : @ui.Ctx, src : Source, key : String, pane : Int) -> Unit {
  match @sfdesk.tab_take_drop(c) {
    Some((item, x, y)) if within(c.rect_of(pane), x, y) => refs_put(src, key, [item])
    _ => ()
  }
}

///|
/// Whether (x, y) is in the rectangle, where there is one.
fn within(r : (Double, Double, Double, Double)?, x : Double, y : Double) -> Bool {
  match r {
    Some((rx, ry, rw, rh)) => x >= rx && x < rx + rw && y >= ry && y < ry + rh
    None => false
  }
}

///|
/// A row of the 文件 tab carried over the chat (box `pane`; ChatSide.tsx DropHint, ChatPage.css.ts dropHint): the chat
/// frosted over under its composer, the row's mark twice a card's and 松开以添加到消息 in its middle.
fn drop_hint(c : @ui.Ctx, pane : Int) -> Unit {
  let item = match @sfdesk.dragged() {
    Some(i) => i
    None => return
  }
  let (px, py, _) = c.pointer()
  if !within(c.rect_of(pane), px, py) {
    return
  }
  let l = c.layer(fn() {
    c.layer(fn() { floating_ground(c, Fill(1.0), corner=0.0) |> ignore }) |> ignore
    c.box(style=drop_hint_box, fn() {
      let mark = c.box(fn() {
        if item.dir {
          @sf.icon(c, "folder", size=drop_folder, color=@sf.theme().p.muted) |> ignore
        } else {
          file_sheet(c, item.name)
        }
      })
      c.look(mark, @ui.look(scale=2.0))
      c.text(tr("web-main.composer.dropHere"), style=drop_hint_words) |> ignore
    })
    |> ignore
  })
  // (drawn only: what it is let go on is the tab's to say)
  c.draw_only(l)
}

///|
/// What is said in its middle: its mark over its words, 16 apart less what the mark grows by (a card's, twice).
// kept across runs: a value (no field of it changes)
let drop_hint_box : @ui.Style = @ui.style(w=Full, h=Full, gap=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let drop_hint_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// A folder's mark there, as large as a card's sheet.
let drop_folder : Double = 30.0

///|
/// The chat's own keys (keymap.ts, ChatPage.tsx useShortcut): ⌘↓ to its end (with the cursor in an empty composer
/// too), ⌘⇧E into the archive while nothing is left in it, ⌘⇧H its first agent's history beside it (one in front:
/// the panel closed), ⌘. its agents at work stopped; Esc closes its panel (wide_keys.mbt, once nothing else took it).
fn chat_keys(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let empty = match drafts.get(draft_key(r)) {
    Some(d) => draft_empty(d)
    None => true
  }
  if @settings.action_pressed(c, prefs, "chat.latest", in_field=empty) {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) => (src.call)("chat.latest", { "station": Json::string(r.station), "thread": Json::number(th) }, fn(_) {  })
        None => ()
      }
    }
  }
  if @settings.action_pressed(c, prefs, "chat.archive", in_field=true) && v.archivable && !v.archived && !v.offline {
    archive_chat(src, r, v)
    @sfdesk.wide.landed = ""
  }
  // an agent's history in front: the panel closed; else the first agent's open, or the first agent's opened
  // (ChatPage.tsx chat.history)
  if @settings.action_pressed(c, prefs, "chat.history", in_field=true) && v.agents.length() > 0 {
    let (tabs, front) = side_of(v)
    let agent = fn(t : String) { v.agents.iter().any(fn(a) { a.key == t }) }
    if agent(front) {
      side_change(r, "clear", None)
    } else {
      side_change(r, "open", Some(tabs.iter().find_first(agent).unwrap_or(v.agents[0].key)))
    }
  }
  if @settings.action_pressed(c, prefs, "chat.stop", in_field=true) {
    for a in v.agents {
      if a.status == "running" || a.status == "queued" {
        act(
          src,
          tr("android-chat.agent.stop"),
          "stop/" + r.station + "/" + a.key,
          "session.stop",
          { "station": Json::string(r.station), "key": Json::string(a.key) },
          done=tr("android-chat.history.stopped"),
        )
      }
    }
  }
}

///|
/// The chat itself in the pane, left of its side panel: its messages, its bar over them, the composer at its foot.
fn wide_chat_pane(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
  view : ChatView?,
  list : Array[Entry],
  error : Json?,
) -> Unit {
  let pane = c.id("chat/pane")
  c.box(style=side_panel_style, id=pane, fn() {
    match view {
      None => {
        wide_chat_bar(c, src, w, r, None)
        let failed = match error {
          Some(e) =>
            Some(fill("android-chat.chat.unreadable", [("error", text(Some(e), "message"))]))
          None => None
        }
        // (a chat just made from a new chat is the core's own: nothing breathing while its first view comes)
        if failed is Some(_) || !new_chat_made(c, r) {
          waiting_messages(c, failed)
        }
        c.layer(fn() {
          c.spacer()
          wide_composer(c, src, r, None)
        })
        |> ignore
        // its first words, as typed, till their row is in the list (flight.mbt)
        flight_frame(c, draft_key(r))
        flight_waiting(c, draft_key(r))
        flight_files(c, draft_key(r))
      }
      Some(v) => {
        messages(c, src, r, v, list)
        c.layer(fn() { wide_chat_bar(c, src, w, r, Some(v)) }) |> ignore
        bar_popovers(c, src, r, v)
        // come to from a new chat: what it showed fading under the composer (wide_switch.mbt)
        switch_veil(c)
        // a row of the 文件 tab carried over it: frosted, under its composer
        drop_hint(c, pane)
        c.layer(fn() {
          c.spacer()
          wide_composer(c, src, r, Some(v))
        })
        |> ignore
        flight_waiting(c, draft_key(r))
        flight_files(c, draft_key(r))
        pick_layer(c, src, r)
        link_menu_layer(c)
      }
    }
  })
  |> ignore
}

///|
/// The composer at the pane's foot (dock.css.ts): 12 from its sides, 804 wide at most, in the middle.
fn wide_composer(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView?) -> Unit {
  wide_center(c, fn() { composer(c, src, r, v) })
}

///|
/// What the composer's column holds, in the pane's middle (the column and the capsule's curve each side, 804 wide at
/// most, 12 from the pane's sides: dock.css.ts), in the wide frame; as it is elsewhere.
fn wide_center(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if !wide_on.val {
    body()
    return
  }
  let inner = wide_composer_w(c)
  c.box(style=wide_centred, fn() {
    c.box(w=Px(inner), fn() { c.sized(inner, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
/// The composer's width in the wide frame's pane `c.width` wide (dock.css.ts composerBox: the column and 22 each side,
/// 12 from the pane's sides).
fn wide_composer_w(c : @ui.Ctx) -> Double {
  dmin(c.width - 24.0, column_w + 44.0)
}

///|
/// The chat's bar (ChatPage.tsx header): the title, its station while no agent is in it, its people, its agents (each
/// its history beside the chat); at its end 归档 while nothing is left in it, 服务和后台任务 while it has some (a popover),
/// "…" (a popover: what is done with the chat, agent 往来 among it, as the web's), the side panel's switch while it is
/// closed.
fn wide_chat_bar(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?) -> Unit {
  let t = @sf.theme()
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let bar = c.id("chat-bar")
  // the bar's empty part drags the window (in one with its buttons in the app's top row)
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  // (beside the rail its room as the block moves: page_bar_room)
  let (room_l, room_r, ml, mr) = @sfdesk.page_bar_room()
  c.box(moves="page-bar", dir=Row, w=Fill(1.0), h=Px(wide_bar_h), pl=room_l, pr=room_r, ml~, mr~, pb=1.0, gap=16.0, align=ACenter, bg=t.p.bg, id=bar, fn() {
    // (the title, its people and agents 10 apart, 8 in from the bar's padding: session.css.ts pageBarTitle)
    c.box(dir=Row, w=Fill(1.0), pl=bar_title_in, gap=bar_title_gap, align=ACenter, fn() {
      let title = match v {
        Some(view) => view.title
        None => r.title
      }
      c.box(max_w=dmax(80.0, c.width * 0.42), fn() { c.text(title, style=bar_title) |> ignore })
      |> ignore
      match v {
        Some(view) => {
          if view.agents.length() == 0 {
            match station {
              Some(s) => station_chip(c, r.station, s)
              None => ()
            }
          }
          if view.people.length() > 0 {
            bar_people(c, src, view.people)
          }
          for i, a in view.agents {
            let id = c.id("bar-agent/" + a.key)
            c.cursor(id, Hand)
            // its execution history beside the chat (the web's: ChatPage.tsx AgentTile), pressed again in front, closed
            if c.clicked(id) {
              side_toggle(r, a.key)
            }
            c.box(id~, fn() {
              if i == 0 {
                agent_station_mark(c, a, station)
              } else {
                model_mark(c, a, mark_side())
              }
            })
            |> ignore
            // the pointer resting on it: its card (AgentCard.tsx), as the web's
            wide_hover(c, "agent-hover/" + a.key, id, tile=true, fn() { agent_card(c, src, r, a) }) |> ignore
          }
        }
        None => ()
      }
    })
    |> ignore
    match v {
      // ⌘F's bar, in place of the buttons while it is open
      Some(view) if wide.find_chat == side_key(r) => find_bar(c, src, r, view)
      Some(view) =>
        c.box(style=bar_buttons, fn() {
          let archive = view.archivable && !view.archived
          if archive {
            if doing("archive/" + r.station + "/" + r.session) {
              c.box(style=bar_button_busy, fn() { @sf.spinner(c) |> ignore })
              |> ignore
            } else if icon_button(c, "chat-archive", "archive", label=tr("web-pages.chat.archive"), action="chat.archive") {
              archive_chat(src, r, view)
              @sfdesk.wide.landed = ""
            }
          }
          let jobs = (src.topic)("chatJobs", chat_params(r))
          // its services and jobs, and what is done with it: each a popover under its button (wide_panel.mbt)
          if items(jobs.value, "jobs").length() > 0 && icon_button(c, "chat-jobs", "web", label=tr("web-pages.chat.services"), action="chat.jobs") {
            wide.jobs_open = !wide.jobs_open
          }
          if view.thread is Some(_) && icon_button(c, "chat-more", "more", label=tr("web-pages.chat.info")) {
            wide.info_open = !wide.info_open
          }
          // the side panel's switch while it is closed: the first agent's history in it
          if side_of(view).0.length() == 0 && view.agents.length() > 0 && icon_button(c, "chat-panel", "panel-open", label=tr("web-pages.chat.openPanel"), action="chat.history") {
            side_change(r, "open", Some(view.agents[0].key))
          }
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// How far in the chat's title stands from the bar's padding, and how far apart it, its people and its agents are
/// (session.css.ts pageBarTitle: 8, 10).
let bar_title_in : Double = 8.0

///|
let bar_title_gap : Double = 10.0

///|
/// Who is in the chat, in its bar (components.tsx PeopleStack, max 5): each a 16 circle, their picture or their
/// initial in 600 on the paper, ringed 1.5 in the sidebar's ground, each 4 over the one before, the first over them
/// all; more than five, +n after them; on hover their names.
fn bar_people(c : @ui.Ctx, src : Source, people : Array[Person]) -> Unit {
  let t = @sf.theme()
  let shown = if people.length() > 5 { people[:5].to_array() } else { people }
  let n = shown.length()
  let step = person_side + 2.0 * person_ring
  let id = c.id("bar-people")
  wide_tip(
    c,
    "bar-people",
    id,
    fill("web-main.people.in", [("names", people.map(fn(p) { p.display }).join(tr("web-main.list.separator")))]),
  )
  // (their rings out past them: the first's face where the stack starts, Chat's boxShadow)
  c.box(style=people_row, tx=-person_ring, id~, fn() {
    c.box(w=Px(step + (person_side - 4.0) * (n - 1).to_double()), h=Px(step), fn() {
      // the last drawn first, each under the one before it
      for j in 0..<n {
        let i = n - 1 - j
        let p = shown[i]
        c.layer(fn() {
          c.box(
            w=Px(step),
            h=Px(step),
            radius=step / 2.0,
            bg=t.p.sidebar,
            tx=(person_side - 4.0) * i.to_double(),
            align=ACenter,
            justify=JCenter,
            fn() {
              if p.picture != "" {
                avatar(c, src, p.id, p.display, p.picture, person_side)
              } else {
                c.box(style=person_letter, bg=t.p.paper, fn() {
                  c.text(person_initial(p.display), style=person_letter_words) |> ignore
                })
                |> ignore
              }
            },
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    if people.length() > 5 {
      c.box(style=people_more, fn() { c.text("+\{people.length() - 5}", style=people_more_words) |> ignore }) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let people_row : @ui.Style = @ui.style(row=true, align=ACenter)

///|
/// The pane's ground under a chat.
// kept across runs: a value (no field of it changes)
let wide_pane_ground : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let wide_centred : @ui.Style = @ui.style(row=true, w=Full, justify=JCenter)

///|
/// A page's title in its bar (sidebar.css.ts pageBar h1: 14 in 600, on 20).
// kept across runs: a value (no field of it changes)
let bar_title : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let bar_title_room : @ui.Style = @ui.style(w=Full)

///|
/// What is done in a page's bar, at its end, 2 apart (ChatPage.css.ts pageBarActions); a button under way, its 32.
// kept across runs: a value (no field of it changes)
let bar_buttons : @ui.Style = @ui.style(row=true, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let bar_button_busy : @ui.Style = @ui.style(w=S8, h=S8, align=ACenter, justify=JCenter)

///|
/// A person in the bar, 16 across, ringed 1.5 (components.css.ts peopleStack).
let person_side : Double = 16.0

///|
let person_ring : Double = 1.5

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
let person_letter : @ui.Style = @ui.style(w=S4, h=S4, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let person_letter_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let people_more : @ui.Style = @ui.style(pl=S1_5)

///|
// kept across runs: a value (no field of it changes)
let people_more_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

///|
/// An icon button of a page's bar (page.css.ts iconBtn): 32 square, the nav's corner, the pointer's ground and ink
/// on hover. True on the frame after a press.
fn icon_button(c : @ui.Ctx, key : String, icon : String, label? : String = "", action? : String = "") -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.hovered(id) || c.pressed(id)
  let b = c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=12.0,
    align=ACenter,
    justify=JCenter,
    bg=if hot { t.p.hover } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size=16.0, color=if hot { t.p.text } else { t.p.muted }) |> ignore },
  )
  // named for a screen reader (the web's aria-label), and said under it on hover with its keys (the web's IconButton)
  if label != "" {
    c.semantics(b, Button, id~, label~)
    wide_tip(c, key, id, label, action~)
  }
  c.clicked(id)
}

///|
/// A page's bar in the wide frame (styles/sidebar.css.ts pageBar): 45 high, 12 in; back (a page under another), the
/// title in 14 and 600, what the page does at its end. True on the frame after back was pressed.
fn page_bar_wide(c : @ui.Ctx, title : String, back : Bool, trailing : () -> Unit) -> Bool {
  let t = @sf.theme()
  let bar = c.id("page-bar")
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  let mut went = false
  let (room_l, room_r, ml, mr) = @sfdesk.page_bar_room()
  c.box(moves="page-bar", dir=Row, w=Fill(1.0), h=Px(wide_bar_h), pl=room_l, pr=room_r, ml~, mr~, pb=1.0, gap=8.0, align=ACenter, bg=t.p.bg, id=bar, fn() {
    if back {
      went = icon_button(c, "page-bar/back", "chevron-left")
    }
    c.box(style=bar_title_room, fn() { c.text(title, style=bar_title) |> ignore }) |> ignore
    c.box(style=bar_buttons, trailing) |> ignore
  })
  |> ignore
  went
}
