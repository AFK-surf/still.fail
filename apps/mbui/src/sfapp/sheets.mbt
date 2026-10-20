// The sheets over a chat (slice 8): its own, from "…" (ember apps/android chat/screens/ChatInfo.kt openChatInfo,
// askTitle, InfoList, InfoRow), an agent's card (AgentSheet.kt openAgent, AgentStatus, AgentLines, AgentTiles,
// AgentNotes, StopButton), its services and jobs and one job (Jobs.kt openJobs, JobGroups, JobInfoRow, JobDot, metaOf,
// openJob, JobBody), and the jobs left up a long while at the top of Home (OpenJobs.kt). What they show is the core's
// (the `chat`, `agentCard`, `stations`, `chatJobs`, `jobLog` and `longJobs` views); what is done goes through its calls.
//
// Not here yet, against the Android app: sharing the chat with other workspaces (its row is shown, not opened), making
// it public (Publish.kt), a watched chat's question before archiving, the station's card (its row closes the sheet),
// the run settings page (its row is shown), dragging a sheet by its grabber.

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
/// Rows on one quiet card (ChatInfo.kt InfoList): 14 round, the ink at 5%.
fn info_list(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), radius=14.0, bg=@sf.alpha(t.p.text, 0.05), clip=true, body) |> ignore
}

///|
/// A row of it (InfoRow): 12 in, 10 above and under, what it holds 12 apart; pressed, a shade. True on the frame after
/// it was tapped (never when `key` is "": a row that leads nowhere).
fn info_row(c : @ui.Ctx, key : String, body : () -> Unit, align? : @ui.Align = ACenter) -> Bool {
  let t = @sf.theme()
  let id = if key == "" { 0 } else { c.id(key) }
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=12.0,
    pady=10.0,
    gap=12.0,
    align~,
    bg=if id != 0 && c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
    id~,
    body,
  )
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
/// An allowance's windows, compact (Parts.kt QuotaChips, FillChip): a box per window with what is left in it (its mark
/// before it when there are several), its ground filled from the left as far as is left; a low one in its colour.
fn quota_chips(c : @ui.Ctx, quota : Json?, small? : Bool = false) -> Unit {
  if text(quota, "state") != "ok" {
    return
  }
  let windows = items(quota, "windows")
  if windows.length() == 0 {
    return
  }
  let t = @sf.theme()
  let lone = windows.length() == 1
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    for w in windows {
      let wv = Some(w)
      let left = dmax(0.0, dmin(100.0, number(wv, "left")))
      let level = text(wv, "level")
      let low = level == "amber" || level == "red"
      let tone = match level {
        "red" => t.p.red
        "amber" => 0xD9962BFFL
        _ => t.p.green
      }
      let ground = if low { @sf.alpha(tone, 0.2) } else { @sf.alpha(t.p.muted, 0.22) }
      let fs = if small { 10.0 } else { 11.0 }
      c.box(h=Px(if small { 16.0 } else { 20.0 }), radius=fill_chip_radius, bg=t.p.chip, clip=true, fn() {
        c.layer(fn() {
          c.box(w=Fill(left / 100.0), h=Fill(1.0), radius=@sf.concentric(fill_chip_radius, 0.0), bg=ground, fn() {  }) |> ignore
        })
        |> ignore
        c.box(
          dir=Row,
          h=Fill(1.0),
          padx=if small { 5.0 } else { 8.0 },
          gap=5.0,
          align=ACenter,
          fn() {
            if !lone {
              c.text(text(wv, "mark"), size=fs, weight=600, color=@sf.mix(t.p.text, 0.5, t.p.muted), wrap=false)
              |> ignore
            }
            c.text(
              "\{left.to_int()}%",
              size=fs,
              weight=600,
              color=if low { tone } else { t.p.text },
              wrap=false,
            )
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A choice of a few (Parts.kt Seg): a track of the ink at 6%, 10 round, the chosen one on a light thumb with a
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
  let mut sel = chosen
  for i, _ in labels {
    if c.clicked(c.id(key + "/" + i.to_string())) && i != sel {
      sel = i
    }
  }
  c.box(
    dir=Row,
    w=if fill { Fill(1.0) } else { Auto },
    h=Px(height),
    pad=2.0,
    radius=10.0,
    bg=@sf.alpha(t.p.text, 0.06),
    fn() {
      for i, l in labels {
        let on = i == sel
        c.box(
          w=if fill { Fill(1.0) } else { Auto },
          h=Fill(1.0),
          padx=if fill { 12.0 } else { 10.0 },
          radius=8.0,
          align=ACenter,
          justify=JCenter,
          bg=if on { if t.dark { 0x3A3B40FFL } else { 0xFFFFFFFFL } } else { 0L },
          border=if on { 0.5 } else { 0.0 },
          border_color=t.p.line,
          id=c.id(key + "/" + i.to_string()),
          fn() {
            c.text(
              l,
              size=if fill { 14.0 } else { 13.0 },
              color=if on { t.p.text } else { t.p.muted },
              wrap=false,
            )
            |> ignore
          },
        )
        |> ignore
      }
    },
  )
  |> ignore
  sel
}

///|
/// The agent of a chat by its session, as the chat's view has it.
fn agent_json(chat : Json?, key : String) -> Json? {
  for a in items(chat, "agents") {
    if text(field(Some(a), "session"), "key") == key {
      return Some(a)
    }
  }
  None
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
            wake_next_second(c, now - from)
          }
          elapsed(dmin(now, from + sec * second_ms) - from) + " / " + elapsed(sec * second_ms)
        }
        None => {
          wake_next_second(c, now - from)
          elapsed(now - from)
        }
      }
    }
    _ => {
      let from = since.unwrap_or(now)
      wake_next_second(c, now - from)
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
    c.rich(runs, size=13.0, line=18.0, color=t.p.text, w=Fill(1.0)) |> ignore
  })
  |> ignore
}

// ── the chat's own sheet (ChatInfo.kt) ──────────────────────────────────

///|
/// The cloud's address, for a chat's link (the app's MBUI_CLOUD, else still.fail's own).
fn cloud_origin() -> String {
  match @ui.env("MBUI_CLOUD") {
    "" => "https://app.still.fail"
    o => o
  }
}

///|
/// A chat's still.fail link (ChatLink.kt chatLink): <cloud>/o/<workspace>/<station>/<session>; "" for a station of no
/// workspace or a chat with no session yet.
fn chat_link(station : String, session : String) -> String {
  match station.find("/") {
    Some(at) if at > 0 && at < station.length() - 1 && session != "" => {
      let cloud = cloud_origin()
      let base = if cloud.has_suffix("/") {
        cloud.view(end_offset=cloud.length() - 1).to_owned()
      } else {
        cloud
      }
      base +
      "/o/" +
      station.view(end_offset=at).to_owned() +
      "/" +
      station.view(start_offset=at + 1).to_owned() +
      "/" +
      encode_component(session)
    }
    _ => ""
  }
}

///|
/// As JavaScript's encodeURIComponent.
fn encode_component(s : String) -> String {
  let sb = StringBuilder()
  let bytes = utf8_bytes(s)
  let hex = "0123456789ABCDEF"
  for b in bytes {
    let x = b.to_int()
    let ch = Int::unsafe_to_char(x)
    if (x >= 0x30 && x <= 0x39) ||
      (x >= 0x41 && x <= 0x5A) ||
      (x >= 0x61 && x <= 0x7A) ||
      "-_.!~*'()".contains_char(ch) {
      sb.write_char(ch)
    } else {
      sb.write_char('%')
      sb.write_char(hex.get_char(x / 16).unwrap_or('0'))
      sb.write_char(hex.get_char(x % 16).unwrap_or('0'))
    }
  }
  sb.to_string()
}

///|
/// Copies a chat's link as a reference is sent (ChatLink.kt copyChatLink, chatLinkText): `[title](link)`.
fn copy_chat_link(c : @ui.Ctx, title : String, link : String) -> Unit {
  let shown = title.replace_all(old="[", new=" ").replace_all(old="]", new=" ").replace_all(old="\n", new=" ").trim(chars=" ").to_string()
  let shown = if shown == "" { link } else { shown }
  c.copy_text("[" + shown + "](" + link + ")")
  say(c, tr("android-chat.annotate.copied"))
}

///|
/// The chat itself, from "…" (ChatInfo.kt openChatInfo): its name (with a way to change it) over who started it, how
/// many take part and when it was last written in; its agents, each where it stands (a tap opens its card); then what
/// can be done with it: pin it, copy its link, its sharing, archive it. As tall as what it shows.
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
  let xshare = field(chat, "xshare")
  let rows = dmax(agents.length().to_double(), 1.0) * 56.0 +
    (
      (if pinned is Some(_) { 1.0 } else { 0.0 }) +
      (if slack != "" { 1.0 } else { 0.0 }) +
      (if xshare is Some(_) { 1.0 } else { 0.0 }) +
      2.0
    ) *
    40.0
  let tall = 22.0 + 84.0 + rows + 10.0 + 30.0
  sheet_frame(c, "info", tall, fn() {
    let (archived, offline) = match view {
      Some(v) => (v.archived, v.offline)
      None => (false, false)
    }
    // archived or offline it is only read: no name to change, nothing to archive
    let open = view is Some(_) && !archived && !offline
    let thread = field(chat, "thread")
    let link = if view is Some(_) { chat_link(r.station, r.session) } else { "" }
    let title = text(chat, "title")
    c.box(w=Fill(1.0), pl=18.0, pr=18.0, pb=30.0, fn() {
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
            bg=@sf.alpha(t.p.text, if c.pressed(id) { 0.1 } else { 0.05 }),
            align=ACenter,
            justify=JCenter,
            id~,
            fn() { @sf.icon(c, "edit", size=16.0, color=t.p.text) |> ignore },
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
            people_stack(c, src, shown, 16.0)
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
              }) {
              open_sheet(c, AgentOf(r, key))
            }
          }
        })
        c.box(h=Px(10.0), fn() {  }) |> ignore
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
          match xshare {
            Some(Object(_)) =>
              info_row(c, "", fn() {
                @sf.icon(c, "users", size=16.0, color=t.p.text) |> ignore
                c.text(tr("web-pages.chat.xshare"), size=14.0, color=t.p.text, wrap=false) |> ignore
                c.box(w=Fill(1.0), align=AEnd, fn() {
                  c.text(text(xshare, "text"), size=13.0, color=t.p.muted, wrap=false) |> ignore
                })
                |> ignore
              })
              |> ignore
            _ => ()
          }
          if slack != "" {
            info_row(c, "", fn() {
              @sf.slack_mark(c, 16.0) |> ignore
              c.box(w=Fill(1.0), fn() {
                c.text(tr("android-chat.info.slack.open"), size=14.0, color=t.p.text, wrap=false) |> ignore
              })
              |> ignore
              chevron(c)
            })
            |> ignore
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
            match view {
              Some(v) => archive_chat(src, r, v)
              None => ()
            }
          }
        })
      }
    })
    |> ignore
  })
}

///|
/// Renaming the chat (ChatInfo.kt askTitle): a field with its name, 取消 and 保存 (an empty name gives it back its
/// first message); the sheet goes as it is saved, the core showing the new name at once.
fn rename_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double?, was : String) -> Unit {
  let t = @sf.theme()
  let key = "rename/field"
  sheet_frame(c, "rename", c.height * 0.42, fn() {
    if !c.has_editor(key) {
      c.set_editor_text(key, was)
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
          )
          now = res.text
        },
      )
      |> ignore
      c.text(tr("android-chat.rename.note"), size=12.0, color=t.p.muted, line=17.0) |> ignore
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if sheet_button(c, "rename/cancel", tr("common.cancel"), false, true) {
          c.take_editor_text(key) |> ignore
          close_sheet(c)
        }
        let title = now.trim(chars=" \n\t").to_string()
        if sheet_button(c, "rename/save", tr("common.save"), true, title != was) {
          c.take_editor_text(key) |> ignore
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
    bg=if c.pressed(id) && enabled { @sf.over(ground, @sf.alpha(t.p.bg, 0.15)) } else { ground },
    id~,
    fn() {
      c.text(label, size=15.0, weight=600, color=if primary { t.p.bg } else { t.p.text }, wrap=false)
      |> ignore
    },
  )
  |> ignore
  c.clicked(id) && enabled
}

// ── an agent's card (AgentSheet.kt) ─────────────────────────────────────

///|
/// An agent of the chat in brief (AgentSheet.kt openAgent): what it runs and where it stands (with a stop while it
/// works), its latest lines, the figures that say most, then where to go on: the station it runs on, its account, its
/// history, its jobs.
fn agent_sheet(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, key : String) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r)).value
  let a = agent_json(chat, key)
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let jobs = items(a, "jobs")
  let notes = items(card, "attention").length()
  let turns = items(a, "turns").length() > 0
  let rows = 3.0 + (if jobs.length() > 0 { 1.0 } else { 0.0 })
  let tall = 22.0 +
    52.0 +
    (if turns { 72.0 + 76.0 } else { 0.0 }) +
    (if notes > 0 { 8.0 + notes.to_double() * 20.0 } else { 0.0 }) +
    12.0 +
    rows * 40.0 +
    24.0
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  sheet_frame(c, "agent", tall, fn() {
    let s = field(a, "session")
    let status = text(a, "status")
    c.box(w=Fill(1.0), pl=18.0, pr=18.0, pb=24.0, fn() {
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
      agent_tiles(c, card, 14.0)
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
              // the station's card is a later slice's
              close_sheet(c)
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
        // changing how it runs (History.kt RunSettingsScreen) is not here yet: the row says it
        agent_row(c, "", tr("android-chat.agent.account"), value, fn() {
          quota_chips(c, field(account, "quota"))
        })
        |> ignore
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
          app.nav.push(History(r, key))
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
    bg=@sf.alpha(t.p.red, if c.pressed(id) { 0.22 } else { 0.14 }),
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else {
        @sf.icon(c, "stop", size=11.0, color=t.p.red) |> ignore
      }
      c.text(tr("android-chat.agent.stop"), size=13.0, weight=500, color=t.p.red, wrap=false) |> ignore
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
fn agent_tiles(c : @ui.Ctx, card : Json?, top : Double) -> Unit {
  let t = @sf.theme()
  let context = field(card, "context")
  let cost = text(card, "cost")
  let cache = field(card, "cache")
  if cost == "" && cache is None && context is None {
    return
  }
  let tile = fn(figure : String, name : String, color : Int64) {
    c.box(
      w=Fill(1.0),
      radius=14.0,
      bg=@sf.alpha(t.p.text, 0.05),
      pl=12.0,
      pr=12.0,
      pt=9.0,
      pb=8.0,
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
        c.text(name, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
      },
    )
    |> ignore
  }
  c.box(dir=Row, w=Fill(1.0), pt=top, gap=8.0, fn() {
    if cost != "" {
      tile(cost, tr("android-chat.agent.cost"), t.p.text)
    }
    if cache is Some(Object(_)) {
      tile(text(cache, "text"), tr("android-chat.agent.cache"), t.p.text)
    }
    match context {
      Some(Object(_)) =>
        if flag(context, "unknown") {
          tile(text(context, "text"), tr("android-chat.agent.context"), t.p.text)
        } else {
          tile(
            "\{number(context, "percent").round().to_int()}%",
            tr("android-chat.agent.context"),
            match text(context, "level") {
              "red" => t.p.red
              "amber" => 0xD9962BFFL
              _ => t.p.text
            },
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
fn job_groups(c : @ui.Ctx, r : ChatRef, view : Json?, jobs : Array[Json]) -> Unit {
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
          // up or being started again: its page (Preview.kt); else what it said and its output
          let tone = text(Some(j), "tone")
          if tone == "up" || tone == "restart" {
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
          open_sheet(c, JobOf(r, id))
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
  sheet_frame(c, "jobs", c.height * 0.62, fn() {
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
              c.text(tr("android-misc.jobs.onlyNow"), size=14.0, color=t.p.accent, wrap=false) |> ignore
            } else {
              c.text(text(view, "allText"), size=14.0, color=t.p.accent, wrap=false) |> ignore
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
              c.text(text(view, "clearText"), size=14.0, color=t.p.accent, wrap=false) |> ignore
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
    c.box(
      padx=2.0,
      pady=6.0,
      gap=2.0,
      radius=8.0,
      bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
      id~,
      body,
    )
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
  sheet_frame(c, "job", c.height * 0.8, fn() {
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
                let lines = words.split("\n").map(fn(l) { l.to_owned() }).to_array()
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
                      c.rich([@ui.span(lines[i], mono=true)], size=11.5, line=17.0, color=t.p.text, w=Fill(1.0))
                      |> ignore
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
          bg=@sf.alpha(t.p.red, if c.pressed(sid) { 0.2 } else { 0.12 }),
          id=sid,
          fn() {
            if busy {
              @sf.spinner(c, size=14.0) |> ignore
            } else {
              @sf.icon(c, "stop", size=16.0, color=t.p.red) |> ignore
            }
            c.text(tr("android-misc.jobs.stop"), size=15.0, weight=500, color=t.p.red, wrap=false)
            |> ignore
          },
        )
        |> ignore
      }
    })
    |> ignore
  })
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
    bg=if c.pressed(row) { @sf.alpha(t.p.text, 0.06) } else { 0L },
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
    },
  )
  |> ignore
}
