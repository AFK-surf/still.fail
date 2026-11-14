// What a post asks, under it in its chat on the desktop (still.fail web/src/Decisions.tsx MessageDecision,
// DecisionOptions; Chat.tsx AskDismiss; Decisions.css.ts decision, options, settledLine; Chat.css.ts askDismiss): who
// decides, then the options while it waits for the viewer (numbered, pressing one answers with it: decision.answer);
// once settled, how it went in one quiet line. A login card stays as its login goes; an agent's request about a vault
// item is answered on its own card. 忽略 lets go what no one has decided (decision.dismiss). Answered or let go, on
// screen or not, what is under the post changes from that moment (sfbase's list_turns.mbt Turns::in_turn, `start`):
// the options, 忽略 with them, fade out as their room closes, and the line saying how it went comes in their place, its
// room opening as theirs closes, its words fading in after them (sfbase's under_post.mbt).

///|
/// Under post `m` of chat `here` (thread `thread`; None while nothing can be sent there), what it asks; `turns`: its
/// list's, which says from when what is under the post changed.
fn message_decision(c : @ui.Ctx, src : Source, here : MessageHere, m : Message, turns : Turns?) -> Unit {
  match (m.card, here.core) {
    (Some(card), Some(core)) if card.kind == "login" && card.login != "" => {
      let open = match m.decision {
        Some(d) => !d.resolved && !d.dismissed
        None => true
      }
      c.box(style=decision_box, fn() {
        match card.assignee_text {
          Some(a) if open => c.text(a, style=settled_line) |> ignore
          _ => ()
        }
        // (on the chat's station, or another of its workspace: the card's)
        let station = if card.station == "" {
          here.station
        } else {
          match here.station.find("/") {
            Some(i) => here.station.exact_view(end=i).to_owned() + "/" + card.station
            None => card.station
          }
        }
        login_card(c, core, station, card.login)
        // (letting it go: under it while it is asked, as under a post with no card)
        ask_dismiss(c, src, here, m.seq, m.asked, false)
      })
      |> ignore
      return
    }
    _ => ()
  }
  // a post that asks with no card (an agent's need): 忽略 alone under it while it is asked (Chat.tsx: AskDismiss
  // beside no MessageDecision)
  if m.card is None && m.options is None {
    if m.asked {
      c.box(style=decision_box, fn() { ask_dismiss(c, src, here, m.seq, m.asked, false) }) |> ignore
    }
    return
  }
  // an agent's request about a vault item that says what it is: its card is in place of the words (message.mbt)
  if m.card is Some({ ask: Some(_), .. }) || m.card is Some({ phone: Some(_), .. }) || m.card is Some({ signin: Some(_), .. }) || m.card is Some({ rig: Some(_), .. }) {
    return
  }
  let resolved = match m.decision {
    Some(d) => d.resolved || d.dismissed
    None => false
  }
  let options = match m.card {
    Some(card) => if card.kind == "options" { card.options } else { None }
    None => m.options
  }
  let key = here.station + "/" + m.ts
  // (answered or let go: open no more from that moment, on screen or not; `start_at` when it changed, what goes and
  // comes under it moving from then)
  let open = match turns {
    Some(tu) => tu.in_turn(c, "ask/" + m.ts, !resolved)
    None => !resolved
  }
  let start_at = match turns {
    Some(tu) => tu.start("ask/" + m.ts)
    None => None
  }
  let thread = if here.view.offline || here.view.archived { None } else { here.view.thread }
  // (what comes and goes under it, each room holding the room over it: closed, nothing of it is left, a gap between
  // rooms none of which shows with them; decision_box's gap would stay till the last frame of a close, then go at once)
  c.box(style=decision_rooms, fn() {
    under_post(
      c,
      "options/" + key,
      open,
      exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
      close=close_gap,
      start_at?,
      fn() {
        c.box(style=decision_box, fn() {
          // (who decides; answered, it fades out where it is as the options close round it: the one picked is
          // marked among the options as they go, an answer in words is the viewer's row under them, nothing to say
          // again (the user, 2026-10-29: 有个勾不就行了吗); let go, 已忽略 in its place, the one fading out, then the
          // other in: chat_rows.mbt said_in_place)
          match m.card {
            Some({ assignee_text: Some(a), .. }) => {
              let went = match m.decision {
                Some({ dismissed: true, text: Some(w), .. }) => Some(w)
                _ => None
              }
              let (was, now) = said_in_place(c, "who/" + key, resolved)
              let i = c.text(if was is Some(_) { a } else { went.unwrap_or(a) }, style=settled_line)
              c.look(i, match was {
                Some(l) => l
                None => if went is Some(_) { now } else { @ui.look(alpha=0.0) }
              })
            }
            _ => ()
          }
          match m.card {
            // an agent's request for a vault item: approved here, not answered in words
            Some({ vault, assignee, .. }) if vault != "" =>
              match here.core {
                Some(core) => @settings.vault_actions(c, core, workspace_of(here.station), vault, mine_to(here, assignee))
                None => ()
              }
            _ =>
              match (options, thread) {
                (Some(list), Some(th)) if list.length() > 0 => decision_options(c, src, here, m, th, list, resolved, on_pick=fn(i) {
                    // the answer's row comes in as the core has it, the list following its end for it, as for words
                    // sent. An option that closes the card says nothing: no row comes, the list is not asked to follow
                    match turns {
                      Some(_) if !list[i].closes => {
                        // (asked of the list: its key names it only where it is built, not in this row)
                        reading_of(here.station + "\u{1}" + here.session).end_asked = true
                      }
                      _ => ()
                    }
                  })
                _ => ()
              }
          }
        })
        |> ignore
      },
    )
    ask_dismiss(c, src, here, m.seq, m.asked, resolved, asking=open, asked_at=start_at, lead=true)
    // (in their place as they close, from the same moment)
    let outcome = match m.decision {
      Some({ text: Some(words), .. }) if resolved && !open => Some(words)
      _ => None
    }
    under_post(
      c,
      "outcome/" + key,
      outcome is Some(_),
      start_at?,
      enter=@motion.trans(
        fade=0.0,
        spec=@motion.Snap(0.0),
        fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
      ),
      open=close_gap,
      exit=@motion.trans(spec=@motion.Snap(0.0)),
      close=@motion.Snap(0.0),
      fn() {
        match outcome {
          Some(w) => {
            match options {
              Some(list) if list.length() > 0 => {
                let chosen = match m.decision {
                  Some(d) => d.chosen
                  None => None
                }
                c.box(style=settled_room, fn() {
                  let line = c.sp(c.theme().leading(settled_leading).unwrap_or(c.text_size(settled_size).1))
                  let id = @sf.ask_history_trigger(c, "options/" + key, [@ui.span(w)], settled_line, line)
                  card_history(c, id, padded=false, fn(p) {
                    @sf.options_card(
                      p,
                      "history-options/" + key,
                      list.map(fn(o) { (o.label, o.detail, o.recommended) }),
                      false,
                      None,
                      chosen=list.search_by(fn(o) { Some(o.label) == chosen }),
                      history=true,
                    )
                  })
                }) |> ignore
              }
              _ => c.text(w, style=settled_line) |> ignore
            }
          }
          None => ()
        }
      },
    )
  })
  |> ignore
}

///|
/// A result's read-only history: a press on the line opens it in a panel (a sheet on a small screen), the original
/// card's content rather than its now-inactive actions. Only a press: no hover card as well, two boxes of the same
/// (the user, 2026-11-03: 「改成只允许点击吧」).
fn card_history(c : @ui.Ctx, id : Int, padded? : Bool = true, body : (@ui.Ctx) -> Unit) -> Unit {
  c.on_press(id, fn() {
    @sf.panel(
      @sf.t("web-main.history.details"),
      fn(p, _) {
        if padded {
          p.box(style=@sf.panel_words_in(), fn() { body(p) }) |> ignore
        } else {
          body(p)
        }
      },
      from=Of(id),
    )
  })
}

///|
/// An agent's request about a vault item, in place of its post `m`'s words: what is asked as a
/// card, as wide as what it says (320 at least where there is the room), its answer
/// at its foot as the core said it with the message (`ask.answer`: the vault it holds), so
/// the card is whole as it comes; once decided, one line saying how it ended. In a chat's list, decided, on screen or
/// not, the card fades out as its room closes from that moment and the line comes in its place, its room opening, its
/// words fading in after the card, as a post's answered options do (message_decision, Turns::in_turn). Where nothing is
/// answered (no core: a letter's), the card without its answer.
fn vault_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : VaultAsk) -> Unit {
  let asked : Asked = {
    name: ask.name,
    reason: ask.reason,
    timeout_kind: ask.timeout_kind,
    timeout_seconds: ask.timeout_seconds,
    approved_timeout_kind: ask.approved_timeout_kind,
    approved_timeout_seconds: ask.approved_timeout_seconds,
    mode: ask.mode,
    command: ask.command,
    how_text: ask.how_text,
    save_kind: ask.save_kind,
    username: ask.username,
    filename: ask.filename,
    typed: ask.typed,
    station: ask.station,
    describe: ask.describe,
    new_name: ask.new_name,
    new_about: ask.new_about,
    was_about: ask.was_about,
    remove: ask.remove,
  }
  let decided = ask.status != ""
  // (a file the person picks: as wide as it may be from the first, what is picked coming in beside its button with
  // nothing moving)
  let room = if ask.typed && ask.save_kind == "file" { @sf.ask_card_room_most } else { @sf.ask_card_room }
  let asking = fn() {
    c.box(style=room.then(ask_card_under_head), fn() {
      match here.core {
        Some(core) =>
          @settings.vault_card(
            c,
            core,
            workspace_of(here.station),
            card.vault,
            asked,
            @settings.card_answer(ask.answer, ask.lasts, mine_to(here, card.assignee), who=card.assignee_text),
            ended=if decided { Some((ask.status, ask.scope)) } else { None },
          )
        None => @settings.vault_ask_words(c, asked)
      }
    })
    |> ignore
  }
  let ended = fn(history : (String, (Int) -> Unit)?) {
    @settings.vault_outcome(c, asked, ask.status, ask.scope, inline=here.inline, history~)
  }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "vault/" + m.ts, !decided)
      let start_at = l.turns.start("vault/" + m.ts)
      under_post(
        c,
        "vault-card/" + key,
        open,
        exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
        close=close_gap,
        start_at?,
        asking,
      )
      under_post(
        c,
        "vault-ended/" + key,
        decided && !open,
        start_at?,
        enter=@motion.trans(
          fade=0.0,
          spec=@motion.Snap(0.0),
          fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
        ),
        open=close_gap,
        exit=@motion.trans(spec=@motion.Snap(0.0)),
        close=@motion.Snap(0.0),
        fn() {
          ended(Some(("vault/" + key, fn(id) {
            card_history(c, id, fn(p) {
              @settings.vault_ask_details(p, asked)
            })
          })))
        },
      )
    }
    None => if decided { ended(None) } else { asking() }
  }
}

///|
/// An agent's request for its person's phone in place of its post's words: its card while it waits
/// (answered with `adb.decide` on the chat's station), then a line saying how it went: decided, the card goes and the
/// line comes in its place from that moment (vault_ask_card's).
fn phone_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : PhoneAsk) -> Unit {
  let decided = ask.status != ""
  let asking = fn() {
    c.box(style=@sf.ask_card_room.then(ask_card_under_head), fn() {
      @settings.phone_card(c, here.core, here.station, ask.request, ask.reason, mine_to(here, card.assignee), lasts=ask.lasts, who=card.assignee_text, ended=if decided { Some((ask.status, ask.scope, ask.why)) } else { None }, how=fn() { open_page(Setting(@settings.Route::AdbShare(""))) })
    })
    |> ignore
  }
  // (granted: how its station holds the phone, and on the phone, what is left to do for it a press away)
  let ended = fn(history : (String, (Int) -> Unit)?) {
    let mine = mine_to(here, card.assignee)
    let link = @settings.phone_link(here.core, here.station, ask.link)
    let step = match here.core {
      Some(core) if ask.status == "granted" && mine && @settings.phone_lends(c) => @settings.adb_step_at(c, core, here.station).map(fn(s) { (core, s) })
      _ => None
    }
    @settings.phone_outcome(c, ask.status, ask.scope, ask.why, inline=here.inline, link~, step_here=step is Some(_), history~)
    // (on the phone, the first thing left, as a login's card is under its message: the card does it, never a page about
    // it, and changes to the next as each is done, going once the station holds the phone; one the phone cannot do,
    // its own prompt's or the station's, said with nothing to press)
    match step {
      Some((core, s)) =>
        // (its line how, or why it is not done by itself; never the page's button's words: the card is the press)
        step_card(c, "phone-step/" + m.ts, s.title, s.sub, go=if s.act == "" {
          None
        } else {
          Some(fn() { @settings.adb_do(core, s.act, station=here.station) })
        })
      None => ()
    }
  }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "phone/" + m.ts, !decided)
      let start_at = l.turns.start("phone/" + m.ts)
      under_post(
        c,
        "phone-card/" + key,
        open,
        exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
        close=close_gap,
        start_at?,
        asking,
      )
      under_post(
        c,
        "phone-ended/" + key,
        decided && !open,
        start_at?,
        enter=@motion.trans(
          fade=0.0,
          spec=@motion.Snap(0.0),
          fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
        ),
        open=close_gap,
        exit=@motion.trans(spec=@motion.Snap(0.0)),
        close=@motion.Snap(0.0),
        fn() {
          ended(Some(("phone/" + key, fn(id) {
            card_history(c, id, fn(p) {
              @sf.ask_words(p, @sf.t("android-misc.adb.ask.chat.title"), ask.reason)
            })
          })))
        },
      )
    }
    None => if decided { ended(None) } else { asking() }
  }
}

///|
/// An agent's request for a rig of the workspace in place of its post's words (a station that only runs tasks): its card while it waits
/// (answered by the rig's person with `rig.decide` on the chat's station), then a line saying how it went: decided,
/// the card goes and the line comes in its place from that moment (phone_ask_card's).
fn rig_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : RigAsk) -> Unit {
  let decided = ask.status != ""
  let granted = (ask.granted_kind, ask.granted_seconds)
  let words = fn() { @settings.rig_outcome_words(ask.status, ask.why, ask.delivered, granted) }
  let asking = fn() {
    c.box(style=@sf.ask_card_room.then(ask_card_under_head), fn() {
      @settings.rig_card(
        c,
        here.core,
        here.station,
        ask.request,
        ask.name,
        ask.reason,
        (ask.timeout_kind, ask.timeout_seconds),
        {
          "rig": Json::string(ask.rig),
          "name": Json::string(ask.name),
          "session": Json::string(ask.session),
          "chat": Json::string(ask.chat),
          "title": Json::string(ask.title),
          "by": Json::string(ask.by),
          "device": Json::string(ask.device),
          "deviceName": Json::string(ask.device_name),
        },
        mine_to(here, card.assignee),
        device=ask.device_name,
        who=card.assignee_text,
        ended=if decided { Some((ask.status == "granted", words())) } else { None },
        lock=fn() { open_page(Setting(@settings.Route::AdbShare(""))) },
      )
    })
    |> ignore
  }
  let ended = fn(history : (String, (Int) -> Unit)?) {
    @settings.rig_outcome(c, ask.status, ask.why, ask.delivered, granted, inline=here.inline, history~)
  }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "rig/" + m.ts, !decided)
      let start_at = l.turns.start("rig/" + m.ts)
      under_post(
        c,
        "rig-card/" + key,
        open,
        exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
        close=close_gap,
        start_at?,
        asking,
      )
      under_post(
        c,
        "rig-ended/" + key,
        decided && !open,
        start_at?,
        enter=@motion.trans(
          fade=0.0,
          spec=@motion.Snap(0.0),
          fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
        ),
        open=close_gap,
        exit=@motion.trans(spec=@motion.Snap(0.0)),
        close=@motion.Snap(0.0),
        fn() {
          ended(Some(("rig/" + key, fn(id) {
            card_history(c, id, fn(p) {
              @sf.ask_words(p, @sf.t("web-pages.rigs.ask.title", args=[("name", ask.name)]), ask.reason)
            })
          })))
        },
      )
    }
    None => if decided { ended(None) } else { asking() }
  }
}

///|
/// Whether what is asked of `assignee` is the viewer's to answer (anyone's where it names no one).
fn mine_to(here : MessageHere, assignee : String) -> Bool {
  let me = here.view.me
  assignee == "" || me == "" || assignee.to_lower() == me.to_lower()
}

///|
/// A post's options in one card, numbered (DecisionOptions: the library's options card, as wide as what it says);
/// pressing one answers with it (`decision.answer`), the one being sent turning; settled, none pressed any more, the
/// one picked as it was. `on_pick`: told of the one picked (its place among them) first.
pub fn decision_options(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  m : Message,
  thread : Double,
  options : Array[Choice],
  resolved : Bool,
  on_pick? : (Int) -> Unit = fn(_) {  },
) -> Unit {
  let on = [
    ("station", here.station),
    ("thread", thread.to_int().to_string()),
    ("seq", m.seq.to_int().to_string()),
  ]
  // the one on its way (the core's doing: its option)
  let mut busy : Int? = None
  for d in items(src.topic("doing", {}).get().value, "doing") {
    let dv = Some(d)
    if text(dv, "call") == "decision.answer" && text(dv, "stage") != "failed" {
      let params = field(dv, "params")
      if on.iter().all(fn(kv) { text(params, kv.0) == kv.1 }) {
        busy = options.search_by(fn(o) { o.label == text(params, "option") })
      }
    }
  }
  let chosen = if resolved {
    match m.decision {
      Some({ chosen: Some(label), .. }) => options.search_by(fn(o) { o.label == label })
      _ => None
    }
  } else {
    None
  }
  // as wide as what it says, as wide as where it is at most
  c.box(style=options_room, fn() {
    @sf.options_card(
      c,
      "options/" + m.ts,
      options.map(fn(o) { (o.label, o.detail, o.recommended) }),
      !resolved,
      if resolved { None } else { busy },
      chosen~,
      wide=true,
      on_pick=fn(i) {
        let label = options[i].label
        on_pick(i)
        // picked, felt as something done (a no as something refused: act)
        @ui.haptic(Confirm)
        act(src, @sf.t("web-main.decisions.answerWhat", args=[("option", label)]), "", "decision.answer", {
          "station": Json::string(here.station),
          "thread": Json::number(thread),
          "seq": Json::number(m.seq),
          "option": Json::string(label),
        })
      },
    )
  })
  |> ignore
}

///|
/// 忽略 under what asks what no one has decided, post `seq` of the chat (`asked`: the core's, on the post or the chat's
/// `stateAsk`): the viewer lets it go (`decision.dismiss`),
/// let go at once and back if that fails. Let go, on screen or not, it goes from that moment (Turns::in_turn,
/// `own_at`), fading and shrinking to 85% as its room closes (the archive buttons' 280 ms, ArchiveEase); the card
/// answered, it goes so with the options (`asking` false, from `asked_at`).
fn ask_dismiss(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  seq : Double,
  asked : Bool,
  resolved : Bool,
  asking? : Bool = true,
  asked_at? : Double? = None,
  at_end? : Bool = false,
  lead? : Bool = false,
) -> Unit {
  guard here.view.thread is Some(thread) && !here.view.offline && !here.view.archived else { return }
  if !asked && !resolved {
    return
  }
  let k = seq_key(here.station, thread, seq)
  // (answered, it goes with the options, from their moment; let go here, from its own)
  // (at the end of a card, no motion of its own: the card's, as the core says it let go)
  let (mine, own_at) = match here.list {
    Some(l) if !at_end => {
      (l.turns.in_turn(c, "dismiss/" + k, !dismissed.has(k)), l.turns.start("dismiss/" + k))
    }
    _ => (!dismissed.has(k), None)
  }
  // (its room while it has one; pressed while it is asked, not let go nor answered)
  let shown = asking && mine
  let live = shown && !resolved && !dismissed.has(k)
  let at = if !asking { asked_at } else { own_at }
  let id = c.id("ask-dismiss/" + k)
  c.on_press(id, fn() {
    if live {
      dismissed.add(k)
      // let go, felt as an answer picked is
      @ui.haptic(Confirm)
      act(
        src,
        @sf.t("web-main.decisions.dismissWhat"),
        "",
        "decision.dismiss",
        { "station": Json::string(here.station), "thread": Json::number(thread), "seq": Json::number(seq) },
        failed=fn() { dismissed.remove(k) },
      )
    }
  })
  // (at the end of the card: there until the card goes, as the core says it let go; pressed once)
  if at_end {
    if asking {
      need_dismiss(c, "ask-dismiss/" + k, live)
    }
    return
  }
  let hot = live && c.hovered(id)
  under_post(
    c,
    "dismiss/" + k,
    shown,
    exit=@motion.trans(fade=0.0, scale=archive_scale, ox=0.0, oy=0.0, spec=archive_tween),
    start_at?=at,
    lead~,
    fn() {
      // (let go or answered: faded out where it is as its room closes)
      let look = @motion.presence(c, "dismiss-live/" + k, live, enter=@motion.trans(fade=0.0, spec=archive_tween))
      let b = c.box(style=dismiss_room, id=if live { id } else { 0 }, fn() {
        c.rich([@ui.span(@sf.t("web-main.chat.asks.dismiss"), underline=hot)], style=if hot {
          dismiss_words_hot
        } else {
          dismiss_words
        })
        |> ignore
      })
      c.look(b, look.unwrap_or(@ui.look(alpha=0.0)))
      @motion.leaving(c, b, live)
    },
  )
}

///|
/// 忽略 at the end of the line saying what the chat needs (`at_end`; `live` it takes a press, else faded where it was):
/// quiet words to press ending the line's row, a button's room round them (@sf.ask_line_button).
fn need_dismiss(c : @ui.Ctx, key : String, live : Bool) -> Unit {
  @sf.ask_line_button(c, @sf.t("web-main.chat.asks.dismiss"), key~, mark=state_icon, disabled=!live) |> ignore
}

///|
/// What was let go here (by its post: seq_key), gone at once: back if letting it go failed. Read by member, so that
/// a chat's row kept as its nodes is built again as its 忽略 is pressed, and only that row.
// kept across runs: put back by rows_reset
pub let dismissed : @signals.Keyed[String] = @signals.keyed()

///|
/// What is under a post (decision): 8 under its words, at the column's start.
// kept across runs: a value (no field of it changes)
let decision_box : @ui.Style = @ui.css("w=Full gap=S1_5 align=AStart")

///|
/// What comes and goes under a post with options (its options, 忽略, how it went): rooms with no gap of their own
/// between them, the one that needs one holding it (under_post's `lead`).
// kept across runs: a value (no field of it changes)
let decision_rooms : @ui.Style = @ui.css("w=Full align=AStart")

///|
/// The options: 8 over them.
// kept across runs: a value (no field of it changes)
let options_room : @ui.Style = @ui.css("w=Full pt=S0_5 align=AStart")

///|
/// How it was settled, who decides (settledLine): 12 on 18, the subtle ink.
// kept across runs: a value (no field of it changes)
let settled_line : @ui.TextStyle = @ui.text_style(size=settled_size, leading=settled_leading, color=Subtle)

///|
// kept across runs: a value (no field of it changes)
let settled_size : @ui.TextSize = Meta

///|
// kept across runs: a value (no field of it changes)
let settled_leading : @ui.Leading = L5

///|
// kept across runs: a value (no field of it changes)
let settled_room : @ui.Style = @ui.css("align=AStart")

///|
/// 忽略 (askDismiss): 6 under the options, 12 on 18 in the subtle ink, the text's and underlined under the pointer.
// kept across runs: a value (no field of it changes)
let dismiss_room : @ui.Style = @ui.css("pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let dismiss_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dismiss_words_hot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false)

///|
/// An agent's request as its card in place of its post's words: a little under the post's head, as a card under a
/// post's words is, not on it as a line of words is (over @sf.ask_card_room or its room for a file).
// kept across runs: a value (no field of it changes)
let ask_card_under_head : @ui.Style = @ui.css("mt=S2")
