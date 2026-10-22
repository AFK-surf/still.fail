// A chat in the wide frame's pane (ember web/src/pages/ChatPage.tsx, styles/sidebar.css.ts pageBar, session.css.ts,
// dock.css.ts): its bar (45 high, the title 14 in 600, who is in it, its agents; at its end 归档 while nothing is left
// in it, its services and jobs, its info), the messages in a column 760 wide at most in the middle of the pane (the
// phone's rows: chat.mbt), the composer at its foot, 804 at most. What the phone's chat page does (reading, following
// its end, the way to the newest, telling the core what shows) is the same page's.

///|
/// The column the messages keep to (later.css.ts: 760), and the least room at its sides (session.css.ts: 40).
let column_w : Double = 760.0

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
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    match view {
      None => {
        wide_chat_bar(c, src, w, r, None)
        let failed = match error {
          Some(e) =>
            Some(fill("android-chat.chat.unreadable", [("error", text(Some(e), "message"))]))
          None => None
        }
        waiting_messages(c, failed)
        c.layer(fn() {
          c.spacer()
          wide_composer(c, src, r, None)
        })
        |> ignore
      }
      Some(v) => {
        messages(c, src, r, v, list)
        c.layer(fn() { wide_chat_bar(c, src, w, r, Some(v)) }) |> ignore
        c.layer(fn() {
          c.spacer()
          wide_composer(c, src, r, Some(v))
        })
        |> ignore
        flight_waiting(c, draft_key(r))
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
/// What the composer's column holds, in the pane's middle (804 wide at most, 12 from its sides; the composer's own 10
/// at its sides inside), in the wide frame; as it is elsewhere.
fn wide_center(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if !wide_on.val {
    body()
    return
  }
  let inner = dmin(c.width - 24.0, column_w + 44.0)
  c.box(dir=Row, w=Fill(1.0), justify=JCenter, fn() {
    c.box(w=Px(inner + 20.0), fn() { c.sized(inner + 20.0, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
/// The chat's bar (ChatPage.tsx header): the title, its station while no agent is in it, its people, its agents (each
/// its card); at its end 归档 while nothing is left in it, 服务和后台任务 while it has some, "…" (对话信息: the rest of what is
/// done with the chat, agent 往来 among it, as the web's).
fn wide_chat_bar(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?) -> Unit {
  let t = @sf.theme()
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let bar = c.id("chat-bar")
  // the bar's empty part drags the window (in one with its buttons in the app's top row)
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  c.box(dir=Row, w=Fill(1.0), h=Px(45.0), pl=12.0, pr=12.0, pb=1.0, gap=16.0, align=ACenter, bg=t.p.bg, id=bar, fn() {
    c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
      let title = match v {
        Some(view) => view.title
        None => r.title
      }
      c.box(max_w=dmax(80.0, c.width * 0.42), fn() {
        c.text(title, size=14.0, weight=600, color=t.p.text, wrap=false, line=20.0) |> ignore
      })
      |> ignore
      match v {
        Some(view) => {
          if view.agents.length() == 0 {
            match station {
              Some(s) => station_chip(c, r.station, s)
              None => ()
            }
          }
          let people = if view.people.length() > 5 { view.people[:5].to_array() } else { view.people }
          if people.length() > 0 {
            people_stack(c, src, people, 16.0)
          }
          for i, a in view.agents {
            let id = c.id("bar-agent/" + a.key)
            c.cursor(id, Hand)
            if c.clicked(id) {
              open_sheet(c, AgentOf(r, a.key))
            }
            c.box(id~, fn() {
              if i == 0 {
                agent_station_mark(c, a, station)
              } else {
                model_mark(c, a, 22.0)
              }
            })
            |> ignore
          }
        }
        None => ()
      }
    })
    |> ignore
    match v {
      Some(view) =>
        c.box(dir=Row, gap=2.0, align=ACenter, fn() {
          let archive = view.archivable && !view.archived
          if archive {
            if doing("archive/" + r.station + "/" + r.session) {
              c.box(w=Px(32.0), h=Px(32.0), align=ACenter, justify=JCenter, fn() { @sf.spinner(c) |> ignore })
              |> ignore
            } else if icon_button(c, "chat-archive", "archive") {
              archive_chat(src, r, view)
              wide.landed = ""
            }
          }
          let jobs = (src.topic)("chatJobs", chat_params(r))
          if items(jobs.value, "jobs").length() > 0 && icon_button(c, "chat-jobs", "boxes") {
            dui.jobs_all = false
            open_sheet(c, JobsOf(r))
          }
          if view.thread is Some(_) && icon_button(c, "chat-more", "more") {
            open_sheet(c, Info(r))
          }
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// An icon button of a page's bar (page.css.ts iconBtn): 32 square, the nav's corner, the pointer's ground and ink
/// on hover. True on the frame after a press.
fn icon_button(c : @ui.Ctx, key : String, icon : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.hovered(id) || c.pressed(id)
  c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=12.0,
    align=ACenter,
    justify=JCenter,
    bg=if hot { t.p.hover } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size=16.0, color=if hot { t.p.text } else { t.p.muted }) |> ignore },
  )
  |> ignore
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
  c.box(dir=Row, w=Fill(1.0), h=Px(45.0), pl=12.0, pr=12.0, pb=1.0, gap=8.0, align=ACenter, bg=t.p.bg, id=bar, fn() {
    if back {
      went = icon_button(c, "page-bar/back", "chevron-left")
    }
    c.box(w=Fill(1.0), fn() {
      c.text(title, size=14.0, weight=600, color=t.p.text, wrap=false, line=20.0) |> ignore
    })
    |> ignore
    c.box(dir=Row, gap=2.0, align=ACenter, trailing) |> ignore
  })
  |> ignore
  went
}
