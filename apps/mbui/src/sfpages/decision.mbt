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
        ask_dismiss(c, src, here, m, false)
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
      c.box(style=decision_box, fn() { ask_dismiss(c, src, here, m, false) }) |> ignore
    }
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
                (Some(list), Some(th)) if list.length() > 0 => decision_options(c, src, here, m, th, list, resolved)
                _ => ()
              }
          }
        })
        |> ignore
      },
    )
    ask_dismiss(c, src, here, m, resolved, asking=open, asked_at~)
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
        fade_spec=@motion.tween(options_out_ms, ease=CssOut, delay=options_out_ms),
      ),
      open=close_gap,
      exit=@motion.trans(spec=@motion.Snap(0.0)),
      close=@motion.Snap(0.0),
      fn() {
        match outcome {
          Some(w) => c.text(w, style=settled_line) |> ignore
          None => ()
        }
      },
    )
  })
  |> ignore
}

///|
/// An agent's request about a vault item, in place of its post's words (VaultAsk.tsx VaultAsk): what is asked as a card,
/// as wide as what it says (320 at least where there is the room, 560 at most: VaultAsk.css.ts card), its answer at its
/// foot (VaultApproval.tsx VaultCard: the settings' vault_ask, the vault page's too, which fills its page); once
/// decided, one line saying how it ended. Where nothing is answered (no core: a letter's), the card without its answer.
fn vault_ask_card(c : @ui.Ctx, here : MessageHere, card : Card, ask : VaultAsk) -> Unit {
  let asked : Asked = {
    name: ask.name,
    mode: ask.mode,
    command: ask.command,
    save_kind: ask.save_kind,
    username: ask.username,
    station: ask.station,
  }
  if ask.status != "" {
    @settings.vault_outcome(c, asked, ask.status, ask.scope)
    return
  }
  c.box(style=@sf.ask_card_room, fn() {
    match here.core {
      Some(core) =>
        @settings.vault_ask(
          c,
          core,
          workspace_of(here.station),
          card.vault,
          asked,
          mine_to(here, card.assignee),
          who=card.assignee_text,
        )
      None => @settings.vault_ask_words(c, asked)
    }
  })
  |> ignore
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
/// one picked as it was.
pub fn decision_options(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  m : Message,
  thread : Double,
  options : Array[Choice],
  resolved : Bool,
  on_pick? : () -> Unit = fn() {  },
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
        on_pick()
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
/// gone at once and back if that fails. It goes as the archive buttons go (280 ms, ArchiveEase: fading, to 85% from its
/// top left, its room closing), in its turn among what changes the list's height, and with the options once the card
/// is answered (`asking` false, from `asked_at`).
fn ask_dismiss(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  m : Message,
  resolved : Bool,
  asking? : Bool = true,
  asked_at? : Double = -1.0,
) -> Unit {
  guard here.view.thread is Some(thread) && !here.view.offline && !here.view.archived else { return }
  if !m.asked && !resolved {
    return
  }
  let k = seq_key(here.station, m.thread, m.seq)
  // (answered, it goes with the options, in their turn; let go here, in a turn of its own)
  let (mine, own_at) = match here.list {
    Some(l) =>
      (l.turns.in_turn(c, "dismiss/" + k, !dismissed.contains(k), dismiss_turn_ms), l.turns.started_at("dismiss/" + k))
    None => (!dismissed.contains(k), -1.0)
  }
  let shown = asking && mine
  let at = if !asking { asked_at } else { own_at }
  let id = c.id("ask-dismiss/" + m.ts)
  if shown {
    c.cursor(id, Hand)
  }
  if shown && c.clicked(id) {
    dismissed[k] = true
    c.tell("ask-dismiss/" + m.ts, fn() {
      act(
        src,
        @sf.t("web-main.decisions.dismissWhat"),
        "",
        "decision.dismiss",
        { "station": Json::string(here.station), "thread": Json::number(thread), "seq": Json::number(m.seq) },
        failed=fn() { dismissed.remove(k) |> ignore },
      )
    })
  }
  let hot = shown && c.hovered(id)
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
/// 忽略 (askDismiss): 6 under the options, 12 on 18 in the subtle ink, the text's and underlined under the pointer.
// kept across runs: a value (no field of it changes)
let dismiss_room : @ui.Style = @ui.css("pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let dismiss_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dismiss_words_hot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false)
