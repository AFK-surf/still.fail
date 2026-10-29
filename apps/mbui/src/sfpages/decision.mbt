// What a post asks, under it in its chat on the desktop (ember web/src/Decisions.tsx MessageDecision,
// DecisionOptions; Chat.tsx AskDismiss; Decisions.css.ts decision, options, settledLine; Chat.css.ts askDismiss): who
// decides, then the options while it waits for the viewer (numbered, pressing one answers with it: decision.answer);
// once settled, how it went in one quiet line. A login card stays as its login goes; an agent's request about a vault
// item is answered on its own card. 忽略 lets go what no one has decided (decision.dismiss). What closes does so in its
// turn among what changes the list's height (sfbase's list_turns.mbt).

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
  // answered, what is under it closes in its turn, its options and 忽略 together (after the answer has come in): they
  // go (200 ms, fading to 90%, Decisions.css.ts), their room closing on the rows' spring a little late, how it went
  // fading in after them in their place
  let open = match turns {
    Some(tu) => tu.in_turn(c, "ask/" + m.ts, !resolved, close_turn_ms)
    None => !resolved
  }
  let asked_at = match turns {
    Some(tu) => tu.started_at("ask/" + m.ts)
    None => -1.0
  }
  let start_at = if asked_at >= 0.0 { Some(asked_at) } else { None }
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
          match m.card {
            Some({ assignee_text: Some(a), .. }) => c.text(a, style=settled_line) |> ignore
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
    ask_dismiss(c, src, here, m.seq, m.asked, resolved, asking=open, asked_at~)
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
/// the card is whole as it comes; once decided, one line saying how it ended. In a chat's list, decided, the card goes
/// in its turn among what changes the list's height, as a post's answered options do (message_decision: fading to 90%,
/// its room closing on the rows' spring a little late), how it went fading in after it in its place. Where nothing is
/// answered (no core: a letter's, the 奏 page's, which answers it under the post), the card without its answer.
fn vault_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : VaultAsk) -> Unit {
  let asked : Asked = {
    name: ask.name,
    mode: ask.mode,
    command: ask.command,
    save_kind: ask.save_kind,
    username: ask.username,
    typed: ask.typed,
    station: ask.station,
  }
  let decided = ask.status != ""
  let asking = fn() {
    c.box(style=@sf.ask_card_room, fn() {
      match here.core {
        Some(core) =>
          @settings.vault_card(
            c,
            core,
            workspace_of(here.station),
            card.vault,
            asked,
            @settings.card_answer(ask.answer, ask.lasts, mine_to(here, card.assignee), who=card.assignee_text),
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
      let open = l.turns.in_turn(c, "vault/" + m.ts, !decided, close_turn_ms)
      let at = l.turns.started_at("vault/" + m.ts)
      let start_at = if at >= 0.0 { Some(at) } else { None }
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
/// (answered with `adb.decide` on the chat's station), then a line saying how it went.
fn phone_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : PhoneAsk) -> Unit {
  let decided = ask.status != ""
  let asking = fn() {
    c.box(style=@sf.ask_card_room, fn() {
      @settings.phone_card(c, here.core, here.station, ask.request, ask.reason, mine_to(here, card.assignee), lasts=ask.lasts, who=card.assignee_text)
    })
    |> ignore
  }
  let ended = fn() { @settings.phone_outcome(c, ask.status, ask.scope, ask.why) }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "phone/" + m.ts, !decided, close_turn_ms)
      let at = l.turns.started_at("phone/" + m.ts)
      let start_at = if at >= 0.0 { Some(at) } else { None }
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
  let at = c.id("options-room/" + m.ts)
  let room = match c.laid_size(at) {
    Some((w, _)) => w
    None => 0.0
  }
  c.box(style=options_room, id=at, fn() {
    match
      @sf.options_card(
        c,
        "options/" + m.ts,
        options.map(fn(o) { (o.label, o.detail, o.recommended) }),
        !resolved,
        busy,
        chosen~,
        wide=true,
        room~,
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
/// `stateAsk`): the viewer lets it go (`decision.dismiss`), gone at once and back if that fails. It goes as the archive
/// buttons go (280 ms, ArchiveEase: fading, to 85% from its top left, its room closing), in its turn among what changes
/// the list's height, and with the options once the card is answered (`asking` false, from `asked_at`).
fn ask_dismiss(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  seq : Double,
  asked : Bool,
  resolved : Bool,
  asking? : Bool = true,
  asked_at? : Double = -1.0,
  at_end? : Bool = false,
) -> Unit {
  guard here.view.thread is Some(thread) && !here.view.offline && !here.view.archived else { return }
  if !asked && !resolved {
    return
  }
  let k = seq_key(here.station, thread, seq)
  // (answered, it goes with the options, in their turn; let go here, in a turn of its own)
  // (at the end of a card, no motion of its own: the card's, as the core says it let go)
  let (mine, own_at) = match here.list {
    Some(l) if !at_end =>
      (l.turns.in_turn(c, "dismiss/" + k, !dismissed.contains(k), dismiss_turn_ms), l.turns.started_at("dismiss/" + k))
    _ => (!dismissed.contains(k), -1.0)
  }
  let shown = asking && mine
  let at = if !asking { asked_at } else { own_at }
  let id = c.id("ask-dismiss/" + k)
  if shown && c.clicked(id) {
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
  let hot = shown && c.hovered(id)
  // (at the end of the card: there until the card goes, as the core says it let go; pressed once)
  if at_end {
    if asking {
      let words = @sf.t("web-main.chat.asks.dismiss")
      // (on the card row's lines, level with its first line and the bell: ask_line_words; a press reaches it from
      // round it, press_reach)
      let look = @sf.theme().chat_list
      let b = c.box(id=if shown { id } else { 0 }, fn() {
        let said = (if hot { look.state_turn } else { look.state_quiet }).then(dismiss_end)
        c.text(words, style=@sf.ask_line_words(said)) |> ignore
      })
      if shown {
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
    start_at?=if at >= 0.0 { Some(at) } else { None },
    fn() {
      c.box(style=dismiss_room, id=if shown { id } else { 0 }, fn() {
        c.rich([@ui.span(@sf.t("web-main.chat.asks.dismiss"), underline=hot)], style=if hot {
          dismiss_words_hot
        } else {
          dismiss_words
        })
        |> ignore
      })
      |> ignore
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
