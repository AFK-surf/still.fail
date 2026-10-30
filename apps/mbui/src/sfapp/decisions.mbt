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
// puts it. The reply is the chat's composer whole (its files, its quotes, its draft the core keeps); the card turns
// as it is moved across, as the Android app's does.

///|
/// The 奏 page over what is open.
pub fn open_decisions() -> Unit {
  @sfbase.history_push()
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
  let capsule = c.box(
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
  // (Home.kt DecisionsCapsule: 「n 件待你决定」 to a screen reader)
  c.semantics(capsule, Button, id~, label=fill("android-chat.home.decisions", [("n", n.to_string())]))
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
  // as the core lists them: those answered, let go or decided here gone at once (back if that could not be done), those
  // set aside last (client/core-ts decisions.ts)
  let shown = items(view, "items")
  // the bar's 奏 at the stack's root: a place's top bar, room at its foot for the bar (slice 7's); else pushed
  let place = app.nav.under() is None
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    if place {
      place_top_bar(c, "decisions")
    } else {
      nav_bar(c, tr("android-misc.bar.place.decisions"))
    }
    // what it shows 4 under the bar (Decisions.kt: Spacer(top)); none left and all read, the day so far, scrolling up
    // to the bar, its 4 inside what scrolls (Idle's `top`)
    let idle = shown.length() == 0 && view is Some(_) && !flag(field(view, "wait"), "reading")
    c.box(w=Fill(1.0), h=Fill(1.0), pb=if place && has_bar() { nav_foot() + bar_room } else { nav_foot() }, fn() {
      if idle {
        decisions_idle(c, view, 4.0)
        // the last one, gone: drawn going over it
        deck_out(c, src, c.width, c.height)
        return
      }
      c.box(style=decisions_body, fn() {
        if shown.length() == 0 {
          // none yet while stations are still read is not none: their cards to come
          waiting_cards(c, topic.error)
          // the last one, gone: drawn going over them
          deck_out(c, src, c.width, c.height)
          return
        }
        deck(c, src, shown, 0)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What the page shows, 4 under its bar (Decisions.kt: Spacer(top), PlacePage.kt's `top` for a page pushed).
// kept across runs: a value (no field of it changes)
let decisions_body : @ui.Style = @ui.css("w=Full h=Full pt=S1")

///|
/// The cards to come while they are read (the library's Waiting): a made-up decision's card in its bones, as the deck
/// shows one; what went wrong over it in red.
fn waiting_cards(c : @ui.Ctx, error : Json?) -> Unit {
  let t = @sf.theme()
  @sf.waiting(
    c,
    fill=true,
    fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
        decision_face(c, @sfbase.sample_source, @sfbase.sample_decision(), fn(_) {  }, fn() {  }, false)
      })
      |> ignore
    },
    error=match error {
      Some(e) => error_words(e)
      None => ""
    },
  )
}

///|
/// None left (Decisions.kt Idle): the page stays for the next to come and says how the day went, where the next may come
/// from (the viewer's chats with an agent at work or waiting) and what was answered today. Each opens its chat. `top`:
/// the room over it, inside what scrolls (Decisions.kt Idle: `top = top + 16.dp`).
fn decisions_idle(c : @ui.Ctx, view : Json?, top : Double) -> Unit {
  let t = @sf.theme()
  let today = field(view, "today")
  let working = items(view, "working")
  let answered = items(view, "answered")
  let rows : Array[() -> Unit] = [
    fn() {
      c.box(w=Fill(1.0), pt=top + 16.0, align=ACenter, fn() {
        for f in items(field(view, "wait"), "failing") {
          c.box(pb=8.0, fn() { @sf.wait_pill(c, text(Some(f), "text"), error=true) }) |> ignore
        }
        c.box(pt=8.0, fn() {
          c.text(tr("android-misc.decisions.idle.title"), size=t.t.title, weight=600, color=t.p.text, wrap=false)
          |> ignore
        })
        |> ignore
        c.box(pt=4.0, fn() {
          c.text(tr("android-misc.decisions.idle.note"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
        if today is Some(Object(_)) {
          c.box(dir=Row, pt=14.0, gap=28.0, fn() {
            let figure = fn(f : String, words : String) {
              c.box(align=ACenter, fn() {
                c.text(f, size=20.0, weight=600, color=t.p.text, wrap=false) |> ignore
                c.text(words, size=t.t.caption, color=t.p.subtle, wrap=false) |> ignore
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
      c.text(words, size=t.t.caption, weight=500, color=t.p.subtle, wrap=false) |> ignore
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
  @sfbase.history_push()
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
/// A chat at work (the turning yellow ring) or a card answered (a quiet dot): its words over where it is, when at the
/// end of its words' line (Decisions.kt IdleRow).
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
    id~,
    fn() {
      c.box(w=Px(12.0), h=Px(12.0), pt=4.0, align=ACenter, justify=JCenter, fn() {
        if busy {
          at_work_mark(c)
        } else {
          c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=t.p.subtle, fn() {  }) |> ignore
        }
      })
      |> ignore
      // its words and when on its first line, where it is under them as wide as the words (a line of its own)
      @sf.row_lines(c, fn() {
        @sf.name_words(c, main, idle_main) |> ignore
        c.text(at, size=t.t.caption, color=t.p.subtle, wrap=false) |> ignore
      }, fn() { c.text(meta, size=t.t.meta, color=t.p.subtle, wrap=false, w=Fill(1.0)) |> ignore })
      // Decisions.kt IdleRow: clip(Smooth(10)).clickable
      @motion.ripple(c, id, 10.0)
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// An idle row's words (what it asked, the chat at work): a line, cut short where its time leaves it less.
// kept across runs: a value (no field of it changes)
let idle_main : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// How long a decision takes to go up after it is answered, and to come in. Flown off across or back where it rests,
/// let go by the finger: a Move as long as its way there is far, as fast as the finger let it go.
let card_up_ms : Double = 360.0

///|
let card_arrive_ms : Double = 260.0

///|
/// How far a card is turned as it is moved across, a width's worth (Decisions.kt: 4°), about its top's middle.
// kept across runs: a value
let card_tilt : Double = 4.0 * @math.PI / 180.0

///|
/// How small a card comes in from, and goes up to (Decisions.kt: 0.94, 0.88), about its top's middle.
let card_arrive_scale : Double = 0.94

///|
let card_gathered_scale : Double = 0.88

///|
/// The deck's motions, each from 0 to 1 on its curve: the one that went flying off (across or up), the front one
/// going back where it rests, the front one coming in (1: there).
fn card_out(c : @ui.Ctx) -> @motion.Anim {
  deck_anim(c, "deck/out")
}

///|
fn card_back(c : @ui.Ctx) -> @motion.Anim {
  deck_anim(c, "deck/back")
}

///|
fn card_arrive(c : @ui.Ctx) -> @motion.Anim {
  deck_anim(c, "deck/arrive")
}

///|
/// The deck's motions as asked (the same each time: @motion.anim's, global) and the frame each was last drawn in,
/// kept to say when those drawn are at rest.
let deck_anims : Map[String, (@motion.Anim, Int)] = {}

///|
fn deck_anim(c : @ui.Ctx, key : String) -> @motion.Anim {
  let a = @motion.anim(c, key, 1.0, global=true)
  deck_anims[key] = (a, c.frame_number())
  a
}

///|
/// When the deck's motions drawn in the last frame that drew any (one flying off or up, one going back, one coming
/// in: none left, nothing comes in) are at rest (the frames' clock; -1: none moves; +inf: told to go, not started
/// yet): a test runs to it.
pub fn deck_rest() -> Double {
  let mut last = -1
  deck_anims.each(fn(_, af) { if af.1 > last { last = af.1 } })
  let mut end = -1.0
  deck_anims.each(fn(_, af) { if af.1 == last && af.0.ends_at() > end { end = af.0.ends_at() } })
  end
}

///|
/// `a` from 0 to 1 by `ms` on `ease`, from now (said once: the framework draws it to its end).
fn card_go(a : @motion.Anim, ms : Double, ease : @ui.Ease) -> Unit {
  a.snap(0.0)
  a.animate(1.0, @motion.tween(ms, ease~))
}

///|
/// The front one comes in.
fn card_comes(c : @ui.Ctx) -> Unit {
  card_go(card_arrive(c), card_arrive_ms, Out)
}

///|
/// The front decision `item` goes (`dir` its side, 2 up after answering): `after` (what it goes to) done at once, the
/// deck without it from now on; it is only drawn flying off, as the next comes in (the only one, set aside: it again).
/// Across, from where the finger let it go as fast as it went (`v`, points per second) over `width` (the deck's).
fn go_decision(
  c : @ui.Ctx,
  dir : Int,
  item : Json,
  after : () -> Unit,
  v? : Double = 0.0,
  width? : Double = 0.0,
) -> Unit {
  dui.out = Some(item)
  dui.out_dir = dir
  dui.out_from = dui.drag
  if dir == 2 {
    card_go(card_out(c), card_up_ms, Leave)
  } else {
    // (its way as deck_out draws it: from where it was let go to a width and a quarter off its side)
    let way = dir.to_double() * width * 1.25 - dui.out_from
    let a = card_out(c)
    a.snap(0.0)
    a.animate(1.0, @motion.move(points=dabs(way)), velocity=if way == 0.0 { 0.0 } else { v / way })
  }
  dui.drag = 0.0
  dui.going = 0
  card_comes(c)
  after()
}

///|
/// The deck (Decisions.kt Deck): the decision in front, swiped where it rests (across first: the swipe; up or down
/// first: the messages'); under it, as it moves, what letting it go that way does; the hint and where this one is.
fn deck(c : @ui.Ctx, src : Source, shown : Array[Json], at : Int) -> Unit {
  let t = @sf.theme()
  let item = shown[at]
  let key = decision_key(item)
  let n = shown.length()
  if dui.front != key {
    // a new one in front: it comes in (unless it is the first the page shows, or it came in as the one before went)
    if dui.front != "" && dui.out is None {
      card_comes(c)
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
  // (what could not be done: the core puts it back in its place)
  let say_failed = fn(what : String) {
    fn(e : Json) { toast_later(fill("android-misc.act.failed", [("what", what), ("error", error_words(e))])) }
  }
  let call = fn(name : String, what : String, extra : Map[String, Json]) {
    if src.read_only {
      toast_later(read_only_words)
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
  let set_aside = fn(v : Double) {
    go_decision(c, -1, item, fn() { call("decision.defer", tr("android-misc.decisions.deferWhat"), {}) }, v~, width~)
  }
  let dismiss = fn(v : Double) {
    go_decision(c, 1, item, fn() { call("decision.dismiss", tr("android-misc.decisions.dismissWhat"), {}) }, v~, width~)
  }
  let answer = fn(o : Choice) {
    go_decision(c, 2, item, fn() {
      call("decision.answer", tr("android-misc.decisions.answerWhat"), { "option": Json::string(o.label) })
    })
  }
  // the finger on the card: its own box a drag area across (no node of its own); past the slop across first it is the
  // swipe, and what it pressed lets go; up or down first, the messages' (mbui's claim by way); not from the reply's
  // field. Its speed as let go is the input's own.
  let swipe_area = frame
  c.drag_on(swipe_area, axis=Horizontal)
  let field_rect = c.rect_of(c.id("deck/composer"))
  let in_field = fn(x : Double, y : Double) {
    match field_rect {
      Some((fx, fy, fw, fh)) => x >= fx && x < fx + fw && y >= fy && y < fy + fh
      None => false
    }
  }
  match c.drag_of(swipe_area) {
    Some(d) => {
      if d.down && !dui.held && dui.going == 0 && !in_field(d.x0, d.y0) {
        dui.held = true
        dui.swiping = false
      }
      // past the slop across: the card follows the finger from there (the drag's own moves, as mbui's drag_value)
      let (dx, _) = d.take_move()
      if dui.held && d.down && d.moving {
        dui.swiping = true
        dui.drag = dui.drag + dx
      }
      if dui.held && !d.down {
        dui.held = false
        if dui.swiping && d.take_end() {
          let at = dui.drag
          // its speed as the finger left it (px/s), the input's own
          let v = d.vx * 1000.0
          let fling = dabs(v) > 900.0 && dabs(at) > 16.0 && (v > 0.0) == (at > 0.0)
          if at > width * 0.35 || (fling && at > 0.0) {
            dismiss(v)
          } else if at < -width * 0.35 || (fling && at < 0.0) {
            set_aside(v)
          } else {
            // back where it rests
            dui.going = 3
            dui.going_from = at
            // (its way a share of where it was let go, `at` back to 0: as fast as the finger went)
            let back = card_back(c)
            back.snap(0.0)
            back.animate(1.0, @motion.move(points=dabs(at)), velocity=if at == 0.0 { 0.0 } else { -v / at })
          }
        }
      }
    }
    None => ()
  }
  let down = match c.drag_of(swipe_area) {
    Some(d) => d.down
    None => false
  }
  let swiped = dui.swiping
  if !down {
    dui.swiping = false
  }
  // let go short: back where it rests
  if dui.going == 3 {
    let back = card_back(c)
    // (till the end it declared as it set out)
    if !back.over() {
      dui.drag = dui.going_from * (1.0 - back.get())
    } else {
      dui.going = 0
      dui.drag = 0.0
    }
  }
  let arrive = card_arrive(c).get()
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), clip=true, id=frame, fn() {
      // under it, what letting it go that way does: left 待定 (at the right edge it uncovers), right 不再提醒
      let x = dui.drag
      if x != 0.0 {
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
                size=t.t.title,
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
      c.layer(fn() {
        let card = c.box(w=Fill(1.0), h=Fill(1.0), tx=dui.drag, opacity=arrive, bg=t.p.bg, fn() {
          decision_face(c, src, item, fn(o) { if !swiped && dui.going == 0 { answer(o) } }, fn() { set_aside(0.0) }, true)
        })
        // coming in from a little smaller, about its top's middle (Decisions.kt: lerp(0.94, 1, arrive)); turned as it
        // is moved across, 4° a width (rotationZ = drag / width * 4)
        c.look(
          card,
          @ui.look(
            scale=card_arrive_scale + (1.0 - card_arrive_scale) * arrive,
            oy=0.0,
            rot=dui.drag / width * card_tilt,
          ),
        )
      })
      |> ignore
      // over it, the one that went
      deck_out(c, src, width, height)
    })
    |> ignore
    // the hint, and where this one is among them
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, pb=10.0, align=ACenter, fn() {
      c.box(w=Fill(1.0), fn() {
        c.text(tr("android-misc.decisions.hint"), size=t.t.caption, color=t.p.subtle, wrap=false) |> ignore
      })
      |> ignore
      c.text("\{at + 1} / \{n}", size=t.t.caption, color=t.p.subtle, wrap=false) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The one that went, flying off across or up after an answer (`width` × `height` the deck's), over what is in front
/// (the next, or none left): only drawn, a tap there is what is under it's.
fn deck_out(c : @ui.Ctx, src : Source, width : Double, height : Double) -> Unit {
  let o = match dui.out {
    Some(o) => o
    None => return
  }
  let t = @sf.theme()
  let a = card_out(c)
  // (gone at the end it declared as it set off)
  if a.over() {
    dui.out = None
    return
  }
  // (its curve's: card_go's, as it set out)
  let p = a.get()
  // up: drawn smaller as it rises, to 88% by 40% of the way (Decisions.kt: lerp(1, 0.88, gathered)); across, as it is
  let (x, y, scale) = if dui.out_dir == 2 {
    let lift = height * p
    (dui.out_from, -lift, 1.0 - dmin(lift / height / 0.4, 1.0) * (1.0 - card_gathered_scale))
  } else {
    let to = dui.out_dir.to_double() * width * 1.25
    (dui.out_from + (to - dui.out_from) * p, 0.0, 1.0)
  }
  c.layer(fn() {
    let card = c.box(w=Fill(1.0), h=Fill(1.0), tx=x, ty=y, bg=t.p.bg, fn() {
      decision_face(c, src, o, fn(_) {  }, fn() {  }, false)
    })
    // turned as it is across, on as it flies (Decisions.kt: rotationZ = drag / width * 4)
    c.look(card, @ui.look(scale~, oy=0.0, rot=x / width * card_tilt))
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
  let view = chat_view_made(
    Json::object({
      "title": Json::string(text(v, "title")),
      "messages": Json::array(messages),
      "agents": Json::array([]),
      "people": Json::array([]),
    }),
  )
  let here = { station, session, view }
  // its messages as their chat draws them (sfpages' rows, as the desktop's 奏 page has them), out of its list: what
  // they ask is answered at the card's foot
  let rows_here : @sfpages.MessageHere = {
    station,
    session,
    view,
    go: None,
    inline: c.width <= @sfpages.chat_narrow_w,
    gutter: 0.0,
    list: None,
    core: None,
  }
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
      id=open,
      fn() {
        c.box(fn() { c.text(text(v, "title"), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore })
        |> ignore
        @sf.icon(c, "chevron-right", size=14.0, color=t.p.subtle) |> ignore
        // Decisions.kt: the row clickable
        @motion.ripple(c, open, 0.0)
      },
    )
    |> ignore
    match opt_text(card, "assigneeText") {
      Some(a) =>
        c.box(padx=16.0, pady=4.0, fn() { c.text(a, size=t.t.meta, color=t.p.muted) |> ignore }) |> ignore
      None => ()
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let rows : Array[() -> Unit] = []
      for m in view.messages {
        rows.push(fn() { @sfpages.message_row(c, src, rows_here, m) })
      }
      rows.push(fn() {
        match kind {
          // an agent's request for a vault item: approved here (Vault.kt), the 奏 page's the viewer's
          // (one that says what it is: answered on its card, in the post above)
          "options" if text(card, "vault") != "" && field(card, "vaultAsk") is Some(_) => ()
          "options" if text(card, "vault") != "" => {
            let ws = match station.find("/") {
              Some(i) => station.view(end_offset=i).to_string()
              None => station
            }
            vault_approval(c, src, ws, text(card, "vault"), true)
          }
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
              c.text(tr("android-misc.decisions.replyInChat"), size=t.t.meta, color=t.p.muted) |> ignore
              let go = c.id(pre + "go-reply")
              if live && c.clicked(go) {
                open_decision_chat(v)
              }
              c.box(w=Fill(1.0), pady=12.0, radius=12.0, bg=t.p.text, align=ACenter, id=go, fn() {
                c.text(tr("android-misc.decisions.goReply"), size=t.t.ui, weight=500, color=t.p.bg, wrap=false)
                |> ignore
              })
              |> ignore
            })
            |> ignore
        }
      })
      rows.push(fn() { c.box(h=Px(if replies { composer_room + 10.0 } else { 10.0 }), fn() {  }) |> ignore })
      c.list(pre + "messages/" + key, rows.length(), 90.0, fn(i) {
        // (20 apart, as in the chat: the viewer's message sent soon after the one before it, joined_gap)
        let joined = i < view.messages.length() && view.messages[i].joined
        c.box(
          w=Fill(1.0),
          pl=14.0,
          pr=14.0,
          pt=if i == 0 {
            10.0
          } else if i == rows.length() - 1 {
            0.0
          } else if joined {
            joined_gap
          } else {
            gap
          },
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
/// The reply at the foot (Decisions.kt DecisionComposer: the chat's composer whole, its files, its quotes, its draft
/// the core keeps as `decision:<station>:<thread>:<seq>`): what is written goes as the viewer's message quoting the
/// post (`decision.reply`), at once; refused by the core, the decision comes back, and what was written too where
/// nothing was written since, and why is said.
fn decision_composer(c : @ui.Ctx, src : Source, item : Json, key : String, placeholder : String) -> Unit {
  let v = Some(item)
  let station = text(v, "station")
  let draft = "decision:" + station + ":" + number(v, "thread").to_int().to_string() + ":" +
    number(v, "seq").to_int().to_string()
  composer(c, src, chat_ref(station, text(v, "session")), None, fresh=Some({
    key: draft,
    placeholder: if placeholder != "" { placeholder } else { tr("android-misc.decisions.placeholder") },
    send: fn(d) { decision_reply(c, src, item, key, d) },
    tools: None,
    held: false,
  }))
}

///|
/// The reply sent (Decisions.kt `reply`): the draft taken, the decision gone at once.
fn decision_reply(c : @ui.Ctx, src : Source, item : Json, key : String, d : Draft) -> Unit {
  if src.read_only {
    say(c, read_only_words)
    return
  }
  if dui.going != 0 {
    return
  }
  let v = Some(item)
  let words = with_link_words(d.text.get().trim(chars=" \n\t").to_owned(), d)
  let files = up_files(d)
  let uploads = up_uploads(d)
  let quotes = d.quotes.map(fn(q) { quote_json(d, q, true) })
  let taken_text = d.text.get()
  let taken_files = d.files.copy()
  let taken_quotes = d.quotes.copy()
  let taken_comments = d.comments.copy()
  ref_field_put(d, "")
  d.files.clear()
  d.quotes.clear()
  d.comments.clear()
  d.error.set(None)
  sent_draft(d, taken_files.length())
  save_draft(src, d)
  c.blur()
  go_decision(c, 2, item, fn() {  })
  let reply : Map[String, Json] = {
    "station": Json::string(text(v, "station")),
    "thread": Json::number(number(v, "thread")),
    "seq": Json::number(number(v, "seq")),
    "text": Json::string(words),
    "attachments": Json::array(files),
    "quotes": Json::array(quotes),
  }
  // the files still going up: it waits for them (Decisions.kt reply's taken.uploads)
  if uploads.length() > 0 {
    reply["uploads"] = Json::array(uploads)
  }
  (src.call)(
    "decision.reply",
    Json::object(reply),
    fn(res) {
      match res {
        Err(e) => {
          if text(Some(e), "code") == "invalid_params" && draft_empty(d) {
            d.text.set(taken_text)
            d.put_text.set(Some(taken_text))
            for f in taken_files {
              d.files.push(f)
            }
            for q in taken_quotes {
              d.quotes.push(q)
            }
            for k, w in taken_comments {
              d.comments[k] = w
            }
            save_draft(src, d)
          }
          toast_later(fill("android-misc.decisions.replyFailed", [("error", error_words(e))]))
        }
        Ok(_) => ()
      }
    },
  )
}

///|
fn dabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}
