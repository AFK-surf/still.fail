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
/// 11 round (6 under 30), and its state's badge over the corner (Badge: solid accent waiting on someone, an accent ring
/// at work, red failed) ringed in `around`.
fn model_mark_big(c : @ui.Ctx, maker : String, runtime : String, size : Double, state : String, around : Int64) -> Unit {
  let t = @sf.theme()
  let xs = size < 30.0
  c.box(w=Px(size), h=Px(size), fn() {
    c.box(
      w=Px(size),
      h=Px(size),
      radius=if xs { 6.0 } else { 11.0 },
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
/// A sheet's side margin (Android ChatInfo.kt, AgentSheet.kt: padding(start = 18.dp, end = 18.dp)).
let sheet_side : Double = 18.0

///|
/// What is under a fitted sheet's last card. Android: its column's padding(bottom = …) (ChatInfo.kt 30.dp,
/// AgentSheet.kt 24.dp), the sheet then made taller by the navigation bar (Sheet.kt: fit + foot, foot
/// WindowInsets.navigationBars). mbui draws inside the system bars (its Android host's view is set in by them,
/// MainActivity's onApplyWindowInsets), so that part is outside what it draws: the padding alone.
let chat_info_foot : Double = 30.0

///|
let agent_sheet_foot : Double = 24.0

///|
/// A row of an info card, its ground under the finger: Android ChatInfo.kt INFO_ROW (14.dp).
let info_row_radius : Double = 14.0

///|
/// An info card round its rows, INFO_PAD (6.dp) in: Android ChatInfo.kt InfoList, Smooth(concentricOut(INFO_ROW,
/// INFO_PAD)).
let info_list_radius : Double = @sf.surface_corner(6.0, info_row_radius)

///|
/// Rows on one quiet card (Android ChatInfo.kt InfoList): its rows INFO_PAD (6) in, the ink at 5%.
// kept across runs: a value (no field of it changes)
let info_list_style : @ui.Style = @ui.css("w=Full p=S1_5 bg=A(Fg,O5) clip")

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
/// A row that leads with a tile (a model's mark, 36 and 11 round): INFO_IN (4) in all round, so the tile is
/// concentric with the row and the card.
// kept across runs: a value (no field of it changes)
let info_row_tile : @ui.Style = @ui.css("px=S1")

///|
/// Its ground rounded INFO_ROW, pressed a shade. True on the frame after it was tapped (never when `key` is "": a row
/// that leads nowhere).
fn info_row(c : @ui.Ctx, key : String, body : () -> Unit, align? : @ui.Align = ACenter, tile? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = if key == "" { 0 } else { c.id(key) }
  let look = if tile { info_row_style.then(info_row_tile) } else { info_row_style }
  c.box(style=look.then(@ui.style(align~)), radius=info_row_radius, id~, fn() {
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
/// An allowance's windows, compact (Parts.kt QuotaChips): the settings' boxes (one FillChip, as Android's app has).
fn quota_chips(c : @ui.Ctx, quota : Json?, small? : Bool = false, gap? : Double = 8.0, tip? : (Int, Json) -> Unit) -> Unit {
  @settings.quota_chips(c, quota, small~, gap~, tip?)
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
    c.rich(runs, size=13.0, line=18.0, color=t.p.text, w=Fill(1.0), max_lines=2) |> ignore
  })
  |> ignore
}

// ── the chat's own sheet (ChatInfo.kt) ──────────────────────────────────

///|
/// The chat itself, from "…" (ChatInfo.kt openChatInfo): its name (with a way to change it) over who started it, how
/// many take part and when it was last written in; its agents, each where it stands (a tap opens its card); then what
/// can be done with it: what its agents and other chats' wrote each other, pin it, copy its link, its sharing, archive
/// it. As tall as what it shows.
fn chat_info_sheet(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  ignore(w)
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
  let feishu = text(chat, "feishuUrl")
  let xshare = field(chat, "xshare")
  sheet_frame(c, "info", c.height * 0.55, fit=true, fn() {
    let (archived, offline) = match view {
      Some(v) => (v.archived, v.offline)
      None => (false, false)
    }
    // archived or offline it is only read: no name to change, nothing to archive
    let open = view is Some(_) && !archived && !offline
    let thread = field(chat, "thread")
    let link = if view is Some(_) { chat_link(r.station, r.session) } else { "" }
    let title = text(chat, "title")
    c.box(w=Fill(1.0), pl=sheet_side, pr=sheet_side, pb=chat_info_foot, fn() {
      c.box(dir=Row, w=Fill(1.0), pt=4.0, gap=12.0, align=AStart, fn() {
        c.box(w=Fill(1.0), max_h=48.0, clip=true, fn() {
          c.text(title, size=18.0, weight=700, color=t.p.text, line=24.0) |> ignore
        })
        |> ignore
        if open {
          let id = c.id("info/rename")
          if c.clicked(id) {
            open_sheet(c, Rename(r, opt_number(thread, "id"), title))
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
          c.text(facts.join(" · "), size=13.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
      if agents.length() > 0 {
        info_list(c, fn() {
          for a in agents {
            let av = Some(a)
            let s = field(av, "session")
            let key = text(s, "key")
            if info_row(c, "info/agent/" + key, fn() {
                model_mark_big(
                  c,
                  text(field(s, "maker"), "id"),
                  text(s, "runtime"),
                  36.0,
                  state_of_badge(text(av, "badge")),
                  @sf.over(t.p.bg, @sf.alpha(t.p.card, 0.8)),
                )
                c.box(w=Fill(1.0), fn() {
                  c.text(text(s, "agentText"), size=15.0, weight=600, color=t.p.text, wrap=false) |> ignore
                  let since = agent_since(c, src, av)
                  let line = if since == "" {
                    text(s, "statusText")
                  } else {
                    text(s, "statusText") + " · " + since
                  }
                  c.text(line, size=12.0, color=t.p.muted, wrap=false) |> ignore
                })
                |> ignore
                quota_chips(c, match field(field(av, "account"), "quota") {
                  Some(_) as q => q
                  None => field(field(av, "profile"), "quota")
                })
                chevron(c)
              }, tile=true) {
              open_sheet(c, AgentOf(r, key))
            }
          }
        })
        c.box(h=Px(10.0), fn() {  }) |> ignore
      }
      let letters = number(chat, "letters")
      if open || link != "" || letters > 0.0 || slack != "" || xshare is Some(_) {
        info_list(c, fn() {
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
                open_letters(c, r, th)
              }
            _ => ()
          }
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
                      size=14.0,
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
                c.text(tr("web-main.chat.copyLink"), size=14.0, color=t.p.text, wrap=false) |> ignore
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
                open_relay(c, src, r, th)
              }
            _ => ()
          }
          match xshare {
            Some(Object(_)) => xshare_row(c, r, opt_number(thread, "id"), xshare)
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
            open_outside(slack)
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
                c.text(tr("android-chat.info.archive"), size=14.0, color=t.p.text, wrap=false) |> ignore
              })
              |> ignore
            }) {
            // a chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words)
            match (view, text(field(chat, "watch"), "ask")) {
              (Some(v), "") => archive_chat(src, r, v)
              (Some(v), ask) => {
                close_sheet(c)
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
        Some(_) as p => publish_list(c, src, r.station, number(thread, "id"), p)
        None => ()
      }
    })
    |> ignore
  })
}

///|
/// The rename sheet's words (its field shows them), and the chat they were given the name of ("" none yet: given the
/// next time it is shown).
let rename_field : @ui.Field = @ui.Field::new()

///|
let rename_given : Ref[String] = Ref("")

///|
/// Renaming the chat (ChatInfo.kt askTitle): a field with its name, 取消 and 保存 (an empty name gives it back its
/// first message); the sheet goes as it is saved, the core showing the new name at once.
fn rename_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double?, was : String) -> Unit {
  let t = @sf.theme()
  let key = "rename/field"
  sheet_frame(c, "rename", c.height * 0.42, fn() {
    let whose = r.station + "/" + r.session
    if rename_given.val != whose {
      rename_given.val = whose
      rename_field.set(was)
      c.focus_editor(key)
    }
    sheet_head(c, tr("android-chat.rename.title"))
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      let mut now = was
      c.box(
        w=Fill(1.0),
        padx=14.0,
        pady=12.0,
        radius=12.0,
        bg=t.p.card,
        border=1.0,
        border_color=t.p.line,
        fn() {
          let res = c.editor(
            key,
            placeholder=tr("android-chat.rename.field"),
            font_size=15.0,
            line=21.0,
            max_lines=3,
            plain=true,
            color=t.p.text,
            placeholder_color=t.p.subtle,
            caret_color=t.p.accent,
            enter_sends=false,
            field=rename_field,
          )
          now = res.text
        },
      )
      |> ignore
      c.text(tr("android-chat.rename.note"), size=12.0, color=t.p.muted, line=17.0) |> ignore
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if sheet_button(c, "rename/cancel", tr("common.cancel"), false, true) {
          rename_field.set("")
          rename_given.val = ""
          close_sheet(c)
        }
        let title = now.trim(chars=" \n\t").to_string()
        if sheet_button(c, "rename/save", tr("common.save"), true, title != was) {
          rename_field.set("")
          rename_given.val = ""
          close_sheet(c)
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
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A sheet's button (Controls.kt Button): the ink with the page's colour on it when `primary`, the chip otherwise.
fn sheet_button(c : @ui.Ctx, key : String, label : String, primary : Bool, enabled : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ground = if primary { t.p.text } else { t.p.chip }
  c.box(
    padx=18.0,
    pady=10.0,
    radius=12.0,
    opacity=if enabled { 1.0 } else { 0.4 },
    bg=ground,
    id~,
    fn() {
      c.text(label, size=15.0, weight=600, color=if primary { t.p.bg } else { t.p.text }, wrap=false)
      |> ignore
      // Controls.kt Button: clickable over its clip
      if enabled {
        @motion.ripple(c, id, 12.0)
      }
    },
  )
  |> ignore
  c.clicked(id) && enabled
}

// ── an agent's card (AgentSheet.kt) ─────────────────────────────────────

///|
/// An agent of the chat in brief (AgentSheet.kt openAgent): what it runs and where it stands (with a stop while it
/// works), its latest lines, the figures that say most, then where to go on: the station it runs on, its account, its
/// history, its jobs; and its context by hand (context.mbt).
fn agent_sheet(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, key : String) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r)).value
  let a = agent_json(chat, key)
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let jobs = items(a, "jobs")
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  sheet_frame(c, "agent", c.height * 0.55, fit=true, fn() {
    let s = field(a, "session")
    let status = text(a, "status")
    c.box(w=Fill(1.0), pl=sheet_side, pr=sheet_side, pb=agent_sheet_foot, fn() {
      c.box(dir=Row, w=Fill(1.0), pt=4.0, gap=12.0, align=ACenter, fn() {
        model_mark_big(
          c,
          text(field(s, "maker"), "id"),
          text(s, "runtime"),
          40.0,
          state_of_badge(text(a, "badge")),
          @sf.over(t.p.bg, @sf.alpha(t.p.card, 0.8)),
        )
        c.box(w=Fill(1.0), gap=1.0, fn() {
          c.text(text(s, "agentText"), size=17.0, weight=700, color=t.p.text, wrap=false) |> ignore
          agent_status(c, src, a)
        })
        |> ignore
        if status == "running" || status == "queued" {
          stop_button(c, src, r.station, key)
        }
      })
      |> ignore
      agent_lines(c, card)
      let entry = context_entry(c, r, key, s)
      agent_tiles(c, card, 14.0, entry~)
      agent_notes(c, card, 10.0)
      c.box(h=Px(12.0), fn() {  }) |> ignore
      info_list(c, fn() {
        match station {
          Some(st) =>
            if info_row(c, "agent/station", fn() {
                c.text(tr("android-chat.agent.station"), size=14.0, color=t.p.muted, wrap=false) |> ignore
                c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                  if @sf.has_station_mark(st.emoji, st.icon) {
                    @sf.station_mark(c, st.emoji, st.icon, 15.0, t.p.text)
                  }
                  c.text(st.name, size=14.0, color=t.p.text, wrap=false) |> ignore
                })
                |> ignore
                chevron(c)
              }) {
              // the station's card in place of this one
              close_sheet(c)
              @settings.open_station_peek(r.station)
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
        if agent_row(c, "agent/account", tr("android-chat.agent.account"), value, fn() {
            quota_chips(c, field(account, "quota"))
          }) {
          close_sheet(c)
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
          close_sheet(c)
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
          open_sheet(c, JobsOf(r))
        }
      })
    })
    |> ignore
  })
}

///|
/// A row of the card (AgentSheet.kt AgentRow): what it is about, what there is of it, where a tap leads.
fn agent_row(c : @ui.Ctx, key : String, label : String, value : String, trailing : () -> Unit) -> Bool {
  let t = @sf.theme()
  info_row(c, key, fn() {
    c.text(label, size=14.0, color=t.p.muted, wrap=false) |> ignore
    c.box(w=Fill(1.0), fn() {
      c.text(value, size=14.0, color=t.p.text, wrap=false) |> ignore
    })
    |> ignore
    trailing()
    chevron(c)
  })
}

///|
/// Stopping its turn, while it works (AgentSheet.kt StopButton): red on its tint, a spinner while it is asked.
fn stop_button(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let t = @sf.theme()
  let skey = "stop/" + station + "/" + key
  let busy = doing(skey)
  let id = c.id("agent/stop")
  if c.clicked(id) && !busy {
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
      c.text(tr("android-chat.agent.stop"), size=13.0, weight=500, color=t.p.red, wrap=false) |> ignore
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
        size=13.0,
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
      Some(o) => if c.clicked(id) && !o.busy { (o.open)() }
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
              "amber" => 0xD9962BFFL
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
        size=13.0,
        color=if text(Some(n), "level") == "amber" { 0xD9962BFFL } else { t.p.red },
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
/// How long a restarting service's dot takes to breathe out and in.
let job_breath_ms : Double = 1400.0

///|
/// A job's status (JobDot): a small dot (a restarting service's breathes).
fn job_dot(c : @ui.Ctx, tone : String) -> Unit {
  let t = @sf.theme()
  let breath = if tone == "restart" {
    let f = c.cycle(job_breath_ms)
    let p = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
    1.0 - 0.65 * p
  } else {
    1.0
  }
  c.box(
    w=Px(8.0),
    h=Px(8.0),
    radius=4.0,
    opacity=breath,
    bg=job_tint(tone).unwrap_or(t.p.subtle),
    fn() {  },
  )
  |> ignore
}

///|
/// The line under a job's name (metaOf): its state's word in its dot's colour, what it said in the ink.
fn job_meta(c : @ui.Ctx, job : Json?, size : Double) -> Unit {
  let t = @sf.theme()
  let tint = job_tint(text(job, "tone"))
  let runs = items(job, "meta").map(fn(p) {
    let pv = Some(p)
    match text(pv, "kind") {
      "word" => @ui.span(text(pv, "text"), color=tint.unwrap_or(0L))
      "notice" => @ui.span(text(pv, "text"), color=t.p.text)
      _ => @ui.span(text(pv, "text"))
    }
  })
  c.rich(runs, size~, color=t.p.muted, wrap=false) |> ignore
}

///|
/// A job's row (JobInfoRow): its dot on its name's line, what it is up to under it; over ones faded.
fn job_row(c : @ui.Ctx, key : String, job : Json?) -> Bool {
  let t = @sf.theme()
  let off = job_tint(text(job, "tone")) is None
  info_row(
    c,
    key,
    fn() {
      c.box(pt=7.0, opacity=if off { 0.55 } else { 1.0 }, fn() { job_dot(c, text(job, "tone")) })
      |> ignore
      c.box(w=Fill(1.0), gap=1.0, opacity=if off { 0.55 } else { 1.0 }, fn() {
        c.text(text(job, "name"), size=15.0, weight=500, color=t.p.text, wrap=false) |> ignore
        job_meta(c, job, 12.5)
      })
      |> ignore
      c.box(pt=4.0, fn() { chevron(c) }) |> ignore
    },
    align=AStart,
  )
}

///|
/// A group's label (Controls.kt GroupLabel): 13, muted, 14 above it and 4 under.
fn group_label(c : @ui.Ctx, label : String) -> Unit {
  c.box(pt=14.0, pb=4.0, fn() {
    c.text(label, size=13.0, color=@sf.theme().p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// Services, then background jobs (Jobs.kt JobGroups), each group's head with how many are up or alive; a service up
/// or being started again opens its page (service.mbt), one that did not start (or is over) and any job its sheet.
fn job_groups(
  c : @ui.Ctx,
  r : ChatRef,
  view : Json?,
  jobs : Array[Json],
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
            close_sheet(c)
            app.nav.push(Service(r.station, id))
          } else {
            dui.job_tab = 1
            open_sheet(c, JobOf(r, id))
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
            None => open_sheet(c, JobOf(r, id))
          }
        }
      }
    })
  }
}

///|
/// What matters now of the chat's services and jobs (Jobs.kt openJobs), from the bar's button: the rest a tap away,
/// the ended cleared.
fn jobs_sheet(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("chatJobs", chat_params(r))
  sheet_frame(c, "jobs", c.height * 0.62, draggable=true, fn() {
    sheet_head(c, tr("android-misc.jobs.title"))
    let view = match topic.value {
      Some(Object(_)) as v => v
      _ => {
        waiting_rows(c, 3, topic.error)
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
          c.text(tr("android-misc.jobs.none"), size=15.0, weight=600, color=t.p.text) |> ignore
          c.text(tr("android-misc.jobs.none.text"), size=13.0, color=t.p.muted) |> ignore
        })
        |> ignore
      })
    }
    if jobs.length() > 0 && shown.length() == 0 {
      rows.push(fn() {
        c.box(padx=20.0, pady=8.0, fn() {
          c.text(tr("android-misc.jobs.noneNow"), size=13.0, color=t.p.muted) |> ignore
        })
        |> ignore
      })
    }
    rows.push(fn() { job_groups(c, r, view, shown) })
    if jobs.length().to_double() > number(view, "current") {
      rows.push(fn() {
        if sheet_link(c, "jobs/all", fn() {
            if dui.jobs_all {
              c.text(tr("android-misc.jobs.onlyNow"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
            } else {
              c.text(text(view, "allText"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
              c.text(text(view, "hiddenText"), size=12.0, color=t.p.muted) |> ignore
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
              c.text(text(view, "clearText"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
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
    c.list(
      "jobs-sheet/" + r.station + "/" + r.session,
      rows.length() + 1,
      60.0,
      fn(i) {
        c.box(w=Fill(1.0), pl=18.0, pr=18.0, fn() {
          if i < rows.length() {
            (rows[i])()
          } else {
            c.box(h=Px(30.0), fn() {  }) |> ignore
          }
        })
        |> ignore
      },
    )
    |> ignore
  })
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
/// What is being read breathing (Waiting.kt Waiting): `n` rows of shapes, what went wrong over them in red.
fn waiting_rows(c : @ui.Ctx, n : Int, error : Json?) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=18.0, gap=12.0, fn() {
    match error {
      Some(e) =>
        c.text(error_words(e), size=13.0, color=t.p.red, line=18.0) |> ignore
      None => ()
    }
    let breath = if error is None { @sf.breath(c) } else { 0.6 }
    for i in 0..<n {
      c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, opacity=breath, fn() {
        c.box(w=Px(36.0), h=Px(36.0), radius=11.0, bg=t.p.neutral_bg, fn() {  }) |> ignore
        c.box(w=Fill(1.0), gap=6.0, fn() {
          c.box(w=Px(if i % 2 == 0 { 160.0 } else { 120.0 }), h=Px(12.0), radius=6.0, bg=t.p.neutral_bg, fn() {  })
          |> ignore
          c.box(w=Px(220.0), h=Px(10.0), radius=5.0, bg=t.p.neutral_bg, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A job, from the chat's sheet (Jobs.kt openJob, JobBody): its name and how it stands, what it said or its output as it
/// grows (a service has only its output), stopped from here while it runs.
fn job_sheet(c : @ui.Ctx, src : Source, r : ChatRef, id : String) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("chatJobs", chat_params(r))
  let job = items(topic.value, "jobs").iter().find_first(fn(j) { text(Some(j), "id") == id })
  sheet_frame(c, "job", c.height * 0.8, draggable=true, fn() {
    let j = match job {
      Some(j) => Some(j)
      None => {
        sheet_head(c, tr("android-misc.jobs.job"))
        c.box(padx=18.0, fn() {
          c.text(
            if topic.value is Some(_) { tr("android-misc.jobs.gone") } else { tr("common.reading") },
            size=14.0,
            color=t.p.muted,
          )
          |> ignore
        })
        |> ignore
        return
      }
    }
    job_detail(c, src, r, id, j)
  })
}

///|
/// A job, what it is, said and wrote (Jobs.kt openJob's body): its dot, name and line, its command, then what it said
/// or its output (a service's output alone), and stopping it while it runs. In its sheet on a phone, in the side
/// panel's 任务 tab beside a chat in the wide frame (wide_panel.mbt).
fn job_detail(c : @ui.Ctx, src : Source, r : ChatRef, id : String, j : Json?) -> Unit {
  let t = @sf.theme()
  let service = flag(j, "service")
  let tab = if service { 1 } else { dui.job_tab }
  let running = text(j, "state") == "running"
  c.box(dir=Row, w=Fill(1.0), pl=22.0, pr=22.0, pt=4.0, pb=14.0, gap=12.0, align=AStart, fn() {
    c.box(pt=8.0, fn() { job_dot(c, text(j, "tone")) }) |> ignore
    c.box(w=Fill(1.0), fn() {
      c.text(text(j, "name"), size=16.0, weight=600, color=t.p.text) |> ignore
      job_meta(c, j, 12.5)
    })
    |> ignore
  })
  |> ignore
  c.box(w=Fill(1.0), h=Fill(1.0), pl=18.0, pr=18.0, pb=24.0, gap=14.0, fn() {
    let command = text(j, "command")
    if command.trim(chars=" \n").to_string() != "" {
      c.rich([@ui.span(command, mono=true)], size=11.5, line=17.0, color=t.p.muted, w=Fill(1.0)) |> ignore
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
            c.text(tr("android-misc.jobs.noNotices"), size=13.0, color=t.p.muted) |> ignore
          })
          |> ignore
        }
        for n in notices {
          c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
            c.box(w=Px(48.0), fn() {
              c.text(text(Some(n), "clock"), size=14.0, color=t.p.subtle, wrap=false) |> ignore
            })
            |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(text(Some(n), "text"), size=14.0, color=t.p.text) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      let last = (src.topic)("jobLog", {
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
          c.text(said, size=11.0, color=t.p.subtle) |> ignore
          match text(last, "last") {
            "" => ()
            l => c.rich([@ui.span(l, mono=true)], size=11.5, color=t.p.muted, wrap=false) |> ignore
          }
        })
        |> ignore
      }
    } else {
      let log = (src.topic)("jobLog", {
        "station": Json::string(r.station),
        "job": Json::string(id),
        "lines": Json::number(300.0),
      })
      c.box(
        w=Fill(1.0),
        h=Fill(1.0),
        min_h=120.0,
        radius=16.0,
        bg=@sf.alpha(t.p.text, 0.05),
        clip=true,
        fn() {
          match log.value {
            Some(Object(_)) as v => {
              let words = match text(v, "text") {
                "" => tr("android-misc.jobs.noOutput")
                s => s
              }
              // in a terminal's colours where the core says them (its `runs`: Jobs.kt termText), else as words
              let runs = items(v, "runs")
              let styled = if runs.length() > 0 { Some(term_lines(runs, t.p.text, t.dark)) } else { None }
              let lines = match styled {
                Some(ls) => Array::make(ls.length(), "")
                None => words.split("\n").map(fn(l) { l.to_owned() }).to_array()
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
                    let line = match styled {
                      Some(ls) => ls[i]
                      None => [@ui.span(lines[i], mono=true)]
                    }
                    c.rich(line, size=11.5, line=17.0, color=t.p.text, w=Fill(1.0)) |> ignore
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
      if c.clicked(sid) && !busy {
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
          c.text(tr("android-misc.jobs.stop"), size=15.0, weight=500, color=t.p.red, wrap=false)
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
          c.text(text(gv, "head"), size=12.0, color=t.p.muted, wrap=false) |> ignore
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
              size=12.0,
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
  if c.clicked(row) && chat is Some(Object(_)) {
    app.nav.push(Chat({ station, session: text(chat, "id"), title: text(chat, "title"), station_name: "" }))
    // a service: its page over its chat (OpenJobs.kt OpenRow)
    if flag(job, "service") {
      app.nav.push(Service(station, id))
    }
  }
  let skey = "job-stop/" + station + "/" + id
  let stop = c.id("open-job-stop/" + station + "/" + id)
  if c.clicked(stop) && !doing(skey) {
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
        c.text(text(job, "name"), size=14.0, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          text(job, "whereText") + " · " + text(job, "age"),
          size=12.0,
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
let info_words : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
/// A link opened in the system's app for it (ChatInfo.kt: ACTION_VIEW), said when there is none.
fn open_outside(url : String) -> Unit {
  if !@ui.open_url(url) {
    toast_later(tr("android-chat.link.failed"))
  }
}

///|
/// Opens the chat's letters' sheet at its list; its letters held (the core's `chatLetters`) until the chat is left.
fn open_letters(c : @ui.Ctx, r : ChatRef, thread : Double) -> Unit {
  dui.letters_open = ""
  dui.letters_held[r.station + "\u{1}" + r.session] = thread
  open_sheet(c, LettersOf(r, thread))
}

///|
/// The params of a chat's letters (the core's `chatLetters` view).
fn letters_params(r : ChatRef, thread : Double) -> Map[String, Json] {
  { "station": Json::string(r.station), "thread": Json::number(thread) }
}

///|
/// A chat written with, its row in the letters' sheet (Letters.kt): 18 in, 10 over and under, its two lines 2 apart;
/// pressed a shade.
// kept across runs: a value (no field of it changes)
let letters_row : @ui.Style = @ui.css("w=Full px=S4_5 py=S2_5 gap=S0_5 pressed{bg=A(Fg,O5)}")

///|
/// Its first line: its title as wide as there is room, how many and when at its end, 8 apart.
// kept across runs: a value (no field of it changes)
let letters_row_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// What fills a line's room (its title, beside what is at its end).
// kept across runs: a value (no field of it changes)
let letters_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A chat's title (15, medium) and what is said in brief of it (13, muted), each on a line.
// kept across runs: a value (no field of it changes)
let letters_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let letters_meta : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// None: said 18 in, 12 over and under, 15 muted.
// kept across runs: a value (no field of it changes)
let letters_none_box : @ui.Style = @ui.css("px=S4_5 py=S3")

///|
// kept across runs: a value (no field of it changes)
let letters_none : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted)

///|
/// One opened, its head: back (a round 36, pressed a shade), then its title; 6 in at the start, 18 at the end.
// kept across runs: a value (no field of it changes)
let letters_head : @ui.Style = @ui.css("row w=Full pl=S1_5 pr=S4_5 pb=S1_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let letters_back : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter pressed{bg=A(Fg,O5)}")

///|
/// A letter, as the chat draws a message: 14 in, 20 under the one before.
// kept across runs: a value (no field of it changes)
let letters_said : @ui.Style = @ui.css("w=Full px=S3_5 pt=S1 pb=S4")

///|
/// Older ones on their way: a spinner, 8 under the last.
// kept across runs: a value (no field of it changes)
let letters_more : @ui.Style = @ui.css("w=Full pt=S2 align=ACenter")

///|
/// Room under the last row, over the sheet's foot (Letters.kt bottom = 30).
// kept across runs: a value (no field of it changes)
let letters_foot : @ui.Style = @ui.css("h=S8")

///|
/// What the chat's agents and other chats' wrote each other, not said in it (Letters.kt openLetters): the chats it
/// wrote with, a row each, the last written with first (its title, how many and when, the last letter in brief under
/// them); one opened, back to the list and its title (which opens that chat), then its letters both ways in the order
/// written, each drawn as the chat draws a message (Chat.kt SaidAlone).
fn letters_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  sheet_frame(c, "letters", c.height * 0.8, draggable=true, fn() {
    sheet_head(c, tr("web-main.letters.title"))
    letters_body(c, src, r, thread)
  })
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
      waiting_rows(c, 3, topic.error)
      return
    }
  }
  let chats = items(view, "chats")
  let whole = flag(view, "whole")
  // not here yet: its rows to come
  if chats.length() == 0 && !whole {
    waiting_rows(c, 3, topic.error)
    return
  }
  let rows : Array[() -> Unit] = []
  if chats.length() == 0 {
    rows.push(fn() {
      c.box(style=letters_none_box, fn() { c.text(tr("web-main.letters.none"), style=letters_none) |> ignore })
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
        c.box(style=letters_head, fn() {
          let back = c.id("letters/back")
          if c.clicked(back) {
            dui.letters_open = ""
          }
          c.box(style=letters_back, id=back, fn() {
            @sf.icon(c, "chevron-left", size=20.0, color=@sf.theme().p.accent) |> ignore
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
      let here = { station: r.station, session: r.session, view: v }
      for m in items(ch, "letters") {
        let message = message_of(m)
        rows.push(fn() {
          c.box(style=letters_said, fn() { said(c, src, here, message, [], decide=false) }) |> ignore
        })
      }
    }
    _ =>
      for ch in chats {
        let ch = Some(ch)
        let key = text(ch, "key")
        rows.push(fn() {
          // a chat it wrote with: its title, how many and when, the last letter in brief under them
          let id = c.id("letters/row/" + key)
          if c.clicked(id) {
            dui.letters_open = key
          }
          c.box(style=letters_row, id~, fn() {
            c.box(style=letters_row_head, fn() {
              c.box(style=letters_grow, fn() { c.text(text(ch, "title"), style=letters_title) |> ignore }) |> ignore
              let n = fill("web-main.letters.count", [("n", items(ch, "letters").length().to_string())])
              let ago = text(field(field(ch, "time"), "lastActiveAt"), "ago")
              c.text(if ago == "" { n } else { n + " · " + ago }, style=letters_meta) |> ignore
            })
            |> ignore
            c.text(text(ch, "last"), style=letters_meta) |> ignore
          })
          |> ignore
        })
      }
  }
  // not all of the chat is here yet: older ones may come
  if !whole {
    rows.push(fn() { c.box(style=letters_more, fn() { @sf.spinner(c, size=16.0) |> ignore }) |> ignore })
  }
  c.list(
    "letters-sheet/" + r.station + "/" + r.session + "/" + dui.letters_open,
    rows.length() + 1,
    60.0,
    fn(i) {
      if i < rows.length() {
        (rows[i])()
      } else {
        c.box(style=letters_foot, fn() {  }) |> ignore
      }
    },
  )
  |> ignore
}
