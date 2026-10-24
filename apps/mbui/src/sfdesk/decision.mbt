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
  let parts = chat_parts.val
  match m.card {
    Some(card) if card.kind == "login" && card.login != "" => {
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
        (parts.login_card)(c, src, station, card.login)
      })
      |> ignore
      return
    }
    _ => ()
  }
  if m.card is None && m.options is None {
    return
  }
  // an agent's request about a vault item that says what it is: its card is in place of the words (message.mbt)
  if m.card is Some({ ask: Some(_), .. }) {
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
  // answered, what is under it closes in its turn, its options and 忽略 together (after the answer has come in)
  let open = match turns {
    Some(tu) => tu.in_turn(c, "ask/" + m.ts, !resolved, close_turn_ms)
    None => !resolved
  }
  let thread = if here.view.offline || here.view.archived { None } else { here.view.thread }
  c.box(style=decision_box, fn() {
    if open {
      match m.card {
        Some({ assignee_text: Some(a), .. }) => c.text(a, style=settled_line) |> ignore
        _ => ()
      }
      match m.card {
        // an agent's request for a vault item: approved here (VaultApproval.tsx), not answered in words
        Some({ vault, assignee, .. }) if vault != "" => {
          let ws = match here.station.find("/") {
            Some(i) => here.station.view(end_offset=i).to_string()
            None => here.station
          }
          let me = here.view.me
          let mine = assignee == "" || me == "" || assignee.to_lower() == me.to_lower()
          @settings.vault_actions(c, (parts.vault_core)(src, ws), ws, vault, mine)
        }
        _ =>
          match (options, thread) {
            (Some(list), Some(th)) if list.length() > 0 => decision_options(c, src, here, m, th, list, resolved)
            _ => ()
          }
      }
      ask_dismiss(c, src, here, m, resolved)
    } else {
      match m.decision {
        Some({ text: Some(words), .. }) => c.text(words, style=settled_line) |> ignore
        _ => ()
      }
    }
  })
  |> ignore
  ignore(key)
}

///|
/// A post's options in one card, numbered (DecisionOptions: the library's options card, as wide as what it says);
/// pressing one answers with it (`decision.answer`), the one being sent turning; settled, none pressed any more, the
/// one picked as it was.
fn decision_options(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  m : Message,
  thread : Double,
  options : Array[Choice],
  resolved : Bool,
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
  c.box(style=options_room, fn() {
    match
      @sf.options_card(
        c,
        "options/" + m.ts,
        options.map(fn(o) { (o.label, o.detail, o.recommended) }),
        !resolved,
        busy,
        chosen~,
        wide=true,
        room=c.width,
      ) {
      Some(i) if !resolved => {
        let label = options[i].label
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
/// 忽略 under a post that asks what no one has decided (the core's `asked`): the viewer lets it go (`decision.dismiss`),
/// gone at once and back if that fails; answered, it goes with the options.
fn ask_dismiss(c : @ui.Ctx, src : Source, here : MessageHere, m : Message, resolved : Bool) -> Unit {
  guard here.view.thread is Some(thread) && !here.view.offline && !here.view.archived else { return }
  let key = seq_key(here.station, m.thread, m.seq)
  if !(m.asked || resolved) || dismissed.contains(key) {
    return
  }
  let id = c.id("ask-dismiss/" + m.ts)
  c.cursor(id, Hand)
  if c.clicked(id) {
    dismissed[key] = true
    c.tell("ask-dismiss/" + m.ts, fn() {
      act(
        src,
        @sf.t("web-main.decisions.dismissWhat"),
        "",
        "decision.dismiss",
        { "station": Json::string(here.station), "thread": Json::number(thread), "seq": Json::number(m.seq) },
        failed=fn() { dismissed.remove(key) },
      )
    })
  }
  let hot = c.hovered(id)
  c.box(style=dismiss_room, id~, fn() {
    c.rich([@ui.span(@sf.t("web-main.chat.asks.dismiss"), underline=hot)], style=if hot {
      dismiss_words_hot
    } else {
      dismiss_words
    })
    |> ignore
  })
  |> ignore
}

///|
/// What was let go here (by its post: seq_key), gone at once: back if letting it go failed.
let dismissed : Map[String, Bool] = {}

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
let settled_line : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle)

///|
/// 忽略 (askDismiss): 6 under the options, 12 on 18 in the subtle ink, the text's and underlined under the pointer.
// kept across runs: a value (no field of it changes)
let dismiss_room : @ui.Style = @ui.css("pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let dismiss_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dismiss_words_hot : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Fg, wrap=false)
