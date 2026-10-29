// What a post asks, under it in its chat on the desktop (ember web/src/Decisions.tsx MessageDecision,
// DecisionOptions; Chat.tsx AskDismiss; Decisions.css.ts decision, options, settledLine; Chat.css.ts askDismiss): who
// decides, then the options while it waits for the viewer (numbered, pressing one answers with it: decision.answer);
// once settled, how it went in one quiet line. A login card stays as its login goes; an agent's request about a vault
// item is answered on its own card. 忽略 lets go what no one has decided (decision.dismiss). Answered on screen, a card
// stays as it is, none of it pressed any more, and becomes its line once out of sight (sfbase's list_turns.mbt
// Turns::in_turn): the list's height changes only for what comes.

///|
/// Whether post `seq` of chat `here` (None: where the chat stands) was on screen in its list as the frame before left
/// it (Reading::sees); never out of a chat's list.
fn seen_in(c : @ui.Ctx, here : MessageHere, seq : Double?) -> Bool {
  match here.list {
    Some(l) => reading_of(l.rk).sees(c.frame_number(), seq)
    None => false
  }
}

///|
/// Under post `m` of chat `here` (thread `thread`; None while nothing can be sent there), what it asks; `turns`: its
/// list's, what closes takes its turn there.
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
            Some(i) => here.station.view(end_offset=i).to_string() + "/" + card.station
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
  if m.card is Some({ ask: Some(_), .. }) || m.card is Some({ phone: Some(_), .. }) {
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
  // answered, what is under it stays as it is while it is on screen, the one picked marked, none pressed, 忽略 faded
  // in its room; out of sight its options and 忽略 are gone, how it went in their place, at once
  let open = match turns {
    Some(tu) => tu.in_turn(c, "ask/" + m.ts, !resolved, close_turn_ms, seen=seen_in(c, here, Some(m.seq)))
    None => !resolved
  }
  let start_at = match turns {
    Some(tu) => tu.start("ask/" + m.ts)
    None => None
  }
  let thread = if here.view.offline || here.view.archived { None } else { here.view.thread }
  c.box(style=decision_box, fn() {
    under_post(
      c,
      "options/" + key,
      open,
      exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
      close=close_gap,
      start_at?,
      fn() {
        c.box(style=decision_box, fn() {
          // (who decides; answered while it shows, it fades out where it is, its room kept: the one picked is
          // marked among the options, an answer in words is the viewer's row under them, nothing to say again (the
          // user, 2026-10-29: 有个勾不就行了吗); let go, 已忽略 in its place, the one fading out, then the other in:
          // chat_rows.mbt said_in_place)
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
            // an agent's request for a vault item: approved here (VaultApproval.tsx), not answered in words
            Some({ vault, assignee, .. }) if vault != "" =>
              match here.core {
                Some(core) => @settings.vault_actions(c, core, workspace_of(here.station), vault, mine_to(here, assignee))
                None => ()
              }
            _ =>
              match (options, thread) {
                (Some(list), Some(th)) if list.length() > 0 => decision_options(c, src, here, m, th, list, resolved, on_pick=fn(i) {
                    // the answer's row comes in first, in a turn kept for it now, they close in the next; the list
                    // following its end for it, as for words sent (Decisions.tsx DecisionOptions' pick). An option
                    // that closes the card says nothing: no row comes, nothing waits for one
                    match turns {
                      Some(tu) if !list[i].closes => {
                        tu.keep_turn(c)
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
    ask_dismiss(c, src, here, m.seq, m.asked, resolved, asking=open, asked_at=start_at)
    // (in their place once they close: in the same turn)
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
            let id = c.id("outcome-options/" + key)
            c.box(style=settled_room, fn() {
              c.box(id~, fn() { c.text(w, style=settled_line) |> ignore }) |> ignore
            }) |> ignore
            match options {
              Some(list) if list.length() > 0 => {
                let chosen = match m.decision {
                  Some(d) => d.chosen
                  None => None
                }
                hover(c, "outcome-options/" + key, id, padded=false, fn() {
                  @sf.options_card(
                    c,
                    "history-options/" + key,
                    list.map(fn(o) { (o.label, o.detail, o.recommended) }),
                    false,
                    None,
                    chosen=list.search_by(fn(o) { Some(o.label) == chosen }),
                    history=true,
                  ) |> ignore
                }) |> ignore
              }
              _ => ()
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
/// An agent's request about a vault item, in place of its post `m`'s words (VaultAsk.tsx VaultAsk): what is asked as a
/// card, as wide as what it says (320 at least where there is the room, 560 at most: VaultAsk.css.ts card), its answer
/// at its foot as the core said it with the message (`ask.answer`: the vault it holds; VaultApproval.tsx VaultCard), so
/// the card is whole as it comes; once decided, one line saying how it ended. In a chat's list, decided on screen, the
/// card stays as it is, the answer given marked and none pressed any more, and is that line once out of sight, as a
/// post's answered options are (message_decision, Turns::in_turn). Where nothing is answered (no core: a letter's, the
/// 奏 page's, which answers it under the post), the card without its answer.
fn vault_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : VaultAsk) -> Unit {
  let asked : Asked = {
    name: ask.name,
    mode: ask.mode,
    command: ask.command,
    save_kind: ask.save_kind,
    username: ask.username,
    filename: ask.filename,
    typed: ask.typed,
    station: ask.station,
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
  let ended = fn() { @settings.vault_outcome(c, asked, ask.status, ask.scope, inline=here.inline) }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "vault/" + m.ts, !decided, close_turn_ms, seen=seen_in(c, here, Some(m.seq)))
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
        ended,
      )
    }
    None => if decided { ended() } else { asking() }
  }
}

///|
/// An agent's request for its person's phone in place of its post's words (docs/adb-share.md): its card while it waits
/// (answered with `adb.decide` on the chat's station), then a line saying how it went: decided on screen, the card
/// stays, the answer given marked, till it is out of sight (vault_ask_card's).
fn phone_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : PhoneAsk) -> Unit {
  let decided = ask.status != ""
  let asking = fn() {
    c.box(style=@sf.ask_card_room.then(ask_card_under_head), fn() {
      @settings.phone_card(c, here.core, here.station, ask.request, ask.reason, mine_to(here, card.assignee), lasts=ask.lasts, who=card.assignee_text, ended=if decided { Some((ask.status, ask.scope, ask.why)) } else { None }, how=fn() { open_page(Setting(@settings.Route::AdbShare(""))) })
    })
    |> ignore
  }
  let ended = fn() { @settings.phone_outcome(c, ask.status, ask.scope, ask.why, inline=here.inline) }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "phone/" + m.ts, !decided, close_turn_ms, seen=seen_in(c, here, Some(m.seq)))
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
        ended,
      )
    }
    None => if decided { ended() } else { asking() }
  }
}

///|
/// Whether what is asked of `assignee` is the viewer's to answer (anyone's where it names no one).
pub fn mine_to(here : MessageHere, assignee : String) -> Bool {
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
  for d in items((src.topic)("doing", {}).value, "doing") {
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
    match
      @sf.options_card(
        c,
        "options/" + m.ts,
        options.map(fn(o) { (o.label, o.detail, o.recommended) }),
        !resolved,
        if resolved { None } else { busy },
        chosen~,
        wide=true,
      ) {
      Some(i) if !resolved => {
        let label = options[i].label
        // (the 奏 page sends the decision on its way first: DecisionOptions' onPick)
        on_pick(i)
        c.tell("options/" + m.ts, fn() {
          act(src, @sf.t("web-main.decisions.answerWhat", args=[("option", label)]), "", "decision.answer", {
            "station": Json::string(here.station),
            "thread": Json::number(thread),
            "seq": Json::number(m.seq),
            "option": Json::string(label),
          })
        })
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// 忽略 under what asks what no one has decided, post `seq` of the chat (`asked`: the core's, on the post or the chat's
/// `stateAsk`; `state`: shown where the chat stands, not under the post): the viewer lets it go (`decision.dismiss`),
/// let go at once and back if that fails. Let go, or the card answered, on screen it fades where it is (the archive
/// buttons' 280 ms, ArchiveEase), its room kept; out of sight it is gone, its room with it (Turns::in_turn), with the
/// options once the card is answered (`asking` false, from `asked_at`).
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
  state? : Bool = false,
) -> Unit {
  guard here.view.thread is Some(thread) && !here.view.offline && !here.view.archived else { return }
  if !asked && !resolved {
    return
  }
  let k = seq_key(here.station, thread, seq)
  // (answered, it goes with the options, in their turn; let go here, in a turn of its own)
  // (at the end of a card, no motion of its own: the card's, as the core says it let go)
  let (mine, own_at) = match here.list {
    Some(l) if !at_end => {
      let seen = seen_in(c, here, if state { None } else { Some(seq) })
      (l.turns.in_turn(c, "dismiss/" + k, !dismissed.contains(k), dismiss_turn_ms, seen~), l.turns.start("dismiss/" + k))
    }
    _ => (!dismissed.contains(k), None)
  }
  // (its room while it has one; pressed while it is asked, not let go nor answered)
  let shown = asking && mine
  let live = shown && !resolved && !dismissed.contains(k)
  let at = if !asking { asked_at } else { own_at }
  let id = c.id("ask-dismiss/" + k)
  if live && c.clicked(id) {
    dismissed[k] = true
    c.tell("ask-dismiss/" + k, fn() {
      act(
        src,
        @sf.t("web-main.decisions.dismissWhat"),
        "",
        "decision.dismiss",
        { "station": Json::string(here.station), "thread": Json::number(thread), "seq": Json::number(seq) },
        failed=fn() { dismissed.remove(k) |> ignore },
      )
    })
  }
  let hot = live && c.hovered(id)
  // (at the end of the card: there until the card goes, as the core says it let go; pressed once)
  if at_end {
    if asking {
      let words = @sf.t("web-main.chat.asks.dismiss")
      // (on the card row's lines, level with its first line and the bell: ask_line_words; a press reaches it from
      // round it, press_reach)
      let look = @sf.theme().chat_list
      let b = c.box(id=if live { id } else { 0 }, fn() {
        let said = (if hot { look.state_turn } else { look.state_quiet }).then(dismiss_end)
        c.text(words, style=@sf.ask_line_words(said)) |> ignore
      })
      if live {
        c.semantics(b, Button, id~, label=words)
      }
    }
    return
  }
  under_post(
    c,
    "dismiss/" + k,
    shown,
    exit=@motion.trans(fade=0.0, scale=archive_scale, ox=0.0, oy=0.0, spec=archive_tween),
    start_at?=at,
    fn() {
      // (let go or answered on screen: faded where it is, its room kept till it is out of sight)
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
/// What was let go here (by its post: seq_key), gone at once: back if letting it go failed.
pub let dismissed : Map[String, Bool] = {}

///|
/// What is under a post (decision): 8 under its words, at the column's start.
// kept across runs: a value (no field of it changes)
let decision_box : @ui.Style = @ui.css("w=Full gap=S1_5 align=AStart")

///|
/// The options (Decisions.css.ts options): 8 over them.
// kept across runs: a value (no field of it changes)
let options_room : @ui.Style = @ui.css("w=Full pt=S0_5 align=AStart")

///|
/// How it was settled, who decides (settledLine): 12 on 18, the subtle ink.
// kept across runs: a value (no field of it changes)
let settled_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle)

///|
// kept across runs: a value (no field of it changes)
let settled_room : @ui.Style = @ui.css("align=AStart")

///|
/// 忽略 (askDismiss): 6 under the options, 12 on 18 in the subtle ink, the text's and underlined under the pointer.
// kept across runs: a value (no field of it changes)
let dismiss_room : @ui.Style = @ui.css("pt=S0_5")

///|
/// 忽略 at the end of the card saying what the chat needs (`at_end`): the line's words, as wide as they are, the quiet
/// ink and the line's own under the pointer, its room the card row's (ask_line_card), not padding of its own.
// kept across runs: a value (no field of it changes)
let dismiss_end : @ui.TextStyle = @ui.text_style(w=Hug, wrap=false)

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
