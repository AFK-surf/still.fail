// An agent's execution history, a page of its own (slice 8: ember apps/android chat/screens/History.kt HistoryScreen,
// Steps, Item, Message, Group, StepRow, Folding, Whole, PhaseLine, Details; ui/ToolStep.kt): what it received and what
// it sent, drawn alike (a line saying what and where, then its words in brief beside a bar); what it did in between,
// grouped, each group opening to its calls and thoughts, a call opening to what it asked for (a command, an edit as a
// diff, a file, a patch, a plan, its fields) and what came back. Its details: where it stands, its figures, how it
// runs, the station. What it shows is the core's `history {station, key}` view; a call in brief is read whole as it is
// opened (`history.detail`), the page before as the reader nears the top (`history.older`).
//
// Opened at an entry (a link's `?history=…&entry=…`), that entry's item comes near the top, for a moment marked. A
// Slack user's name offers 这是我 or 不是我 (`slack.identity`); a place is a way there.

///|
/// A page's compact bar (Parts.kt NavBar): back, with where it goes back to, in the accent; the title in the middle;
/// what is at its end.
fn page_bar(c : @ui.Ctx, key : String, back : String, title : String, trailing : () -> Unit) -> Unit {
  if @sf.nav_bar(c, key + "/back", back, title, trailing~, bg=@sf.theme().p.bg, top=status_top()) {
    @sfbase.go_back() |> ignore
  }
}

///|
fn history_params(r : ChatRef, key : String) -> Map[String, Json] {
  { "station": Json::string(r.station), "key": Json::string(key) }
}

///|
/// The history's page left: what it followed let go.
fn history_left(src : Source, r : ChatRef, key : String) -> Unit {
  (src.leave)("history", history_params(r, key))
  // the station's figures its details read
  @sfbase.let_go(src, @sfbase.history_scope(r.station, key))
  history_placed.remove("history/" + r.station + "/" + key)
  history_short.remove("history/" + r.station + "/" + key)
}

///|
/// The page (History.kt HistoryScreen): its bar (copying its link at its end), the agent at its head with what can be
/// done to it and the tabs, then its steps or its details; its steps opened at `entry` (a transcript entry), else at
/// its newest.
fn history_page(c : @ui.Ctx, src : Source, r : ChatRef, key : String, entry : Int?) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r))
  let title = text(chat.value, "title")
  let link = match chat_link(r.station, key) {
    "" => ""
    l => l + "?history=" + @codec.encode_uri_component(key)
  }
  // over the navigation bar (History.kt: windowInsetsPadding(navigationBars))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
    page_bar(c, "history", tr("common.back"), tr("android-chat.history.title"), fn() {
      if title != "" && link != "" && nav_button(c, "copy", 18.0, key="history/copy", said=tr("web-mobile.history.copyLink")) {
        copy_chat_link(c, title, link)
      }
    })
    history_body(c, src, r, key, entry, chat)
    // a Slack user's name tapped: its menu (link_menu.mbt)
    link_menu_layer(c)
  })
  |> ignore
}

///|
/// What the history's page shows under its bar: the
/// agent at its head with what can be done to it and the tabs, then its steps or its details.
fn history_body(c : @ui.Ctx, src : Source, r : ChatRef, key : String, entry : Int?, chat : Topic) -> Unit {
  let t = @sf.theme()
  let a = agent_json(chat.value, key)
  match a {
    None => {
      waiting_messages(
        c,
        match chat.error {
          Some(e) => Some(error_words(e))
          None => None
        },
      )
      return
    }
    Some(_) => ()
  }
  let s = field(a, "session")
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, gap=6.0, align=ACenter, fn() {
    model_mark_big(
      c,
      text(field(s, "maker"), "id"),
      text(s, "runtime"),
      20.0,
      state_of_badge(text(a, "badge")),
      t.p.bg,
    )
    // (its name cut short where what it does and its tabs leave it less: a name)
    c.box(w=Fill(1.0), fn() {
      c.text(text(s, "agentText"), size=t.t.title, weight=700, color=t.p.text, wrap=false, w=Cut) |> ignore
    })
    |> ignore
    history_actions(c, src, r, a)
    @sf.head_end(c, fn() {
      dui.history_tab.set(@sf.segmented(
        c,
        "history/tab",
        [tr("android-chat.history.tab.steps"), tr("android-chat.history.tab.details")],
        dui.history_tab.get(),
      ))
    })
  })
  |> ignore
  history_summary(c, a)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    if dui.history_tab.get() == 0 {
      // its steps, as every pane draws them (sfpages' history_steps.mbt); opened at an entry, brought to it once
      let lkey = "history/" + r.station + "/" + key
      match entry {
        Some(e) if !history_placed.contains(lkey) => {
          history_placed[lkey] = true
          @sfpages.history_focus(r.station, key, e)
        }
        _ => ()
      }
      @sfpages.history_steps(c, src, r.station, key)
    } else {
      history_details(c, src, r, key, a)
    }
  })
  |> ignore
}

///|
/// What can be done to it now (History.kt Actions): stop a turn, let an idle process go; each a 28 disc, a spinner
/// while it is asked.
fn history_actions(c : @ui.Ctx, src : Source, r : ChatRef, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let key = text(s, "key")
  let status = text(a, "status")
  let one = fn(icon : String, done : String, call : String) {
    let dkey = call + "/" + r.station + "/" + key
    let busy = doing(dkey)
    let id = c.id("history/" + call)
    if !busy && c.clicked(id) {
      act(
        src,
        done,
        dkey,
        call,
        { "station": Json::string(r.station), "key": Json::string(key) },
        done~,
      )
    }
    c.box(
      w=Px(28.0),
      h=Px(28.0),
      radius=14.0,
      bg=t.p.chip,
      align=ACenter,
      justify=JCenter,
      id~,
      fn() {
        if busy {
          @sf.spinner(c, size=12.0) |> ignore
        } else {
          @sf.icon(c, icon, size=14.0, color=t.p.text) |> ignore
        }
        // History.kt: clip(CircleShape).clickable
        @motion.ripple(c, id, 14.0)
      },
    )
    |> ignore
  }
  if status == "running" || status == "queued" {
    one("stop", tr("android-chat.history.stopped"), "session.stop")
  }
  if text(s, "process") == "warm" {
    one("unplug", tr("android-chat.history.evicted"), "session.evict")
  }
}

///|
/// The head's short line (History.kt Summary): only what is worth a look now: a quota running out (its chip, what it
/// says and more in its tip), the disk filling up (amber), an account that cannot run (red).
fn history_summary(c : @ui.Ctx, a : Json?) -> Unit {
  let t = @sf.theme()
  let notes = items(a, "attention")
  if notes.length() == 0 {
    c.box(h=Px(8.0), fn() {  }) |> ignore
    return
  }
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=6.0, pb=8.0, gap=10.0, align=ACenter, fn() {
    for i, n in notes {
      let nv = Some(n)
      match field(nv, "quota") {
        Some(Object(_)) as q => {
          // (what the core says of it, and more, over it while it is pointed at, held by a finger: HistorySummary's tip)
          let more = text(nv, "more")
          @sf.quota_chip(c, q, small=true, key="history/attention/" + i.to_string(), said=text(nv, "text") + (if more != "" {
            "\n" + more
          } else {
            ""
          }))
        }
        _ =>
          c.text(
            text(nv, "text"),
            size=t.t.caption,
            color=if text(nv, "kind") == "disk" { t.p.warn_ink } else { t.p.red },
            wrap=false,
          )
          |> ignore
      }
    }
  })
  |> ignore
}

///|
/// How a history's steps were put in place as it opened (History.kt Steps: `follow.placed`), by its list's key: at
/// its newest, followed (true), or at an entry, not followed (false). Not there: not put in place yet.
let history_placed : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// The histories whose page before, asked for an entry before what was loaded, could not be had: put in place with
/// what there is.
let history_short : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// Its details (History.kt Details): where it stands and its figures as its card has them, how it runs in a line,
/// what it runs on and has done, what it used, the station.
fn history_details(c : @ui.Ctx, src : Source, r : ChatRef, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let usage = @sfpages.history_usage(src, r.station, key)
  let host = @sfbase.hold(src, @sfbase.history_scope(r.station, key), "host", { "station": Json::string(r.station) }).value
  let detail = fn(label : String, value : String, marked : Bool) {
    c.box(dir=Row, w=Fill(1.0), gap=16.0, fn() {
      c.box(w=Px(76.0), fn() { c.text(label, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore })
      |> ignore
      if marked {
        c.box(style=details_turns, fn() {
          c.text(value, style=details_turns_words, keep=true) |> ignore
          // (in the list's row, said at its least: a mark with how many)
          @sfpages.work_mark(c, src, r.station, key, details_turns_mark, details_turns_link, lead=" · ", smallest=true)
        })
        |> ignore
      } else {
        c.box(w=Fill(1.0), fn() { c.text(value, size=t.t.ui, color=t.p.text) |> ignore }) |> ignore
      }
    })
    |> ignore
  }
  let rows : Array[() -> Unit] = [
    fn() {
      c.box(w=Fill(1.0), pt=2.0, fn() { agent_status(c, src, a) }) |> ignore
      agent_tiles(c, card, 14.0)
      agent_notes(c, card, 10.0)
      c.box(h=Px(6.0), fn() {  }) |> ignore
      // changing how it runs is a page of its own (RunSettingsScreen)
      if run_row(c, a) {
        @sfbase.history_push()
        app.nav.push(Setting(@settings.Route::RunSettings(r.station, key)))
      }
      c.box(w=Fill(1.0), pt=12.0, pb=10.0, gap=8.0, fn() {
        detail(tr("android-chat.history.detail.runtime"), text(s, "runtimeText"), false)
        match text(s, "processText") {
          "" => ()
          p => detail(tr("android-chat.history.detail.process"), p, false)
        }
        match text(card, "work") {
          "" => ()
          // (and after it what it has going in the background and its checklist, a mark that opens them from the
          // foot: the first to give way)
          w => detail(tr("android-chat.agent.turns"), w, true)
        }
      })
      |> ignore
      if usage.length() > 0 {
        group_label(c, tr("android-chat.agent.usage"))
        c.box(w=Fill(1.0), pt=6.0, pb=10.0, gap=8.0, fn() {
          for u in usage {
            detail(text(Some(u), "label"), text(Some(u), "value"), false)
          }
        })
        |> ignore
      }
      group_label(c, "Station")
      c.box(w=Fill(1.0), pt=6.0, pb=10.0, gap=8.0, fn() {
        detail(tr("android-chat.history.detail.name"), station_name_of(src, r), false)
        match host {
          Some(Object(_)) => detail(tr("android-chat.history.detail.machine"), text(host, "identity"), false)
          _ => ()
        }
      })
      |> ignore
      c.box(h=Px(30.0), fn() {  }) |> ignore
    },
  ]
  c.list("history-details/" + r.station + "/" + key, rows.length(), 400.0, fn(i) {
    c.box(w=Fill(1.0), pl=18.0, pr=18.0, fn() { (rows[i])() }) |> ignore
  })
  |> ignore
}

///|
/// A station's name, from the stations the app knows (its address's workspace's), else as the chat's row said it.
fn station_name_of(src : Source, r : ChatRef) -> String {
  let scope = match r.station.find("/") {
    Some(i) => r.station.view(end_offset=i).to_owned()
    None => r.station
  }
  match stations_of((src.topic)("stations", { "scope": Json::string(scope) }).value).iter().find_first(fn(
    s,
  ) {
    s.address == r.station
  }) {
    Some(s) => s.name
    None => r.station_name
  }
}

///|
/// How it runs, in one line (History.kt RunRow): the model (never cut short), how hard it thinks, the account; a
/// hairline round it. True on the frame after a tap (the run settings page opened).
fn run_row(c : @ui.Ctx, a : Json?) -> Bool {
  let t = @sf.theme()
  let s = field(a, "session")
  let name = text(field(a, "account"), "name")
  let model = match opt_text(s, "model") {
    Some(m) =>
      match text(s, "modelName") {
        "" => m
        n => n
      }
    None => tr("android-chat.pick.model")
  }
  let effort = match text(s, "effort") {
    "" => tr("android-chat.pick.effort.default")
    e => e
  }
  let account = if flag(s, "profilePinned") {
    name
  } else {
    fill("android-chat.history.run.auto", [("name", name)])
  }
  let id = c.id("history-run-row")
  c.box(w=Fill(1.0), pt=6.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=12.0,
      pady=10.0,
      gap=6.0,
      radius=10.0,
      border=1.0,
      border_color=t.p.line,
      align=ACenter,
      id~,
      fn() {
        @sf.maker_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), 15.0) |> ignore
        // how it runs on its line, its account's allowance under it, a line of its own (beside it, the allowance left
        // the line where it had not the room: gone)
        c.box(style=run_words, keep=true, fn() {
          c.box(style=run_line, fn() {
            c.text(model, size=t.t.ui, color=t.p.text, wrap=false, w=Cut, keep=true) |> ignore
            c.box(w=Fill(1.0), keep=true, fn() {
              c.text(" · " + effort + " · " + account, size=t.t.meta, color=t.p.muted, wrap=false, w=Cut, keep=true)
              |> ignore
            })
            |> ignore
          })
          |> ignore
          allowance_line(c, field(field(a, "account"), "quota"))
        })
        |> ignore
        @sf.icon(c, "chevron-down", size=14.0, color=t.p.muted) |> ignore
        // History.kt: clip(Smooth(10)).clickable
        @motion.ripple(c, id, 10.0)
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// An entry opened in full (History.kt's reader, Sheet.kt ReaderHost): back to 执行历史, the line it was under, then
/// all its words as Markdown, 20 from the sides, 12 between.
fn words_page(c : @ui.Ctx, src : Source, head : String, words : String) -> Unit {
  ignore(src)
  let t = @sf.theme()
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    page_bar(c, "words", tr("android-misc.reader.back"), "", fn() {  })
    c.list("words/" + head + "/" + words.length().to_string(), 2, 200.0, fn(i) {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=if i == 1 { 30.0 } else { 12.0 }, fn() {
        if i == 0 {
          if head != "" {
            c.text(head, size=t.t.meta, color=t.p.muted) |> ignore
          }
        } else {
          @sf.markdown(c, words) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

// ── a call, drawn by what it is (ui/ToolStep.kt) ────────────────────────

///|
/// The boxes of a step drawn so far, numbered for where each is scrolled to (within the step's scope).
let boxed_n : Ref[Int] = { val: 0 }

///|
/// The steps' parts as the core read them (`history.tool`), by what was asked.
let tool_parts : Map[String, Json] = {}

///|
/// How it runs and its account's allowance under it, in what the row leaves its mark and its chevron.
// kept across runs: a value (no field of it changes)
let run_words : @ui.Style = @ui.css("w=Full")

///|
/// How it runs: its model, how hard it thinks and its account, on a line.
// kept across runs: a value (no field of it changes)
let run_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// Its turns' value with the mark of its work past its turns after it (work_mark): one line, its words cut short only
/// once the mark has given way.
// kept across runs: a value (no field of it changes)
let details_turns : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let details_turns_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let details_turns_link : @ui.TextStyle = @ui.text_style(size=Meta, color=Link, wrap=false)

///|
/// The mark after them: quieter than them (12, muted), a link's ink under the finger.
// kept across runs: a value (no field of it changes)
let details_turns_mark : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
