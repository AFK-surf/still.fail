// An agent's execution history, a page of its own (slice 8: ember apps/android chat/screens/History.kt HistoryScreen,
// Steps, Item, Message, Group, StepRow, Folding, Whole, PhaseLine, Details; ui/ToolStep.kt): what it received and what
// it sent, drawn alike (a line saying what and where, then its words in brief beside a bar); what it did in between,
// grouped, each group opening to its calls and thoughts, a call opening to what it asked for (a command, an edit as a
// diff, a file, a patch, a plan, its fields) and what came back. Its details: where it stands, its figures, how it
// runs, the station. What it shows is the core's `history {station, key}` view; a call in brief is read whole as it is
// opened (`history.detail`), the page before as the reader nears the top (`history.older`).
//
// Not here yet, against the Android app: code highlighting (code is the code face in the ink), a capped block's own
// scroll (it is cut at its height), the run settings page (its row is shown), opening at an entry, a Slack user's
// 这是我, a place's link.

///|
/// A page's compact bar (Parts.kt NavBar): back, with where it goes back to, in the accent; the title in the middle;
/// what is at its end.
fn page_bar(c : @ui.Ctx, key : String, back : String, title : String, trailing : () -> Unit) -> Unit {
  if @sf.nav_bar(c, key + "/back", back, title, trailing~, bg=@sf.theme().p.bg) {
    app.nav.pop() |> ignore
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
}

///|
/// The page (History.kt HistoryScreen): its bar (copying its link at its end), the agent at its head with what can be
/// done to it and the tabs, then its steps or its details.
fn history_page(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  let t = @sf.theme()
  let chat = (src.topic)("chat", chat_params(r))
  let title = text(chat.value, "title")
  let link = match chat_link(r.station, key) {
    "" => ""
    l => l + "?history=" + encode_component(key)
  }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    page_bar(c, "history", tr("common.back"), tr("android-chat.history.title"), fn() {
      if title != "" && link != "" && nav_button(c, "copy", 18.0, key="history/copy") {
        copy_chat_link(c, title, link)
      }
    })
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
      c.box(w=Fill(1.0), fn() {
        c.text(text(s, "agentText"), size=16.0, weight=700, color=t.p.text, wrap=false) |> ignore
      })
      |> ignore
      history_actions(c, src, r, a)
      dui.history_tab = seg(
        c,
        "history/tab",
        [tr("android-chat.history.tab.steps"), tr("android-chat.history.tab.details")],
        dui.history_tab,
      )
    })
    |> ignore
    history_summary(c, a)
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      if dui.history_tab == 0 {
        history_steps(c, src, r, key)
      } else {
        history_details(c, src, r, key, a)
      }
    })
    |> ignore
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
    if c.clicked(id) && !busy {
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
      bg=if c.pressed(id) { @sf.over(t.p.chip, @sf.alpha(t.p.text, 0.08)) } else { t.p.chip },
      align=ACenter,
      justify=JCenter,
      id~,
      fn() {
        if busy {
          @sf.spinner(c, size=12.0) |> ignore
        } else {
          @sf.icon(c, icon, size=14.0, color=t.p.text) |> ignore
        }
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
/// The head's short line (History.kt Summary): only what is worth a look now: a quota running out (its chip), the disk
/// filling up (amber), an account that cannot run (red).
fn history_summary(c : @ui.Ctx, a : Json?) -> Unit {
  let t = @sf.theme()
  let notes = items(a, "attention")
  if notes.length() == 0 {
    c.box(h=Px(8.0), fn() {  }) |> ignore
    return
  }
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=6.0, pb=8.0, gap=10.0, align=ACenter, fn() {
    for n in notes {
      let nv = Some(n)
      match field(nv, "quota") {
        Some(Object(_)) as q =>
          quota_chips(
            c,
            Some(
              Json::object({
                "state": "ok",
                "windows": Json::array([
                  Json::object({
                    "mark": Json::string(text(q, "mark")),
                    "left": Json::number(number(q, "left")),
                    "level": Json::string(text(q, "level")),
                  }),
                ]),
              }),
            ),
            small=true,
          )
        _ =>
          c.text(
            text(nv, "text"),
            size=12.0,
            color=if text(nv, "kind") == "disk" { 0xD9962BFFL } else { t.p.red },
            wrap=false,
          )
          |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A line of the steps' list (History.kt Line): the top's edge, an item, a step going on now, the turn's phase, the
/// room at the foot.
priv enum HLine {
  HEdge
  HItem(Json)
  HLive(Json)
  HPhase(Json)
  HFoot
}

///|
/// Its steps (History.kt Steps): its newest at the foot, followed while the reader stays there; the page before
/// brought in near the top (`history.older`, once a page); in brief until it is read.
fn history_steps(c : @ui.Ctx, src : Source, r : ChatRef, key : String) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("history", history_params(r, key))
  let h = match topic.value {
    Some(Object(_)) as v => v
    _ => {
      c.box(w=Fill(1.0), pt=20.0, align=ACenter, fn() {
        @sf.wait_line(c, tr("android-chat.history.loading"))
      })
      |> ignore
      return
    }
  }
  if flag(h, "empty") {
    history_edge(c, text(h, "edge"))
    return
  }
  let its = items(h, "items")
  let lines : Array[HLine] = [HEdge]
  for i in its {
    lines.push(HItem(i))
  }
  for l in items(h, "live") {
    lines.push(HLive(l))
  }
  match field(h, "phase") {
    Some(Object(_) as p) => lines.push(HPhase(p))
    _ => ()
  }
  lines.push(HFoot)
  let first = match its.get(0) {
    Some(i) => text(Some(i), "key")
    None => ""
  }
  let lkey = "history/" + r.station + "/" + key
  // the list's first item moved down by what came in above it: what is in view stays put
  let more = flag(h, "more")
  let older = more && dui.history_asked == first && first != ""
  match c.list_info(lkey) {
    Some(info) if more && info.first >= 0 && info.first <= 2 && dui.history_asked != first => {
      dui.history_asked = first
      (src.call)("history.older", { "station": Json::string(r.station), "key": Json::string(key) }, fn(
        res,
      ) {
        if res is Err(_) {
          dui.history_asked = ""
        }
      })
    }
    _ => ()
  }
  c.list(
    lkey,
    lines.length(),
    40.0,
    fn(i) {
      c.box(w=Fill(1.0), pl=18.0, pr=18.0, pt=if i <= 1 { 0.0 } else { 10.0 }, fn() {
        match lines[i] {
          HEdge =>
            if older {
              c.box(w=Fill(1.0), pady=10.0, align=ACenter, fn() { @sf.spinner(c, size=14.0) |> ignore })
              |> ignore
            } else {
              history_edge(c, text(h, "edge"))
            }
          HItem(item) => history_item(c, src, r, key, Some(item))
          HLive(l) =>
            c.text(text(Some(l), "text"), size=13.0, color=t.p.muted, wrap=false) |> ignore
          HPhase(p) => phase_line(c, src, Some(p))
          HFoot => c.box(h=Px(24.0), fn() {  }) |> ignore
        }
      })
      |> ignore
    },
    stick_end=true,
  )
  |> ignore
}

///|
/// What shows at its top (History.kt Edge): where the session begins, or why there is nothing yet.
fn history_edge(c : @ui.Ctx, words : String) -> Unit {
  c.box(w=Fill(1.0), pady=10.0, fn() {
    c.text(words, size=12.0, color=@sf.theme().p.subtle, center=true, w=Fill(1.0)) |> ignore
  })
  |> ignore
}

///|
/// A sentence of the catalog's around a part drawn on its own (`{name}`): its words before it and after it.
fn around(key : String) -> (String, String) {
  let s = tr(key)
  match s.find("{name}") {
    Some(i) => (s.view(end_offset=i).to_owned(), s.view(start_offset=i + 6).to_owned())
    None => (s, "")
  }
}

///|
/// An item (History.kt Item): what it received, what it posted, a state it marked, its own words, a group of steps.
fn history_item(c : @ui.Ctx, src : Source, r : ChatRef, key : String, item : Json?) -> Unit {
  let t = @sf.theme()
  let body = field(item, "body")
  let content = field(body, "content")
  let ik = text(item, "key")
  match text(body, "kind") {
    "received" =>
      c.box(w=Fill(1.0), gap=10.0, fn() {
        match opt_text(content, "note") {
          Some(note) =>
            history_message(c, ik + "/note", "received", fn() {
              let (b, a) = around("android-chat.history.received.note")
              history_label(c, [(b, false), ("still.fail", true), (a, false)])
            }, note, false)
          None => ()
        }
        for k, task in items(content, "tasks") {
          let tv = Some(task)
          let icon = if flag(tv, "agent") { "agent" } else { "command" }
          let color = if flag(tv, "failed") { t.p.red } else { t.p.muted }
          match opt_text(tv, "result") {
            Some(res) =>
              history_message(c, ik + "/task/" + k.to_string(), icon, fn() {
                c.text(text(tv, "text"), size=13.0, color~, wrap=false) |> ignore
              }, res, true)
            None =>
              c.box(dir=Row, gap=5.0, align=ACenter, fn() {
                @sf.icon(c, icon, size=14.0, color~) |> ignore
                c.text(text(tv, "text"), size=13.0, color~, wrap=false) |> ignore
              })
              |> ignore
          }
        }
        for k, m in items(content, "messages") {
          let mv = Some(m)
          let notice = text(mv, "notice")
          history_message(
            c,
            ik + "/message/" + k.to_string(),
            "received",
            fn() {
              let (b, a) = around(
                if notice == "job" {
                  "android-chat.history.received.jobMessage"
                } else {
                  "android-chat.history.received.message"
                },
              )
              let name = if notice == "stillfail" {
                "still.fail"
              } else {
                text(field(mv, "from"), "name")
              }
              let parts = [(b, false), (name, true), (a, false)]
              match field(mv, "place") {
                Some(Object(_)) as p => {
                  parts.push((" · ", false))
                  parts.push((text(p, "name"), true))
                }
                _ => ()
              }
              history_label(c, parts)
            },
            text(mv, "text"),
            false,
          )
        }
      })
      |> ignore
    "post" => {
      let place = field(content, "place")
      history_message(c, ik, "send", fn() {
        let (b, a) = around("android-chat.history.sent.to")
        let to = match place {
          Some(Object(_)) => text(place, "name")
          _ => "Slack"
        }
        history_label(c, [(b, false), (to, true), (a, false)])
        if flag(content, "block") {
          pill(c, "Block", if t.dark { 0x81AEFAFFL } else { 0x1559C4FFL })
        }
        if flag(content, "failed") {
          pill(c, tr("android-chat.history.send.failed"), t.p.red)
        }
      }, text(content, "text"), true)
    }
    "mark" =>
      c.box(dir=Row, gap=6.0, align=ACenter, fn() {
        let wait = field(content, "wait")
        match wait {
          Some(Object(_)) => {
            @sf.icon(c, "wait", size=14.0, color=t.p.muted) |> ignore
            if field(wait, "until") is None || field(wait, "until") == Some(Json::null()) {
              // still waiting: it counts on here
              let since = number(wait, "since")
              let now = (src.now)()
              let most = opt_number(wait, "seconds")
              // (at its most it stands still)
              if most is None || now - since < most.unwrap_or(0.0) * second_ms {
                wake_next_second(c, now - since)
              }
              let waited = dmax((now - since) / second_ms, 0.0)
              let waited = match most {
                Some(most) => dmin(waited, most)
                None => waited
              }
              let what = match text(wait, "what") {
                "" => ""
                w => w + " · "
              }
              let most = match opt_number(wait, "seconds") {
                Some(sec) => " / " + elapsed(sec * 1000.0)
                None => ""
              }
              c.text(
                what +
                fill("android-chat.history.waiting", [("time", elapsed(waited * 1000.0))]) +
                most,
                size=13.0,
                color=t.p.muted,
                wrap=false,
              )
              |> ignore
            } else {
              c.text(text(content, "text"), size=13.0, color=t.p.muted, wrap=false) |> ignore
            }
          }
          _ => c.text(text(content, "text"), size=13.0, color=t.p.muted) |> ignore
        }
      })
      |> ignore
    "text" =>
      c.box(w=Fill(1.0), pl=if flag(content, "subagent") { 12.0 } else { 0.0 }, fn() {
        let words = text(content, "text")
        if brief(c, ik, words) {
          app.nav.push(
            Words(
              fill("android-chat.history.wrote", [("name", agent_name(src, r, key))]),
              words,
            ),
          )
        }
      })
      |> ignore
    "group" => history_group(c, src, r, key, ik, content)
    _ => ()
  }
}

///|
/// The agent's name, as the chat has it.
fn agent_name(src : Source, r : ChatRef, key : String) -> String {
  text(field(agent_json((src.topic)("chat", chat_params(r)).value, key), "session"), "agentText")
}

///|
/// A label's words in a line, some of them strong (History.kt Strong: 13, semibold, the ink), the rest muted.
fn history_label(c : @ui.Ctx, parts : Array[(String, Bool)]) -> Unit {
  let t = @sf.theme()
  c.rich(
    parts
    .filter(fn(p) { p.0 != "" })
    .map(fn(p) {
      if p.1 {
        @ui.span(p.0, weight=600, color=t.p.text)
      } else {
        @ui.span(p.0)
      }
    }),
    size=13.0,
    color=t.p.muted,
    wrap=false,
  )
  |> ignore
}

///|
/// A small tinted word after a label (History.kt Pill).
fn pill(c : @ui.Ctx, words : String, color : Int64) -> Unit {
  c.box(pl=6.0, fn() {
    c.box(padx=6.0, pady=1.0, radius=6.0, bg=@sf.alpha(color, 0.12), fn() {
      c.text(words, size=11.0, color~, wrap=false) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Markdown as one run of plain words, for a brief (History.kt plain): no fences, headings, emphasis or line breaks.
fn plain_brief(s : String) -> String {
  let lines = s.split("\n").map(fn(l) {
    let mut x = l.to_owned()
    if x.has_prefix("```") {
      return " "
    }
    let trimmed = x.trim_start(chars=" ").to_string()
    for p in ["###### ", "##### ", "#### ", "### ", "## ", "# ", "> ", "- ", "* ", "+ "] {
      if trimmed.has_prefix(p) {
        x = trimmed.view(start_offset=p.length()).to_owned()
        break
      }
    }
    x
  })
  let joined = lines.to_array().join(" ").replace_all(old="**", new="").replace_all(old="__", new="").replace_all(
    old="`",
    new="",
  )
  let sb = StringBuilder()
  let mut space = false
  for ch in joined {
    if ch == ' ' || ch == '\t' || ch == '\r' {
      if !space {
        sb.write_char(' ')
      }
      space = true
    } else {
      sb.write_char(ch)
      space = false
    }
  }
  sb.to_string().trim(chars=" ").to_string()
}

///|
/// What an entry says, in brief (History.kt Brief): its words as plain text, two lines at most. True on the frame after
/// a tap (it opens in full).
fn brief(c : @ui.Ctx, key : String, words : String) -> Bool {
  let t = @sf.theme()
  let id = c.id("brief/" + key)
  c.box(
    w=Fill(1.0),
    max_h=42.0,
    radius=6.0,
    clip=true,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
    id~,
    fn() {
      c.text(plain_brief(words), size=14.0, color=t.p.text, line=21.0, w=Fill(1.0)) |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// A message in or out (History.kt Message): a line saying what and where, then its words in brief beside a bar. A tap
/// on the words opens the whole of it on a page of its own (as Markdown when `md`).
fn history_message(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : () -> Unit,
  words : String,
  md : Bool,
) -> Unit {
  let t = @sf.theme()
  ignore(md)
  c.box(w=Fill(1.0), gap=5.0, fn() {
    c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
      c.box(pr=5.0, fn() { @sf.icon(c, icon, size=14.0, color=t.p.muted) |> ignore }) |> ignore
      // what and where, cut at the row's end (the mark keeps its room)
      c.box(dir=Row, w=Fill(1.0), align=ACenter, clip=true, fn() { label() }) |> ignore
    })
    |> ignore
    c.box(dir=Row, w=Fill(1.0), fn() {
      c.box(w=Px(2.0), radius=1.0, bg=t.p.line, fn() {  }) |> ignore
      c.box(w=Fill(1.0), pl=10.0, fn() {
        if brief(c, key, words) {
          app.nav.push(Words("", words))
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A group of steps (History.kt Group): named by its latest call, how many failed and are running; opened, its calls
/// and thoughts.
fn history_group(c : @ui.Ctx, src : Source, r : ChatRef, key : String, ik : String, g : Json?) -> Unit {
  let t = @sf.theme()
  let gkey = "group/" + ik
  let id = c.id(gkey)
  if c.clicked(id) {
    if dui.opened.contains(gkey) {
      dui.opened.remove(gkey)
    } else {
      dui.opened[gkey] = true
    }
  }
  let open = dui.opened.contains(gkey)
  let failures = number(g, "failures").to_int()
  let pending = number(g, "pending").to_int()
  c.box(w=Fill(1.0), fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      pady=4.0,
      gap=6.0,
      radius=6.0,
      align=ACenter,
      bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
      id~,
      fn() {
        @sf.icon(c, if open { "chevron-down" } else { "chevron-right" }, size=13.0, color=t.p.subtle)
        |> ignore
        c.box(max_h=if open { 60.0 } else { 20.0 }, clip=true, fn() {
          c.text(
            text(g, "summary"),
            size=14.0,
            color=if failures > 0 { t.p.red } else { t.p.muted },
            wrap=open,
            line=20.0,
          )
          |> ignore
        })
        |> ignore
        if failures > 0 {
          pill(c, fill("android-chat.history.group.failed", [("n", failures.to_string())]), t.p.red)
        }
        if pending > 0 {
          pill(c, fill("android-chat.history.group.pending", [("n", pending.to_string())]), t.p.accent_text)
        }
      },
    )
    |> ignore
    if open {
      let rows = items(g, "rows")
      let calls = rows.iter().any(fn(x) { text(Some(x), "kind") == "step" })
      c.box(w=Fill(1.0), pl=19.0, pt=4.0, pb=4.0, gap=6.0, fn() {
        for k, row in rows {
          let rv = Some(row)
          let content = field(rv, "content")
          let rkey = ik + "/" + k.to_string()
          match text(rv, "kind") {
            "step" => {
              let said = opt_text(content, "said")
              let name = match said {
                Some(s) => s
                None => text(content, "name")
              }
              folding(
                c,
                "step/" + rkey,
                name,
                if said is None { text(content, "hint") } else { "" },
                text(content, "meta"),
                flag(content, "failed"),
                fn() {
                  whole(c, src, r, key, content, fn() {
                    tool_step_body(
                      c,
                      text(content, "name"),
                      text(content, "call"),
                      said is Some(_),
                      opt_text(content, "result"),
                      flag(content, "failed"),
                    )
                  })
                },
              )
            }
            "thought" => {
              let words = fn() {
                c.text(text(content, "text"), size=13.0, color=t.p.muted, line=20.0, w=Fill(1.0))
                |> ignore
              }
              if !calls {
                whole(c, src, r, key, content, words)
              } else {
                folding(
                  c,
                  "thought/" + rkey,
                  tr("android-chat.history.thinking"),
                  text(content, "first"),
                  "",
                  false,
                  fn() { whole(c, src, r, key, content, words) },
                )
              }
            }
            _ => ()
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A line that opens to what is behind it (History.kt Folding): its name (medium with a hint after it, in the code
/// face), what it says of itself at its end (red when it failed).
fn folding(
  c : @ui.Ctx,
  key : String,
  name : String,
  hint : String,
  meta : String,
  failed : Bool,
  body : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  if c.clicked(id) {
    if dui.opened.contains(key) {
      dui.opened.remove(key)
    } else {
      dui.opened[key] = true
    }
  }
  let open = dui.opened.contains(key)
  c.box(w=Fill(1.0), gap=4.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      pady=3.0,
      gap=8.0,
      align=ACenter,
      bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
      id~,
      fn() {
        let ink = if failed { t.p.red } else { t.p.text }
        if hint == "" {
          c.box(w=Fill(1.0), fn() { c.text(name, size=13.0, color=ink, wrap=false) |> ignore }) |> ignore
        } else {
          c.box(max_w=160.0, fn() {
            c.text(name, size=13.0, weight=500, color=ink, wrap=false) |> ignore
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            c.rich([@ui.span(hint, mono=true)], size=12.0, color=t.p.muted, wrap=false) |> ignore
          })
          |> ignore
        }
        if meta != "" {
          c.text(meta, size=11.0, color=if failed { t.p.red } else { t.p.subtle }, wrap=false) |> ignore
        }
      },
    )
    |> ignore
    if open {
      body()
    }
  })
  |> ignore
}

///|
/// What a call or thought holds, as it shows (History.kt Whole): in brief, read whole once opened (`history.detail`
/// over its entries), saying so till it comes; read and still in brief a second later, what is held is all there is.
fn whole(c : @ui.Ctx, src : Source, r : ChatRef, key : String, content : Json?, body : () -> Unit) -> Unit {
  if !flag(content, "brief") {
    body()
    return
  }
  let t = @sf.theme()
  let entries = items(content, "entries").map(fn(e) {
    match e {
      Number(n, ..) => n
      _ => 0.0
    }
  })
  let ekey = key + "/" + entries.map(fn(e) { e.to_int64().to_string() }).join(",")
  match dui.detail_at.get(ekey) {
    None => {
      dui.detail_at[ekey] = -1.0
      if entries.length() > 0 {
        let mut lo = entries[0]
        let mut hi = entries[0]
        for e in entries {
          lo = dmin(lo, e)
          hi = dmax(hi, e)
        }
        (src.call)(
          "history.detail",
          {
            "station": Json::string(r.station),
            "key": Json::string(key),
            "from": Json::number(lo),
            "to": Json::number(hi),
          },
          fn(res) {
            match res {
              Ok(_) => dui.detail_at[ekey] = (src.now)()
              Err(e) => dui.detail_at[ekey] = -2.0 - (if error_words(e) == "" { 0.0 } else { 0.0 })
            }
          },
        )
      }
    }
    _ => ()
  }
  let at = dui.detail_at.get(ekey).unwrap_or(-1.0)
  let settled = at >= 0.0 && (src.now)() - at >= detail_settle_ms
  if settled {
    body()
  } else {
    if at >= 0.0 {
      c.wake_in(at + detail_settle_ms - (src.now)())
    }
    c.text(
      if at <= -2.0 {
        fill("android-chat.history.stepUnread", [("error", "")])
      } else {
        tr("common.reading")
      },
      size=13.0,
      color=t.p.muted,
    )
    |> ignore
  }
}

///|
/// A second: what a clock shown in whole seconds goes on by.
let second_ms : Double = 1000.0

///|
/// How long a step's details read show 读取中 after the read answered, for the history to take what it read.
let detail_settle_ms : Double = 1000.0

///|
/// A clock showing `ms` gone by in whole seconds is drawn again when it shows the next second (not a second after
/// whatever frame came last).
fn wake_next_second(c : @ui.Ctx, ms : Double) -> Unit {
  let shown = (dmax(ms, 0.0) / second_ms).floor()
  c.wake_in((shown + 1.0) * second_ms - ms)
}

///|
/// The turn's state with the model (History.kt PhaseLine): a dot in the accent, its words, a clock running.
fn phase_line(c : @ui.Ctx, src : Source, p : Json?) -> Unit {
  let t = @sf.theme()
  let ran = (src.now)() - number(p, "since")
  wake_next_second(c, ran)
  let secs = dmax(ran / second_ms, 0.0).to_int()
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.accent, fn() {  }) |> ignore
    c.text(text(p, "text"), size=13.0, color=t.p.text, wrap=false) |> ignore
    c.text("\{secs}s", size=12.0, color=t.p.subtle, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// Its details (History.kt Details): where it stands and its figures as its card has them, how it runs in a line,
/// what it runs on and has done, what it used, the station.
fn history_details(c : @ui.Ctx, src : Source, r : ChatRef, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let usage = items((src.topic)("history", history_params(r, key)).value, "usage")
  let host = (src.topic)("host", { "station": Json::string(r.station) }).value
  let detail = fn(label : String, value : String) {
    c.box(dir=Row, w=Fill(1.0), gap=16.0, fn() {
      c.box(w=Px(76.0), fn() { c.text(label, size=14.0, color=t.p.muted, wrap=false) |> ignore })
      |> ignore
      c.box(w=Fill(1.0), fn() { c.text(value, size=14.0, color=t.p.text) |> ignore }) |> ignore
    })
    |> ignore
  }
  let rows : Array[() -> Unit] = [
    fn() {
      c.box(w=Fill(1.0), pt=2.0, fn() { agent_status(c, src, a) }) |> ignore
      agent_tiles(c, card, 14.0)
      agent_notes(c, card, 10.0)
      c.box(h=Px(6.0), fn() {  }) |> ignore
      run_row(c, a)
      c.box(w=Fill(1.0), pt=12.0, pb=10.0, gap=8.0, fn() {
        detail(tr("android-chat.history.detail.runtime"), text(s, "runtimeText"))
        match text(s, "processText") {
          "" => ()
          p => detail(tr("android-chat.history.detail.process"), p)
        }
        match text(card, "work") {
          "" => ()
          w => detail(tr("android-chat.agent.turns"), w)
        }
      })
      |> ignore
      if usage.length() > 0 {
        group_label(c, tr("android-chat.agent.usage"))
        c.box(w=Fill(1.0), pt=6.0, pb=10.0, gap=8.0, fn() {
          for u in usage {
            detail(text(Some(u), "label"), text(Some(u), "value"))
          }
        })
        |> ignore
      }
      group_label(c, "Station")
      c.box(w=Fill(1.0), pt=6.0, pb=10.0, gap=8.0, fn() {
        detail(tr("android-chat.history.detail.name"), station_name_of(src, r))
        match host {
          Some(Object(_)) => detail(tr("android-chat.history.detail.machine"), text(host, "identity"))
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
/// hairline round it. (Changing it is the run settings page's, not here yet.)
fn run_row(c : @ui.Ctx, a : Json?) -> Unit {
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
      fn() {
        @sf.maker_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), 15.0) |> ignore
        c.text(model, size=14.0, color=t.p.text, wrap=false) |> ignore
        c.box(w=Fill(1.0), fn() {
          c.text(" · " + effort + " · " + account, size=14.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
        quota_chips(c, field(field(a, "account"), "quota"))
        @sf.icon(c, "chevron-down", size=14.0, color=t.p.muted) |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// An entry opened in full (History.kt's reader): the line it was under, then all its words as Markdown.
fn words_page(c : @ui.Ctx, src : Source, head : String, words : String) -> Unit {
  ignore(src)
  let t = @sf.theme()
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    page_bar(c, "words", tr("common.back"), "", fn() {  })
    c.list("words/" + head + "/" + words.length().to_string(), 2, 200.0, fn(i) {
      c.box(w=Fill(1.0), pl=18.0, pr=18.0, pb=if i == 1 { 30.0 } else { 8.0 }, fn() {
        if i == 0 {
          if head != "" {
            c.text(head, size=13.0, color=t.p.muted) |> ignore
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
/// A call's arguments, when they are JSON (cut short by the station: closed where it stops).
fn parse_call(s : String) -> Json? {
  let t = s.trim(chars=" \n\t").to_string()
  if !t.has_prefix("{") && !t.has_prefix("[") {
    return None
  }
  // (what starts so is never null: null says it did not parse)
  let whole = @json.parse(t) catch { _ => Json::null() }
  if !(whole is Null) {
    return Some(whole)
  }
  // the station keeps a long call to its first 4000 characters, then `… (n more characters)`
  match t.rev_find("\n… (") {
    Some(i) => {
      let closed = @json.parse(close_json(t.view(end_offset=i).to_owned())) catch {
        _ => Json::null()
      }
      if closed is Null {
        None
      } else {
        Some(closed)
      }
    }
    None => None
  }
}

///|
/// JSON the station cut short, closed where it stops (ToolStep.kt close): the string it was in ends with an ellipsis,
/// what was open is closed.
fn close_json(json : String) -> String {
  let open : Array[Char] = []
  let mut quoted = false
  let mut escaped = false
  for ch in json {
    if escaped {
      escaped = false
    } else if quoted {
      if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
      }
    } else if ch == '"' {
      quoted = true
    } else if ch == '{' {
      open.push('}')
    } else if ch == '[' {
      open.push(']')
    } else if ch == '}' || ch == ']' {
      open.pop() |> ignore
    }
  }
  let mut out = json
  if quoted {
    out = (if escaped { out.view(end_offset=out.length() - 1).to_owned() } else { out }) + "…\""
  }
  out = out.trim_end(chars=" \n\t").to_string()
  if out.has_suffix(":") {
    out = out + "null"
  } else if out.has_suffix(",") {
    out = out.view(end_offset=out.length() - 1).to_owned()
  }
  let sb = StringBuilder()
  sb.write_string(out)
  let mut i = open.length() - 1
  while i >= 0 {
    sb.write_char(open[i])
    i = i - 1
  }
  sb.to_string()
}

///|
fn jstr(v : Json?) -> String? {
  match v {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// A scalar as JSON writes it.
fn scalar_text(v : Json) -> String {
  match v {
    String(s) => s
    Number(n, ..) =>
      if n == n.floor() && n < 1.0e15 && n > -1.0e15 {
        n.to_int64().to_string()
      } else {
        n.to_string()
      }
    True => "true"
    False => "false"
    Null => "null"
    _ => v.stringify()
  }
}

///|
/// JSON written out, two spaces a level (as the Android app's pretty printing).
fn pretty_json(v : Json, depth : Int) -> String {
  let pad = fn(d : Int) -> String {
    let sb = StringBuilder()
    for _ in 0..<d {
      sb.write_string("  ")
    }
    sb.to_string()
  }
  match v {
    Object(m) => {
      if m.size() == 0 {
        return "{}"
      }
      let parts = []
      for k, x in m {
        parts.push(pad(depth + 1) + Json::string(k).stringify() + ": " + pretty_json(x, depth + 1))
      }
      "{\n" + parts.join(",\n") + "\n" + pad(depth) + "}"
    }
    Array(a) => {
      if a.length() == 0 {
        return "[]"
      }
      "[\n" +
      a.map(fn(x) { pad(depth + 1) + pretty_json(x, depth + 1) }).join(",\n") +
      "\n" +
      pad(depth) +
      "]"
    }
    _ => v.stringify()
  }
}

///|
/// A command as it would be typed: `["bash", "-lc", "ls"]` is `ls`.
fn command_of(a : Map[String, Json]) -> String? {
  let c = match a.get("command") {
    Some(x) => Some(x)
    None => a.get("cmd")
  }
  match c {
    Some(String(s)) => Some(s)
    Some(Array(parts)) if parts.iter().all(fn(p) { p is String(_) }) => {
      let words = parts.map(fn(p) { scalar_text(p) })
      let first = match words.get(0) {
        Some(f) =>
          match f.rev_find("/") {
            Some(i) => f.view(start_offset=i + 1).to_owned()
            None => f
          }
        None => ""
      }
      if (first == "sh" || first == "bash" || first == "zsh") && words.get(1) == Some("-lc") {
        Some(words[2:].to_array().join(" "))
      } else {
        Some(words.join(" "))
      }
    }
    _ => None
  }
}

///|
/// The quiet tinted box code and output sit in (ToolStep.kt Boxed), kept to `max` high: what is taller scrolls within
/// it (mbui's Ctx::capped: a finger up or down on it moves it while it can go that way, else the page).
fn boxed(c : @ui.Ctx, ground : Int64, max : Double, padx : Double, pady : Double, body : () -> Unit) -> Unit {
  let n = boxed_n.val
  boxed_n.val += 1
  c.capped("boxed/\{n}", max, bg=ground, radius=10.0, padx~, pady~, body) |> ignore
}

///|
/// The boxes of a step drawn so far, numbered for where each is scrolled to (within the step's scope).
let boxed_n : Ref[Int] = { val: 0 }

///|
/// The language a file is in, by its extension (ToolStep.kt languageOf).
fn language_of(path : String?) -> String {
  let p = match path {
    Some(p) => p
    None => return ""
  }
  let mut i = p.length()
  while i > 0 {
    let u = p.at(i - 1).to_int()
    if u == 46 {
      break
    }
    if !((u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95) {
      return ""
    }
    i = i - 1
  }
  if i == 0 || i == p.length() {
    return ""
  }
  let ext = p.view(start_offset=i).to_string().to_lower()
  match ext {
    "mjs" | "cjs" => "js"
    "mts" => "ts"
    "yml" => "yaml"
    "zsh" | "bash" => "sh"
    "h" => "c"
    "hpp" => "cpp"
    e => e
  }
}

///|
fn code_ground() -> Int64 {
  @sf.theme().p.code_ground
}

///|
/// Code (a command, a file written or read) in the code face, highlighted by its language (Highlight.kt), wrapping,
/// kept to 360 high and scrolled within (ToolStep.kt Block).
fn code_lines(c : @ui.Ctx, words : String, language? : String = "") -> Unit {
  let t = @sf.theme()
  let n = boxed_n.val
  boxed_n.val += 1
  c.capped("code/\{n}", 360.0, bg=code_ground(), radius=12.0, padx=12.0, pady=8.0, fn() {
    c.rich(
      match @sf.highlight(words, language, t.dark) {
        Some(runs) => runs
        None => [@ui.span(words, mono=true)]
      },
      size=12.0,
      line=18.6,
      color=t.p.text,
      w=Fill(1.0),
    )
    |> ignore
  })
  |> ignore
}

///|
/// The small facts beside the main thing (ToolStep.kt Facts): `key value`, the scalars not shown otherwise.
fn facts(c : @ui.Ctx, a : Map[String, Json], skip : Array[String]) -> Unit {
  let rest = []
  for k, v in a {
    if skip.contains(k) {
      continue
    }
    match v {
      False | Null | Object(_) | Array(_) => ()
      True => rest.push((k, None))
      _ => rest.push((k, Some(scalar_text(v))))
    }
  }
  fact_row(c, rest)
}

///|
fn fact_row(c : @ui.Ctx, rest : Array[(String, String?)]) -> Unit {
  if rest.length() == 0 {
    return
  }
  let t = @sf.theme()
  let runs = []
  for i, f in rest {
    if i > 0 {
      runs.push(@ui.span("   "))
    }
    runs.push(@ui.span(f.0))
    match f.1 {
      Some(v) => {
        runs.push(@ui.span(" "))
        runs.push(@ui.span(v, weight=500, color=t.p.muted, mono=true))
      }
      None => ()
    }
  }
  c.box(w=Fill(1.0), padx=2.0, fn() {
    c.rich(runs, size=11.0, color=t.p.subtle, w=Fill(1.0)) |> ignore
  })
  |> ignore
}

///|
/// A file's path, and what is said of it beside (ToolStep.kt PathLine).
fn path_line(c : @ui.Ctx, path : String, extra : String) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), padx=2.0, gap=8.0, align=AEnd, fn() {
    c.box(fn() {
      c.rich([@ui.span(path, mono=true)], size=12.0, line=18.0, color=t.p.text) |> ignore
    })
    |> ignore
    if extra != "" {
      c.text(extra, size=11.0, color=t.p.subtle, wrap=false, line=18.0) |> ignore
    }
  })
  |> ignore
}

///|
/// The red and green of a diff (ToolStep.css.ts).
fn diff_colors() -> (Int64, Int64, Int64, Int64) {
  if @sf.theme().dark {
    (0xF68482FFL, 0x442322FFL, 0x68C894FFL, 0x1B3426FFL)
  } else {
    (0xA12F35FFL, 0xFFF0EFFFL, 0x006A3FFFL, 0xE7F6EDFFL)
  }
}

///|
/// Lines taken out and put in, with the lines both share at the ends as context (ToolStep.kt Diff).
fn diff(c : @ui.Ctx, from : String, to : String) -> Unit {
  let a = from.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let b = to.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let mut head = 0
  while head < a.length() && head < b.length() && a[head] == b[head] {
    head = head + 1
  }
  let mut tail = 0
  while tail < a.length() - head &&
        tail < b.length() - head &&
        a[a.length() - 1 - tail] == b[b.length() - 1 - tail] {
    tail = tail + 1
  }
  let rows : Array[(Char, String)] = []
  for i in 0..<head {
    rows.push((' ', a[i]))
  }
  for i in head..<(a.length() - tail) {
    rows.push(('-', a[i]))
  }
  for i in head..<(b.length() - tail) {
    rows.push(('+', b[i]))
  }
  for i in (a.length() - tail)..<a.length() {
    rows.push((' ', a[i]))
  }
  diff_lines(c, rows)
}

///|
/// Marked lines (ToolStep.kt Lines): taken out on red, put in on green, a patch's headers in blue.
fn diff_lines(c : @ui.Ctx, rows : Array[(Char, String)]) -> Unit {
  let t = @sf.theme()
  let (red, red_bg, green, green_bg) = diff_colors()
  boxed(c, code_ground(), 360.0, 0.0, 6.0, fn() {
    for row in rows {
      let (mark, words) = row
      let ground = match mark {
        '-' => red_bg
        '+' => green_bg
        _ => 0L
      }
      let ink = match mark {
        '-' | '+' => t.p.text
        '@' => if t.dark { 0x81AEFAFFL } else { 0x1559C4FFL }
        _ => t.p.muted
      }
      c.box(w=Fill(1.0), pt=if mark == '@' { 4.0 } else { 0.0 }, bg=ground, fn() {
        if mark == '-' || mark == '+' {
          c.layer(fn() {
            c.box(pl=9.0, fn() {
              c.rich(
                [@ui.span(mark.to_string(), mono=true)],
                size=12.0,
                line=18.6,
                color=if mark == '-' { red } else { green },
              )
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        c.box(w=Fill(1.0), pl=22.0, pr=12.0, fn() {
          c.rich(
            [@ui.span(if words == "" { " " } else { words }, mono=true, weight=if mark == '@' { 500 } else { 0 })],
            size=12.0,
            line=18.6,
            color=ink,
            w=Fill(1.0),
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
}

///|
/// A patch as apply_patch takes it (ToolStep.kt Patch): file headers, lines put in and taken out.
fn patch(c : @ui.Ctx, words : String) -> Unit {
  let rows : Array[(Char, String)] = []
  let body = if words.has_suffix("\n") { words.view(end_offset=words.length() - 1).to_owned() } else { words }
  for l in body.split("\n") {
    let line = l.to_owned()
    if line.has_prefix("*** Add File:") ||
      line.has_prefix("*** Update File:") ||
      line.has_prefix("*** Delete File:") ||
      line.has_prefix("*** Move to:") ||
      line.has_prefix("@@") {
      rows.push(('@', line))
    } else if line.has_prefix("*** Begin Patch") || line.has_prefix("*** End Patch") {
      ()
    } else if line.has_prefix("+") {
      rows.push(('+', line.view(start_offset=1).to_owned()))
    } else if line.has_prefix("-") {
      rows.push(('-', line.view(start_offset=1).to_owned()))
    } else if line.has_prefix(" ") {
      rows.push((' ', line.view(start_offset=1).to_owned()))
    } else {
      rows.push((' ', line))
    }
  }
  diff_lines(c, rows)
}

///|
/// A list of things to do, as TodoWrite and update_plan give it (ToolStep.kt Plan).
fn plan(c : @ui.Ctx, list : Array[Json]) -> Unit {
  let t = @sf.theme()
  let (_, _, green, _) = diff_colors()
  c.box(w=Fill(1.0), padx=2.0, gap=2.0, fn() {
    for item in list {
      let iv = Some(item)
      let words = match jstr(field(iv, "content")) {
        Some(s) => s
        None => text(iv, "step")
      }
      let status = text(iv, "status")
      c.box(dir=Row, w=Fill(1.0), fn() {
        c.box(w=Px(16.0), fn() {
          c.text(
            match status {
              "completed" => "✓"
              "in_progress" => "›"
              _ => "·"
            },
            size=12.0,
            line=18.0,
            color=match status {
              "completed" => green
              "in_progress" => t.p.accent
              _ => t.p.subtle
            },
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          c.rich(
            [@ui.span(words, strike=status == "completed", weight=if status == "in_progress" { 600 } else { 0 })],
            size=12.0,
            line=18.0,
            color=if status == "completed" { t.p.muted } else { t.p.text },
            w=Fill(1.0),
          )
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
/// Fields one to a row (ToolStep.kt Fields): short ones inline, long text as a block, nested data as JSON.
fn fields(c : @ui.Ctx, a : Map[String, Json], skip : Array[String]) -> Unit {
  let t = @sf.theme()
  let rows = []
  for k, v in a {
    if skip.contains(k) || v is Null || v == Json::string("") {
      continue
    }
    rows.push((k, v))
  }
  if rows.length() == 0 {
    none_line(c, tr("android-misc.tool.noArgs"))
    return
  }
  c.box(w=Fill(1.0), padx=2.0, gap=4.0, fn() {
    for row in rows {
      let (k, v) = row
      c.box(dir=Row, w=Fill(1.0), gap=12.0, fn() {
        c.box(min_w=64.0, max_w=120.0, fn() {
          c.text(k, size=11.0, color=t.p.subtle, line=18.0) |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          match v {
            String(s) if s.contains("\n") || s.length() > 120 =>
              boxed(c, code_ground(), 240.0, 12.0, 8.0, fn() {
                c.text(s, size=12.0, line=19.2, color=t.p.text, w=Fill(1.0)) |> ignore
              })
            Object(_) | Array(_) => json_block(c, v)
            _ =>
              c.rich([@ui.span(scalar_text(v), mono=true)], size=12.0, line=18.0, color=t.p.text, w=Fill(1.0))
              |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn json_block(c : @ui.Ctx, v : Json) -> Unit {
  let t = @sf.theme()
  boxed(c, code_ground(), 240.0, 12.0, 8.0, fn() {
    c.rich([@ui.span(pretty_json(v, 0), mono=true)], size=12.0, line=18.6, color=t.p.text, w=Fill(1.0))
    |> ignore
  })
}

///|
fn none_line(c : @ui.Ctx, words : String) -> Unit {
  c.box(padx=2.0, fn() {
    c.text(words, size=11.0, color=@sf.theme().p.subtle) |> ignore
  })
  |> ignore
}

///|
/// A step opened (ToolStep.kt ToolStepBody): what the call asked for, then what came back.
fn tool_step_body(
  c : @ui.Ctx,
  name : String,
  call : String,
  said : Bool,
  result : String?,
  failed : Bool,
) -> Unit {
  c.box(w=Fill(1.0), pl=6.0, pr=6.0, pt=4.0, pb=10.0, gap=8.0, fn() {
    // its boxes numbered within it (where each is scrolled to)
    c.scope(c.id("step/" + name + "/" + call), fn() {
      boxed_n.val = 0
      c.box(w=Fill(1.0), gap=6.0, fn() { tool_call(c, name, call, said) }) |> ignore
      match result {
        Some(r) => tool_result(c, name, call, r, failed)
        None => ()
      }
    })
  })
  |> ignore
}

///|
/// The language a file is in, by its extension (not drawn yet: there is no highlighting).
fn file_of(a : Map[String, Json]) -> String? {
  match jstr(a.get("file_path")) {
    Some(f) => Some(f)
    None =>
      match jstr(a.get("notebook_path")) {
        Some(f) => Some(f)
        None => jstr(a.get("path"))
      }
  }
}

///|
/// What a call asked for (ToolStep.kt ToolCall). `said`: its description already shows as the step's name.
fn tool_call(c : @ui.Ctx, name : String, call : String, said : Bool) -> Unit {
  let a = match parse_call(call) {
    Some(Object(m)) => m
    _ => {
      let trimmed = call.trim(chars=" \n\t").to_string()
      if trimmed.has_prefix("*** Begin Patch") {
        patch(c, trimmed)
      } else if trimmed != "" {
        code_lines(c, call, language=if name == "exec" { "js" } else { "" })
      }
      return
    }
  }
  let skip = if said { ["description"] } else { [] }
  let file = file_of(a)
  let get = fn(k : String) { jstr(a.get(k)) }
  let list = match a.get("todos") {
    Some(Array(l)) => Some(l)
    _ =>
      match a.get("plan") {
        Some(Array(l)) => Some(l)
        _ => None
      }
  }
  let queries = match a.get("queries") {
    Some(Array(q)) if q.length() > 0 && q.iter().all(fn(x) { x is String(_) }) => Some(q.map(scalar_text))
    _ => None
  }
  let long_fields = a.values().filter(fn(v) {
    match v {
      String(s) => s.length() > 120
      _ => false
    }
  }).count()
  match command_of(a) {
    Some(cmd) => {
      code_lines(c, cmd, language="sh")
      facts(c, a, skip + ["command", "cmd"])
      return
    }
    None => ()
  }
  match (file, get("old_string"), get("new_string")) {
    (Some(f), Some(old), Some(new)) => {
      path_line(c, f, if a.get("replace_all") == Some(Json::boolean(true)) {
        tr("android-misc.tool.replaceAll")
      } else {
        ""
      })
      diff(c, old, new)
      return
    }
    _ => ()
  }
  match (file, a.get("edits")) {
    (Some(f), Some(Array(edits))) => {
      path_line(c, f, "")
      for e in edits {
        diff(c, text(Some(e), "old_string"), text(Some(e), "new_string"))
      }
      return
    }
    _ => ()
  }
  match (file, get("content")) {
    (Some(f), Some(body)) => {
      path_line(c, f, "")
      code_lines(c, body, language=language_of(Some(f)))
      return
    }
    _ => ()
  }
  match list {
    Some(l) => {
      match get("explanation") {
        Some(x) => boxed(c, code_ground(), 100000.0, 12.0, 8.0, fn() { @sf.markdown(c, x) |> ignore })
        None => ()
      }
      plan(c, l)
      return
    }
    None => ()
  }
  match get("prompt") {
    Some(p) if name == "Agent" || name == "Task" || name == "subagent" || p.length() > 200 => {
      facts(c, a, skip + ["prompt"])
      boxed(c, code_ground(), 100000.0, 12.0, 8.0, fn() { @sf.markdown(c, p) |> ignore })
      return
    }
    _ => ()
  }
  match get("text") {
    Some(x) if x != "" && long_fields <= 1 => {
      facts(c, a, skip + ["text"])
      boxed(c, code_ground(), 100000.0, 12.0, 8.0, fn() { @sf.markdown(c, x) |> ignore })
      return
    }
    _ => ()
  }
  match file {
    Some(f) if a
      .keys()
      .all(fn(k) {
        ["file_path", "path", "notebook_path", "offset", "limit"].contains(k) || skip.contains(k)
      }) => {
      let from = match a.get("offset") {
        Some(Number(n, ..)) => Some(n.to_int64())
        _ => None
      }
      let n = match a.get("limit") {
        Some(Number(x, ..)) => Some(x.to_int64())
        _ => None
      }
      let range = match (from, n) {
        (Some(f), Some(k)) =>
          fill("android-misc.tool.linesFrom", [("from", f.to_string()), ("n", k.to_string())])
        (Some(f), None) => fill("android-misc.tool.from", [("from", f.to_string())])
        (None, Some(k)) => fill("android-misc.tool.lines", [("n", k.to_string())])
        _ => ""
      }
      path_line(c, f, range)
      return
    }
    _ => ()
  }
  match queries {
    Some(q) => {
      let t = @sf.theme()
      for x in q {
        c.box(padx=2.0, fn() {
          c.rich([@ui.span(x, mono=true)], size=12.0, line=18.0, color=t.p.text, w=Fill(1.0)) |> ignore
        })
        |> ignore
      }
      facts(c, a, skip + ["queries"])
      return
    }
    None => ()
  }
  for k in ["pattern", "query", "url"] {
    match get(k) {
      Some(x) => {
        let t = @sf.theme()
        c.box(padx=2.0, fn() {
          c.rich([@ui.span(x, mono=true)], size=12.0, line=18.0, color=t.p.text, w=Fill(1.0)) |> ignore
        })
        |> ignore
        fields(c, a, skip + [k])
        return
      }
      None => ()
    }
  }
  fields(c, a, skip)
}

///|
/// Codex's command output (ToolStep.kt commandOutput): how it ended in a header, then the output.
fn command_output(words : String) -> (Array[String], String)? {
  let lines = words.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let mut i = 0
  if i < lines.length() && lines[i].has_prefix("Chunk ID: ") {
    i = i + 1
  }
  let mut wall = ""
  if i < lines.length() && lines[i].has_prefix("Wall time: ") {
    wall = lines[i].view(start_offset=11).to_owned()
    i = i + 1
  }
  let mut code = ""
  if i < lines.length() && lines[i].has_prefix("Process exited with code ") {
    code = lines[i].view(start_offset=25).to_owned()
    i = i + 1
  }
  if i < lines.length() && lines[i].has_prefix("Original token count: ") {
    i = i + 1
  }
  if i >= lines.length() || !lines[i].has_prefix("Output:") || (wall == "" && code == "") {
    return None
  }
  let first = lines[i].view(start_offset=7).to_owned()
  let rest = lines[i + 1:].to_array()
  let out = if first == "" { rest.join("\n") } else { ([first] + rest).join("\n") }
  let said = []
  if code != "" {
    said.push(fill("android-misc.tool.exitCode", [("code", code)]))
  }
  if wall != "" {
    said.push(fill("android-misc.tool.took", [("time", wall)]))
  }
  Some((said, out))
}

///|
/// DeepSeek Harness's bash: its output, then how it ended where that was not well (`[exit code: 1]`).
fn exit_marker(words : String) -> (Array[String], String)? {
  let trimmed = words.trim_end(chars=" \n\t").to_string()
  guard trimmed.has_suffix("]") else { return None }
  match trimmed.rev_find("[exit code: ") {
    Some(i) => {
      let code = trimmed.view(start_offset=i + 12, end_offset=trimmed.length() - 1).to_owned()
      let before = trimmed.view(end_offset=i).to_owned()
      let before = if before.has_suffix("\n") {
        before.view(end_offset=before.length() - 1).to_owned()
      } else {
        before
      }
      Some(([fill("android-misc.tool.exitCode", [("code", code)])], before))
    }
    None => None
  }
}

///|
/// Claude Code's Read (ToolStep.kt readLines): `cat -n` lines (`   12→text` or `   12\ttext`) without their numbers;
/// what follows them left out.
fn read_lines(words : String, colon : Bool) -> String? {
  let out = []
  for l in words.split("\n") {
    let line = l.to_owned()
    let mut i = 0
    if !colon {
      while i < line.length() && line.get_char(i) == Some(' ') {
        i = i + 1
      }
    }
    let start = i
    while i < line.length() && digit_at(line, i) {
      i = i + 1
    }
    if i == start {
      break
    }
    let sep = line.get_char(i)
    if colon {
      if sep != Some(':') {
        break
      }
      i = i + 1
      if line.get_char(i) == Some(' ') {
        i = i + 1
      }
    } else if sep == Some('→') || sep == Some('\t') {
      i = i + 1
    } else {
      break
    }
    out.push(line.view(start_offset=i).to_owned())
  }
  if out.length() == 0 {
    None
  } else {
    Some(out.join("\n"))
  }
}

///|
fn digit_at(s : String, i : Int) -> Bool {
  match s.get_char(i) {
    Some(ch) => ch >= '0' && ch <= '9'
    None => false
  }
}

///|
/// DeepSeek Harness's read and write (ToolStep.kt unwrap): the file's path and kind, then what is in it, in tags.
fn unwrap_tags(words : String) -> String? {
  guard words.has_prefix("<path>") else { return None }
  match words.find("<content>") {
    Some(i) => {
      let mut body = words.view(start_offset=i + 9).to_owned()
      if body.has_prefix("\n") {
        body = body.view(start_offset=1).to_owned()
      }
      let trimmed = body.trim_end(chars=" \n\t").to_string()
      if trimmed.has_suffix("</content>") {
        body = trimmed.view(end_offset=trimmed.length() - 10).to_owned()
      }
      if body.has_suffix("\n") {
        body = body.view(end_offset=body.length() - 1).to_owned()
      }
      Some(body)
    }
    None => None
  }
}

///|
/// Output as it came (ToolStep.kt Output): muted, on red when it failed.
fn output_box(c : @ui.Ctx, words : String, failed : Bool) -> Unit {
  let t = @sf.theme()
  let (_, red_bg, _, _) = diff_colors()
  boxed(c, if failed { red_bg } else { code_ground() }, 360.0, 12.0, 8.0, fn() {
    c.rich(
      [@ui.span(words, mono=true)],
      size=12.0,
      line=18.6,
      color=if failed { t.p.text } else { t.p.muted },
      w=Fill(1.0),
    )
    |> ignore
  })
}

///|
/// The file a call names (its path), if it is one.
fn call_file(call : String) -> String? {
  match parse_call(call) {
    Some(Object(m)) => file_of(m)
    _ => None
  }
}

///|
/// What a call gave back (ToolStep.kt ToolResult).
fn tool_result(c : @ui.Ctx, name : String, call : String, result : String, failed : Bool) -> Unit {
  if result.trim(chars=" \n\t").to_string() == "" {
    none_line(c, tr("android-misc.tool.noOutput"))
    return
  }
  c.box(w=Fill(1.0), gap=4.0, fn() {
    let codex = match command_output(result) {
      Some(x) => Some(x)
      None => if name == "bash" { exit_marker(result) } else { None }
    }
    let read = if !failed && (name == "Read" || name == "NotebookRead") { read_lines(result, false) } else { None }
    let inner = if !failed && codex is None && read is None && (name == "read" || name == "write") {
      unwrap_tags(result)
    } else {
      None
    }
    let inner_lines = match inner {
      Some(x) if name == "read" => read_lines(x, true)
      _ => None
    }
    match (codex, read, inner_lines, inner) {
      (Some((said, out)), _, _, _) => {
        if said.length() > 0 {
          fact_row(c, said.map(fn(s) { (s, None) }))
        }
        if out.trim(chars=" \n\t").to_string() != "" {
          output_box(c, out, failed)
        } else {
          none_line(c, tr("android-misc.tool.noOutput"))
        }
      }
      (_, Some(r), _, _) => code_lines(c, r, language=language_of(call_file(call)))
      (_, _, Some(r), _) => code_lines(c, r, language=language_of(call_file(call)))
      (_, _, _, Some(x)) => output_box(c, x, false)
      _ =>
        match (if failed { None } else { parse_call(result) }) {
          Some(Object(m)) => fields(c, m, [])
          Some(v) => json_block(c, v)
          None => output_box(c, result, failed)
        }
    }
  })
  |> ignore
  ignore(call)
}
