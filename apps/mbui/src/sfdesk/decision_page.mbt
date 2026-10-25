// The 奏 page on the desktop (ember web/src/DecisionDesk.tsx DecisionPage; Decisions.tsx DecisionMessages,
// DecisionPicks, DecisionAnswer, DecisionReply, DecisionFoot, flyOff; DecisionsIdle.tsx; DecisionDesk.css.ts page, bar*;
// Decisions.css.ts deck, card, scroll, column, foot, reply, arriving, empty, elsewhere; DecisionsIdle.css.ts): the
// decision picked in the sidebar's 奏 (the core's `shown`), its bar its chat (opening it) and station, 待定 and 不再提醒
// at its end; under it who is to decide, the post and what came just before it as the chat draws them, its options (a
// vault request's answer, a login's card, or the way to its chat for a card this page does not know), and the chat's
// composer floating at the foot to reply in words (`decision.reply`). Answered it is drawn in and pulled up, set aside
// it goes left, dismissed right, the next rising in its place. None left: how the day went, where the next may come
// from and what was answered today, each opening its chat. Everything said goes through the core's calls.

///|
/// What the page keeps of its own: the decision on its way off (its item, which way: 1 left, 2 right, 3 up), each
/// leaving counted (its motion's key), and the one that last came in front (to rise as it does).
priv struct ZouOwn {
  mut leaving : Json?
  mut way : Int
  mut n : Int
  mut front : String
}

///|
let zou_own : ZouOwn = { leaving: None, way: 0, n: 0, front: "" }

///|
fn zou_page_reset() -> Unit {
  zou_own.leaving = None
  zou_own.way = 0
  zou_own.n = 0
  zou_own.front = ""
}

///|
/// The 奏 page for workspace `w`.
fn decision_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let topic = (src.topic)("decisions", { "workspace": Json::string(w.id) })
  let view = match topic.value {
    Some(Object(_)) as v => v
    _ => None
  }
  let shown = items(view, "items")
  let d = shown.get(decision_front(view, shown))
  let core = settings_core(src, w)
  // another come in front (not the first the page shows, nor one in place of one leaving, which rises as that goes)
  let key = match d {
    Some(x) => decision_key(x)
    None => ""
  }
  if key != zou_own.front {
    if zou_own.front != "" && key != "" && zou_own.leaving is None {
      zou_rise(c)
    }
    zou_own.front = key
  }
  c.box(style=zp_page, fn() {
    zou_bar(c, src, d)
    let deck = c.id("zou/deck")
    let (dw, dh) = c.laid_size(deck).unwrap_or((c.width, c.height))
    c.box(style=zp_deck, id=deck, fn() {
      match d {
        Some(x) => {
          let card = c.box(style=zp_card, fn() { zou_card(c, src, w, core, x, true) })
          let p = zou_anim(c, "zou/rise").get()
          if p < 1.0 {
            c.look(card, @ui.look(alpha=p, dy=zou_rise_dy * (1.0 - p), scale=zou_rise_scale + (1.0 - zou_rise_scale) * p))
          }
        }
        None => {
          let wait = field(view, "wait")
          if view is Some(_) && !flag(wait, "reading") && items(wait, "failing").length() == 0 {
            zou_idle(c, view)
          } else if view is None && topic.error is Some(e) {
            c.box(style=zp_empty, fn() { c.text(text(Some(e), "message"), style=zp_empty_words) |> ignore }) |> ignore
          } else {
            c.box(style=zp_waiting, fn() { @sf.waiting(c, shape=Cards, count=2) }) |> ignore
          }
        }
      }
      zou_leaving(c, src, w, core, dw, dh)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The page's bar (DecisionDesk.tsx DecisionPage's header): its chat (opening it) and its station on the left; 待定 and
/// 不再提醒 on the right.
fn zou_bar(c : @ui.Ctx, src : Source, d : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=zp_bar, moves="page-bar", fn() {
    c.box(style=zp_bar_lead, fn() {
      match d {
        Some(x) => {
          let v = Some(x)
          let open = c.id("zou/chat")
          c.cursor(open, Hand)
          if c.clicked(open) {
            zou_open(x)
          }
          let b = c.box(style=if c.lit(open) { zp_bar_chat_hot } else { zp_bar_chat }, id=open, fn() {
            c.text(text(v, "title"), style=zp_bar_chat_words) |> ignore
          })
          c.semantics(b, Button, id=open, label=@sf.t("web-main.decisions.openChat"))
          @sf.tip(c, "zou/chat-tip", open, @sf.t("web-main.decisions.openChat"))
          // (short of room, its station is left out first)
          c.box(style=zp_bar_station, drop=zp_drop_station, fn() {
            if @sf.has_station_mark(text(v, "stationEmoji"), text(v, "stationIcon")) {
              @sf.station_mark(c, text(v, "stationEmoji"), text(v, "stationIcon"), zp_station_mark, t.p.subtle)
            }
            c.text(text(v, "stationName"), style=zp_bar_station_words) |> ignore
          })
          |> ignore
        }
        None => ()
      }
    })
    |> ignore
    c.box(style=zp_bar_actions, fn() {
      match d {
        Some(x) => {
          // (a written reply goes at once, as a message does: nothing waits on it here)
          if zou_bar_button(c, "zou/defer", @sf.t("web-main.decisions.defer"), true) {
            zou_leave(c, x, 1)
            c.tell("zou/defer", fn() { zou_call(src, "decision.defer", x, @sf.t("web-main.decisions.deferWhat")) })
          }
          if zou_bar_button(c, "zou/dismiss", @sf.t("web-main.decisions.dismiss"), true) {
            zou_leave(c, x, 2)
            c.tell("zou/dismiss", fn() { zou_call(src, "decision.dismiss", x, @sf.t("web-main.decisions.dismissWhat")) })
          }
        }
        None => ()
      }
    })
    |> ignore
    page_bar_end(c)
  })
  |> ignore
}

///|
/// One of the bar's buttons (barButton): 28 high, 10 in, the muted ink, the text's and its ground under the pointer;
/// faint while it cannot be pressed. True as it is pressed.
fn zou_bar_button(c : @ui.Ctx, key : String, label : String, on : Bool) -> Bool {
  let id = if on { c.id(key) } else { 0 }
  c.cursor(id, Hand)
  let hot = on && c.lit(id)
  let b = c.box(style=(if !on { zp_button_off } else if hot { zp_button_hot } else { zp_button }).then(@sf.finger_least_h()), id~, fn() {
    c.text(label, style=if hot { zp_button_words_hot } else { zp_button_words }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  id != 0 && c.clicked(id)
}

///|
/// Decision `x` as the page shows it (its card: the deck's card), `live` the one in front (the one leaving takes
/// nothing): who is to decide, the post and what came before it (DecisionMessages), under them what answers it
/// (DecisionPicks), the composer over the foot (DecisionFoot, DecisionAnswer).
fn zou_card(c : @ui.Ctx, src : Source, w : Workspace, core : Core, x : Json, live : Bool) -> Unit {
  let v = Some(x)
  let station = text(v, "station")
  let card = field(v, "card")
  let kind = match text(card, "type") {
    "" => if @sfbase.choices_of(v, "options").unwrap_or([]).length() > 0 { "options" } else { "" }
    k => k
  }
  let vault = text(card, "vault")
  let replies = (kind == "options" || kind == "text") && vault == ""
  let messages = items(v, "before").copy()
  match field(v, "message") {
    Some(m) => messages.push(m)
    None => ()
  }
  let cv = chat_view(
    Json::object({
      "title": Json::string(text(v, "title")),
      "messages": Json::array(messages),
      "agents": Json::array([]),
      "people": Json::array([]),
    }),
  )
  // (as the chat draws them, out of its list: what they ask is answered under them here; a vault request's card
  // without its answer, which is here's)
  let here : MessageHere = {
    station,
    session: text(v, "session"),
    view: cv,
    go: None,
    inline: false,
    gutter: 0.0,
    list: None,
    core: None,
  }
  let draft = "decision:" + station + ":" + number(v, "thread").to_int().to_string() + ":" +
    number(v, "seq").to_int().to_string()
  let room = if replies { @sfpages.composer_room(c, draft) } else { 0.0 }
  let pre = if live { "zou/" } else { "zou-out/" }
  let lkey = pre + "messages/" + decision_key(x)
  let rows : Array[() -> Unit] = []
  match opt_text(card, "assigneeText") {
    Some(a) => rows.push(fn() { c.text(a, style=zp_assignee) |> ignore })
    None => ()
  }
  for m in cv.messages {
    rows.push(fn() { message_row(c, src, here, m) })
  }
  rows.push(fn() { zou_picks(c, src, core, here, x, kind, live) })
  c.box(style=zp_card_fill, fn() {
    // the newest in view (the post over what answers it), the column at the foot while it is short (column: margin
    // auto auto 0): over it the room it leaves, as its rows were laid out
    let laid = (0).until(rows.length() + 1).fold(init=0.0, fn(sum, i) {
      sum + c.list_row_height(lkey, i + 1).unwrap_or(zp_row_est)
    })
    let short = match c.list_info(lkey) {
      Some(info) => dmax(0.0, info.height - laid)
      None => 0.0
    }
    c.list(
      lkey,
      rows.length() + 2,
      zp_row_est,
      fn(j) {
        if j == 0 {
          c.box(style=@ui.style(h=Fixed(short)), fn() {  }) |> ignore
          return
        }
        let i = j - 1
        guard rows.get(i) is Some(row) else {
          // its end clear of the foot floating over it (DecisionFoot: its height), and 12
          c.box(style=@ui.style(h=Fixed(room + zp_foot_gap)), fn() {  }) |> ignore
          return
        }
        c.box(style=if i == 0 { zp_row_first } else { zp_row }, fn() {
          c.box(style=zp_column, fn() { row() }) |> ignore
        })
        |> ignore
      },
      stick_end=true,
    )
    |> ignore
    if replies && live {
      c.layer(fn() {
        c.spacer()
        zou_answer(c, src, w, x, draft, if kind == "text" { text(card, "placeholder") } else { "" })
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// What answers it, under the post (DecisionPicks): a vault request's answer, its options (picked, it goes up), a
/// login's card, nothing for a text card (the composer is its), else the way to its chat.
fn zou_picks(c : @ui.Ctx, src : Source, core : Core, here : MessageHere, x : Json, kind : String, live : Bool) -> Unit {
  let v = Some(x)
  let card = field(v, "card")
  let vault = text(card, "vault")
  if vault != "" {
    let ws = workspace_of(here.station)
    let mine = mine_to(here, text(card, "assignee"))
    match field(card, "vaultAsk") {
      // (as the core said it with the card, from the vault it holds)
      Some(Object(_)) as ask => {
        let answer = @settings.card_answer(text(ask, "answer"), text(ask, "lasts"), mine)
        @settings.vault_foot(c, core, ws, vault, answer, field(ask, "save") is Some(_))
      }
      _ => @settings.vault_actions(c, core, ws, vault, mine)
    }
    return
  }
  match kind {
    "options" => {
      let options = match @sfbase.choices_of(card, "options") {
        Some(o) if o.length() > 0 => o
        _ => @sfbase.choices_of(v, "options").unwrap_or([])
      }
      match field(v, "message") {
        Some(mj) =>
          decision_options(c, src, here, message_of(mj), number(v, "thread"), options, !live, on_pick=fn() {
            zou_leave(c, x, 3)
          })
        None => ()
      }
    }
    "text" => ()
    "login" if text(card, "login") != "" => {
      let station = if text(card, "station") == "" {
        here.station
      } else {
        workspace_of(here.station) + "/" + text(card, "station")
      }
      login_card(c, core, station, text(card, "login"))
    }
    _ => {
      let go = if live { c.id("zou/elsewhere") } else { 0 }
      c.cursor(go, Hand)
      if go != 0 && c.clicked(go) {
        zou_open(x)
      }
      let b = c.box(style=if c.lit(go) { zp_elsewhere_hot } else { zp_elsewhere }, id=go, fn() {
        c.text(@sf.t("web-main.decisions.elsewhere"), style=zp_elsewhere_words) |> ignore
      })
      c.semantics(b, Button, id=go, label=@sf.t("web-main.decisions.elsewhere"))
    }
  }
}

///|
/// The reply to write at the page's foot (DecisionAnswer, DecisionReply): the chat's composer, its draft the core keeps
/// as `decision:<station>:<thread>:<seq>`; sent, it goes as the viewer's message quoting the post (`decision.reply`)
/// and the decision goes up at once; refused by the core, what was written comes back where nothing was written since,
/// and why is said.
fn zou_answer(c : @ui.Ctx, src : Source, w : Workspace, x : Json, draft : String, placeholder : String) -> Unit {
  let v = Some(x)
  let station = text(v, "station")
  let spec : @sfpages.ComposerSpec = {
    station,
    draft,
    session: text(v, "session"),
    placeholder: if placeholder != "" { placeholder } else { @sf.t("web-main.composer.placeholder") },
    toolbar: None,
    roomy: false,
    locked: false,
    offline: false,
  }
  let width = composer_width(c.width)
  // (in a panel of its own, at its foot: its capsule where its ends stand concentric with the corners they are in)
  let capsule_in = @sfpages.composer_capsule_in(c.width)
  let foot = c.box(style=if @sf.in_pane() { zp_foot_tape() } else { zp_foot }, fn() {
    c.box(style=@ui.style(w=Fixed(width)), fn() {
      c.sized(width, c.height, fn() {
        @sfpages.composer(c, src, w, spec, fn(wr) {
          if src.read_only {
            toast_later(read_only_words)
            return
          }
          zou_leave(c, x, 3)
          writing_take(src, wr, fn(taken) {
            guard taken is Some(_) else { return }
            let params : Map[String, Json] = {
              "station": Json::string(station),
              "thread": Json::number(number(v, "thread")),
              "seq": Json::number(number(v, "seq")),
              "text": Json::string(text(taken, "text")),
              "attachments": Json::array(items(taken, "attachments")),
              "quotes": Json::array(items(taken, "quotes")),
            }
            let going = items(taken, "uploads")
            if going.length() > 0 {
              params["uploads"] = Json::array(going)
            }
            (src.call)("decision.reply", Json::object(params), fn(res) {
              match res {
                Err(e) => {
                  if text(Some(e), "code") == "invalid_params" {
                    writing_restore(src, wr, "", unless_written=true)
                  }
                  toast_later(
                    @sf.t("android-misc.act.failed", args=[
                      ("what", @sf.t("web-main.decisions.replyWhat")),
                      ("error", error_words(e)),
                    ]),
                  )
                }
                Ok(_) => ()
              }
            })
          })
        }, capsule_in~)
      })
    })
    |> ignore
  })
  @motion.measure(c, foot, "composer/foot")
}

///|
/// Decision `x` sets off (1 left: set aside; 2 right: dismissed; 3 up: answered), the next rising in its place: drawn
/// leaving over it (flyOff) for its motion's time.
fn zou_leave(c : @ui.Ctx, x : Json, way : Int) -> Unit {
  zou_own.leaving = Some(x)
  zou_own.way = way
  zou_own.n += 1
  let a = zou_anim(c, "zou/leave")
  a.snap(0.0)
  if way == 3 {
    a.animate(1.0, @motion.tween(zou_up_ms, ease=Bezier(0.55, 0.0, 0.85, 0.35)))
  } else {
    a.animate(1.0, @motion.tween(zou_off_ms, ease=Bezier(0.4, 0.0, 0.9, 0.6)))
  }
  zou_rise(c)
}

///|
/// The next comes in (Decisions.css.ts arriving: from 12 under at 98%, faded, 240 ms easing out); answered, there at
/// once under the one pulled up.
fn zou_rise(c : @ui.Ctx) -> Unit {
  let a = zou_anim(c, "zou/rise")
  if zou_own.way == 3 && zou_own.leaving is Some(_) {
    a.snap(1.0)
    return
  }
  a.snap(0.0)
  a.animate(1.0, @motion.tween(zou_rise_ms, ease=Out))
}

///|
/// The page's motions (from 0 to 1, global: they run on as the page is drawn again).
fn zou_anim(c : @ui.Ctx, key : String) -> @motion.Anim {
  @motion.anim(c, key, 1.0, global=true)
}

///|
/// The decision leaving, over what is in front (`dw` × `dh` the deck's): answered, drawn in to 88% and pulled up,
/// faster and faster; set aside or dismissed, across and off. Drawn only.
fn zou_leaving(c : @ui.Ctx, src : Source, w : Workspace, core : Core, dw : Double, dh : Double) -> Unit {
  let x = match zou_own.leaving {
    Some(x) => x
    None => return
  }
  let a = zou_anim(c, "zou/leave")
  // (gone at the end it declared as it set off)
  if a.over() {
    zou_own.leaving = None
    return
  }
  let p = a.get()
  let (tx, ty, scale) = match zou_own.way {
    3 => (0.0, -dh * p, 1.0 - dmin(p / 0.4, 1.0) * (1.0 - zou_gathered))
    1 => (-(dw + zou_off_more) * p, 0.0, 1.0)
    _ => ((dw + zou_off_more) * p, 0.0, 1.0)
  }
  let l = c.layer(fn() {
    let card = c.box(style=zp_card, tx~, ty~, fn() { zou_card(c, src, w, core, x, false) })
    c.look(card, @ui.look(scale~, oy=0.0))
  })
  c.draw_only(l)
}

///|
/// A decision's chat opened (its title pressed, the way to answer there).
fn zou_open(x : Json) -> Unit {
  let v = Some(x)
  @sfbase.open_chat({
    station: text(v, "station"),
    session: text(v, "session"),
    title: text(v, "title"),
    station_name: text(v, "stationName"),
  })
}

///|
/// Set aside or dismissed (`decision.defer`, `decision.dismiss`): the core lets go of it at once, back if that fails.
fn zou_call(src : Source, call : String, x : Json, what : String) -> Unit {
  let v = Some(x)
  act(src, what, "", call, {
    "station": Json::string(text(v, "station")),
    "thread": Json::number(number(v, "thread")),
    "seq": Json::number(number(v, "seq")),
  })
}

///|
/// None left (DecisionsIdle): its face, 奏折已全部批完 and where the next will show; the day in figures (answered, the
/// average wait, at work); the chats at work (the next may come from there) and what was answered today, each opening
/// its chat.
fn zou_idle(c : @ui.Ctx, view : Json?) -> Unit {
  let t = @sf.theme()
  let today = field(view, "today")
  c.box(style=zi_idle, fn() {
    c.box(style=zi_column, fn() {
      c.box(style=zi_head, fn() {
        if @sf.has_drawable("buddy_idle") {
          @sf.drawable(c, if t.dark { "buddy_idle_dark" } else { "buddy_idle" }, zi_face) |> ignore
        }
        c.text(@sf.t("web-main.decisions.idle.title"), style=zi_title) |> ignore
        c.text(@sf.t("web-main.decisions.idle.note"), style=zi_note) |> ignore
        if today is Some(Object(_)) {
          c.box(style=zi_stats, fn() {
            zi_stat(c, number(today, "count").to_int().to_string(), @sf.t("web-main.decisions.idle.answered"))
            if text(today, "waited") != "" {
              zi_stat(c, text(today, "waited"), @sf.t("web-main.decisions.idle.waited"))
            }
            zi_stat(c, number(today, "working").to_int().to_string(), @sf.t("web-main.decisions.idle.working"))
          })
          |> ignore
        }
      })
      |> ignore
      let working = items(view, "working")
      if working.length() > 0 {
        c.box(style=zi_section, fn() {
          c.text(@sf.t("web-main.decisions.idle.workingTitle"), style=zi_section_title) |> ignore
          for wj in working {
            let wv = Some(wj)
            zi_row(
              c,
              "zou-idle/working/" + text(wv, "station") + "/" + text(wv, "session"),
              text(wv, "title"),
              [@ui.span(text(wv, "line"))],
              text(field(field(wv, "time"), "lastActiveAt"), "ago"),
              true,
              fn() {
                @sfbase.open_chat({ station: text(wv, "station"), session: text(wv, "session"), title: text(wv, "title"), station_name: "" })
              },
            )
          }
        })
        |> ignore
      }
      let answered = items(view, "answered")
      if answered.length() > 0 {
        c.box(style=zi_section, fn() {
          c.text(@sf.t("web-main.decisions.idle.answeredTitle"), style=zi_section_title) |> ignore
          for aj in answered {
            let av = Some(aj)
            zi_row(
              c,
              "zou-idle/answered/" + text(av, "station") + "/" + number(av, "thread").to_int().to_string() + "/" +
              number(av, "seq").to_int().to_string(),
              text(av, "text"),
              [@ui.span(text(av, "title") + " · "), @ui.span(text(av, "answer"), color=t.p.text)],
              text(av, "clock"),
              false,
              fn() {
                @sfbase.open_chat({ station: text(av, "station"), session: text(av, "session"), title: text(av, "title"), station_name: "" })
              },
            )
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The day's figure over its words (stat).
fn zi_stat(c : @ui.Ctx, figure : String, words : String) -> Unit {
  c.box(style=zi_stat_box, fn() {
    c.text(figure, style=zi_figure) |> ignore
    c.text(words, style=zi_figure_words) |> ignore
  })
  |> ignore
}

///|
/// A chat or a card answered (row): its mark (at work, the turning spokes; answered, a quiet dot), its words over where
/// it is, when at its end; its ground under the pointer; pressed, `open`.
fn zi_row(
  c : @ui.Ctx,
  key : String,
  main : String,
  meta : Array[@ui.Run],
  when : String,
  busy : Bool,
  open : () -> Unit,
) -> Unit {
  let id = c.id(key)
  c.cursor(id, Hand)
  if c.clicked(id) {
    c.tell(key, open)
  }
  let b = c.box(style=if c.lit(id) { zi_row_hot } else { zi_row_box }, id~, fn() {
    if busy {
      c.box(style=zi_busy_room, fn() { @sf.spokes(c, zi_busy, zi_busy_ink) |> ignore }) |> ignore
    } else {
      c.box(style=zi_done, fn() {  }) |> ignore
    }
    c.box(style=zi_words, fn() {
      c.text(main, style=zi_main) |> ignore
      c.rich(meta, style=zi_meta) |> ignore
    })
    |> ignore
    if when != "" {
      c.text(when, style=zi_when) |> ignore
    }
  })
  c.semantics(b, Button, id~, label=main)
}

///|
/// The page (DecisionDesk.css.ts page): its bar, then the decision filling the pane, on the canvas.
// kept across runs: a value (no field of it changes)
let zp_page : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// The bar (sidebar.css.ts pageBar): 45, its chat and station on the left, its buttons on the right, 2 apart.
// kept across runs: a value (no field of it changes)
let zp_bar : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wide_bar_h_size, px=S3, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let zp_bar_lead : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=ACenter, clip=true)

///|
/// Its chat (barChat): 13, 600, 2 by 6 in, its ground under the pointer, cut where short.
// kept across runs: a value (no field of it changes)
let zp_bar_chat : @ui.Style = @ui.css("row px=S1_5 py=S0_5 radius=Md")

///|
// kept across runs: a value (no field of it changes)
let zp_bar_chat_hot : @ui.Style = zp_bar_chat.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let zp_bar_chat_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// Its station (barStation): 12, subtle, its mark 12 before its name.
// kept across runs: a value (no field of it changes)
let zp_bar_station : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zp_bar_station_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
let zp_station_mark : Double = 12.0

///|
let zp_drop_station : Int = 1

///|
// kept across runs: a value (no field of it changes)
let zp_bar_actions : @ui.Style = @ui.css("row gap=SPx align=ACenter")

///|
/// 待定, 不再提醒 (barButton): 28 high, 10 in, 12 in the muted ink; the text's and the ground under the pointer; faint
/// while it cannot be pressed.
// kept across runs: a value (no field of it changes)
let zp_button : @ui.Style = @ui.css("row h=S7 px=S2_5 radius=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zp_button_hot : @ui.Style = zp_button.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let zp_button_off : @ui.Style = zp_button.then(@ui.css("opacity=O40"))

///|
// kept across runs: a value (no field of it changes)
let zp_button_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let zp_button_words_hot : @ui.TextStyle = zp_button_words.then(@ui.text_style(color=Fg))

///|
/// The deck under the bar (deck): what is left, what leaves drawn over it, cut at its edges.
// kept across runs: a value (no field of it changes)
let zp_deck : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)

///|
/// One decision (card): all of the deck, on the canvas (it covers what is under it).
// kept across runs: a value (no field of it changes)
let zp_card : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let zp_card_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Its rows (scroll, column): 24 over the first, 20 apart, 32 in from the deck's sides; the column the chat's width (760
/// at most) in the middle.
// kept across runs: a value (no field of it changes)
let zp_row : @ui.Style = @ui.css("w=Full px=S8 pt=S5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zp_row_first : @ui.Style = @ui.css("w=Full px=S8 pt=S6 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zp_column : @ui.Style = @ui.style(w=Full, max_w=@sf.notice_w)

///|
/// About how tall a row stands before it is laid out.
let zp_row_est : Double = 90.0

///|
/// The room under the last row over the foot (scroll: 12 and the foot's height).
let zp_foot_gap : Double = 12.0

///|
/// Who is to decide (settledLine): 12 on 18, subtle.
// kept across runs: a value (no field of it changes)
let zp_assignee : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle)

///|
/// The foot (foot): 8 over the composer, 16 under it, 32 in, the composer in the middle.
// kept across runs: a value (no field of it changes)
let zp_foot : @ui.Style = @ui.css("w=Full px=S8 pt=S2 pb=S4 align=ACenter")

///|
/// In a panel of its own (the tape's): the composer as far from its foot as from its sides (composer_side), in its
/// foot corners concentric with it.
fn zp_foot_tape() -> @ui.Style {
  zp_foot.then(@ui.style(pb=@sf.room_of(composer_side())))
}

///|
/// The way to its chat (elsewhere): the column's width, 38 high, 14 in, on the chips' grey, 13 medium.
// kept across runs: a value (no field of it changes)
let zp_elsewhere : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.elsewhere_h,
  px=S3_5,
  radius=Xl,
  bg=Neutral,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let zp_elsewhere_hot : @ui.Style = zp_elsewhere.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let zp_elsewhere_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// Nothing come yet and why (empty): in the middle, 13 muted.
// kept across runs: a value (no field of it changes)
let zp_empty : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let zp_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let zp_waiting : @ui.Style = @ui.css("w=Full h=Full px=S8 pt=S6")

///|
/// How the next comes in (arriving: from 12 under at 98%, 240 ms) and how the one before goes (flyOff: up 360 ms to 88%
/// by 40% of the way; across 260 ms, 24 past the deck's edge).
pub let zou_rise_ms : Double = 240.0

///|
let zou_rise_dy : Double = 12.0

///|
let zou_rise_scale : Double = 0.98

///|
let zou_up_ms : Double = 360.0

///|
let zou_off_ms : Double = 260.0

///|
let zou_off_more : Double = 24.0

///|
let zou_gathered : Double = 0.88

///|
/// None left (idle, column): scrolling in the deck, 32 by 24 in; the column 560 at most in the middle, 28 apart.
// kept across runs: a value (no field of it changes)
let zi_idle : @ui.Style = @ui.css("w=Full h=Full px=S6 py=S8 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let zi_column : @ui.Style = @ui.style(w=Full, max_w=@sf.idle_column_w, gap=S7)

///|
/// Its head (head): its face (72), the title (16, 600, 22) 6 under it, the note (13 muted), the figures 10 under them.
// kept across runs: a value (no field of it changes)
let zi_head : @ui.Style = @ui.css("w=Full gap=S1_5 align=ACenter")

///|
let zi_face : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let zi_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, leading=L6, center=true)

///|
// kept across runs: a value (no field of it changes)
let zi_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, center=true)

///|
/// The day in numbers (stats, stat): 32 apart, each a figure (22 on 26, 600) over its words (12 on 16, subtle).
// kept across runs: a value (no field of it changes)
let zi_stats : @ui.Style = @ui.css("row pt=S2_5 gap=S8 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let zi_stat_box : @ui.Style = @ui.css("gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let zi_figure : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let zi_figure_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, color=Subtle, wrap=false)

///|
/// A section (section, sectionTitle): its rows 2 apart under its title (12 on 18, 500, subtle, 10 in).
// kept across runs: a value (no field of it changes)
let zi_section : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let zi_section_title : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, leading=L5, color=Subtle)

///|
/// A row (row): 8 by 10 in, its mark 10 before its words, its ground under the pointer.
// kept across runs: a value (no field of it changes)
let zi_row_box : @ui.Style = @ui.css("row w=Full px=S2_5 py=S2 gap=S2_5 radius=Lg align=AStart")

///|
// kept across runs: a value (no field of it changes)
let zi_row_hot : @ui.Style = zi_row_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let zi_busy_room : @ui.Style = @ui.css("pt=S1")

///|
let zi_busy : Double = 12.0

///|
let zi_busy_ink : Int64 = 0xF2B01EFFL

///|
/// Answered: a quiet dot (done: 6, 7 down, 3 in).
// kept across runs: a value (no field of it changes)
let zi_done : @ui.Style = @ui.css("w=S1_5 h=S1_5 mt=S2 mx=S0_5 radius=Full bg=Subtle")

///|
// kept across runs: a value (no field of it changes)
let zi_words : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let zi_main : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, leading=L5, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let zi_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let zi_when : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)
