// The decisions page 「奏」 (slice 8: ember apps/android chat/screens/Decisions.kt DecisionsScreen, Idle, Deck, Face,
// DecisionComposer; Home.kt DecisionsCapsule): the workspace's cards waiting for the viewer one at a time, as the core's
// `decisions {scope}` view has them. The chat's title small at the top (to its chat), the messages before the post and
// the post as the chat draws them, under them an options card's options (a tap answers: the card flies up and the next
// comes in), and the reply field at the foot (a text card's, or a word instead of an option: `decision.reply`). The
// whole decision is swiped: left 待定 (set aside on this device: last, still waiting), right 不再提醒 (dismissed for the
// viewer); let go past a third of the width or flung, it flies off; short of that it springs back. None left: how the
// day went, where the next may come from, what was answered today.
//
// It is reached from the bottom bar's 奏 (slice 7's): `open_decisions()`, or `decisions_capsule` drawn where the bar
// puts it. Not here yet, against the Android app: the card's tilt and scale as it moves (boxes have no transforms yet),
// attachments and quotes in the reply (words only), the reply's draft kept by the core, a vault item's approval, a
// login card's buttons on this page (its card as in the chat).

///|
/// The 奏 page over what is open.
pub fn open_decisions() -> Unit {
  app.nav.push(Decisions)
}

///|
/// 奏 N (Home.kt DecisionsCapsule): the decisions page's way in, there at 0 too (奏 alone, a 56 disc), else 奏 and how
/// many, drawn (1 to 9, + past that), 56 high on `ground` (the glass the bar gives it).
fn decisions_capsule(c : @ui.Ctx, src : Source, w : Workspace, ground : Int64) -> Unit {
  let t = @sf.theme()
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let n = count(field(field(marks.value, "workspaces"), w.id), "decisions")
  let id = c.id("decisions-capsule")
  if c.clicked(id) {
    open_decisions()
  }
  c.box(
    dir=Row,
    h=Px(56.0),
    min_w=56.0,
    pl=if n == 0 { 0.0 } else { 10.0 },
    pr=if n == 0 { 0.0 } else { 20.0 },
    gap=6.0,
    radius=28.0,
    align=ACenter,
    justify=JCenter,
    bg=ground,
    id~,
    fn() {
      @sf.icon(c, "zou", size=40.0, color=t.p.text) |> ignore
      if n > 0 {
        @sf.icon(c, if n <= 9 { "num-\{n}" } else { "num-more" }, size=24.0, color=t.p.text) |> ignore
      }
    },
  )
  |> ignore
}

///|
/// A decision's own key: its station, chat and post.
fn decision_key(item : Json) -> String {
  let v = Some(item)
  seq_key(text(v, "station"), number(v, "thread"), number(v, "seq"))
}

///|
/// The decisions as this device shows them (DecisionsLocal.shown): those answered or let go here gone, those set
/// aside here last; what the core's list no longer has forgotten.
fn shown_decisions(all : Array[Json]) -> Array[Json] {
  let keys = all.map(decision_key)
  dui.dgone.retain(fn(k) { keys.contains(k) })
  dui.dlater.retain(fn(k) { keys.contains(k) })
  let rest = all.filter(fn(i) { !dui.dgone.contains(decision_key(i)) })
  let first = rest.filter(fn(i) { !dui.dlater.contains(decision_key(i)) })
  for k in dui.dlater {
    match rest.iter().find_first(fn(i) { decision_key(i) == k }) {
      Some(i) => first.push(i)
      None => ()
    }
  }
  first
}

///|
/// The page (DecisionsScreen): pushed, its bar's back to the chats; the deck, or none left, or what is being read.
fn decisions_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("decisions", { "workspace": Json::string(w.id) })
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => None
  }
  let shown = shown_decisions(items(view, "items"))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    nav_bar(c, tr("android-misc.bar.place.decisions"))
    c.box(w=Fill(1.0), h=Fill(1.0), pt=4.0, fn() {
      if shown.length() == 0 {
        // none yet while stations are still read is not none: their cards to come
        if view is Some(_) && !flag(field(view, "wait"), "reading") {
          decisions_idle(c, view)
        } else {
          waiting_cards(c, topic.error)
        }
        return
      }
      deck(c, src, shown)
    })
    |> ignore
  })
  |> ignore
}

///|
/// Cards to come, breathing (Waiting.kt Waiting, WaitShape.Cards): what went wrong over them in red.
fn waiting_cards(c : @ui.Ctx, error : Json?) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=16.0, pt=8.0, gap=12.0, fn() {
    match error {
      Some(e) =>
        c.box(w=Fill(1.0), align=ACenter, fn() { @sf.wait_pill(c, error_words(e), error=true) })
        |> ignore
      None => ()
    }
    let breath = if error is None { @sf.breath(c) } else { 0.6 }
    for _ in 0..<2 {
      c.box(w=Fill(1.0), h=Px(132.0), radius=20.0, bg=t.p.neutral_bg, opacity=breath, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// None left (Decisions.kt Idle): the page stays for the next to come and says how the day went, where the next may come
/// from (the viewer's chats with an agent at work or waiting) and what was answered today. Each opens its chat.
fn decisions_idle(c : @ui.Ctx, view : Json?) -> Unit {
  let t = @sf.theme()
  let today = field(view, "today")
  let working = items(view, "working")
  let answered = items(view, "answered")
  let rows : Array[() -> Unit] = [
    fn() {
      c.box(w=Fill(1.0), pt=16.0, align=ACenter, fn() {
        for f in items(field(view, "wait"), "failing") {
          c.box(pb=8.0, fn() { @sf.wait_pill(c, text(Some(f), "text"), error=true) }) |> ignore
        }
        if @sf.has_drawable("buddy_idle") {
          @sf.drawable(c, if t.dark { "buddy_idle_dark" } else { "buddy_idle" }, 72.0) |> ignore
        }
        c.box(pt=8.0, fn() {
          c.text(tr("android-misc.decisions.idle.title"), size=17.0, weight=600, color=t.p.text, wrap=false)
          |> ignore
        })
        |> ignore
        c.box(pt=4.0, fn() {
          c.text(tr("android-misc.decisions.idle.note"), size=14.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
        if today is Some(Object(_)) {
          c.box(dir=Row, pt=14.0, gap=28.0, fn() {
            let figure = fn(f : String, words : String) {
              c.box(align=ACenter, fn() {
                c.text(f, size=20.0, weight=600, color=t.p.text, wrap=false) |> ignore
                c.text(words, size=12.0, color=t.p.subtle, wrap=false) |> ignore
              })
              |> ignore
            }
            figure(count(today, "count").to_string(), tr("android-misc.decisions.idle.answered"))
            match text(today, "waited") {
              "" => ()
              waited => figure(waited, tr("android-misc.decisions.idle.waited"))
            }
            figure(count(today, "working").to_string(), tr("android-misc.decisions.idle.working"))
          })
          |> ignore
        }
      })
      |> ignore
    },
  ]
  let title = fn(words : String) {
    c.box(pl=10.0, pt=28.0, pb=4.0, fn() {
      c.text(words, size=12.0, weight=500, color=t.p.subtle, wrap=false) |> ignore
    })
    |> ignore
  }
  if working.length() > 0 {
    rows.push(fn() {
      title(tr("android-misc.decisions.idle.workingTitle"))
      for k, wk in working {
        let wv = Some(wk)
        if idle_row(
            c,
            "idle/working/" + k.to_string(),
            text(wv, "title"),
            text(wv, "line"),
            text(field(field(wv, "time"), "lastActiveAt"), "ago"),
            true,
          ) {
          open_decision_chat(wv)
        }
      }
    })
  }
  if answered.length() > 0 {
    rows.push(fn() {
      title(tr("android-misc.decisions.idle.answeredTitle"))
      for k, a in answered {
        let av = Some(a)
        if idle_row(
            c,
            "idle/answered/" + k.to_string(),
            text(av, "text"),
            text(av, "title") + " · " + text(av, "answer"),
            text(av, "clock"),
            false,
          ) {
          open_decision_chat(av)
        }
      }
    })
  }
  rows.push(fn() { c.box(h=Px(24.0), fn() {  }) |> ignore })
  c.list("decisions-idle", rows.length(), 200.0, fn(i) {
    c.box(w=Fill(1.0), pl=16.0, pr=16.0, fn() { (rows[i])() }) |> ignore
  })
  |> ignore
}

///|
/// A decision's chat opened over the page (by its session).
fn open_decision_chat(v : Json?) -> Unit {
  app.nav.push(
    Chat({
      station: text(v, "station"),
      session: text(v, "session"),
      title: text(v, "title"),
      station_name: text(v, "stationName"),
    }),
  )
}

///|
/// A chat at work (the turning yellow ring) or a card answered (a quiet dot): its words over where it is, when at its
/// end (Decisions.kt IdleRow).
fn idle_row(c : @ui.Ctx, key : String, main : String, meta : String, at : String, busy : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=10.0,
    pady=8.0,
    gap=10.0,
    radius=10.0,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
    id~,
    fn() {
      c.box(w=Px(12.0), h=Px(12.0), pt=4.0, align=ACenter, justify=JCenter, fn() {
        if busy {
          agent_state_mark(c, "run")
        } else {
          c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=t.p.subtle, fn() {  }) |> ignore
        }
      })
      |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(main, size=15.0, weight=500, color=t.p.text, wrap=false) |> ignore
        c.text(meta, size=13.0, color=t.p.subtle, wrap=false) |> ignore
      })
      |> ignore
      c.text(at, size=12.0, color=t.p.subtle, wrap=false) |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// The front decision goes (`dir` its side, 2 up after answering), `after` is done once it has, and the next comes in.
fn go_decision(c : @ui.Ctx, dir : Int, after : () -> Unit) -> Unit {
  if dui.going != 0 && dui.going != 3 {
    return
  }
  dui.going = dir
  dui.going_at = c.now()
  dui.going_from = dui.drag
  dui.after_go = after
  c.request_frame()
}

///|
/// The deck (Decisions.kt Deck): the decision in front, swiped where it rests (across first: the swipe; up or down
/// first: the messages'); under it, as it moves, what letting it go that way does; the hint and where this one is.
fn deck(c : @ui.Ctx, src : Source, shown : Array[Json]) -> Unit {
  let t = @sf.theme()
  let item = shown[0]
  let key = decision_key(item)
  let n = shown.length()
  if dui.front != key {
    // a new one in front: it comes in (unless it is the first the page shows)
    if dui.front != "" {
      dui.arrive_at = c.now()
    }
    dui.front = key
    dui.drag = 0.0
    dui.going = 0
    dui.held = false
    dui.swiping = false
  }
  let frame = c.id("deck/frame")
  let (fx, fy, fw, fh) = match c.rect_of(frame) {
    Some(r) => r
    None => (0.0, 0.0, c.width, c.height)
  }
  let width = dmax(fw, 1.0)
  let height = dmax(fh, 1.0)
  let vk = Some(item)
  let say_failed = fn(what : String) {
    fn(e : Json) {
      dui.dgone.retain(fn(k) { k != key })
      dui.dlater.retain(fn(k) { k != key })
      toast_later(fill("android-misc.act.failed", [("what", what), ("error", error_words(e))]))
    }
  }
  let call = fn(name : String, what : String, extra : Map[String, Json]) {
    if src.read_only {
      toast_later(read_only_words)
      dui.dgone.retain(fn(k) { k != key })
      dui.dlater.retain(fn(k) { k != key })
      return
    }
    let p : Map[String, Json] = {
      "station": Json::string(text(vk, "station")),
      "thread": Json::number(number(vk, "thread")),
      "seq": Json::number(number(vk, "seq")),
    }
    for k, v in extra {
      p[k] = v
    }
    let failed = say_failed(what)
    (src.call)(name, Json::object(p), fn(res) {
      match res {
        Err(e) => failed(e)
        Ok(_) => ()
      }
    })
  }
  let set_aside = fn() {
    go_decision(c, -1, fn() {
      dui.dlater.retain(fn(k) { k != key })
      dui.dlater.push(key)
      call("decision.defer", tr("android-misc.decisions.deferWhat"), {})
    })
  }
  let dismiss = fn() {
    go_decision(c, 1, fn() {
      dui.dgone.push(key)
      call("decision.dismiss", tr("android-misc.decisions.dismissWhat"), {})
    })
  }
  let answer = fn(o : Choice) {
    go_decision(c, 2, fn() {
      dui.dgone.push(key)
      call("decision.answer", tr("android-misc.decisions.answerWhat"), { "option": Json::string(o.label) })
    })
  }
  // the finger: across first, it is the swipe (and what it pressed lets go); up or down first, the messages'
  let (px, py, down) = c.pointer()
  let field_rect = c.rect_of(c.id("deck/composer"))
  let in_field = match field_rect {
    Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
    None => false
  }
  if down && !dui.held && dui.going == 0 {
    if px >= fx && px < fx + fw && py >= fy && py < fy + fh && !in_field {
      dui.held = true
      dui.swiping = false
      dui.from_x = px
      dui.from_y = py
      dui.base = dui.drag
      dui.last_x = px
      dui.last_t = c.now()
      dui.speed = 0.0
    }
  } else if dui.held && down {
    let dx = px - dui.from_x
    let dy = py - dui.from_y
    if !dui.swiping {
      if dabs(dy) > 8.0 && dabs(dy) > dabs(dx) {
        dui.held = false
      } else if dabs(dx) > 8.0 {
        dui.swiping = true
        dui.from_x = px
      }
    }
    if dui.swiping {
      dui.drag = dui.base + (px - dui.from_x)
      let dt = c.now() - dui.last_t
      if dt > 0.0 {
        dui.speed = (px - dui.last_x) / dt * 1000.0
      }
      dui.last_x = px
      dui.last_t = c.now()
      c.request_frame()
    }
  } else if dui.held && !down {
    dui.held = false
    if dui.swiping {
      let at = dui.drag
      let v = dui.speed
      let fling = dabs(v) > 900.0 && dabs(at) > 16.0 && (v > 0.0) == (at > 0.0)
      if at > width * 0.35 || (fling && at > 0.0) {
        dismiss()
      } else if at < -width * 0.35 || (fling && at < 0.0) {
        set_aside()
      } else {
        // back where it rests
        dui.going = 3
        dui.going_at = c.now()
        dui.going_from = at
      }
    }
  }
  let swiped = dui.swiping
  if !down {
    dui.swiping = false
  }
  // where it is: flying off across (260 ms), up after an answer (360 ms), back where it rests (250 ms)
  let mut lift = 0.0
  if dui.going != 0 {
    let ms = match dui.going {
      2 => 360.0
      3 => 250.0
      _ => 260.0
    }
    let p = if c.stable() { 1.0 } else { dmin((c.now() - dui.going_at) / ms, 1.0) }
    match dui.going {
      2 => lift = height * @ui.bezier(0.55, 0.0, 0.85, 0.35, p)
      3 => dui.drag = dui.going_from * (1.0 - @ui.bezier(0.2, 0.0, 0.0, 1.0, p))
      dir => {
        let to = dir.to_double() * width * 1.25
        dui.drag = dui.going_from + (to - dui.going_from) * @ui.bezier(0.2, 0.0, 0.0, 1.0, p)
      }
    }
    if p < 1.0 {
      c.request_frame()
    } else if dui.going == 3 {
      dui.going = 0
      dui.drag = 0.0
    } else {
      let after = dui.after_go
      dui.after_go = fn() {  }
      after()
      // the only one, set aside: still the one in front; it comes in again
      if n == 1 && !dui.dgone.contains(key) {
        dui.drag = 0.0
        dui.going = 0
        dui.arrive_at = c.now()
      }
      c.request_frame()
    }
  }
  let arrive = if dui.arrive_at < 0.0 || c.stable() {
    1.0
  } else {
    let p = dmin((c.now() - dui.arrive_at) / 260.0, 1.0)
    if p < 1.0 {
      c.request_frame()
    }
    @ui.bezier(0.2, 0.7, 0.2, 1.0, p)
  }
  let moving = dui.going == 1 || dui.going == -1 || dui.going == 2
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), clip=true, id=frame, fn() {
      // under it, what letting it go that way does: left 待定 (at the right edge it uncovers), right 不再提醒
      let x = dui.drag
      if x != 0.0 && !moving {
        c.layer(fn() {
          c.box(
            dir=Row,
            w=Fill(1.0),
            h=Fill(1.0),
            padx=24.0,
            align=ACenter,
            justify=if x > 0.0 { JStart } else { JEnd },
            opacity=dmin(dabs(x) / (width * 0.12), 1.0),
            fn() {
              c.text(
                tr(if x > 0.0 { "android-misc.decisions.dismiss" } else { "android-misc.decisions.defer" }),
                size=16.0,
                weight=600,
                color=t.p.muted,
                wrap=false,
              )
              |> ignore
            },
          )
          |> ignore
        })
        |> ignore
      }
      if moving && n > 1 {
        c.layer(fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
            decision_face(c, src, shown[1], fn(_) {  }, fn() {  }, false)
          })
          |> ignore
        })
        |> ignore
      }
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          tx=dui.drag,
          ty=-lift + 12.0 * (1.0 - arrive),
          opacity=arrive * (if dui.going == 2 { 1.0 - dmin(lift / height / 0.4, 1.0) * 0.6 } else { 1.0 }),
          bg=t.p.bg,
          fn() {
            decision_face(c, src, item, fn(o) { if !swiped && dui.going == 0 { answer(o) } }, set_aside, true)
          },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the hint, and where this one is among them
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, pb=10.0, align=ACenter, fn() {
      c.box(w=Fill(1.0), fn() {
        c.text(tr("android-misc.decisions.hint"), size=12.0, color=t.p.subtle, wrap=false) |> ignore
      })
      |> ignore
      c.text("1 / \{n}", size=12.0, color=t.p.subtle, wrap=false) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A decision as the page shows it (Decisions.kt Face): its chat's title (to the chat), who is to decide, the messages
/// before it and the post as the chat draws them, under the post its options (or, a card this app does not know, the
/// way to answer it in its chat), the reply field floating over them at the foot. `live`: the one in front (the one
/// under it, shown as it goes, takes nothing).
fn decision_face(
  c : @ui.Ctx,
  src : Source,
  item : Json,
  on_pick : (Choice) -> Unit,
  on_set_aside : () -> Unit,
  live : Bool,
) -> Unit {
  ignore(on_set_aside)
  let t = @sf.theme()
  let v = Some(item)
  let key = decision_key(item)
  let station = text(v, "station")
  let session = text(v, "session")
  let card = field(v, "card")
  let kind = match text(card, "type") {
    "" => "options"
    k => k
  }
  let messages = items(v, "before").copy()
  match field(v, "message") {
    Some(m) => messages.push(m)
    None => ()
  }
  let view = chat_view(
    Json::object({
      "title": Json::string(text(v, "title")),
      "messages": Json::array(messages),
      "agents": Json::array([]),
      "people": Json::array([]),
    }),
  )
  let here = { station, session, view }
  let options = match choices_of(card, "options") {
    Some(o) if o.length() > 0 => o
    _ => choices_of(v, "options").unwrap_or([])
  }
  let replies = kind == "options" || kind == "text"
  let pre = if live { "deck/" } else { "deck-under/" }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let open = c.id(pre + "chat")
    if live && c.clicked(open) {
      open_decision_chat(v)
    }
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=16.0,
      pady=8.0,
      gap=4.0,
      align=ACenter,
      bg=if c.pressed(open) { @sf.alpha(t.p.text, 0.06) } else { 0L },
      id=open,
      fn() {
        c.box(fn() { c.text(text(v, "title"), size=13.0, color=t.p.muted, wrap=false) |> ignore })
        |> ignore
        @sf.icon(c, "chevron-right", size=14.0, color=t.p.subtle) |> ignore
      },
    )
    |> ignore
    match opt_text(card, "assigneeText") {
      Some(a) =>
        c.box(padx=16.0, pady=4.0, fn() { c.text(a, size=13.0, color=t.p.muted) |> ignore }) |> ignore
      None => ()
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let rows : Array[() -> Unit] = []
      for m in view.messages {
        rows.push(fn() { said(c, src, here, m, [], decide=false) })
      }
      rows.push(fn() {
        match kind {
          "options" =>
            match decision_options(c, pre + "options/" + key, options, true, None) {
              Some(o) if live => on_pick(o)
              _ => ()
            }
          "text" => ()
          "login" => {
            let post = view.messages.last()
            match post {
              Some(m) => decision_under(c, src, here, m)
              None => ()
            }
          }
          _ =>
            c.box(w=Fill(1.0), gap=8.0, fn() {
              c.text(tr("android-misc.decisions.replyInChat"), size=13.0, color=t.p.muted) |> ignore
              let go = c.id(pre + "go-reply")
              if live && c.clicked(go) {
                open_decision_chat(v)
              }
              c.box(w=Fill(1.0), pady=12.0, radius=12.0, bg=t.p.text, align=ACenter, id=go, fn() {
                c.text(tr("android-misc.decisions.goReply"), size=15.0, weight=500, color=t.p.bg, wrap=false)
                |> ignore
              })
              |> ignore
            })
            |> ignore
        }
      })
      rows.push(fn() { c.box(h=Px(if replies { composer_room + 10.0 } else { 10.0 }), fn() {  }) |> ignore })
      c.list(pre + "messages/" + key, rows.length(), 90.0, fn(i) {
        c.box(
          w=Fill(1.0),
          pl=14.0,
          pr=14.0,
          pt=if i == 0 { 10.0 } else if i == rows.length() - 1 { 0.0 } else { 20.0 },
          fn() { (rows[i])() },
        )
        |> ignore
      })
      |> ignore
      if replies && live {
        c.layer(fn() {
          c.spacer()
          decision_composer(c, src, item, key, if kind == "text" { text(card, "placeholder") } else { "" })
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The reply's field at the foot (Decisions.kt DecisionComposer, in the chat composer's capsule): its words go as the
/// viewer's message quoting the post (`decision.reply`), at once; refused by the core, the decision and the words come
/// back and why is said.
fn decision_composer(c : @ui.Ctx, src : Source, item : Json, key : String, placeholder : String) -> Unit {
  let t = @sf.theme()
  let fkey = "decision-reply/" + key
  let v = Some(item)
  let mut words = ""
  let send = c.id("deck/send")
  c.box(w=Fill(1.0), pl=10.0, pr=10.0, pt=8.0, pb=10.0, id=c.id("deck/composer"), fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      pad=composer_inset,
      gap=2.0,
      radius=composer_corner,
      align=AEnd,
      bg=floating_ground(),
      shadow=2.0,
      shadow_color=0x0000004DL,
      shadow_y=0.5,
      fn() {
        c.box(w=Fill(1.0), min_h=36.0, pl=plus_ink, pr=14.0, pt=7.0, pb=7.0, justify=JCenter, fn() {
          let res = c.editor(
            fkey,
            placeholder=if placeholder != "" { placeholder } else { tr("android-misc.decisions.placeholder") },
            font_size=send_size,
            line=send_line,
            max_lines=6,
            plain=true,
            color=t.p.text,
            placeholder_color=t.p.subtle,
            caret_color=t.p.accent,
            enter_sends=false,
          )
          words = res.text
        })
        |> ignore
        let ready = words.trim(chars=" \n\t").to_string() != "" && dui.going == 0
        c.box(
          w=Px(36.0),
          h=Px(36.0),
          radius=18.0,
          align=ACenter,
          justify=JCenter,
          bg=if ready { t.p.text } else { @sf.over(t.p.raised, @sf.alpha(t.p.text, 0.18)) },
          id=send,
          fn() {
            @sf.icon(c, "arrow-up", size=18.0, color=if ready { t.p.bg } else { t.p.raised }) |> ignore
          },
        )
        |> ignore
        if c.clicked(send) && ready {
          if src.read_only {
            say(c, read_only_words)
          } else {
            let taken = c.take_editor_text(fkey)
            c.blur()
            go_decision(c, 2, fn() { dui.dgone.push(key) })
            (src.call)(
              "decision.reply",
              {
                "station": Json::string(text(v, "station")),
                "thread": Json::number(number(v, "thread")),
                "seq": Json::number(number(v, "seq")),
                "text": Json::string(taken.trim(chars=" \n\t").to_string()),
                "attachments": Json::array([]),
                "quotes": Json::array([]),
              },
              fn(res) {
                match res {
                  Err(e) => {
                    dui.dgone.retain(fn(k) { k != key })
                    if text(Some(e), "code") == "invalid_params" {
                      c.set_editor_text(fkey, taken)
                    }
                    toast_later(fill("android-misc.decisions.replyFailed", [("error", error_words(e))]))
                  }
                  Ok(_) => ()
                }
              },
            )
          }
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
fn dabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}
