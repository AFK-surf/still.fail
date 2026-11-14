// The sheets over a chat (slice 8): its own, from "…" (still.fail apps/android chat/screens/ChatInfo.kt openChatInfo,
// askTitle, InfoList, InfoRow), an agent's card (AgentSheet.kt openAgent, AgentStatus, AgentLines, AgentTiles,
// AgentNotes, StopButton), its services and jobs and one job (Jobs.kt openJobs, JobGroups, JobInfoRow, JobDot, metaOf,
// openJob, JobBody), and the jobs left up a long while at the top of Home. What they show is the core's
// (the `chat`, `agentCard`, `stations`, `chatJobs`, `jobLog` and `longJobs` views); what is done goes through its calls.
//
// An agent's station opens the station's card in its place (settings/station_peek.mbt), its account how it runs.
//
// The jobs' and a job's sheets drag between half and nearly all of the screen, as Android's.

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
/// A model's mark as a sheet and the history have it: its maker's mark on a tile with a hairline,
/// the ladder's small block's 10 round (Parts.kt's 11: concentric so in a row's corner, 10 in, all four alike; 6 under
/// 30), and its state's badge over the corner (Badge: solid accent waiting on someone, an accent ring
/// at work, red failed) ringed in `around`.
fn model_mark_big(c : @ui.Ctx, maker : String, runtime : String, size : Double, state : String, around : Int64, plain? : Bool = false) -> Unit {
  let t = @sf.theme()
  let xs = size < 30.0
  c.box(w=Px(size), h=Px(size), fn() {
    c.box(
      w=Px(size),
      h=Px(size),
      radius=if xs { 6.0 } else { @sf.small_corner },
      bg=if plain { 0L } else { t.p.card },
      border=if plain { 0.0 } else { 1.0 },
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
/// An info card round its rows: a card of the ladder's (what it holds is content: a model's tile, its words, its
/// allowance; the user, 2026-11-03), its rows the ladder's inset in, so their words and tiles 16 in from its edges.
let info_list_radius : Double = @sf.card_corner

///|
/// Rows on one quiet card: its rows the ladder's inset in, the ink at 5%.
// kept across runs: a value (no field of it changes)
let info_list_style : @ui.Style = @ui.css("w=Full bg=A(Fg,O5) clip").then(@ui.style(p=@sf.room_of(@sf.corner_inset)))

///|
fn info_list(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=info_list_style.then(@sf.panel_card_out()), radius=info_list_radius, body) |> ignore
}

///|
/// A row of it (Android InfoRow): 44 high at least, its words the ladder's inset (8) in from its sides and INFO_IN (4) from
/// top and bottom, what it holds 12 apart.
// kept across runs: a value (no field of it changes)
let info_row_style : @ui.Style = @ui.css("row w=Full min_h=S11 py=S1 gap=S3").then(@ui.style(px=@sf.room_of(@sf.text_in)))

///|
/// A row that leads with a tile (a model's mark, 36): its tile the ladder's inset in from the row's top and start, so
/// round by the ladder's next step in the row's corner (mbui works it out: 18 less 8, 10).
// kept across runs: a value (no field of it changes)
let info_row_tile : @ui.Style = @ui.style(p=@sf.room_of(@sf.corner_inset), align=AStart)

///|
/// An agent's tile leading its row (a model's mark): as tall as its row's two lines (15 and 12 on the app's 1.4).
let info_tile : Double = 38.0

///|
/// A row that leads with a dot (a job's: 8 round, `job_dot_over` under its top): in the card's corner as far from both
/// its edges as makes it concentric with it (@sf.capsule_in), its words on the dot's line.
// kept across runs: a value (no field of it changes)
let info_row_dot : @ui.Style = @ui.style(
  pl=@sf.capsule_room(info_list_radius, job_dot_side, less=@sf.corner_inset),
  pt=@sf.capsule_room(info_list_radius, job_dot_side, less=@sf.corner_inset + job_dot_over),
)

///|
/// A job's dot (job_dot: 8), and how far under its row's words' top it stands, on its name's line (7).
let job_dot_side : Double = 8.0

///|
let job_dot_over : Double = 7.0

///|
/// Its ground rounded INFO_ROW, pressed a shade; `on_press` as it is tapped (never when `key` is "": a row that leads
/// nowhere).
fn info_row(
  c : @ui.Ctx,
  key : String,
  body : () -> Unit,
  align? : @ui.Align = ACenter,
  tile? : Bool = false,
  dot? : Bool = false,
  on_press? : () -> Unit,
) -> Unit {
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
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
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
/// For how long it has stood where it does: at work since its turn began, waiting as long
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
          if now < from + sec * second_ms {
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
/// Where it stands: a dot in its tone on the first line's middle, its words and, muted,
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

// ── the chat's own sheet ──────────────────────────────────

///|
/// The chat itself, from ⓘ: its name (with a way to change it) over who started it, how
/// many take part and when it was last written in; its agents, each where it stands (a tap opens its card); then what
/// is in it: its pull requests, what else was said, what its agents and other chats' wrote each other, its public
/// links. What is done with it is the "…"'s menu, a row of the list's. As tall as what it shows.
fn chat_info_body(c : @ui.Ctx, src : Source, r : ChatRef, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let chat = src.topic("chat", chat_params(r)).get().value
  let (view, _, _) = view_of_chat(src, r)
  let agents = items(chat, "agents")
  let (archived, offline) = match view {
    Some(v) => (v.archived, v.offline)
    None => (false, false)
  }
  // archived or offline it is only read: no name to change, nothing to archive
  let open = view is Some(_) && !archived && !offline
  let thread = field(chat, "thread")
  let title = text(chat, "title")
  c.box(w=Fill(1.0), fn() {
    // its name and ✎: the panel's title row where it draws one (in the middle of the window: info_title_row), else
    // here, clear of an untitled dialog's close button over its end (@sf.untitled_clear)
    if !@sf.title_row_given.val {
      c.box(style=@sf.untitled_clear().then(title_row_whole), fn() { info_title_row(c, src, r, title, open, thread) }) |> ignore
    }
    // opened by another chat's agent: the way back there (由「…」创建), pressed as a row is
    match view {
      Some({ opener: Some(o), .. }) => {
        let id = c.id("info/opener")
        c.on_press(id, fn() {
          close()
          open_page(Chat(o.chat))
        })
        let said = if o.archived { o.text + " · " + o.note } else { o.text }
        let b = c.box(style=info_opener, id~, fn() {
          @sf.icon(c, "spawned", size=16.0, color=t.p.accent_text) |> ignore
          c.text(said, style=info_opener_words) |> ignore
          @motion.ripple(c, id, 8.0)
        })
        c.semantics(b, Link, id~, label=said)
      }
      _ => ()
    }
    // who started it and when, how many take part, when it was last written in: what there is of them, in a line
    let facts : Array[String] = []
    // (a Feishu chat's by Feishu, a Comma Task's by Comma alone: it is in no place)
    let surface = text(thread, "surface")
    match text(chat, "place") {
      "" if surface.has_prefix("comma:") => facts.push("Comma")
      "" => ()
      p if surface.has_prefix("feishu:") || text(chat, "feishuUrl") != "" => facts.push(@sf.t("web-pages.connect.feishu.name") + " · " + p)
      p => facts.push(fill("android-chat.info.from.slack", [("place", p)]))
    }
    // (made by another chat's agent: that chat said over this line, not a person)
    let creator = match field(thread, "creator") {
      _ if view is Some({ opener: Some(_), .. }) => ""
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
        let shown = if people.length() > 5 { people[:5].to_owned() } else { people }
        c.box(w=Px(19.0 + 14.0 * (shown.length() - 1).to_double()), fn() {
          // ringed in the sheet's ground
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
          info_row(c, "info/agent/" + key, fn() {
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
          }, tile=true,
            on_press=fn() {
              close()
              open_agent(src, r, key)
            },
          )
        }
      })
      c.box(style=info_lists_gap, fn() {  }) |> ignore
    }
    // the chats its agent made (after who works in it): one row, 创建了 N 个对话, each of them in the menu it opens
    match view {
      Some({ opened: [_, ..] as opened, opened_text, .. }) => {
        info_list(c, fn() {
          let key = "info/opened"
          let from = c.id(key)
          info_row(c, key, fn() {
            @sf.icon(c, "spawned", size=16.0, color=t.p.muted) |> ignore
            c.text(opened_text, style=info_opened_title) |> ignore
            chevron(c)
          }, on_press=fn() {
            @sf.menu(@sfpages.opened_items(opened, then=close), from=Of(from), title=opened_text)
          })
        })
        c.box(style=info_lists_gap, fn() {  }) |> ignore
      }
      _ => ()
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
          @sfpages.web_peek(c, src, r.station, text(pv, "url"), @sfpages.pull_title(pv), pid, side=Left, peek=text(pv, "peek"))
          info_row(c, "info/pull/" + text(pv, "key"), fn() {
            @sfpages.pull_mark(c, pv, 16.0)
            c.box(style=@sf.full_width, fn() { c.text(@sfpages.pull_title(pv), style=info_pull_title) |> ignore }) |> ignore
            c.text("#" + count(pv, "number").to_string(), style=letters_meta) |> ignore
          },
            on_press=fn() {
              close()
              @sfbase.open_link_in(src, text(pv, "url"))
            },
          )
        }
        match opt_number(thread, "id") {
          Some(th) if pulls.length() > info_pulls_most =>
            info_row(c, "info/pulls", fn() {
              @sf.icon(c, "list", size=16.0, color=t.p.text) |> ignore
              c.box(style=@sf.full_width, fn() {
                c.text(fill("web-main.things.pullsAll", [("n", pulls.length().to_string())]), style=info_words) |> ignore
              })
              |> ignore
              chevron(c)
            },
              on_press=fn() {
                close()
                @sfpages.things_choose(r, "pulls")
                open_things(src, r, th)
              },
            )
          _ => ()
        }
        // what was said in it besides words: a sheet of their own (sfpages things.mbt)
        match opt_number(thread, "id") {
          Some(th) if said > 0 =>
            info_row(c, "info/things", fn() {
              @sf.icon(c, "photo", size=16.0, color=t.p.text) |> ignore
              c.box(style=@sf.full_width, fn() { c.text(tr("web-main.things.title"), style=info_words) |> ignore })
              |> ignore
              c.text(said.to_string(), style=letters_meta) |> ignore
              chevron(c)
            },
              on_press=fn() {
                close()
                open_things(src, r, th)
              },
            )
          _ => ()
        }
        // what its agents and other chats' wrote each other, not in the chat: their own sheet
        match opt_number(thread, "id") {
          Some(th) if letters > 0.0 =>
            info_row(c, "info/letters", fn() {
              @sf.icon(c, "chats", size=16.0, color=t.p.text) |> ignore
              c.box(style=@sf.full_width, fn() { c.text(tr("web-main.letters.title"), style=info_words) |> ignore })
              |> ignore
              c.text(fill("web-main.letters.count", [("n", letters.to_int().to_string())]), style=letters_meta) |> ignore
              chevron(c)
            },
              on_press=fn() {
                close()
                open_letters(src, r, th)
              },
            )
          _ => ()
        }
      })
    }
    // (its last card at a dialog's foot, as far from it as from its sides)
    c.box(style=@sf.panel_card_foot(), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A chat's or an agent's title row, as wide as it is given.
// kept across runs: a value (no field of it changes)
let title_row_whole : @ui.Style = @ui.css("w=Full")

///|
/// A chat's name and ✎ in a line: ✎ right after the name, on its first line.
// kept across runs: a value (no field of it changes)
let info_title_line : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// A chat's name, as wide as it is, 4 down to stand on ✎'s middle.
// kept across runs: a value (no field of it changes)
let info_title_words : @ui.Style = @ui.css("w=Cut pt=S1")

///|
/// An agent's mark, name and where it stands in a line, what it did under it 16 down (panel_card_in).
// kept across runs: a value (no field of it changes)
let agent_title_line : @ui.Style = @ui.css("row w=Full pt=S1 gap=S3 align=ACenter").then(
  @ui.style(pb=@sf.room_of(@sf.panel_card_in)),
)

///|
/// A chat's name in its sheet's head, two lines at most, its ✎ right after it where it can be renamed (`open`): the
/// panel's title row in the middle of the window (open_info), else the first line of what it holds.
fn info_title_row(c : @ui.Ctx, src : Source, r : ChatRef, title : String, open : Bool, thread : Json?) -> Unit {
  let t = @sf.theme()
  // (its rename right after its name, on the name's first line, not in the corner over the close button: the user,
  // 2026-11-03, 那个改名的图标显然不能放那)
  c.box(style=info_title_line, fn() {
    // (two lines at most, the last ending in an ellipsis: not a third cut off below them)
    c.box(style=info_title_words, fn() { c.text(title, size=t.t.title, weight=700, color=t.p.text, line=24.0, max_lines=2) |> ignore })
    |> ignore
    if open {
      let id = c.id("info/rename")
      c.on_press(id, fn() {
        open_rename(src, r, opt_number(thread, "id"), title, from=Of(id))
      })
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
}

///|
/// The chat's own sheet (chat_info_body) from "…": the library's panel, as tall as what it shows, its name with ✎ beside
/// it its title row in the middle of the window, else its own head.
fn open_info(src : Source, r : ChatRef) -> Unit {
  // (its name its title, with its ✎ after it, in the title's row in the middle of the window: the user, 2026-11-04,
  // 为啥不做成标题; no title of words elsewhere, where what it holds draws its name itself)
  @sf.panel(
    "",
    from=Unanchored,
    title_row=fn(c) {
      let chat = src.topic("chat", chat_params(r)).get().value
      let (view, _, _) = view_of_chat(src, r)
      let open = match view {
        Some(v) => !v.archived && !v.offline
        None => false
      }
      info_title_row(c, src, r, text(chat, "title"), open, field(chat, "thread"))
    },
    fn(c, close) { chat_info_body(c, src, r, close) },
  )
}

///|
/// The chat renamed, asked for its name as it was (@sf.ask): said, the core's `chat.rename`.
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

// ── an agent's card ─────────────────────────────────────

///|
/// An agent of the chat in brief: what it runs and where it stands (with a stop while it
/// works), its latest lines, the figures that say most, then where to go on: the station it runs on, its screens, its
/// account, its history, its jobs; and its context by hand (context.mbt).
fn agent_body(c : @ui.Ctx, src : Source, r : ChatRef, key : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let chat = src.topic("chat", chat_params(r)).get().value
  let a = agent_json(chat, key)
  let card = src.topic("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).get().value
  let jobs = items(a, "jobs")
  let stations = station_marks(src, @sfbase.workspace_of(r.station))
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let s = field(a, "session")
  let entry = context_entry(c, src, r, key, s, close)
  c.box(w=Fill(1.0), fn() {
    // (its head: the panel's title row in the middle of the window (agent_title_row), else its own here, clear of an
    // untitled dialog's close button over its end)
    if !@sf.title_row_given.val {
      c.box(style=@sf.untitled_clear().then(title_row_whole), fn() { agent_title_row(c, src, r, key) }) |> ignore
    }
    // (its words on the card's 24, its figures blocks at its foot 8 in, a row's corner)
    // (each part of it opening its room as what it says comes (the card read after it rose): the sheet's top not
    // stepping up as its height does, 2026-11-09 the user: 「好像还存在高度突变的元素」)
    c.box(style=info_list_style.then(@sf.panel_card_out()), radius=info_list_radius, fn() {
      let parts : Array[(String, () -> Unit)] = []
      if items(card, "latest").length() > 0 {
        parts.push(("lines", fn() { agent_lines(c, card) }))
      }
      if items(card, "attention").length() > 0 {
        parts.push(("notes", fn() { agent_notes(c, card, 10.0) }))
      }
      if agent_tiles_known(card) {
        parts.push(("tiles", fn() { agent_tiles(c, card, 14.0, entry~) }))
      }
      @sf.group_rows(c, "agent-card/" + r.station + "/" + key, parts)
    })
    |> ignore
    c.box(style=info_card_under, fn() {  }) |> ignore
    let screens = match view_of_chat(src, r).0 {
      Some(v) => v.screens
      None => []
    }
    // All visible rows share a column wide enough for their labels in this language and at this text size.
    let labels = [tr("android-chat.agent.account"), tr("android-chat.agent.history"), tr("android-chat.new.model")]
    if station is Some(_) { labels.push(tr("android-chat.agent.station")) }
    if screens.length() > 0 { labels.push(tr("android-chat.agent.screen")) }
    if entry is Some(_) && !(field(card, "context") is Some(Object(_))) { labels.push(tr("android-chat.agent.context")) }
    if jobs.length() > 0 { labels.push(tr("android-chat.agent.jobs")) }
    let label_w = labels.fold(init=0.0, fn(w, label) { dmax(w, c.words_across(label, agent_row_label).ceil()) })
    info_list(c, fn() {
      match station {
        Some(st) =>
          info_row(c, "agent/station", fn() {
            agent_label(c, tr("android-chat.agent.station"), label_w)
            c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
              if @sf.has_station_mark(st.emoji, st.icon) {
                @sf.station_mark(c, st.emoji, st.icon, 15.0, t.p.text)
              }
              c.text(st.name, size=t.t.ui, color=t.p.text, wrap=false, w=Cut) |> ignore
            })
            |> ignore
            chevron(c)
          },
            on_press=fn() {
              // the station's card in place of this one
              close()
              @settings.open_station_peek(r.station, from=Unanchored)
            },
          )
        None => ()
      }
      // the screens of that station a tap away (chat_screens.mbt): its own display named, or that an agent drives one;
      // the one alone opened, more a menu of them, this card gone first
      if screens.length() > 0 {
        let value = if chat_screens_driven(screens) {
          tr("web-pages.chat.screenAgent")
        } else {
          screens[0].title
        }
        let from = c.id("agent/screen")
        agent_row(c, "agent/screen", tr("android-chat.agent.screen"), value, label_w, fn() {  }, on_press=fn() {
          close()
          chat_screens_open(r, screens, from=Of(from))
        })
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
      // What it runs on under its own name, the model and how hard it thinks said (2026-11-10: the only way to its
      // picker was the row named 账号, and how hard it thinks was said nowhere short of the picker). The same model
      // picker as the chat's history and a new chat: every way to the run offers the same choices.
      let model = match text(s, "modelName") {
        "" => text(s, "model")
        n => n
      }
      if model != "" {
        let runs = match text(s, "effort") {
          "" => model
          e => model + " · " + @sfpages.effort_text(e)
        }
        agent_row(c, "agent/model", tr("android-chat.new.model"), runs, label_w, fn() {  }, on_press=fn() {
          close()
          @sfpages.open_triple_panel(src, r.station, "session:" + key, Unanchored, saved=@sf.t("web-pages.chat.pickSaved"))
        })
      }
      // (who runs it: the picker with its accounts open over it)
      agent_row(c, "agent/account", tr("android-chat.agent.account"), value, label_w, fn() {  }, under=fn() {
        allowance_line(c, field(account, "quota"))
      }, on_press=fn() {
        close()
        @sfpages.open_triple_panel(src, r.station, "session:" + key, Unanchored, saved=@sf.t("web-pages.chat.pickSaved"), accounts=true)
      })
      agent_row(
        c,
        "agent/history",
        tr("android-chat.agent.history"),
        match text(card, "work") {
          "" => tr("android-chat.agent.history.none")
          w => w
        },
        label_w,
        fn() {  },
        on_press=fn() {
          close()
          @sfbase.history_push()
          app.nav.push(History(r, key, None))
        },
      )
      // what can be done to its context, where no figure of it is known to be its tile (a station from before tells
      // none of an agent at rest)
      match entry {
        Some(e) if !(field(card, "context") is Some(Object(_))) =>
          agent_row(c, "agent/context", tr("android-chat.agent.context"), "", label_w, fn() {
            if e.busy || e.failed {
              @settings.doing_mark(c, e.busy, if e.failed { Some("") } else { None })
            }
          }, on_press=fn() {
            if !e.busy {
              (e.open)()
            }
          })
        _ => ()
      }
      if jobs.length() > 0 || flag(a, "hasJobs") {
        agent_row(
          c,
          "agent/jobs",
          tr("android-chat.agent.jobs"),
          match text(card, "jobs") {
            "" => tr("android-chat.agent.jobs.idle")
            j => j
          },
          label_w,
          fn() {  },
          on_press=fn() {
            close()
            open_chat_jobs(src, r)
          },
        )
      }
    })
    // (its last card at a dialog's foot, as far from it as from its sides)
    c.box(style=@sf.panel_card_foot(), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// An agent's head in its card: its maker's mark alone, its name and where it stands, its stop where it runs: the panel's
/// title row in the middle of the window (open_agent), else the first line of what it holds (agent_body). Its mark no tile
/// in the panel's corner; what it did a card of the panel's under it, 16 in (the user, 2026-11-03, 面板里可以放卡片).
fn agent_title_row(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  let t = @sf.theme()
  let chat = src.topic("chat", chat_params(r)).get().value
  let a = agent_json(chat, key)
  let s = field(a, "session")
  let status = text(a, "status")
  // (its head the panel's, on its words' line as chat_info_body's title: its mark the maker's alone, no tile in the
  // panel's corner; what it did a card of the panel's under it, 16 in: the user, 2026-11-03, 面板里可以放卡片)
  c.box(style=agent_title_line, fn() {
    model_mark_big(
      c,
      text(field(s, "maker"), "id"),
      text(s, "runtime"),
      40.0,
      state_of_badge(text(a, "badge")),
      @sf.over(t.p.bg, @sf.alpha(t.p.card, 0.8)),
      plain=true,
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
}

///|
/// An agent's card (agent_body): the library's panel, as tall as what it shows, its head its own (its mark, name and
/// where it stands).
fn open_agent(src : Source, r : ChatRef, key : String) -> Unit {
  // (its mark, name and where it stands its title row in the middle of the window: the user, 2026-11-04, 这个是不是也可以
  // 想办法做成标题)
  @sf.panel("", from=Unanchored, title_row=fn(c) { agent_title_row(c, src, r, key) }, fn(c, close) {
    agent_body(c, src, r, key, close)
  })
}

///|
/// A row of the card: what it is about, what there is of it (`under` it what goes with it:
/// an account's allowance, a line of its own), what is under way at its end (`trailing`), where a tap leads.
///|
// kept across runs: a value (no field of it changes)
let agent_row_body_style : @ui.Style = @ui.css("w=Full")

///|
fn agent_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  value : String,
  label_w : Double,
  trailing : () -> Unit,
  under? : () -> Unit,
  on_press? : () -> Unit,
) -> Unit {
  info_row(c, key, fn() {
    agent_label(c, label, label_w)
    c.box(style=agent_row_body_style, keep=true, fn() {
      c.text(value, style=agent_row_value, keep=true) |> ignore
      match under {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
    trailing()
    chevron(c)
  }, on_press?)
}

///|
/// Labels sit in one left-aligned column, so the values beside them line up as well.
fn agent_label(c : @ui.Ctx, label : String, width : Double) -> Unit {
  c.box(w=Px(width), align=AStart, fn() { c.text(label, style=agent_row_label) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let agent_row_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

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
/// Stopping its turn, while it works: red on its tint, a spinner while it is asked.
fn stop_button(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let t = @sf.theme()
  let skey = "stop/" + station + "/" + key
  let busy = doing(skey)
  let id = c.id("agent/stop")
  c.on_press(id, fn() {
    if !busy {
      act(
        src,
        tr("android-chat.agent.stop"),
        skey,
        "session.stop",
        { "station": Json::string(station), "key": Json::string(key) },
        done=tr("android-chat.history.stopped"),
      )
    }
  })
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
  c.box(w=Fill(1.0), pt=8.0, pb=8.0, padx=@sf.text_in, gap=3.0, fn() {
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
/// Whether any of the figures that say most is known (agent_tiles): none (a station from before tells none of an agent
/// at rest), no figures, its context's entry a row instead.
fn agent_tiles_known(card : Json?) -> Bool {
  text(card, "cost") != "" || field(card, "cache") is Some(Object(_)) || field(card, "context") is Some(Object(_))
}

///|
/// The figures that say most (AgentTiles): what it cost, the cache's hit rate, how full its context is, each large over
/// its name, side by side; a context worth a look in its level's colour.
///|
fn agent_tiles_fit_size(c : @ui.Ctx, figure : String, room : Double) -> Double {
  let sizes : Array[Double] = if figure.length() > 6 {
    [16.0, 15.0, 14.0, 13.0, 12.0, 11.0, 10.0]
  } else {
    [20.0, 17.0, 16.0, 15.0, 14.0, 13.0, 12.0, 11.0, 10.0]
  }
  for sz in sizes {
    if @sf.node_words_w(figure, c.sp(sz), weight=600) <= room - 1.0 {
      return sz
    }
  }
  10.0
}

///|
/// The figures that say most (UsageTiles.kt): what it cost, the cache's hit rate, how full its context is — 20/26 bold
/// (shrinking cleanly to fit the tile's inner width so numbers never truncate) above 12/16 muted; its context's opens
/// what can be done to it when it can be.
fn agent_tiles(c : @ui.Ctx, card : Json?, top : Double, entry? : ContextTile? = None) -> Unit {
  let t = @sf.theme()
  let context = field(card, "context")
  let cost = text(card, "cost")
  let cache = field(card, "cache")
  if !agent_tiles_known(card) {
    return
  }
  let tile_count = (if cost != "" { 1 } else { 0 }) +
    (if cache is Some(Object(_)) { 1 } else { 0 }) +
    (if context is Some(Object(_)) { 1 } else { 0 })
  let win_w = c.window_size().0
  let panel_w = if win_w < @sf.narrow_most { win_w } else { dmin(@sf.dialog_w, win_w - @sf.dialog_margin) }
  let row_w = dmax(0.0, panel_w - 2.0 * (@sf.panel_card_in + @sf.corner_inset))
  let tile_w = (row_w - 8.0 * Double::from_int(tile_count - 1)) / Double::from_int(tile_count)
  let figure_room = dmax(0.0, tile_w - 2.0 * @sf.text_in)
  let tile = fn(figure : String, name : String, color : Int64, open : ContextTile?) {
    // its context's, when something can be done to it (context.mbt): a tap opens it
    let id = if open is Some(_) { c.id("agent/context-tile") } else { 0 }
    let fig_size = agent_tiles_fit_size(c, figure, figure_room)
    c.box(
      id~,
      w=Fill(1.0),
      // (blocks at the card's foot, the ladder's inset in: a row's corner, their words on the card's line)
      radius=@sf.row_corner,
      bg=@sf.alpha(t.p.text, 0.05),
      pl=@sf.text_in,
      pr=@sf.text_in,
      pt=9.0,
      pb=8.0,
      // (AgentTiles: 「name figure」 to a screen reader)
      label=name + " " + figure,
      fn() {
        // (on a line of 26 at the system's size of words, its box as high: where a box of 26 drew its 28 before, its
        // glyphs where they were, and growing with them as the system's size of words grows)
        c.box(fn() {
          c.text(
            figure,
            size=fig_size,
            line=26.0,
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
      Some(o) => if !o.busy { c.on_press(id, fn() { (o.open)() }) }
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
  c.box(w=Fill(1.0), pt=top, pb=8.0, padx=@sf.text_in, gap=2.0, fn() {
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

// ── jobs ─────────────────────────────────────────

///|
/// A job's dot's colour: a service up or a job alive green, one restarting amber, one that died
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
/// the muted grey, not faded (at 55% its words were 2.3 to 1: mbui ui/contrast.mbt).
fn job_row(c : @ui.Ctx, key : String, job : Json?, on_press~ : () -> Unit) -> Unit {
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
    on_press~,
  )
}

///|
/// A group's label: 13, muted, 14 above it and 4 under.
fn group_label(c : @ui.Ctx, label : String) -> Unit {
  c.box(style=@sf.panel_words_in(), pt=14.0, pb=4.0, fn() {
    c.text(label, size=@sf.theme().t.meta, color=@sf.theme().p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// Services, then background jobs, each group's head with how many are up or alive; a service up
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
        job_row(c, "job/" + id, Some(j), on_press=fn() {
          // up or being started again: its page; else what it said and its output (picked where it is
          // shown beside the list: the wide frame's 任务 tab)
          let tone = text(Some(j), "tone")
          if pick is Some(f) && tone != "up" && tone != "restart" {
            f(id)
          } else if tone == "up" || tone == "restart" {
            close()
            @sfbase.history_push()
            app.nav.push(Service(r.station, id))
          } else {
            dui.job_tab = 1
            close()
            open_job(src, r, id)
          }
        })
      }
    })
  }
  if plain.length() > 0 {
    head("android-misc.jobs.jobs", text(view, "jobsNote"))
    info_list(c, fn() {
      for j in plain {
        let id = text(Some(j), "id")
        job_row(c, "job/" + id, Some(j), on_press=fn() {
          dui.job_tab = 0
          match pick {
            Some(f) => f(id)
            None => {
              close()
              open_job(src, r, id)
            }
          }
        })
      }
    })
  }
}

///|
/// What matters now of the chat's services and jobs, from the bar's button: those over are not
/// shown (the core leaves them out).
fn jobs_body(c : @ui.Ctx, src : Source, r : ChatRef, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let topic = src.topic("chatJobs", chat_params(r)).get().snapshot()
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => {
      waiting_rows(c, topic.error, fn() { jobs_sample(c, r) })
      return
    }
  }
  let jobs = items(view, "jobs")
  let rows : Array[() -> Unit] = []
  if jobs.length() == 0 {
    rows.push(fn() {
      c.box(style=@sf.panel_words_in(), pady=12.0, gap=4.0, fn() {
        c.text(tr("android-misc.jobs.none"), size=t.t.ui, weight=600, color=t.p.text) |> ignore
        c.text(tr("android-misc.jobs.none.text"), size=t.t.meta, color=t.p.muted) |> ignore
      })
      |> ignore
    })
  }
  rows.push(fn() { job_groups(c, src, r, view, jobs, close) })
  // (its rows on the panel's words' line as the list builds them, as tall as they come to up to the panel's share:
  // @sf.panel_list)
  // (no room of its own under its last: the panel's foot is under it)
  @sf.panel_list(
    c,
    "jobs-sheet/" + r.station + "/" + r.session,
    rows.length(),
    60.0,
    // (each row in the list's column: what is words stands on the panel's words' line itself, its cards
    // panel_card_in from the panel's sides: @sf.panel_card_out)
    fn(i) { c.box(w=Fill(1.0), fn() { (rows[i])() }) |> ignore },
  )
  |> ignore
  // (its last card at a dialog's foot, as far from it as from its sides)
  if jobs.length() > 0 {
    c.box(style=@sf.panel_card_foot(), fn() {  }) |> ignore
  }
}

///|
/// The chat's services and jobs (jobs_body): the library's panel, 62% of the window, dragged between half and nearly
/// all of it.
fn open_chat_jobs(src : Source, r : ChatRef) -> Unit {
  @sf.panel(tr("android-misc.jobs.title"), from=Unanchored, tall=0.62, grows=true, fn(c, close) { jobs_body(c, src, r, close) })
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
/// Words as the job's sheet sets them (an old view's words of a size, a weight and a wrap said alone, as nodes): `size`
/// as the theme has it, on lines of the theme's line to it (or `line` points), the face's own letters.
fn job_words(size : Double, weight? : Int = 400, wrap? : Bool = true, line? : Double = 0.0) -> @view.WordsLook {
  { size, weight, line: if line > 0.0 { line } else { @ui.tree_theme().text_line * size }, wrap, tracking: @view.letters_own, balance: false, max_lines: 0 }
}

///|
/// Words in node `parent`, `words` as they are now, set `look` in `ink`.
fn job_words_node(parent : @view.View, words : () -> String, look : () -> @view.WordsLook, ink : () -> Int64) -> Unit {
  parent.box(fn(w) { w.words(By(words)).words_look(By(look)).ink(By(ink)) |> ignore }) |> ignore
}

///|
/// Pieces of words in node `parent` (an old view's rich words), `runs` as they are now, set `look` in `ink` where a
/// piece says no ink of its own.
fn job_runs_node(parent : @view.View, runs : () -> Array[@ui.Run], look : () -> @view.WordsLook, ink : () -> Int64) -> Unit {
  parent.box(fn(w) {
    w.words_runs(By(runs), look=@signals.untracked(look)).words_look(By(look)).ink(By(ink)) |> ignore
  })
  |> ignore
}

///|
/// A job's dot (job_dot's, as a node) in `parent`: 8 across, its tone's tint as it is now; restarting, breathing to .35
/// and back (@sf.breathe's: breath_ms each way and back, from moment 0 on).
fn job_dot_node(parent : @view.View, tone : () -> String) -> Unit {
  parent.box(fn(d) {
    d
    .width(Is(Some(job_dot_side)))
    .height(Is(Some(job_dot_side)))
    .radius(Is(job_dot_side / 2.0))
    .ground(By(fn() { job_tint(tone()).unwrap_or(@sf.theme().p.subtle) }))
    .alpha(By(fn() {
      if tone() != "restart" {
        1.0
      } else {
        let f = d.cycle(@sf.breath_ms)
        let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
        1.0 - (1.0 - job_dot_low) * @ui.Ease::InOut.at(way)
      }
    }))
    |> ignore
  })
  |> ignore
}

///|
/// How faint a job's dot breathes while it restarts (Jobs.css.ts jobBreathe).
let job_dot_low : Double = 0.35

///|
/// The line under a job's name (job_meta's, as a node) in `parent`: its state's word in its dot's colour's ink, what it
/// said in the ink, the rest muted, `size`, on one line; the job as it is now.
fn job_meta_node(parent : @view.View, job : () -> Json?, size : Double) -> Unit {
  job_runs_node(
    parent,
    fn() {
      let j = job()
      let t = @sf.theme()
      let word = match text(j, "tone") {
        "up" | "live" => t.p.green_ink
        "restart" => t.p.warn_ink
        "fail" => t.p.red
        _ => 0L
      }
      items(j, "meta").map(fn(p) {
        let pv = Some(p)
        match text(pv, "kind") {
          "word" => @ui.span(text(pv, "text"), color=word)
          "notice" => @ui.span(text(pv, "text"), color=t.p.text)
          _ => @ui.span(text(pv, "text"))
        }
      })
    },
    fn() { job_words(size, wrap=false) },
    fn() { @sf.theme().p.muted },
  )
}

///|
/// A job, from the chat's sheet (JobBody), as nodes of the window's tree made once in `v` (open_job's panel's body): its
/// name and how it stands, what it said or its output as it grows (a service has only its output), stopped from here
/// while it runs; while it is read, or once it is gone, words saying so. What it shows follows the core's `chatJobs` as
/// it changes.
fn job_node(v : @view.View, src : Source, r : ChatRef, id : String) -> Unit {
  let topic = fn() { src.topic("chatJobs", chat_params(r)).get().value }
  let job = fn() { items(topic(), "jobs").iter().find_first(fn(j) { text(Some(j), "id") == id }) }
  v.show(fn() { job() is None }, fn(w) {
    @sf.style_node(w, fn() { @sf.panel_words_in_node(w) })
    job_words_node(
      w,
      fn() { if topic() is Some(_) { tr("android-misc.jobs.gone") } else { tr("common.reading") } },
      fn() { job_words(@sf.theme().t.meta) },
      fn() { @sf.theme().p.muted },
    )
  })
  v.show(fn() { job() is Some(_) }, fn(d) {
    // (the room the sheet leaves it, whatever it holds: from none, never pushed past it by a long output)
    d.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    job_detail_node(d, src, r, id, job)
  })
}

///|
/// A job, what it is, said and wrote (job_detail's, as nodes), in `v`: its dot, name and line, its command, then what it
/// said or its output (a service's output alone), and stopping it while it runs; `j` the job as it is now. In its
/// panel (open_job), on its words' line (the wide frame's 任务 tab has its own: sfdesk's jobs.mbt).
fn job_detail_node(v : @view.View, src : Source, r : ChatRef, id : String, j : () -> Json?) -> Unit {
  let service = flag(@signals.untracked(j), "service")
  // (what it said (0) or its output (1), as the sheet was opened to show; a service's, its output)
  let tab = @signals.signal(if service { 1 } else { dui.job_tab })
  let running = fn() { text(j(), "state") == "running" }
  // (on its panel's words' line, clear of an untitled dialog's close button)
  v.box(fn(h) {
    @sf.style_node(h, fn() { @sf.panel_words_in_node(h).then(@sf.untitled_clear_node(h)).then(job_head_at) })
    h.box(fn(b) {
      @sf.style_node(b, fn() { job_head_dot })
      job_dot_node(b, fn() { text(j(), "tone") })
    })
    |> ignore
    h.box(fn(b) {
      @sf.style_node(b, fn() { job_head_words }, in_row=true)
      job_words_node(b, fn() { text(j(), "name") }, fn() { job_words(@sf.theme().t.title, weight=600) }, fn() {
        @sf.theme().p.text
      })
      job_meta_node(b, j, job_meta_size)
    })
    |> ignore
  })
  |> ignore
  v.box(fn(col) {
    @sf.style_node(col, fn() { @sf.panel_words_in_node(col).then(job_body_at) })
    // (filling what its head leaves (job_body_at's h=Full, an old view's Fill), from none: never pushed past it by a
    // long output)
    col.height(Is(None)).grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    col.show(fn() { text(j(), "command").trim(chars=" \n").to_owned() != "" }, fn(w) {
      job_runs_node(
        w,
        fn() { [@ui.span(text(j(), "command"), mono=true)] },
        fn() { job_words(@sf.theme().t.caption, line=job_code_line) },
        fn() { @sf.theme().p.muted },
      )
    })
    if !service {
      col.box(fn(line) {
        line.row(Is(true)) |> ignore
        line.box(fn(slot) {
          @sf.segmented_node(
            slot,
            fn() { [tr("android-misc.jobs.notices"), tr("android-misc.jobs.output")] },
            fn() { tab.get() },
            fn(i) {
              dui.job_tab = i
              tab.set(i)
            },
          )
        })
        |> ignore
      })
      |> ignore
    }
    col.show(fn() { tab.get() == 0 }, fn(said) { job_said_node(said, src, r, id, j) })
    col.show(fn() { tab.get() == 1 }, fn(out) { job_output_node(out, src, r, id) })
    col.show(running, fn(b) { job_stop_node(b, src, r, id, j) })
  })
  |> ignore
}

///|
/// What a job said (job_detail's notices, as nodes) in `v`: its notices each with its clock, or words saying it said
/// none; then what it wrote last and when (the core's `jobLog`, its last line), as they are now.
fn job_said_node(v : @view.View, src : Source, r : ChatRef, id : String, j : () -> Json?) -> Unit {
  // (in the column of what it shows, 14 apart as that has them: none of its own)
  v.gap(Is(job_body_gap)) |> ignore
  v.box(fn(list) {
    @sf.style_node(list, fn() { job_notices })
    list.show(fn() { items(j(), "notices").length() == 0 }, fn(none) {
      @sf.style_node(none, fn() { job_no_notices })
      job_words_node(none, fn() { tr("android-misc.jobs.noNotices") }, fn() { job_words(@sf.theme().t.meta) }, fn() {
        @sf.theme().p.muted
      })
    })
    list.each(
      fn() { items(j(), "notices").mapi(fn(i, n) { (i, n) }) },
      fn(x) { x.0 },
      fn(row, n) {
        let nv = fn() { Some(n.get().1) }
        @sf.style_node(row, fn() { job_notice })
        row.box(fn(b) {
          b.width(Is(Some(job_clock_w))) |> ignore
          job_words_node(b, fn() { text(nv(), "clock") }, fn() { job_words(@sf.theme().t.meta, wrap=false) }, fn() {
            @sf.theme().p.subtle
          })
        })
        |> ignore
        row.box(fn(b) {
          @sf.style_node(b, fn() { job_notice_words }, in_row=true)
          job_words_node(b, fn() { text(nv(), "text") }, fn() { job_words(@sf.theme().t.ui) }, fn() { @sf.theme().p.text })
        })
        |> ignore
      },
    )
  })
  |> ignore
  let last = @sfbase.hold(src, @sfbase.jobs_scope(r.station), "jobLog", {
    "station": Json::string(r.station),
    "job": Json::string(id),
    "lines": Json::number(1.0),
  })
  let said = fn() {
    let l = last.get().value
    match l {
      Some(Object(_)) => text(l, "said")
      _ => text(j(), "outputSaid")
    }
  }
  v.show(fn() { said() != "" }, fn(b) {
    @sf.style_node(b, fn() { job_last })
    job_words_node(b, said, fn() { job_words(@sf.theme().t.caption) }, fn() { @sf.theme().p.subtle })
    b.show(fn() { text(last.get().value, "last") != "" }, fn(w) {
      job_runs_node(
        w,
        fn() { [@ui.span(text(last.get().value, "last"), mono=true)] },
        fn() { job_words(@sf.theme().t.caption, wrap=false) },
        fn() { @sf.theme().p.muted },
      )
    })
  })
}

///|
/// A job's output (job_detail's, as nodes) in `v`: its last lines (the core's `jobLog`) in a terminal's colours as the
/// core says them, a block a line by its number, on a faint ground, scrolling, from its end and kept there as lines come
/// while it is there (a line more makes its block alone); words saying it wrote nothing where it did not, a spinner
/// while it is read.
fn job_output_node(v : @view.View, src : Source, r : ChatRef, id : String) -> Unit {
  let params : Map[String, Json] = {
    "station": Json::string(r.station),
    "job": Json::string(id),
    "lines": Json::number(job_output_most),
  }
  let log = @sfbase.hold(src, @sfbase.jobs_scope(r.station), "jobLog", params)
  // (its lines as they are now, each by its number, in the theme's ink: job_output_of's, a line's runs worked out as it
  // comes and kept while it is the same)
  let lines : @signals.Computed[@sfbase.TermLines?] = @signals.computed(fn(_) {
    guard log.get().value is Some(Object(_)) else { return None }
    let t = @sf.theme()
    Some(@sfbase.job_output_of(src, params, t.p.text, t.dark))
  })
  @sf.style_node(v, fn() { job_output_box.then(@ui.style(bg=Data(@sf.alpha(@sf.theme().p.text, job_output_ink)))) })
  // (filling what is left of its column (job_output_box's h=Full, an old view's Fill), at least its min_h, from none:
  // as tall whatever it holds, its lines scrolling in it)
  v.height(Is(None)).grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
  v.show(fn() { lines.get() is None }, fn(w) {
    @sf.style_node(w, fn() { job_output_wait })
    @sf.spinner_node(w, size=job_output_spin) |> ignore
  })
  v.show(fn() { lines.get() is Some(_) }, fn(b) {
    // (the room its box has, whatever it holds: from none, not from how tall all its lines are, an old list's)
    b.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    let scroll = @view.Scroll::list()
    // (its blocks are its lines by their numbers: a line more one block more, those there before as they were; where
    // it wrote nothing, one saying so, `job_output_none`)
    let keys = fn() {
      match lines.get() {
        Some(l) if l.lines.is_empty() => [job_output_none]
        Some(l) => l.lines.map(fn(x) { x.n })
        None => []
      }
    }
    let first = fn() {
      match lines.get() {
        Some(l) if !l.lines.is_empty() => l.lines[0].n
        _ => job_output_none
      }
    }
    b.scrolls_window(
      scroll,
      keys,
      // (at once, as it was: a debt of 方案 A, given its way list by list, shown to the owner: list-comes-off)
      at_once=true,
      fn(row, n) {
        // (its own line's runs, read again only as that line changes: the same while it is the same line)
        let runs = @signals.computed(
          fn(_) {
            if n == job_output_none {
              [@ui.span(tr("android-misc.jobs.noOutput"), mono=true)]
            } else {
              lines.get().bind(fn(l) { l.at(n) }).map_or([], fn(l) { l.runs })
            }
          },
          same=fn(a, b) { physical_equal(a, b) },
        )
        let top = @signals.computed(fn(_) { first() == n }, same=fn(a, b) { a == b })
        @sf.style_node(row, fn() {
          job_output_line.then(@ui.style(pt=@sf.room_of(if top.get() { job_output_end } else { 0.0 })))
        })
        job_runs_node(row, fn() { runs.get() }, fn() { job_words(@sf.theme().t.caption, line=job_code_line) }, fn() {
          @sf.theme().p.text
        })
      },
      est=job_code_line,
      slop=@ui.touch_slop(),
      bar=@ui.tree_scroll_bar(),
      // (under its last line the room its first has over it: its foot, drawing nothing)
      foot=fn(f) { f.height(Is(Some(job_output_end))) |> ignore },
      // (Ctx::list's stick_end, the old one's: made at its end, kept there as lines come while it is there, not once
      // scrolled off it; followed again once scrolled back to it)
      follows=fn() { true },
      // (what shows held where it is by none of its lines as more come under them: its end followed, an old list's)
      holds=fn(_) { false },
    )
    |> ignore
  })
}

///|
/// The key of the one block of a job's output that wrote nothing: none of its lines' numbers.
let job_output_none : Int = -1

///|
/// How many of a job's last lines its output shows.
let job_output_most : Double = 300.0

///|
/// Stopping a running job (job_detail's 停止, as a node) in `v`: a pale red capsule across, its stop mark (a spinner
/// while it is asked) and its words; pressed, the core asked to stop it, said so (act's).
fn job_stop_node(v : @view.View, src : Source, r : ChatRef, id : String, j : () -> Json?) -> Unit {
  let skey = "job-stop/" + r.station + "/" + id
  let busy = fn() { doing(skey) }
  v.box(fn(b) {
    @sf.style_node(b, fn() { job_stop.then(@ui.style(bg=Data(@sf.alpha(@sf.theme().p.red, job_stop_ink)))) })
    @sf.rippled_node(
      b,
      fn() {
        if !@signals.untracked(busy) {
          @ui.haptic(Confirm)
          act(
            src,
            fill("android-misc.jobs.stopWhat", [("name", text(@signals.untracked(j), "name"))]),
            skey,
            "job.stop",
            { "station": Json::string(r.station), "id": Json::string(id) },
          )
        }
      },
      job_stop_h / 2.0,
      fn() { tr("android-misc.jobs.stop") },
    )
    b.show(busy, fn(s) { @sf.spinner_node(s, size=job_stop_spin) |> ignore })
    b.show(fn() { !busy() }, fn(s) { @sf.icon_node(s, "stop", job_stop_icon, By(fn() { @sf.theme().p.red })) |> ignore })
    job_words_node(b, fn() { tr("android-misc.jobs.stop") }, fn() { job_words(@sf.theme().t.ui, weight=500, wrap=false) }, fn() {
      @sf.theme().p.red
    })
  })
  |> ignore
}

///|
/// A job's head: on its words' line, 4 over it, 14 under, its dot (8 down, on its name's line) and its words 12 apart.
// kept across runs: a value (no field of it changes)
let job_head_at : @ui.Style = @ui.css("row w=Full pt=S1 pb=S3_5 gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let job_head_dot : @ui.Style = @ui.css("pt=S2")

///|
// kept across runs: a value (no field of it changes)
let job_head_words : @ui.Style = @ui.css("w=Full")

///|
/// How big the line under a job's name is in its sheet.
let job_meta_size : Double = 12.5

///|
/// What it shows under its head: filling the sheet's room, 24 over its foot, its parts 14 apart.
// kept across runs: a value (no field of it changes)
let job_body_at : @ui.Style = @ui.css("w=Full h=Full pb=S6 gap=S3_5")

///|
let job_body_gap : Double = 14.0

///|
/// The lines of code it shows (its command, its output), 17 apart.
let job_code_line : Double = 17.0

///|
/// Its notices, 12 apart; none, words saying so 20 in and 8 over and under.
// kept across runs: a value (no field of it changes)
let job_notices : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let job_no_notices : @ui.Style = @ui.css("px=S5 py=S2")

///|
/// A notice: its clock in a column 48 wide, its words 10 after it.
// kept across runs: a value (no field of it changes)
let job_notice : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
let job_clock_w : Double = 48.0

///|
// kept across runs: a value (no field of it changes)
let job_notice_words : @ui.Style = @ui.css("w=Full")

///|
/// What it wrote last and when, 2 apart.
// kept across runs: a value (no field of it changes)
let job_last : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its output: filling what is left, 120 at least, 16 round, on the ink at 5%, cut at its corners; its lines 14 in, 12
/// over the first and under the last; a spinner 12 across 14 in and 12 down while it is read.
// kept across runs: a value (no field of it changes)
let job_output_box : @ui.Style = @ui.css("w=Full h=Full min_h=Fixed(120.0) radius=Xl1_5 clip")

///|
let job_output_ink : Double = 0.05

///|
// kept across runs: a value (no field of it changes)
let job_output_line : @ui.Style = @ui.css("w=Full px=S3_5")

///|
let job_output_end : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let job_output_wait : @ui.Style = @ui.css("px=S3_5 py=S3")

///|
let job_output_spin : Double = 12.0

///|
/// Stopping it: a capsule across, 46 high, its mark and words 6 apart in its middle, on red at 12%.
// kept across runs: a value (no field of it changes)
let job_stop : @ui.Style = @ui.css("row w=Full h=Fixed(46.0) radius=Full gap=S1_5 align=ACenter justify=JCenter")

///|
let job_stop_h : Double = 46.0

///|
let job_stop_ink : Double = 0.12

///|
let job_stop_spin : Double = 14.0

///|
let job_stop_icon : Double = 16.0

///|
/// A job (job_node): the library's panel, most of the window, dragged between half and nearly all of it; titled 任务
/// while it is not there (read, or gone), its own head (its dot and name) once it is.
fn open_job(src : Source, r : ChatRef, id : String) -> Unit {
  let missing = fn() {
    !items(src.topic("chatJobs", chat_params(r)).get().value, "jobs").iter().any(fn(j) { text(Some(j), "id") == id })
  }
  @sf.panel_nodes(
    "",
    from=Unanchored,
    tall=0.8,
    grows=true,
    live=fn() { (if missing() { tr("android-misc.jobs.job") } else { "" }, "", "") },
    fn(v, _) { job_node(v, src, r, id) },
  )
}

///|
/// What is left up a long while on the workspace's stations, at the top of Home's list (in node `v`): web services and
/// background jobs, each under its heading, three of a group and the rest folded under 还有 N 个. A row leads to its
/// chat; its stop at its end.
fn open_jobs_node(v : @view.View, src : Source, w : Workspace) -> Unit {
  let groups = fn() { items(src.topic("longJobs", { "scope": Json::string(w.id) }).get().value, "groups") }
  @sf.style_node(v, fn() { open_jobs_at })
  v.each(groups, fn(g) { text(Some(g), "key") }, fn(gb, g) {
    let gv = fn() { Some(g.get()) }
    let gkey = fn() { "open-jobs/" + text(gv(), "key") }
    let list = fn() { items(gv(), "jobs") }
    let shown = fn() {
      let l = list()
      if dui.opened.contains(gkey()) || l.length() <= 4 {
        l
      } else {
        l[:3].to_owned()
      }
    }
    @sf.style_node(gb, fn() { open_jobs_group })
    gb.box(fn(h) {
      @sf.style_node(h, fn() { open_jobs_head })
      @sf.words_node(h, fn() { text(gv(), "head") }, fn() { open_jobs_head_words }) |> ignore
    })
    |> ignore
    gb.each(shown, fn(j) { text(Some(j), "station") + "/" + text(Some(j), "id") }, fn(row, j) {
      open_job_row_node(row, src, fn() { Some(j.get()) })
    })
    // (on a line of its own, as wide as its words)
    gb.show(fn() { shown().length() < list().length() }, fn(line) {
      @sf.style_node(line, fn() { open_job_line })
      line.box(fn(m) {
        @sf.style_node(m, fn() { open_jobs_more })
        let more = fn() { fill("android-misc.openJobs.more", [("n", (list().length() - shown().length()).to_string())]) }
        @sf.rippled_node(m, fn() { dui.opened[@signals.untracked(gkey)] = true }, open_jobs_more_corner, more)
        @sf.words_node(m, more, fn() { open_jobs_more_words }) |> ignore
      })
      |> ignore
    })
  })
}

///|
/// A job left up (in node `row`): its dot, its name over where it is and how long; the row to its chat, stop at its end.
fn open_job_row_node(row : @view.View, src : Source, job : () -> Json?) -> Unit {
  let station = fn() { text(job(), "station") }
  let id = fn() { text(job(), "id") }
  let skey = fn() { "job-stop/" + station() + "/" + id() }
  @sf.style_node(row, fn() { open_job_row })
  @sf.rippled_node(
    row,
    fn() {
      let j = @signals.untracked(job)
      match @sfbase.job_chat(j) {
        Some(r) => {
          @sfbase.history_push()
          app.nav.push(Chat(r))
          // a service: its page over its chat (the service is the job's station's)
          if flag(j, "service") {
            app.nav.push(Service(text(j, "station"), text(j, "id")))
          }
        }
        None => ()
      }
    },
    open_job_row_corner,
    fn() { text(job(), "name") },
  )
  row.box(fn(d) {
    @sf.style_node(d, fn() { open_job_dot })
    job_dot_node(d, fn() { text(job(), "tone") })
  })
  |> ignore
  row.box(fn(words) {
    @sf.style_node(words, fn() { open_job_words }, in_row=true)
    // (each on a line of its own across it, cut short where it has less room)
    words.box(fn(line) {
      @sf.style_node(line, fn() { open_job_line })
      @sf.words_node(line, fn() { text(job(), "name") }, fn() { open_job_name }) |> ignore
    })
    |> ignore
    words.box(fn(line) {
      @sf.style_node(line, fn() { open_job_line })
      @sf.words_node(line, fn() { text(job(), "whereText") + " · " + text(job(), "age") }, fn() { open_job_meta }) |> ignore
    })
    |> ignore
  })
  |> ignore
  row.box(fn(s) {
    @sf.style_node(s, fn() { open_job_stop })
    @sf.rippled_node(
      s,
      fn() {
        let j = @signals.untracked(job)
        let key = @signals.untracked(skey)
        if !doing(key) {
          @ui.haptic(Confirm)
          // a job's own stop, or a simulator's or a view's (its `stop`: 关闭, 断开)
          let (call, params, _) = long_stop(text(j, "station"), j)
          act(src, fill("android-misc.jobs.stopWhat", [("name", text(j, "name"))]), key, call, params)
        }
      },
      open_job_stop_side / 2.0,
      fn() {
        match text(field(job(), "stop"), "word") {
          "" => tr("android-misc.jobs.stop")
          word => word
        }
      },
    )
    // (stopping, a spinner in its icon's place: one of them made, not one made and one waiting)
    s.pick(fn() { doing(skey()) }, fn(b, stopping) {
      if stopping {
        @sf.spinner_node(b, size=open_job_stop_spin) |> ignore
      } else {
        @sf.icon_node(b, "stop", open_job_stop_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// 10 in at its sides, 4 over, 10 under, its groups 8 apart.
// kept across runs: a value (no field of it changes)
let open_jobs_at : @ui.Style = @ui.css("w=Full pl=S2_5 pr=S2_5 pt=S1 pb=S2_5 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let open_jobs_group : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let open_jobs_head : @ui.Style = @ui.css("px=S2_5 py=S0_5")

///|
// kept across runs: a value (no field of it changes)
let open_jobs_head_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let open_jobs_more : @ui.Style = @ui.css("px=S2_5 py=S1")

///|
let open_jobs_more_corner : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let open_jobs_more_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// Across, 10 in at its left, 4 at its right, 5 over and under, its parts 10 apart and on its middle.
// kept across runs: a value (no field of it changes)
let open_job_row : @ui.Style = @ui.css("row w=Full pl=S2_5 pr=S1 py=S1_25 gap=S2_5 align=ACenter")

///|
let open_job_row_corner : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let open_job_dot : @ui.Style = @ui.css("w=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let open_job_words : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let open_job_line : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let open_job_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut, leading=L4_75)

///|
// kept across runs: a value (no field of it changes)
let open_job_meta : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, w=Cut, leading=L4)

///|
// kept across runs: a value (no field of it changes)
let open_job_stop : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
let open_job_stop_side : Double = 32.0

///|
let open_job_stop_spin : Double = 12.0

///|
let open_job_stop_icon : Double = 15.0

///|
/// An info row's words (14, the ink, on one line).
// kept across runs: a value (no field of it changes)
let info_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

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
/// Opens what was said in the chat besides words (the library's panel, as the letters', what it holds nodes:
/// things_node); 在对话里看 closes it and goes to the message in the chat.
fn open_things(src : Source, r : ChatRef, thread : Double) -> Unit {
  @sf.panel_nodes(tr("web-main.things.title"), from=Unanchored, tall=0.8, grows=true, fn(v, close) {
    @sfpages.things_node(v, src, r, thread, fn(seq) {
      close()
      go_to(r, seq)
    })
  })
}

///|
/// How many pull requests the info names itself (the rest: 全部 N 个).
let info_pulls_most : Int = 3

///|
/// What is between the info's lists (its pull requests', its agents'): as far as they stand from its sides (the user,
/// 2026-11-03: 这个间距又是什么意思).
// kept across runs: a value (no field of it changes)
let info_lists_gap : @ui.Style = @ui.style(h=Fixed(@sf.panel_card_in))

///|
// kept across runs: a value (no field of it changes)
let info_pull_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// The params of a chat's letters (the core's `chatLetters` view).
fn letters_params(r : ChatRef, thread : Double) -> Map[String, Json] {
  { "station": Json::string(r.station), "thread": Json::number(thread) }
}

///|
/// A chat written with, its row in the letters' sheet: 18 in, 10 over and under, its two lines 2 apart;
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
/// then its title; 10 under it, so that back and the first letter's name each have a touch's 44 to be pressed in.
// kept across runs: a value (no field of it changes)
let letters_head : @ui.Style = @ui.css("row w=Full pb=S2_5 gap=S1 align=ACenter")

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
  c.on_press(id, fn() {
    dui.letters_open = key
  })
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
  let topic = src.topic("chatLetters", letters_params(r, thread)).get().snapshot()
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
          c.on_press(back, fn() {
            dui.letters_open = ""
          })
          c.box(style=letters_back, id=back, fn() {
            @sf.icon(c, "chevron-left", size=20.0, color=@sf.theme().p.accent_text) |> ignore
          })
          |> ignore
          let name = c.id("letters/chat")
          c.on_press(name, fn() {
            if link != "" {
              open_link(link)
            }
          })
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

///|
/// The way back to the chat an agent opened it from (chat_info_body): a row a finger presses, its words in the accent.
// kept across runs: a value (no field of it changes)
let info_opener : @ui.Style = @ui.css("row w=Full min_h=S11 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let info_opener_words : @ui.TextStyle = @ui.text_style(size=Body, color=AccentText, wrap=false, w=Cut)

///|
/// The row of the chats its agent made, in the chat's sheet (chat_info_body): how many, its words a row's.
// kept across runs: a value (no field of it changes)
let info_opened_title : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, wrap=false, w=Full)

///|
/// The room under a panel's last card: as far as its sides are in (panel_card_in).
// kept across runs: a value (no field of it changes)
let info_card_under : @ui.Style = @ui.style(h=Fixed(@sf.panel_card_in))
