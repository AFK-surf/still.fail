// The sheets over a chat (slice 8): its own, from "…" (ember apps/android chat/screens/ChatInfo.kt openChatInfo,
// askTitle, InfoList, InfoRow), an agent's card (AgentSheet.kt openAgent, AgentStatus, AgentLines, AgentTiles,
// AgentNotes, StopButton), its services and jobs and one job (Jobs.kt openJobs, JobGroups, JobInfoRow, JobDot, metaOf,
// openJob, JobBody), and the jobs left up a long while at the top of Home (OpenJobs.kt). What they show is the core's
// (the `chat`, `agentCard`, `stations`, `chatJobs`, `jobLog` and `longJobs` views); what is done goes through its calls.
//
// An agent's station opens the station's card in its place (settings/station_peek.mbt), its account how it runs.
//
// The jobs' and a job's sheets drag between half and nearly all of the screen, as Android's (Jobs.kt: draggable).

// ── parts ───────────────────────────────────────────────────────────────

///|
/// An agent's state as its mark's badge says it (ChatAgent.state): block, run, failed, or "" (done).
fn state_of_badge(badge : String) -> String {
  match badge {
    "block" | "run" | "failed" => badge
    _ => ""
  }
}

///|
/// A model's mark as a sheet and the history have it (Parts.kt ModelMark): its maker's mark on a tile with a hairline,
/// the ladder's small block's 10 round (Parts.kt's 11: concentric so in a row's corner, 10 in, all four alike; 6 under
/// 30), and its state's badge over the corner (Badge: solid accent waiting on someone, an accent ring
/// at work, red failed) ringed in `around`.
fn model_mark_big(c : @ui.Ctx, maker : String, runtime : String, size : Double, state : String, around : Int64) -> Unit {
  let t = @sf.theme()
  let xs = size < 30.0
  c.box(w=Px(size), h=Px(size), fn() {
    c.box(
      w=Px(size),
      h=Px(size),
      radius=if xs { 6.0 } else { @sf.small_corner },
      bg=t.p.card,
      border=1.0,
      border_color=t.p.line,
      align=ACenter,
      justify=JCenter,
      fn() {
        @sf.maker_mark(c, maker, runtime, size * (if xs { 0.6 } else { 0.56 })) |> ignore
      },
    )
    |> ignore
    if state != "" {
      let b = if xs { 11.0 } else { 15.0 }
      let ring = if xs { 1.5 } else { 2.0 }
      let inner = b - ring * 2.0
      c.layer(fn() {
        c.box(tx=size - b + 3.0, ty=size - b + 3.0, fn() {
          c.box(w=Px(b), h=Px(b), radius=b / 2.0, bg=around, align=ACenter, justify=JCenter, fn() {
            match state {
              "run" =>
                c.box(
                  w=Px(inner),
                  h=Px(inner),
                  radius=inner / 2.0,
                  border=dmin(2.5, inner / 2.0),
                  border_color=t.p.accent,
                  fn() {  },
                )
                |> ignore
              _ =>
                c.box(
                  w=Px(inner),
                  h=Px(inner),
                  radius=inner / 2.0,
                  bg=if state == "failed" { t.p.red } else { t.p.accent },
                  fn() {  },
                )
                |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}


///|
/// A row of an info card, its ground under the finger: a row of the ladder's.
let info_row_radius : Double = @sf.row_corner

///|
/// An info card round its rows: a list card's, its rows list_pad in.
let info_list_radius : Double = @sf.list_card_corner

///|
/// Rows on one quiet card (Android ChatInfo.kt InfoList): its rows list_pad in (a list card's), the ink at 5%.
// kept across runs: a value (no field of it changes)
let info_list_style : @ui.Style = @ui.css("w=Full bg=A(Fg,O5) clip").then(@ui.style(p=@sf.list_room))

///|
fn info_list(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=info_list_style, radius=info_list_radius, body) |> ignore
}

///|
/// A row of it (Android InfoRow): 44 high at least, its words INFO_TEXT (10) in from its sides and INFO_IN (4) from
/// top and bottom, what it holds 12 apart.
// kept across runs: a value (no field of it changes)
let info_row_style : @ui.Style = @ui.css("row w=Full min_h=S11 px=S2_5 py=S1 gap=S3")

///|
/// A row that leads with a tile (a model's mark, 36): its tile the ladder's inset in from the row's top and start, so
/// in the card's corner that and list_pad in, round by the ladder's small step (mbui works it out: 10.2 in 23, 16 in).
// kept across runs: a value (no field of it changes)
let info_row_tile : @ui.Style = @ui.css("p=S2_5 align=AStart")

///|
/// An agent's tile leading its row (a model's mark): as tall as its row's two lines (15 and 12 on the app's 1.4).
let info_tile : Double = 38.0

///|
/// A row that leads with a dot (a job's: 8 round, `job_dot_over` under its top): in the card's corner as far from both
/// its edges as makes it concentric with it (@sf.capsule_in), its words on the dot's line.
// kept across runs: a value (no field of it changes)
let info_row_dot : @ui.Style = @ui.style(
  pl=@sf.capsule_room(info_list_radius, job_dot_side, less=@sf.list_pad),
  pt=@sf.capsule_room(info_list_radius, job_dot_side, less=@sf.list_pad + job_dot_over),
)

///|
/// A job's dot (job_dot: 8), and how far under its row's words' top it stands, on its name's line (7).
let job_dot_side : Double = 8.0

///|
let job_dot_over : Double = 7.0

///|
/// Its ground rounded INFO_ROW, pressed a shade. True on the frame after it was tapped (never when `key` is "": a row
/// that leads nowhere).
fn info_row(
  c : @ui.Ctx,
  key : String,
  body : () -> Unit,
  align? : @ui.Align = ACenter,
  tile? : Bool = false,
  dot? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = if key == "" { 0 } else { c.id(key) }
  let look = if tile {
    info_row_style.then(info_row_tile)
  } else if dot {
    info_row_style.then(info_row_dot).then(@ui.style(align~))
  } else {
    info_row_style.then(@ui.style(align~))
  }
  c.box(style=look, radius=info_row_radius, id~, fn() {
    body()
    // ChatInfo.kt InfoRow: clip(Smooth(INFO_ROW)).clickable
    if id != 0 {
      @motion.ripple(c, id, info_row_radius)
    }
  })
  |> ignore
  id != 0 && c.clicked(id)
}

///|
fn chevron(c : @ui.Ctx) -> Unit {
  @sf.icon(c, "chevron-right", size=14.0, color=@sf.theme().p.subtle) |> ignore
}

///|
/// A tone's colour (the core's accent | green | blue | red | neutral).
fn tone_color(tone : String) -> Int64 {
  let t = @sf.theme()
  match tone {
    "accent" => t.p.accent
    "green" => t.p.green
    "blue" => if t.dark { 0x81AEFAFFL } else { 0x1559C4FFL }
    "red" => t.p.red
    "amber" | "warn" => 0xD9962BFFL
    _ => t.p.subtle
  }
}

///|
/// A choice of a few (Parts.kt Seg): mbui's toggle group (@kit.toggle_group: the arrows move along it, a screen reader
/// reads its options) in Seg's look: a track of the ink at 6%, 10 round, the chosen one on a light ground with a
/// hairline round it, its word in the ink (the others muted); `fill`, the options share the width. The one chosen,
/// after a tap on another.
fn seg(
  c : @ui.Ctx,
  key : String,
  labels : Array[String],
  chosen : Int,
  height? : Double = 30.0,
  fill? : Bool = false,
) -> Int {
  let t = @sf.theme()
  let items = labels.mapi(fn(i, l) { @kit.item(i.to_string(), label=l) })
  let now = @kit.toggle_group(
    c,
    key,
    items,
    [chosen.to_string()],
    grow=fill,
    look=fn(c, st) {
      c.box(
        w=if fill { Fill(1.0) } else { Auto },
        h=Fill(1.0),
        padx=if fill { 12.0 } else { 10.0 },
        radius=8.0,
        align=ACenter,
        justify=JCenter,
        bg=if st.on { if t.dark { 0x3A3B40FFL } else { 0xFFFFFFFFL } } else { 0L },
        border=if st.on { 0.5 } else { 0.0 },
        border_color=t.p.line,
        fn() {
          c.text(
            st.label,
            size=if fill { 14.0 } else { 13.0 },
            color=if st.on { t.p.text } else { t.p.muted },
            wrap=false,
          )
          |> ignore
        },
      )
      |> ignore
    },
    ground=fn(c, _, options) {
      c.box(
        dir=Row,
        w=if fill { Fill(1.0) } else { Auto },
        h=Px(height),
        pad=2.0,
        radius=10.0,
        bg=@sf.alpha(t.p.text, 0.06),
        options,
      )
      |> ignore
    },
  ).value
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(chosen)
    _ => chosen
  }
}

///|
/// For how long it has stood where it does (AgentSheet.kt agentSince): at work since its turn began, waiting as long
/// as it has (of at most), else when it was last at it.
fn agent_since(c : @ui.Ctx, src : Source, a : Json?) -> String {
  let wait = field(a, "wait")
  let since = opt_number(a, "since")
  if wait is None && since is None {
    return text(field(field(field(a, "session"), "time"), "lastActiveAt"), "ago")
  }
  let now = (src.now)()
  match wait {
    Some(Object(_)) => {
      let from = number(wait, "since")
      match opt_number(wait, "seconds") {
        Some(sec) => {
          // at its most it stands still
          if now - from < sec * second_ms {
            each_second(c, now - from)
          }
          elapsed(dmin(now, from + sec * second_ms) - from) + " / " + elapsed(sec * second_ms)
        }
        None => {
          each_second(c, now - from)
          elapsed(now - from)
        }
      }
    }
    _ => {
      let from = since.unwrap_or(now)
      each_second(c, now - from)
      elapsed(now - from)
    }
  }
}

///|
/// Where it stands (AgentSheet.kt AgentStatus): a dot in its tone on the first line's middle, its words and, muted,
/// for how long; two lines at most.
fn agent_status(c : @ui.Ctx, src : Source, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let since = agent_since(c, src, a)
  c.box(dir=Row, gap=6.0, align=AStart, fn() {
    c.box(pt=6.0, fn() {
      c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=tone_color(text(s, "tone")), fn() {  }) |> ignore
    })
    |> ignore
    let runs = [@ui.span(text(s, "statusText"))]
    if since != "" {
      runs.push(@ui.span(" · " + since, color=t.p.muted))
    }
    c.rich(runs, size=t.t.meta, line=18.0, color=t.p.text, w=Fill(1.0), max_lines=2) |> ignore
  })
  |> ignore
}

// ── the chat's own sheet (ChatInfo.kt) ──────────────────────────────────

///|
/// The chat itself, from "…" (ChatInfo.kt openChatInfo): its name (with a way to change it) over who started it, how
/// many take part and when it was last written in; its agents, each where it stands (a tap opens its card); then what
/// can be done with it: what its agents and other chats' wrote each other, pin it, copy its link, its sharing, archive
/// it. As tall as what it shows.
fn chat_info_body(c : @ui.Ctx, src : Source, r : ChatRef, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r)).value
  let (view, _, _) = view_of_chat(src, r)
  let agents = items(chat, "agents")
  let pinned = match field(chat, "pinned") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
  let slack = text(chat, "slackUrl")
  let slack_app = text(chat, "slackApp")
  let feishu = text(chat, "feishuUrl")
  let xshare = field(chat, "xshare")
  let (archived, offline) = match view {
    Some(v) => (v.archived, v.offline)
    None => (false, false)
  }
  // archived or offline it is only read: no name to change, nothing to archive
  let open = view is Some(_) && !archived && !offline
  let thread = field(chat, "thread")
  let link = if view is Some(_) { chat_link(r.station, r.session) } else { "" }
  let title = text(chat, "title")
  c.box(w=Fill(1.0), fn() {
    // (clear of an untitled dialog's close button over its end: @sf.untitled_clear)
    c.box(style=@sf.untitled_clear(), dir=Row, w=Fill(1.0), pt=4.0, gap=12.0, align=AStart, fn() {
      // (two lines at most, the last ending in an ellipsis: not a third cut off below them)
      c.box(w=Fill(1.0), fn() { c.text(title, size=t.t.title, weight=700, color=t.p.text, line=24.0, max_lines=2) |> ignore })
      |> ignore
      if open {
        let id = c.id("info/rename")
        if c.clicked(id) {
          open_rename(src, r, opt_number(thread, "id"), title, from=Of(id))
        }
        c.box(
          w=Px(32.0),
          h=Px(32.0),
          radius=16.0,
          bg=@sf.alpha(t.p.text, 0.05),
          align=ACenter,
          justify=JCenter,
          id~,
          fn() {
            @sf.icon(c, "edit", size=16.0, color=t.p.text) |> ignore
            // ChatInfo.kt: clip(CircleShape).clickable
            @motion.ripple(c, id, 16.0)
          },
        )
        |> ignore
      }
    })
    |> ignore
    // who started it and when, how many take part, when it was last written in: what there is of them, in a line
    let facts : Array[String] = []
    match text(chat, "place") {
      "" => ()
      p => facts.push(fill("android-chat.info.from.slack", [("place", p)]))
    }
    let creator = match field(thread, "creator") {
      Some(Object(_)) as cr =>
        match text(field(cr, "shown"), "display") {
          "" => text(cr, "name")
          d => d
        }
      _ => ""
    }
    let created = text(field(field(thread, "time"), "createdAt"), "ago")
    if creator != "" && created != "" {
      facts.push(fill("android-chat.info.startedAt", [("name", creator), ("ago", created)]))
    } else if creator != "" {
      facts.push(creator)
    } else if created != "" {
      facts.push(created)
    }
    let people = match view {
      Some(v) => v.people
      None => []
    }
    if people.length() > 1 {
      facts.push(fill("android-chat.info.people.count", [("n", people.length().to_string())]))
    }
    match text(field(field(field(thread, "lastMessage"), "time"), "createdAt"), "ago") {
      "" => ()
      ago => facts.push(fill("android-chat.info.latestAt", [("ago", ago)]))
    }
    c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=16.0, gap=8.0, align=ACenter, fn() {
      if people.length() > 0 {
        let shown = if people.length() > 5 { people[:5].to_array() } else { people }
        c.box(w=Px(19.0 + 14.0 * (shown.length() - 1).to_double()), fn() {
          // ringed in the sheet's ground (ChatInfo.kt: C.surface)
          people_stack(c, src, shown, 16.0, ring=t.p.card)
        })
        |> ignore
      }
      c.box(w=Fill(1.0), fn() {
        // (in as many lines as they take: words of no length known, none of them cut)
        c.text(facts.join(" · "), size=t.t.meta, color=t.p.muted, w=Fill(1.0)) |> ignore
      })
      |> ignore
    })
    |> ignore
    // the pull requests linked in it, the latest 3 (the user, 2026-10-29: most chats have one or two, seen at a look),
    // 全部 N 个 to the rest; tapped, one opens in the browser
    let (said, pulls) = match opt_number(thread, "id") {
      Some(th) => @sfpages.things_now(src, r.station, th)
      None => (0, [])
    }
    if agents.length() > 0 {
      info_list(c, fn() {
        for a in agents {
          let av = Some(a)
          let s = field(av, "session")
          let key = text(s, "key")
          if info_row(c, "info/agent/" + key, fn() {
              // (as tall as its two lines: in the card's corners as far from its top as from its foot)
              model_mark_big(
                c,
                text(field(s, "maker"), "id"),
                text(s, "runtime"),
                info_tile,
                state_of_badge(text(av, "badge")),
                @sf.over(t.p.bg, @sf.alpha(t.p.card, 0.8)),
              )
              // its name, how it is, and its allowance under them, each a line of its own (beside its name the
              // allowance took the name's room, or left the row where it had not the room: the allowance gone)
              c.box(w=Fill(1.0), keep=true, fn() {
                c.text(text(s, "agentText"), style=info_agent_name, keep=true) |> ignore
                let since = agent_since(c, src, av)
                let line = if since == "" {
                  text(s, "statusText")
                } else {
                  text(s, "statusText") + " · " + since
                }
                c.text(line, style=info_agent_line, keep=true) |> ignore
                allowance_line(c, match field(field(av, "account"), "quota") {
                  Some(_) as q => q
                  None => field(field(av, "profile"), "quota")
                })
              })
              |> ignore
              chevron(c)
            }, tile=true) {
            close()
            open_agent(src, r, key)
          }
        }
      })
      c.box(h=Px(10.0), fn() {  }) |> ignore
    }
    // then what is in it, one card (the user, 2026-10-30: who works in it before what it made, what it holds apart
    // from what is done with it): its pull requests, what else was said, what its agents and other chats' wrote
    let letters = number(chat, "letters")
    if pulls.length() > 0 || said > 0 || letters > 0.0 {
      info_list(c, fn() {
        for i, p in pulls {
          if i == info_pulls_most {
            break
          }
          let pv = Some(p)
          // held or right clicked, its menu (在对话中查看, its link copied); pointed at, its card (sfpages things.mbt)
          let pid = c.id("info/pull/" + text(pv, "key"))
          @sfpages.thing_menu(c, pid, number(pv, "seq"), text(pv, "url"), fn(seq) {
            close()
            go_to(r, seq)
          })
          @sfpages.web_peek(c, src, r.station, text(pv, "url"), @sfpages.pull_title(pv), pid, side=Left)
          if info_row(c, "info/pull/" + text(pv, "key"), fn() {
              @sfpages.pull_mark(c, pv, 16.0)
              c.box(style=@sf.full_width, fn() { c.text(@sfpages.pull_title(pv), style=info_pull_title) |> ignore }) |> ignore
              c.text("#" + count(pv, "number").to_string(), style=letters_meta) |> ignore
            }) {
            close()
            @sfbase.open_link_in(src, text(pv, "url"))
          }
        }
        match opt_number(thread, "id") {
          Some(th) if pulls.length() > info_pulls_most =>
            if info_row(c, "info/pulls", fn() {
                @sf.icon(c, "list", size=16.0, color=t.p.text) |> ignore
                c.box(style=@sf.full_width, fn() {
                  c.text(fill("web-main.things.pullsAll", [("n", pulls.length().to_string())]), style=info_words) |> ignore
                })
                |> ignore
                chevron(c)
              }) {
              close()
              @sfpages.things_choose(r, "pulls")
              open_things(src, r, th)
            }
          _ => ()
        }
        // what was said in it besides words: a sheet of their own (sfpages things.mbt)
        match opt_number(thread, "id") {
          Some(th) if said > 0 =>
            if info_row(c, "info/things", fn() {
                @sf.icon(c, "photo", size=16.0, color=t.p.text) |> ignore
                c.box(style=@sf.full_width, fn() { c.text(tr("web-main.things.title"), style=info_words) |> ignore })
                |> ignore
                c.text(said.to_string(), style=letters_meta) |> ignore
                chevron(c)
              }) {
              close()
              open_things(src, r, th)
            }
          _ => ()
        }
        // what its agents and other chats' wrote each other, not in the chat: their own sheet (Letters.kt)
        match opt_number(thread, "id") {
          Some(th) if letters > 0.0 =>
            if info_row(c, "info/letters", fn() {
                @sf.icon(c, "chats", size=16.0, color=t.p.text) |> ignore
                c.box(style=@sf.full_width, fn() { c.text(tr("web-main.letters.title"), style=info_words) |> ignore })
                |> ignore
                c.text(fill("web-main.letters.count", [("n", letters.to_int().to_string())]), style=letters_meta) |> ignore
                chevron(c)
              }) {
              close()
              open_letters(src, r, th)
            }
          _ => ()
        }
      })
      c.box(style=info_lists_gap, fn() {  }) |> ignore
    }
    if open || link != "" || slack != "" || xshare is Some(_) {
      info_list(c, fn() {
        // a station from before pins says nothing of them: its chats are not pinned from here
        match pinned {
          Some(p) if open => {
            let pkey = "pin/" + r.station + "/" + r.session
            let busy = doing(pkey)
            if info_row(c, if busy { "" } else { "info/pin" }, fn() {
                @sf.icon(c, "pin", size=16.0, color=t.p.text) |> ignore
                c.box(w=Fill(1.0), fn() {
                  c.text(
                    tr(if p { "android-chat.unpin" } else { "android-chat.info.pinTop" }),
                    size=t.t.ui,
                    color=t.p.text,
                    wrap=false,
                  )
                  |> ignore
                })
                |> ignore
                if busy {
                  @sf.spinner(c, size=12.0) |> ignore
                }
              }) {
              act(
                src,
                tr(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
                pkey,
                "chat.pin",
                {
                  "station": Json::string(r.station),
                  "session": Json::string(r.session),
                  "pinned": Json::boolean(!p),
                },
              )
            }
          }
          _ => ()
        }
        if link != "" &&
          info_row(c, "info/link", fn() {
            @sf.icon(c, "copy", size=16.0, color=t.p.text) |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(tr("web-main.chat.copyLink"), size=t.t.ui, color=t.p.text, wrap=false) |> ignore
            })
            |> ignore
          }) {
          copy_chat_link(c, title, link)
        }
        // relayed to a channel (docs/relay.md, Relay.kt): a chat with an agent to go on there
        match opt_number(thread, "id") {
          Some(th) if open && agents.length() > 0 =>
            if info_row(c, "info/relay", fn() {
                @sf.icon(c, "arrow-up-right", size=16.0, color=t.p.text) |> ignore
                c.box(style=@sf.full_width, fn() { c.text(tr("web-main.relay.action"), style=info_words) |> ignore })
                |> ignore
                chevron(c)
              }) {
              // (the chat's sheet put down, the picking up in its place)
              close()
              @sfpages.open_relay(src, r, th, from=Unanchored)
            }
          _ => ()
        }
        match xshare {
          Some(Object(_)) => xshare_row(c, src, r, opt_number(thread, "id"), xshare, close)
          _ => ()
        }
        // where it came from, opened there (the system's app for its link)
        if slack != "" &&
          info_row(c, "info/slack", fn() {
            @sf.slack_mark(c, 16.0) |> ignore
            c.box(style=@sf.full_width, fn() { c.text(tr("android-chat.info.slack.open"), style=info_words) |> ignore })
            |> ignore
            chevron(c)
          }) {
          if !@sfbase.open_slack(slack_app, slack) {
            toast_later(tr("android-chat.link.failed"))
          }
        }
        if feishu != "" &&
          info_row(c, "info/feishu", fn() {
            @sf.feishu_mark(c, 16.0) |> ignore
            c.box(style=@sf.full_width, fn() { c.text(tr("web-mobile.chat.openFeishu"), style=info_words) |> ignore })
            |> ignore
            chevron(c)
          }) {
          open_outside(feishu)
        }
        // into the archive, back to the list at once
        if open &&
          info_row(c, "info/archive", fn() {
            @sf.icon(c, "archive", size=16.0, color=t.p.text) |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(tr("android-chat.info.archive"), size=t.t.ui, color=t.p.text, wrap=false) |> ignore
            })
            |> ignore
          }) {
          // a chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words)
          match (view, text(field(chat, "watch"), "ask")) {
            (Some(v), "") => archive_chat(src, r, v)
            (Some(v), ask) => {
              close()
              @sf.confirm(fill("android-chat.archive.ask", [("title", title)]), ask, tr("android-chat.archive"), fn() {
                archive_chat(src, r, v)
              })
            }
            (None, _) => ()
          }
        }
      })
    }
    // making it public, a card of its own (publish.mbt)
    match shown_publish(chat) {
      Some(_) as p => publish_list(c, src, r, number(thread, "id"), p, close)
      None => ()
    }
  })
  |> ignore
}

///|
/// The chat's own sheet (chat_info_body) from "…": the library's panel, as tall as what it shows, its head its own (its
/// name with ✎ beside it).
fn open_info(src : Source, r : ChatRef) -> Unit {
  @sf.panel("", from=Unanchored, fn(c, close) { chat_info_body(c, src, r, close) })
}

///|
/// The chat renamed (ChatInfo.kt askTitle), asked for its name as it was (@sf.ask): said, the core's `chat.rename`.
fn open_rename(src : Source, r : ChatRef, thread : Double?, was : String, from~ : @sf.Anchor) -> Unit {
  @sf.ask(
    tr("android-chat.rename.title"),
    tr("common.save"),
    fn(title) {
      let p : Map[String, Json] = {
        "station": Json::string(r.station),
        "session": Json::string(r.session),
        "title": Json::string(title),
      }
      match thread {
        Some(th) => p["thread"] = Json::number(th)
        None => ()
      }
      act(src, tr("android-chat.rename.verb"), "", "chat.rename", Json::object(p))
    },
    value=was,
    placeholder=tr("android-chat.rename.field"),
    hint=tr("android-chat.rename.note"),
    // (empty: named anew, as its note says)
    empty=true,
    from~,
  )
}

// ── an agent's card (AgentSheet.kt) ─────────────────────────────────────

///|
/// An agent of the chat in brief (AgentSheet.kt openAgent): what it runs and where it stands (with a stop while it
/// works), its latest lines, the figures that say most, then where to go on: the station it runs on, its account, its
/// history, its jobs; and its context by hand (context.mbt).
fn agent_body(c : @ui.Ctx, src : Source, r : ChatRef, key : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r)).value
  let a = agent_json(chat, key)
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let jobs = items(a, "jobs")
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(workspace_of(r.station)) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let s = field(a, "session")
  let status = text(a, "status")
  c.box(w=Fill(1.0), fn() {
    c.box(style=@sf.untitled_clear(), dir=Row, w=Fill(1.0), pt=4.0, gap=12.0, align=ACenter, fn() {
      model_mark_big(
        c,
        text(field(s, "maker"), "id"),
        text(s, "runtime"),
        40.0,
        state_of_badge(text(a, "badge")),
        @sf.over(t.p.bg, @sf.alpha(t.p.card, 0.8)),
      )
      c.box(w=Fill(1.0), gap=1.0, fn() {
        c.text(text(s, "agentText"), size=t.t.title, weight=700, color=t.p.text, wrap=false) |> ignore
        agent_status(c, src, a)
      })
      |> ignore
      if status == "running" || status == "queued" {
        stop_button(c, src, r.station, key)
      }
    })
    |> ignore
    agent_lines(c, card)
    let entry = context_entry(c, src, r, key, s)
    agent_tiles(c, card, 14.0, entry~)
    agent_notes(c, card, 10.0)
    c.box(h=Px(12.0), fn() {  }) |> ignore
    info_list(c, fn() {
      match station {
        Some(st) =>
          if info_row(c, "agent/station", fn() {
              c.text(tr("android-chat.agent.station"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
              c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                if @sf.has_station_mark(st.emoji, st.icon) {
                  @sf.station_mark(c, st.emoji, st.icon, 15.0, t.p.text)
                }
                c.text(st.name, size=t.t.ui, color=t.p.text, wrap=false, w=Cut) |> ignore
              })
              |> ignore
              chevron(c)
            }) {
            // the station's card in place of this one
            close()
            @settings.open_station_peek(r.station, from=Unanchored)
          }
        None => ()
      }
      let account = match field(a, "account") {
        Some(Object(_)) as acc => acc
        _ => field(a, "profile")
      }
      let name = text(account, "name")
      let value = if name == "" {
        tr("android-chat.agent.account.none")
      } else if flag(s, "profilePinned") {
        name
      } else {
        fill("android-chat.agent.account.auto", [("name", name)])
      }
      // changing how it runs is a page of its own (History.kt RunSettingsScreen)
      if agent_row(c, "agent/account", tr("android-chat.agent.account"), value, fn() {  }, under=fn() {
          allowance_line(c, field(account, "quota"))
        }) {
        close()
        app.nav.push(Setting(@settings.Route::RunSettings(r.station, key)))
      }
      if agent_row(
          c,
          "agent/history",
          tr("android-chat.agent.history"),
          match text(card, "work") {
            "" => tr("android-chat.agent.history.none")
            w => w
          },
          fn() {  },
        ) {
        close()
        app.nav.push(History(r, key, None))
      }
      // what can be done to its context, where no figure of it is known to be its tile (a station from before tells
      // none of an agent at rest)
      match entry {
        Some(e) if !(field(card, "context") is Some(Object(_))) =>
          if agent_row(c, "agent/context", tr("android-chat.agent.context"), "", fn() {
              if e.busy || e.failed {
                @settings.doing_mark(c, e.busy, if e.failed { Some("") } else { None })
              }
            }) &&
            !e.busy {
            (e.open)()
          }
        _ => ()
      }
      if jobs.length() > 0 &&
        agent_row(
          c,
          "agent/jobs",
          tr("android-chat.agent.jobs"),
          match text(card, "jobs") {
            "" => tr("android-chat.agent.jobs.idle")
            j => j
          },
          fn() {  },
        ) {
        dui.jobs_all = false
        close()
        open_chat_jobs(src, r)
      }
    })
  })
  |> ignore
}

///|
/// An agent's card (agent_body): the library's panel, as tall as what it shows, its head its own (its mark, name and
/// where it stands).
fn open_agent(src : Source, r : ChatRef, key : String) -> Unit {
  @sf.panel("", from=Unanchored, fn(c, close) { agent_body(c, src, r, key, close) })
}

///|
/// A row of the card (AgentSheet.kt AgentRow): what it is about, what there is of it (`under` it what goes with it:
/// an account's allowance, a line of its own), what is under way at its end (`trailing`), where a tap leads.
fn agent_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  value : String,
  trailing : () -> Unit,
  under? : () -> Unit,
) -> Bool {
  let t = @sf.theme()
  info_row(c, key, fn() {
    c.text(label, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
    c.box(w=Fill(1.0), keep=true, fn() {
      c.text(value, style=agent_row_value, keep=true) |> ignore
      match under {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
    trailing()
    chevron(c)
  })
}

///|
/// An account's allowance (its chips) on a line of its own under what names it, 4 under it; nothing where it says none.
fn allowance_line(c : @ui.Ctx, quota : Json?) -> Unit {
  if @sf.has_quota(quota) {
    c.box(style=allowance_box, fn() { @sf.quota_chips(c, quota) }) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let allowance_box : @ui.Style = @ui.css("row pt=S1")

///|
/// What an agent's row says (its account, its history): on a line, whole while what follows it may leave the row.
// kept across runs: a value (no field of it changes)
let agent_row_value : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// An agent's name in the chat's info (600) and how it is under it (the caption's, muted): each on a line, whole while
/// its allowance may leave the row.
// kept across runs: a value (no field of it changes)
let info_agent_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let info_agent_line : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, w=Cut)

///|
/// Stopping its turn, while it works (AgentSheet.kt StopButton): red on its tint, a spinner while it is asked.
fn stop_button(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let t = @sf.theme()
  let skey = "stop/" + station + "/" + key
  let busy = doing(skey)
  let id = c.id("agent/stop")
  if !busy && c.clicked(id) {
    act(
      src,
      tr("android-chat.agent.stop"),
      skey,
      "session.stop",
      { "station": Json::string(station), "key": Json::string(key) },
      done=tr("android-chat.history.stopped"),
    )
  }
  c.box(
    dir=Row,
    h=Px(32.0),
    padx=14.0,
    gap=6.0,
    radius=16.0,
    align=ACenter,
    bg=@sf.alpha(t.p.red, 0.14),
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else {
        @sf.icon(c, "stop", size=11.0, color=t.p.red) |> ignore
      }
      c.text(tr("android-chat.agent.stop"), size=t.t.meta, weight=500, color=t.p.red, wrap=false) |> ignore
      // its clip clickable
      @motion.ripple(c, id, 16.0)
    },
  )
  |> ignore
}

///|
/// Its latest lines (AgentLines): the things it did, then what it does now, in the ink.
fn agent_lines(c : @ui.Ctx, card : Json?) -> Unit {
  let latest = items(card, "latest")
  if latest.length() == 0 {
    return
  }
  let t = @sf.theme()
  c.box(w=Fill(1.0), pt=12.0, gap=3.0, fn() {
    for l in latest {
      c.text(
        text(Some(l), "text"),
        size=t.t.meta,
        color=if flag(Some(l), "now") { t.p.text } else { t.p.muted },
        wrap=false,
        line=18.0,
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// The figures that say most (AgentTiles): what it cost, the cache's hit rate, how full its context is, each large over
/// its name, side by side; a context worth a look in its level's colour.
fn agent_tiles(c : @ui.Ctx, card : Json?, top : Double, entry? : ContextTile? = None) -> Unit {
  let t = @sf.theme()
  let context = field(card, "context")
  let cost = text(card, "cost")
  let cache = field(card, "cache")
  // none known (a station from before tells none of an agent at rest): no figures, its context's entry a row instead
  if cost == "" && !(cache is Some(Object(_))) && !(context is Some(Object(_))) {
    return
  }
  let tile = fn(figure : String, name : String, color : Int64, open : ContextTile?) {
    // its context's, when something can be done to it (context.mbt): a tap opens it
    let id = if open is Some(_) { c.id("agent/context-tile") } else { 0 }
    c.box(
      id~,
      w=Fill(1.0),
      radius=14.0,
      bg=@sf.alpha(t.p.text, 0.05),
      pl=12.0,
      pr=12.0,
      pt=9.0,
      pb=8.0,
      // (AgentTiles: 「name figure」 to a screen reader)
      label=name + " " + figure,
      fn() {
        c.box(h=Px(26.0), justify=JCenter, fn() {
          c.text(
            figure,
            size=if figure.length() > 6 { 16.0 } else { 20.0 },
            weight=600,
            color~,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        context_tile_name(c, name, open)
      },
    )
    |> ignore
    match open {
      Some(o) => if !o.busy && c.clicked(id) { (o.open)() }
      None => ()
    }
  }
  c.box(dir=Row, w=Fill(1.0), pt=top, gap=8.0, fn() {
    if cost != "" {
      tile(cost, tr("android-chat.agent.cost"), t.p.text, None)
    }
    if cache is Some(Object(_)) {
      tile(text(cache, "text"), tr("android-chat.agent.cache"), t.p.text, None)
    }
    let name = context_tile_label(entry, text(context, "level"))
    match context {
      Some(Object(_)) =>
        if flag(context, "unknown") {
          tile(text(context, "text"), name, t.p.text, entry)
        } else {
          tile(
            "\{number(context, "percent").round().to_int()}%",
            name,
            match text(context, "level") {
              "red" => t.p.red
              "amber" => t.p.warn_ink
              _ => t.p.text
            },
            entry,
          )
        }
      _ => ()
    }
  })
  |> ignore
}

///|
/// What is wrong (AgentNotes), a line each in its level's colour.
fn agent_notes(c : @ui.Ctx, card : Json?, top : Double) -> Unit {
  let notes = items(card, "attention")
  if notes.length() == 0 {
    return
  }
  let t = @sf.theme()
  c.box(w=Fill(1.0), pt=top, gap=2.0, fn() {
    for n in notes {
      c.text(
        text(Some(n), "text"),
        size=t.t.meta,
        color=if text(Some(n), "level") == "amber" { t.p.warn_ink } else { t.p.red },
        line=18.0,
      )
      |> ignore
    }
  })
  |> ignore
}

// ── jobs (Jobs.kt, OpenJobs.kt) ─────────────────────────────────────────

///|
/// A job's dot's colour (Jobs.kt toneTint): a service up or a job alive green, one restarting amber, one that died
/// red; one over the subtle grey (None: the text's own for its word).
fn job_tint(tone : String) -> Int64? {
  let t = @sf.theme()
  match tone {
    "up" | "live" => Some(t.p.green)
    "restart" => Some(0xD9962BFFL)
    "fail" => Some(t.p.red)
    _ => None
  }
}

///|
/// A job's status (JobDot): a small dot (a restarting service's breathes).
fn job_dot(c : @ui.Ctx, tone : String) -> Unit {
  let t = @sf.theme()
  let dot = c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=job_tint(tone).unwrap_or(t.p.subtle), fn() {  })
  if tone == "restart" {
    @sf.breathe(c, dot, low=0.35, resident=true)
  }
}

///|
/// The line under a job's name (metaOf): its state's word in its dot's colour's ink (green's, amber's, red: the dot's
/// green read 3.2 to 1), what it said in the ink.
fn job_meta(c : @ui.Ctx, job : Json?, size : Double) -> Unit {
  let t = @sf.theme()
  let word = match text(job, "tone") {
    "up" | "live" => t.p.green_ink
    "restart" => t.p.warn_ink
    "fail" => t.p.red
    _ => 0L
  }
  let runs = items(job, "meta").map(fn(p) {
    let pv = Some(p)
    match text(pv, "kind") {
      "word" => @ui.span(text(pv, "text"), color=word)
      "notice" => @ui.span(text(pv, "text"), color=t.p.text)
      _ => @ui.span(text(pv, "text"))
    }
  })
  c.rich(runs, size~, color=t.p.muted, wrap=false) |> ignore
}

///|
/// A job's row (JobInfoRow): its dot on its name's line, what it is up to under it; an over one's name stepped back to
/// the muted grey, not faded (at 55% its words were 2.3 to 1: docs/ui-panels.md 对比度).
fn job_row(c : @ui.Ctx, key : String, job : Json?) -> Bool {
  let t = @sf.theme()
  let off = job_tint(text(job, "tone")) is None
  info_row(
    c,
    key,
    fn() {
      c.box(pt=job_dot_over, fn() { job_dot(c, text(job, "tone")) }) |> ignore
      c.box(w=Fill(1.0), gap=1.0, fn() {
        c.text(text(job, "name"), size=t.t.ui, weight=500, color=if off { t.p.muted } else { t.p.text }, wrap=false)
        |> ignore
        job_meta(c, job, 12.5)
      })
      |> ignore
      c.box(pt=4.0, fn() { chevron(c) }) |> ignore
    },
    align=AStart,
    dot=true,
  )
}

///|
/// A group's label (Controls.kt GroupLabel): 13, muted, 14 above it and 4 under.
fn group_label(c : @ui.Ctx, label : String) -> Unit {
  c.box(pt=14.0, pb=4.0, fn() {
    c.text(label, size=@sf.theme().t.meta, color=@sf.theme().p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// Services, then background jobs (Jobs.kt JobGroups), each group's head with how many are up or alive; a service up
/// or being started again opens its page (service.mbt), one that did not start (or is over) and any job its sheet.
fn job_groups(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  view : Json?,
  jobs : Array[Json],
  close : () -> Unit,
  pick? : ((String) -> Unit)? = None,
) -> Unit {
  let services = jobs.filter(fn(j) { flag(Some(j), "service") })
  let plain = jobs.filter(fn(j) { !flag(Some(j), "service") })
  let head = fn(key : String, note : String) {
    group_label(c, tr(key) + (if note != "" { " · " + note } else { "" }))
  }
  if services.length() > 0 {
    head("android-misc.jobs.services", text(view, "servicesNote"))
    info_list(c, fn() {
      for j in services {
        let id = text(Some(j), "id")
        if job_row(c, "job/" + id, Some(j)) {
          // up or being started again: its page (Preview.kt); else what it said and its output (picked where it is
          // shown beside the list: the wide frame's 任务 tab)
          let tone = text(Some(j), "tone")
          if pick is Some(f) && tone != "up" && tone != "restart" {
            f(id)
          } else if tone == "up" || tone == "restart" {
            close()
            app.nav.push(Service(r.station, id))
          } else {
            dui.job_tab = 1
            close()
            open_job(src, r, id)
          }
        }
      }
    })
  }
  if plain.length() > 0 {
    head("android-misc.jobs.jobs", text(view, "jobsNote"))
    info_list(c, fn() {
      for j in plain {
        let id = text(Some(j), "id")
        if job_row(c, "job/" + id, Some(j)) {
          dui.job_tab = 0
          match pick {
            Some(f) => f(id)
            None => {
              close()
              open_job(src, r, id)
            }
          }
        }
      }
    })
  }
}

///|
/// What matters now of the chat's services and jobs (Jobs.kt openJobs), from the bar's button: the rest a tap away,
/// the ended cleared.
fn jobs_body(c : @ui.Ctx, src : Source, r : ChatRef, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("chatJobs", chat_params(r))
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => {
      waiting_rows(c, topic.error, fn() { jobs_sample(c, r) })
      return
    }
  }
  let jobs = items(view, "jobs")
  let shown = if dui.jobs_all { jobs } else { jobs.filter(fn(j) { flag(Some(j), "current") }) }
  let clear_key = "clear/" + r.station
  let rows : Array[() -> Unit] = []
  if jobs.length() == 0 {
    rows.push(fn() {
      c.box(padx=2.0, pady=12.0, gap=4.0, fn() {
        c.text(tr("android-misc.jobs.none"), size=t.t.ui, weight=600, color=t.p.text) |> ignore
        c.text(tr("android-misc.jobs.none.text"), size=t.t.meta, color=t.p.muted) |> ignore
      })
      |> ignore
    })
  }
  if jobs.length() > 0 && shown.length() == 0 {
    rows.push(fn() {
      c.box(padx=20.0, pady=8.0, fn() {
        c.text(tr("android-misc.jobs.noneNow"), size=t.t.meta, color=t.p.muted) |> ignore
      })
      |> ignore
    })
  }
  rows.push(fn() { job_groups(c, src, r, view, shown, close) })
  if jobs.length().to_double() > number(view, "current") {
    rows.push(fn() {
      if sheet_link(c, "jobs/all", fn() {
          if dui.jobs_all {
            c.text(tr("android-misc.jobs.onlyNow"), size=@sf.theme().t.ui, color=@sf.link_ink(), wrap=false) |> ignore
          } else {
            c.text(text(view, "allText"), size=@sf.theme().t.ui, color=@sf.link_ink(), wrap=false) |> ignore
            c.text(text(view, "hiddenText"), size=t.t.caption, color=t.p.muted) |> ignore
          }
        }) {
        dui.jobs_all = !dui.jobs_all
      }
    })
  }
  if number(view, "ended") > 0.0 {
    rows.push(fn() {
      if sheet_link(c, "jobs/clear", fn() {
          c.box(dir=Row, gap=6.0, align=ACenter, fn() {
            c.text(text(view, "clearText"), size=@sf.theme().t.ui, color=@sf.link_ink(), wrap=false) |> ignore
            if doing(clear_key) {
              @sf.spinner(c, size=12.0) |> ignore
            }
          })
          |> ignore
        }) &&
        !doing(clear_key) {
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
    })
  }
  // (its rows on the panel's words' line as the list builds them, as tall as they come to up to the panel's share:
  // @sf.panel_list)
  // (no room of its own under its last: the panel's foot is under it)
  @sf.panel_list(
    c,
    "jobs-sheet/" + r.station + "/" + r.session,
    rows.length(),
    60.0,
    fn(i) { c.box(style=@sf.panel_words_in(), w=Fill(1.0), fn() { (rows[i])() }) |> ignore },
  )
  |> ignore
}

///|
/// The chat's services and jobs (jobs_body): the library's panel, 62% of the window, dragged between half and nearly
/// all of it.
fn open_chat_jobs(src : Source, r : ChatRef) -> Unit {
  @sf.panel(tr("android-misc.jobs.title"), from=Unanchored, tall=0.62, grows=true, fn(c, close) { jobs_body(c, src, r, close) })
}

///|
/// A quiet text button under the groups (Jobs.kt SheetLink).
fn sheet_link(c : @ui.Ctx, key : String, body : () -> Unit) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(pt=14.0, fn() {
    c.box(padx=2.0, pady=6.0, gap=2.0, radius=8.0, id~, fn() {
      body()
      // Jobs.kt SheetLink: clip(Smooth(8)).clickable
      @motion.ripple(c, id, 8.0)
    })
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// What is being read the first time (the library's Waiting): `sample`, its rows of made-up words, in their bones;
/// what went wrong over them in red.
fn waiting_rows(c : @ui.Ctx, error : Json?, sample : () -> Unit) -> Unit {
  c.box(w=Fill(1.0), padx=18.0, fn() {
    @sf.waiting(c, sample, error=match error {
      Some(e) => error_words(e)
      None => ""
    })
  })
  |> ignore
}

///|
/// A job, from the chat's sheet (Jobs.kt openJob, JobBody): its name and how it stands, what it said or its output as it
/// grows (a service has only its output), stopped from here while it runs.
fn job_body(c : @ui.Ctx, src : Source, r : ChatRef, id : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("chatJobs", chat_params(r))
  let job = items(topic.value, "jobs").iter().find_first(fn(j) { text(Some(j), "id") == id })
  let j = match job {
    Some(j) => Some(j)
    None => {
      c.box(style=@sf.panel_words_in(), fn() {
        c.text(
          if topic.value is Some(_) { tr("android-misc.jobs.gone") } else { tr("common.reading") },
          size=t.t.meta,
          color=t.p.muted,
        )
        |> ignore
      })
      |> ignore
      return
    }
  }
  job_detail(c, src, r, id, j)
}

///|
/// A job (job_body): the library's panel, most of the window, dragged between half and nearly all of it; titled 任务
/// while it is not there (read, or gone), its own head (its dot and name) once it is.
fn open_job(src : Source, r : ChatRef, id : String) -> Unit {
  let missing = fn() {
    !items((src.topic)("chatJobs", chat_params(r)).value, "jobs").iter().any(fn(j) { text(Some(j), "id") == id })
  }
  @sf.panel(
    "",
    from=Unanchored,
    tall=0.8,
    grows=true,
    live=fn() { (if missing() { tr("android-misc.jobs.job") } else { "" }, "", "") },
    fn(c, close) { job_body(c, src, r, id, close) },
  )
}

///|
/// A job, what it is, said and wrote (Jobs.kt openJob's body): its dot, name and line, its command, then what it said
/// or its output (a service's output alone), and stopping it while it runs. In its panel (open_job), on its words' line
/// (the wide frame's 任务 tab has its own: sfdesk's jobs.mbt).
fn job_detail(c : @ui.Ctx, src : Source, r : ChatRef, id : String, j : Json?) -> Unit {
  let t = @sf.theme()
  let service = flag(j, "service")
  let tab = if service { 1 } else { dui.job_tab }
  let running = text(j, "state") == "running"
  // (on its panel's words' line, clear of an untitled dialog's close button)
  c.box(style=@sf.panel_words_in().then(@sf.untitled_clear()), dir=Row, w=Fill(1.0), pt=4.0, pb=14.0, gap=12.0, align=AStart, fn() {
    c.box(pt=8.0, fn() { job_dot(c, text(j, "tone")) }) |> ignore
    c.box(w=Fill(1.0), fn() {
      c.text(text(j, "name"), size=t.t.title, weight=600, color=t.p.text) |> ignore
      job_meta(c, j, 12.5)
    })
    |> ignore
  })
  |> ignore
  c.box(style=@sf.panel_words_in(), w=Fill(1.0), h=Fill(1.0), pb=24.0, gap=14.0, fn() {
    let command = text(j, "command")
    if command.trim(chars=" \n").to_string() != "" {
      c.rich([@ui.span(command, mono=true)], size=t.t.caption, line=17.0, color=t.p.muted, w=Fill(1.0)) |> ignore
    }
    if !service {
      dui.job_tab = seg(
        c,
        "job/tab",
        [tr("android-misc.jobs.notices"), tr("android-misc.jobs.output")],
        tab,
        height=34.0,
        fill=true,
      )
    }
    if tab == 0 {
      let notices = items(j, "notices")
      c.box(w=Fill(1.0), gap=12.0, fn() {
        if notices.length() == 0 {
          c.box(padx=20.0, pady=8.0, fn() {
            c.text(tr("android-misc.jobs.noNotices"), size=t.t.meta, color=t.p.muted) |> ignore
          })
          |> ignore
        }
        for n in notices {
          c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
            c.box(w=Px(48.0), fn() {
              c.text(text(Some(n), "clock"), size=t.t.meta, color=t.p.subtle, wrap=false) |> ignore
            })
            |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(text(Some(n), "text"), size=t.t.ui, color=t.p.text) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      let last = @sfbase.hold(src, @sfbase.jobs_scope(r.station), "jobLog", {
        "station": Json::string(r.station),
        "job": Json::string(id),
        "lines": Json::number(1.0),
      }).value
      let said = match last {
        Some(Object(_)) => text(last, "said")
        _ => text(j, "outputSaid")
      }
      if said != "" {
        c.box(w=Fill(1.0), gap=2.0, fn() {
          c.text(said, size=t.t.caption, color=t.p.subtle) |> ignore
          match text(last, "last") {
            "" => ()
            l => c.rich([@ui.span(l, mono=true)], size=t.t.caption, color=t.p.muted, wrap=false) |> ignore
          }
        })
        |> ignore
      }
    } else {
      // in a terminal's colours where the core says them (its `runs`: Jobs.kt termText), else as words
      let output = job_output_lines(src, r.station, id, 300.0, t.p.text, t.dark)
      c.box(
        w=Fill(1.0),
        h=Fill(1.0),
        min_h=120.0,
        radius=16.0,
        bg=@sf.alpha(t.p.text, 0.05),
        clip=true,
        fn() {
          match output {
            Some(written) => {
              let lines = if written.is_empty() {
                [[@ui.span(tr("android-misc.jobs.noOutput"), mono=true)]]
              } else {
                written
              }
              c.list(
                "job-log/" + id,
                lines.length(),
                17.0,
                fn(i) {
                  c.box(w=Fill(1.0), padx=14.0, pt=if i == 0 { 12.0 } else { 0.0 }, pb=if i ==
                    lines.length() - 1 {
                      12.0
                    } else {
                      0.0
                    }, fn() {
                    c.rich(lines[i], size=t.t.caption, line=17.0, color=t.p.text, w=Fill(1.0)) |> ignore
                  })
                  |> ignore
                },
                stick_end=true,
              )
              |> ignore
            }
            _ =>
              c.box(padx=14.0, pady=12.0, fn() { @sf.spinner(c, size=12.0) |> ignore }) |> ignore
          }
        },
      )
      |> ignore
    }
    if running {
      let skey = "job-stop/" + r.station + "/" + id
      let busy = doing(skey)
      let sid = c.id("job/stop")
      if !busy && c.clicked(sid) {
        act(
          src,
          fill("android-misc.jobs.stopWhat", [("name", text(j, "name"))]),
          skey,
          "job.stop",
          { "station": Json::string(r.station), "id": Json::string(id) },
        )
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(46.0),
        radius=23.0,
        gap=6.0,
        align=ACenter,
        justify=JCenter,
        bg=@sf.alpha(t.p.red, 0.12),
        id=sid,
        fn() {
          if busy {
            @sf.spinner(c, size=14.0) |> ignore
          } else {
            @sf.icon(c, "stop", size=16.0, color=t.p.red) |> ignore
          }
          c.text(tr("android-misc.jobs.stop"), size=t.t.ui, weight=500, color=t.p.red, wrap=false)
          |> ignore
          // Jobs.kt: clip(Smooth(23)).clickable
          @motion.ripple(c, sid, 23.0)
        },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// What is left up a long while on the workspace's stations (OpenJobs.kt), at the top of Home's list: web services and
/// background jobs, each under its heading, three of a group and the rest folded under 还有 N 个; nothing while there
/// are none. A row leads to its chat; its stop at its end.
fn open_jobs(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let groups = items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups")
  if groups.length() == 0 {
    return
  }
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=10.0, pr=10.0, pt=4.0, pb=10.0, gap=8.0, fn() {
    for g in groups {
      let gv = Some(g)
      let gkey = "open-jobs/" + text(gv, "key")
      let list = items(gv, "jobs")
      let shown = if dui.opened.contains(gkey) || list.length() <= 4 {
        list
      } else {
        list[:3].to_array()
      }
      c.box(w=Fill(1.0), gap=2.0, fn() {
        c.box(padx=10.0, pady=2.0, fn() {
          c.text(text(gv, "head"), size=t.t.caption, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
        for j in shown {
          open_job_row(c, src, Some(j))
        }
        if shown.length() < list.length() {
          let id = c.id(gkey + "/more")
          if c.clicked(id) {
            dui.opened[gkey] = true
          }
          c.box(padx=10.0, pady=3.0, radius=8.0, id~, fn() {
            c.text(
              fill("android-misc.openJobs.more", [("n", (list.length() - shown.length()).to_string())]),
              size=t.t.caption,
              color=t.p.muted,
              wrap=false,
            )
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A job left up (OpenJobs.kt OpenRow): its dot, its name over where it is and how long; the row to its chat, stop at
/// its end.
fn open_job_row(c : @ui.Ctx, src : Source, job : Json?) -> Unit {
  let t = @sf.theme()
  let station = text(job, "station")
  if station == "" {
    return
  }
  let id = text(job, "id")
  let chat = field(job, "chat")
  let row = c.id("open-job/" + station + "/" + id)
  if chat is Some(Object(_)) && c.clicked(row) {
    app.nav.push(Chat({ station, session: text(chat, "id"), title: text(chat, "title"), station_name: "" }))
    // a service: its page over its chat (OpenJobs.kt OpenRow)
    if flag(job, "service") {
      app.nav.push(Service(station, id))
    }
  }
  let skey = "job-stop/" + station + "/" + id
  let stop = c.id("open-job-stop/" + station + "/" + id)
  if !doing(skey) && c.clicked(stop) {
    act(
      src,
      fill("android-misc.jobs.stopWhat", [("name", text(job, "name"))]),
      skey,
      "job.stop",
      { "station": Json::string(station), "id": Json::string(id) },
    )
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    pl=10.0,
    pr=4.0,
    pt=5.0,
    pb=5.0,
    gap=10.0,
    radius=10.0,
    align=ACenter,
    id=row,
    fn() {
      c.box(w=Px(16.0), align=ACenter, fn() { job_dot(c, text(job, "tone")) }) |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(text(job, "name"), size=t.t.ui, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          text(job, "whereText") + " · " + text(job, "age"),
          size=t.t.caption,
          color=t.p.muted,
          wrap=false,
          line=16.0,
        )
        |> ignore
      })
      |> ignore
      c.box(w=Px(32.0), h=Px(32.0), radius=16.0, align=ACenter, justify=JCenter, id=stop, fn() {
        if doing(skey) {
          @sf.spinner(c, size=12.0) |> ignore
        } else {
          @sf.icon(c, "stop", size=15.0, color=t.p.muted) |> ignore
        }
      })
      |> ignore
      // the row clickable over its clip
      @motion.ripple(c, row, 10.0)
    },
  )
  |> ignore
}

///|
/// An info row's words (14, the ink, on one line).
// kept across runs: a value (no field of it changes)
let info_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// A link opened in the system's app for it (ChatInfo.kt: ACTION_VIEW), said when there is none.
fn open_outside(url : String) -> Unit {
  if !@ui.open_url(url) {
    toast_later(tr("android-chat.link.failed"))
  }
}

///|
/// Opens the chat's letters at their list (the library's panel, most of the window tall, dragged between half and nearly
/// all of it); its letters held (the core's `chatLetters`) until the chat is left.
fn open_letters(src : Source, r : ChatRef, thread : Double) -> Unit {
  dui.letters_open = ""
  dui.letters_held[r.station + "\u{1}" + r.session] = thread
  @sf.panel(tr("web-main.letters.title"), from=Unanchored, tall=0.8, grows=true, fn(c, _) {
    letters_body(c, src, r, thread)
  })
}

///|
/// Opens what was said in the chat besides words (the library's panel, as the letters'); 在对话里看 closes it and goes
/// to the message in the chat.
fn open_things(src : Source, r : ChatRef, thread : Double) -> Unit {
  @sf.panel(tr("web-main.things.title"), from=Unanchored, tall=0.8, grows=true, fn(c, close) {
    @sfpages.things_body(c, src, r, thread, true, fn(seq) {
      close()
      go_to(r, seq)
    })
  })
}

///|
/// How many pull requests the info names itself (the rest: 全部 N 个).
let info_pulls_most : Int = 3

///|
/// What is between the info's lists (its pull requests', its agents'): 10, as under its agents'.
// kept across runs: a value (no field of it changes)
let info_lists_gap : @ui.Style = @ui.css("h=S2_5")

///|
// kept across runs: a value (no field of it changes)
let info_pull_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// The params of a chat's letters (the core's `chatLetters` view).
fn letters_params(r : ChatRef, thread : Double) -> Map[String, Json] {
  { "station": Json::string(r.station), "thread": Json::number(thread) }
}

///|
/// A chat written with, its row in the letters' sheet (Letters.kt): 18 in, 10 over and under, its two lines 2 apart;
/// pressed a shade.
// kept across runs: a value (no field of it changes)
let letters_row : @ui.Style = @ui.css("w=Full py=S2_5 gap=S0_5 pressed{bg=Hover}")

///|
/// Its first line: its title as wide as there is room, how many and when at its end, 8 apart.
// kept across runs: a value (no field of it changes)
let letters_row_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// What fills a line's room (its title, beside what is at its end).
// kept across runs: a value (no field of it changes)
let letters_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A chat's title (15, medium, cut short before how many and when) and what is said in brief of it (13, muted), each on
/// a line.
// kept across runs: a value (no field of it changes)
let letters_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let letters_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The last letter in brief, on one line cut short where the row is narrower than it (a dialog's).
// kept across runs: a value (no field of it changes)
let letters_last : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// None: said 18 in, 12 over and under, 15 muted.
// kept across runs: a value (no field of it changes)
let letters_none_box : @ui.Style = @ui.css("py=S3")

///|
// kept across runs: a value (no field of it changes)
let letters_none : @ui.TextStyle = @ui.text_style(size=Body, color=Muted)

///|
/// One opened, its head: back (a round 36, pressed a shade, its chevron on the panel's words' line: letters_back_in),
/// then its title.
// kept across runs: a value (no field of it changes)
let letters_head : @ui.Style = @ui.css("row w=Full pb=S1_5 gap=S1 align=ACenter")

///|
/// How far its back's chevron is in from its round ground's start (its 36's middle less half the chevron's 16), the
/// ground standing that far out of the panel's words' line.
let letters_back_in : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let letters_back : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter pressed{bg=Hover}")

///|
/// A letter, as the chat draws a message: 14 in, 20 under the one before.
// kept across runs: a value (no field of it changes)
let letters_said : @ui.Style = @ui.css("w=Full pt=S1 pb=S4")

///|
/// Older ones on their way: a spinner, 8 under the last.
// kept across runs: a value (no field of it changes)
let letters_more : @ui.Style = @ui.css("w=Full pt=S2 align=ACenter")


///|
/// A chat it wrote with (`ch`, by `key`): its title, how many and when, the last letter in brief under them; pressed,
/// opened.
fn letter_row(c : @ui.Ctx, key : String, ch : Json?) -> Unit {
  let id = c.id("letters/row/" + key)
  if c.clicked(id) {
    dui.letters_open = key
  }
  c.box(style=letters_row.then(@sf.panel_row_reach()), id~, fn() {
    c.box(style=letters_row_head, fn() {
      c.box(style=letters_grow, fn() { c.text(text(ch, "title"), style=letters_title) |> ignore }) |> ignore
      let n = fill("web-main.letters.count", [("n", items(ch, "letters").length().to_string())])
      let ago = text(field(field(ch, "time"), "lastActiveAt"), "ago")
      c.text(if ago == "" { n } else { n + " · " + ago }, style=letters_meta) |> ignore
    })
    |> ignore
    c.text(text(ch, "last"), style=letters_last) |> ignore
  })
  |> ignore
}

///|
/// The chats written with to come while they are read (in their bones): letter_row's of made-up ones.
fn letters_sample_rows(c : @ui.Ctx) -> Unit {
  for i, n in [(8, 18), (6, 22), (10, 14)] {
    letter_row(c, "sample" + i.to_string(), Some({
      "title": Json::string(@sf.sample_words(n.0)),
      "last": Json::string(@sf.sample_words(n.1)),
      "time": { "lastActiveAt": { "ago": Json::string(@sf.sample_words(3)) } },
    }))
  }
}

///|
/// The chat's services and jobs to come while they are read (in their bones): job_groups of made-up ones.
fn jobs_sample(c : @ui.Ctx, r : ChatRef) -> Unit {
  let job = fn(i : Int, service : Bool, n : Int) -> Json {
    { "id": Json::string("sample" + i.to_string()), "service": Json::boolean(service), "name": Json::string(@sf.sample_words(n)), "tone": "up" }
  }
  job_groups(c, @sfbase.sample_source, r, None, [job(0, true, 6), job(1, true, 8), job(2, false, 7)], fn() {  })
}

///|
/// What the letters' sheet holds below its head, and the wide frame's agent 往来 tab (wide_panel.mbt): the list of the
/// chats written with, or the one opened.
fn letters_body(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  let topic = (src.topic)("chatLetters", letters_params(r, thread))
  let (chat, _, _) = view_of_chat(src, r)
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => {
      waiting_rows(c, topic.error, fn() { letters_sample_rows(c) })
      return
    }
  }
  let chats = items(view, "chats")
  let whole = flag(view, "whole")
  // not here yet: its rows to come
  if chats.length() == 0 && !whole {
    waiting_rows(c, topic.error, fn() { letters_sample_rows(c) })
    return
  }
  let rows : Array[() -> Unit] = []
  if chats.length() == 0 {
    rows.push(fn() {
      c.box(style=letters_none_box.then(@sf.panel_words_in()), fn() { c.text(tr("web-main.letters.none"), style=letters_none) |> ignore })
      |> ignore
    })
  }
  let opened = chats.iter().find_first(fn(ch) { text(Some(ch), "key") == dui.letters_open })
  match (opened, chat) {
    (Some(ch), Some(v)) => {
      let ch = Some(ch)
      let link = text(ch, "link")
      rows.push(fn() {
        // back to the list, and its title (which opens that chat)
        c.box(style=letters_head.then(@sf.panel_words_out_by(letters_back_in)), fn() {
          let back = c.id("letters/back")
          if c.clicked(back) {
            dui.letters_open = ""
          }
          c.box(style=letters_back, id=back, fn() {
            @sf.icon(c, "chevron-left", size=20.0, color=@sf.theme().p.accent_text) |> ignore
          })
          |> ignore
          let name = c.id("letters/chat")
          if link != "" && c.clicked(name) {
            open_link(link)
          }
          c.box(id=name, fn() { c.text(text(ch, "title"), style=letters_title) |> ignore }) |> ignore
        })
        |> ignore
      })
      // each as its chat draws it (sfpages' rows, as the desktop's letters have them)
      let here : @sfpages.MessageHere = {
        station: r.station,
        session: r.session,
        view: v,
        go: None,
        inline: true,
        gutter: 0.0,
        list: None,
        core: None,
      }
      for m in items(ch, "letters") {
        let message = message_of(m)
        rows.push(fn() { c.box(style=letters_said.then(@sf.panel_words_in()), fn() { @sfpages.message_row(c, src, here, message) }) |> ignore })
      }
    }
    _ =>
      for ch in chats {
        let ch = Some(ch)
        let key = text(ch, "key")
        rows.push(fn() { letter_row(c, key, ch) })
      }
  }
  // not all of the chat is here yet: older ones may come
  if !whole {
    rows.push(fn() { c.box(style=letters_more, fn() { @sf.spinner(c, size=16.0) |> ignore }) |> ignore })
  }
  // (its rows on the panel's line as the list builds them: @sf.panel_list)
  // (no room of its own under its last: the panel's foot is under it)
  @sf.panel_list(c, "letters-sheet/" + r.station + "/" + r.session + "/" + dui.letters_open, rows.length(), 60.0, fn(
    i,
  ) {
    (rows[i])()
  })
  |> ignore
}
