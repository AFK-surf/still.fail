// What a post asks under it in a chat's list (decision.mbt's message_decision) as nodes of the window's tree, made once:
// who decides, its options in one card (the library's options_card_node), 忽略, and, answered, how it went in their
// place, a press away from the card as it was. Each comes and goes in a room of its own opening and closing with it
// (under_post's), from the change that brings it. A login's or a vault item's card, the settings' old views, islands.

///|
/// What post `m` asks under it (decision_kind): nothing (0), a login's or a vault item's card (1: the old view, an
/// island), its options (2), 忽略 alone (3: what asks with no card).
fn decision_kind(m : Message, core : Bool) -> Int {
  match m.card {
    Some(card) if card.kind == "login" && card.login != "" && core => return 1
    // (an agent's request about a vault item, its phone, a sign-in: its card in place of the words, message.mbt)
    Some({ ask: Some(_), .. }) | Some({ phone: Some(_), .. }) | Some({ signin: Some(_), .. }) => return 0
    Some({ vault, .. }) if vault != "" => return 4
    _ => ()
  }
  if m.card is None && m.options is None {
    return if m.asked { 3 } else { 0 }
  }
  2
}

///|
/// What post `m` (as it is now) asks under it in `d`, in chat `here`'s list.
fn decision_node(d : @view.View, src : Source, here : () -> MessageHere, m : () -> Message) -> Unit {
  d.pick(fn() { decision_kind(m(), here().core is Some(_)) }, fn(b, which) {
    // (what it holds at its start, as wide as it is; a login's or a vault item's card across the column, as wide as
    // what it says inside that by its own rules (560 at most): login_card's; its options' card as the wide frame's, as
    // wide as what it says and 460 at least, the column at most: options_room's)
    b.lines_up(Is(if which == 3 { Some(Start) } else { None })) |> ignore
    match which {
      1 => login_decision_node(b, src, here, m)
      2 => decision_options_node(b, src, here, m)
      4 => vault_decision_node(b, here, m)
      3 => dismiss_node(b, src, here, fn() { m().seq }, fn() { m().asked }, fn() { false }, fn() { true }, false)
      _ => ()
    }
  })
}

///|
/// A post's options under it (message_decision's): who decides over them, the card; 忽略 under it while it is asked;
/// answered, what is under it fading out where it is and its room closing, how it went coming in its place.
fn decision_options_node(b : @view.View, src : Source, here : () -> MessageHere, m : () -> Message) -> Unit {
  let resolved = fn() {
    match m().decision {
      Some(d) => d.resolved || d.dismissed
      None => false
    }
  }
  let options = fn() {
    let now = m()
    match now.card {
      Some(card) => if card.kind == "options" { card.options } else { None }
      None => now.options
    }
  }
  let thread = fn() {
    let h = here()
    if h.view.offline || h.view.archived { None } else { h.view.thread }
  }
  let open = fn() { !resolved() }
  under_node(b, open, fn(u) {
    u.gap(Is(6.0)).lines_up(Is(None)) |> ignore
    // (who decides; answered while it shows, it says how it was let go in its place, the one fading out, the other in)
    u.show(fn() { m().card is Some({ assignee_text: Some(_), .. }) }, fn(w) { who_node(w, m, resolved) })
    u.show(fn() { options().map(fn(l) { l.length() > 0 }).unwrap_or(false) && thread() is Some(_) }, fn(o) {
      o.padding(Is((0.0, 2.0, 0.0, 0.0))).lines_up(Is(None)) |> ignore
      decision_card_node(o, src, here, m, fn() { options().unwrap_or([]) }, resolved, fn() { thread().unwrap_or(0.0) })
    })
  })
  dismiss_node(b, src, here, fn() { m().seq }, fn() { m().asked }, resolved, open, true)
  // (in their place once they close: their room opening as theirs closes, its words fading in after theirs are out)
  let outcome = fn() {
    match m().decision {
      Some({ text: Some(words), .. }) if resolved() => Some(words)
      _ => None
    }
  }
  under_node(b, fn() { outcome() is Some(_) }, fades_in=true, fn(u) {
    u.lines_up(Is(Some(Start))) |> ignore
    let chosen = fn() {
      match m().decision {
        Some(d) => d.chosen
        None => None
      }
    }
    u.pick(fn() { options().map(fn(l) { l.length() > 0 }).unwrap_or(false) }, fn(line, card) {
      let words = fn() { outcome().unwrap_or("") }
      if !card {
        settled_words_node(line, words)
        return
      }
      // (a press opens the card as it was, the one picked checked, none pressed)
      history_line_node(line, words, fn(at) {
        let list = @signals.untracked(fn() { options().unwrap_or([]) })
        let picked = @signals.untracked(chosen)
        let key = @signals.untracked(fn() { here().station + "/" + m().ts })
        @sf.panel(
          @sf.t("web-main.history.details"),
          fn(p, _) {
            @sf.options_card(
              p,
              "history-options/" + key,
              list.map(fn(o) { (o.label, o.detail, o.recommended) }),
              false,
              None,
              chosen=list.search_by(fn(o) { Some(o.label) == picked }),
              history=true,
            )
            |> ignore
          },
          from=at,
        )
      })
    })
  })
}

///|
/// Who decides (settled_line's), in `w`; once let go, what the core said of that in its place, the one fading out
/// (options_out_ms, Leave) and the other in after it (as long, Out): said_in_place's.
fn who_node(w : @view.View, m : () -> Message, resolved : () -> Bool) -> Unit {
  let who = fn() {
    match m().card {
      Some({ assignee_text: Some(a), .. }) => a
      _ => ""
    }
  }
  let went = fn() {
    match m().decision {
      Some({ dismissed: true, text: Some(t), .. }) => Some(t)
      _ => None
    }
  }
  let first = @signals.untracked(resolved)
  let was = @motion.Way::new(if first { 0.0 } else { 1.0 })
  let now = @motion.Way::new(if first { 1.0 } else { 0.0 })
  w.reacts(resolved, fn(r) {
    let at = w.cause_at()
    if r {
      was.go(0.0, @motion.tween(options_out_ms, ease=Leave), at~)
      now.go(1.0, @motion.tween(options_out_ms, ease=Out, delay=options_out_ms), at~)
    } else {
      was.put(1.0)
      now.put(0.0)
    }
  })
  // (its words as wide as they are, at its start: decision_box's align=AStart, the column round it stretching only
  // the options under it (options_room's w=Full))
  w.lines_up(Is(Some(Start))) |> ignore
  w.box(fn(a) {
    settled_words_node(a, who)
    a.alpha(By(fn() { way_shown(was, a) })) |> ignore
  })
  |> ignore
  w.show(fn() { way_shown(was, w) <= 0.0 && went() is Some(_) }, fn(n) {
    n.over(Is(true)) |> ignore
    settled_words_node(n, fn() { went().unwrap_or("") })
    n.alpha(By(fn() { way_shown(now, n) })) |> ignore
  })
}

///|
/// A line saying how something was settled, in `v` (settled_line's: 12 on 18, the subtle ink).
fn settled_words_node(v : @view.View, words : () -> String) -> Unit {
  v
  .words(By(words))
  .words_look(By(fn() { @ui.style_words(settled_line) }))
  .ink(By(fn() { @ui.style_ink(settled_line) }))
  |> ignore
}

///|
/// How it went, a line to press for the card as it was (ask_history_trigger's): its words, a chevron after them lit
/// under the pointer or the focus (dur_ms); `open` told the window's rectangle it is in.
fn history_line_node(line : @view.View, words : () -> String, open : (@sf.Anchor) -> Unit) -> Unit {
  let lit = @motion.Way::new(0.0)
  line.reacts(fn() { line.pointed() || line.focused() }, fn(on) {
    lit.go(if on { 1.0 } else { 0.0 }, @motion.tween(@sf.dur_ms, ease=Out), at=line.cause_at())
  })
  line
  .row(Is(true))
  .gap(Is(4.0))
  .lines_up(Is(Some(Start)))
  .says(By(fn() { Some(@view.said(Button, label=words() + " · " + @sf.t("web-main.history.details"))) }))
  |> ignore
  // (beside where it is on screen as it is pressed)
  @sf.presses_node(line, fn() {
    match line.shown_rect() {
      Some((x, y, w, h)) => open(At(x, y, w, h))
      None => open(Unanchored)
    }
  })
  line.box(fn(t) { settled_words_node(t, words) }) |> ignore
  line.box(fn(mark) {
    mark
    .height(By(fn() { Some(@ui.style_words(settled_line).line) }))
    .lies_along(Is(Middle))
    |> ignore
    @sf.icon_node(mark, "chevron-right", 12.0, By(fn() {
      let t = @sf.theme()
      @sf.mix(t.p.text, way_shown(lit, mark), t.p.muted)
    }))
    |> ignore
  })
  |> ignore
}

///|
/// The options card of post `m` (decision_options'): as wide as what it says, pressing one answers with it
/// (`decision.answer`), the one on its way turning; settled, none pressed, the one picked checked.
fn decision_card_node(
  o : @view.View,
  src : Source,
  here : () -> MessageHere,
  m : () -> Message,
  options : () -> Array[Choice],
  resolved : () -> Bool,
  thread : () -> Double,
) -> Unit {
  let on = fn() {
    [
      ("station", here().station),
      ("thread", thread().to_int().to_string()),
      ("seq", m().seq.to_int().to_string()),
    ]
  }
  // (the one on its way: the core's doing, its option)
  let busy = fn() {
    if resolved() {
      return None
    }
    let on = on()
    let list = options()
    let mut busy = None
    for d in items((src.topic)("doing", {}).value, "doing") {
      let dv = Some(d)
      if text(dv, "call") == "decision.answer" && text(dv, "stage") != "failed" {
        let params = field(dv, "params")
        if on.iter().all(fn(kv) { text(params, kv.0) == kv.1 }) {
          busy = list.search_by(fn(o) { o.label == text(params, "option") })
        }
      }
    }
    busy
  }
  let chosen = fn() {
    if !resolved() {
      return None
    }
    match m().decision {
      Some({ chosen: Some(label), .. }) => options().search_by(fn(o) { o.label == label })
      _ => None
    }
  }
  // (its agent in a turn: the station refuses closing the card meanwhile)
  let locked = fn() { !resolved() && m().decision is Some({ locked: true, .. }) }
  @sf.options_card_node(
    o,
    fn() { options().map(fn(c) { (c.label, c.detail, c.recommended) }) },
    fn() { !resolved() },
    busy,
    fn(i) {
      guard options().get(i) is Some(c) else { return }
      let h = here()
      // (an answer in words comes as the viewer's row, asked of the list's end; one that closes the card says none)
      if !c.closes && h.list is Some(_) {
        reading_of(h.station + "\u{1}" + h.session).end_asked.set(true)
      }
      @ui.haptic(Confirm)
      act(src, @sf.t("web-main.decisions.answerWhat", args=[("option", c.label)]), "", "decision.answer", {
        "station": Json::string(h.station),
        "thread": Json::number(thread()),
        "seq": Json::number(m().seq),
        "option": Json::string(c.label),
      })
    },
    chosen~,
    wide=true,
    waits=fn() {
      let l = locked()
      options().map(fn(c) { l && c.closes })
    },
    waits_why=fn() { @sf.t("web-main.decisions.locked") },
  )
  |> ignore
}

///|
/// 忽略 under what asks (ask_dismiss's) in `b`: while `asking` and not let go here; the viewer lets it go
/// (`decision.dismiss`), gone at once and back if that fails. Let go or answered, it fades where it is (archive_tween)
/// and its room closes. `lead`: the gap over it in its room.
fn dismiss_node(
  b : @view.View,
  src : Source,
  here : () -> MessageHere,
  seq : () -> Double,
  asked : () -> Bool,
  resolved : () -> Bool,
  asking : () -> Bool,
  lead : Bool,
) -> Unit {
  let thread = fn() {
    let h = here()
    if h.view.offline || h.view.archived { None } else { h.view.thread }
  }
  let key = fn() {
    match thread() {
      Some(th) => Some(seq_key(here().station, th, seq()))
      None => None
    }
  }
  // (let go here: as `dismissed` keeps it, told the nodes)
  let gone = @signals.signal(0, same=fn(a, b) { a == b })
  let let_go = fn() {
    gone.get() |> ignore
    match key() {
      Some(k) => dismissed.contains(k)
      None => false
    }
  }
  let shown = fn() { key() is Some(_) && (asked() || resolved()) && asking() && !let_go() }
  let live = fn() { shown() && !resolved() }
  under_node(b, shown, lead~, scale_out=archive_scale, out=archive_tween, about=(0.0, 0.0), fn(u) {
    u.box(fn(w) {
      let hot = fn() { live() && w.pointed() }
      // (let go or answered on screen: faded where it is from that change, as its room goes too (main's dismiss-live
      // presence, archive_tween), the two looks one over the other)
      let lit = @motion.Way::new(if @signals.untracked(live) { 1.0 } else { 0.0 })
      w.reacts(live, fn(on) { lit.go(if on { 1.0 } else { 0.0 }, archive_tween, at=w.cause_at()) })
      w
      .alpha(By(fn() { way_shown(lit, w) }))
      .padding(Is((0.0, 2.0, 0.0, 0.0)))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.asks.dismiss"))) }))
      |> ignore
      w.box(fn(words) {
        words
        .words_runs(By(fn() { [@ui.span(@sf.t("web-main.chat.asks.dismiss"), underline=hot())] }))
        .words_look(By(fn() { @ui.style_words(if hot() { dismiss_words_hot } else { dismiss_words }) }))
        .ink(By(fn() { @ui.style_ink(if hot() { dismiss_words_hot } else { dismiss_words }) }))
        |> ignore
      })
      |> ignore
      @sf.presses_node(w, on=live, fn() {
        guard key() is Some(k) && thread() is Some(th) else { return }
        dismissed[k] = true
        gone.set(@signals.untracked(fn() { gone.get() }) + 1)
        @ui.haptic(Confirm)
        act(
          src,
          @sf.t("web-main.decisions.dismissWhat"),
          "",
          "decision.dismiss",
          { "station": Json::string(here().station), "thread": Json::number(th), "seq": Json::number(seq()) },
          failed=fn() {
            dismissed.remove(k) |> ignore
            gone.set(@signals.untracked(fn() { gone.get() }) + 1)
          },
        )
      })
    })
    |> ignore
  })
}

///|
/// What comes and goes under a post (under_post's) in `parent`, `body` making it, shown as `shown` says: its room
/// opening and closing on a Move as long as it is tall, what is in it in the middle of its room, cut at both ends.
/// Coming, there at once (`fades_in`: its words fading in after what goes in its place, options_out_ms each); going,
/// fading out where it is, `scale_out` as small as it has gone about `about`, by `out`. All from the change that does it.
fn under_node(
  parent : @view.View,
  shown : () -> Bool,
  body : (@view.View) -> Unit,
  lead? : Bool = false,
  fades_in? : Bool = false,
  scale_out? : Double = options_scale,
  out? : @motion.Spec = @motion.tween(options_out_ms, ease=options_ease),
  about? : (Double, Double) = (0.5, 0.5),
) -> Unit {
  let first = @signals.untracked(shown)
  let room = @motion.Way::new(if first { 1.0 } else { 0.0 })
  let seen = @motion.Way::new(if first { 1.0 } else { 0.0 })
  let inner : Ref[@view.View?] = Ref(None)
  // (how tall it is laid out at its cause's moment: how far its room moves, View::laid_size)
  let tall = fn() { inner.val.map(fn(v) { v.laid_size().1 }).unwrap_or(0.0) }
  // (at rest once both are where they go, as under_rest asks)
  let n = @sfbase.under_goes_told(fn() {
    let now = parent.logic_at()
    let ends = [room, seen].filter(fn(w) { w.goes_at(now) }).map(fn(w) { w.ends_at() })
    ends.fold(init=-1.0, fn(a, b) { if b > a { b } else { a } })
  })
  parent.owns(fn() { @sfbase.under_goes.remove(n) |> ignore }) |> ignore
  let was_on = Ref(first)
  let was_way : Ref[(Double, Double)?] = Ref(None)
  parent.reacts(fn() { (shown(), @ui.row_way_node(parent)) }, fn(now) {
    let (on, way) = now
    let at = parent.cause_at()
    let far = @signals.untracked(tall)
    let to = if on { 1.0 } else { 0.0 }
    // (a change within a row shares the list's height curve, including a later start while sent words leave;
    // another cause while it goes puts its remaining part on the same new way as the other rows)
    if on != fades_in {
      room.put(to)
    } else if room.target() != to || (room.goes_at(at) && way is Some(_) && was_way.val != way) {
      match way {
        Some((start, ms)) => {
          let delay = dmax(0.0, start - at)
          room.go(to, @sfbase.under_row_spec(ms, delay), at=if delay > 0.0 { at } else { start }, velocity=0.0)
        }
        None => room.go(to, @motion.move(over=far), at~)
      }
    }
    was_way.val = way
    // (the look belongs to this change alone; joining another row's height motion must not fade it in again)
    if on != was_on.val {
      if on {
        if fades_in {
          seen.put(0.0)
          seen.go(1.0, @motion.tween(options_out_ms, ease=Leave, delay=options_out_ms), at~)
        } else {
          seen.put(1.0)
        }
      } else if fades_in {
        seen.put(0.0)
      } else {
        seen.go(0.0, out, at~)
      }
      was_on.val = on
    }
  })
  parent.show(fn() { shown() || way_shown(room, parent) > 0.0 }, fn(r) {
    // (cut at both ends as it opens and closes, fading out to them: under_post's reveal)
    r.opens(By(fn() { Some(dmin(1.0, way_shown(room, r))) })).clips(By(fn() { way_shown(room, r) < 1.0 }))
    .cuts_softly(By(fn() { way_shown(room, r) < 1.0 })) |> ignore
    // (what it holds as big as its room is open and faded in from half open, about the middle of what it draws: a list's
    // row coming and going where it is, under_post's reveal `middle`, @motion.reveal_node's)
    r.box(fn(held) {
    held
    .scale(By(fn() { dmax(0.0, dmin(1.0, way_shown(room, held))) }), about=Drawn)
    .alpha(By(fn() {
      let k = way_shown(room, held)
      if k >= 1.0 { 1.0 } else { dmax(0.0, (k - @ui.row_gone_at) / (1.0 - @ui.row_gone_at)) }
    }))
    |> ignore
    held.box(fn(u) {
      inner.val = Some(u)
      u.owns(fn() { inner.val = None }) |> ignore
      u
      .padding(Is((0.0, if lead { 6.0 } else { 0.0 }, 0.0, 0.0)))
      .alpha(By(fn() { way_shown(seen, u) }))
      .scale(By(fn() { if shown() { 1.0 } else { scale_out + (1.0 - scale_out) * way_shown(seen, u) } }), about=At(
        about.0,
        about.1,
      ))
      |> ignore
      // The leading room belongs to this block; the body's own inset (dismiss_room's, for example) is inside it.
      u.box(body) |> ignore
    })
    |> ignore
    })
    |> ignore
  })
}

///|
/// An agent's request for a vault item under post `m` (message_decision's): who decides over it, and its answer at its
/// foot from the vaults topic (settings' vault_actions_node), its room closing as it is answered.
fn vault_decision_node(b : @view.View, here : () -> MessageHere, m : () -> Message) -> Unit {
  let resolved = fn() {
    match m().decision {
      Some(d) => d.resolved || d.dismissed
      None => false
    }
  }
  under_node(b, fn() { !resolved() }, fn(u) {
    u.gap(Is(6.0)).lines_up(Is(None)) |> ignore
    u.show(fn() { m().card is Some({ assignee_text: Some(_), .. }) }, fn(w) { who_node(w, m, resolved) })
    match @signals.untracked(here).core {
      Some(core) => {
        let card = @signals.untracked(m).card.unwrap()
        u.box(fn(a) {
          a.padding(Is((0.0, 2.0, 0.0, 0.0))) |> ignore
          @settings.vault_actions_node(a, core, workspace_of(@signals.untracked(here).station), card.vault, fn() {
            mine_to(here(), m().card.map(fn(c) { c.assignee }).unwrap_or(""))
          })
        })
        |> ignore
      }
      None => ()
    }
  })
}

///|
/// A login's card under post `m` (message_decision's): who decides while it is open, the login's card (on the chat's
/// station or another of its workspace: the card's; login_card_node), and 忽略 under it while it is asked.
fn login_decision_node(b : @view.View, src : Source, here : () -> MessageHere, m : () -> Message) -> Unit {
  let card = @signals.untracked(m).card.unwrap()
  let open = fn() {
    match m().decision {
      Some(d) => !d.resolved && !d.dismissed
      None => true
    }
  }
  b.gap(Is(6.0)).lines_up(Is(Some(Start))) |> ignore
  b.show(fn() { open() && m().card is Some({ assignee_text: Some(_), .. }) }, fn(w) {
    settled_words_node(w, fn() {
      match m().card {
        Some({ assignee_text: Some(a), .. }) => a
        _ => ""
      }
    })
  })
  let h = @signals.untracked(here)
  let station = if card.station == "" {
    h.station
  } else {
    match h.station.find("/") {
      Some(i) => h.station.view(end_offset=i).to_owned() + "/" + card.station
      None => card.station
    }
  }
  match h.core {
    Some(core) =>
      b.box(fn(k) {
        k.width_share(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        login_card_node(k, core, station, card.login)
      })
      |> ignore
    None => ()
  }
  dismiss_node(b, src, here, fn() { m().seq }, fn() { m().asked }, fn() { false }, fn() { true }, false)
}
