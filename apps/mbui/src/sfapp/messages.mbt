// What a message asks, under it on the 奏 card (ember apps/android Decisions.kt DecisionUnder; SettingParts.kt
// DecisionOptions; LoginCards.kt LoginCard), as decide.mbt has it done, and the chat's colours. The messages themselves
// are drawn as their chat draws them, by sfpages' rows (message.mbt, message_files.mbt).
///|
/// What the rows need to know of the chat.
priv struct Here {
  station : String
  session : String
  view : ChatView
}

///|
/// The chat's own colours (ChatInk.kt): the wide screen's tokens over the phone's paper; `neutral` is its bubble.
priv struct Ink {
  text : Int64
  muted : Int64
  subtle : Int64
  neutral : Int64
  name : Int64
  card : Int64
  accent : Int64
  canvas : Int64
}

///|
fn ink() -> Ink {
  if @sf.theme().dark {
    {
      text: 0xE9E9EAFFL,
      muted: 0xA3A5A9FFL,
      subtle: 0x8C8F94FFL,
      neutral: 0x313237FFL,
      name: 0xFC9B6FFFL,
      card: 0x27282BFFL,
      accent: 0xF57E4DFFL,
      canvas: 0x1F2023FFL,
    }
  } else {
    {
      text: 0x24272BFFL,
      muted: 0x646970FFL,
      subtle: 0x73787DFFL,
      neutral: 0xE8E4DCFFL,
      name: 0xA23203FFL,
      card: 0xF6F6F7FFL,
      accent: 0xEF6A3CFFL,
      canvas: 0xFFFFFFFFL,
    }
  }
}

///|
/// Times in messages say how long ago; a tap on one says when, in all of them, until tapped again.

///|
/// The flight of words sent whose row is being built (flight.mbt), for its bubble and what is under it.
let flying : Ref[SendFlight?] = { val: None }

///|
/// System notices opened (all their words, and their time), by message.
let opened_notices : Map[String, Bool] = {}

///|
/// The press an image of a message was last quoted by (file_item): a passage of its message is not picked by it too.
let image_quoted_at : Ref[Int] = { val: -1 }

///|
/// The kind of a file by its name (FileKinds.kt kindOf): image, video, or anything else.
fn kind_of(name : String) -> String {
  let lower = @sf.lower(name)
  let ext = match lower.rev_find(".") {
    Some(i) if i > 0 => lower.view(start_offset=i + 1).to_string()
    _ => ""
  }
  match ext {
    "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "avif" | "bmp" | "ico" => "image"
    "mp4" | "m4v" | "webm" | "mov" | "ogv" => "video"
    _ => ""
  }
}



///|
/// The session whose workspace keeps a file: as the core says it, else the chat's first agent's.
fn owner_of(here : Here, a : Attachment) -> String {
  if a.owner != "" {
    a.owner
  } else {
    match here.view.agents.get(0) {
      Some(ag) => ag.key
      None => here.session
    }
  }
}

///|
/// Under a post (Decisions.kt DecisionUnder): a login card as its login stands; an options card's options while it
/// waits, who is to decide above them, a tap answering with one; once answered (or let go, or replaced) the options go
/// (200 ms, CSS's ease-out: fading, to 90%, the one picked as it was while the rest step back, their room closing on
/// the rows' spring a little late) and how it went comes in a quiet line in their place (fading in once they have
/// gone, its room opening on the same spring).
///
/// `asking`: what is under it shows as asking still (in a chat, till its turn to close comes: Turns::in_turn, from
/// `asked_at`); by default while it is not settled.
fn decision_under(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  asking? : Bool,
  asked_at? : Double = -1.0,
) -> Unit {
  let k = ink()
  let (quiet_size, quiet_line) = quiet_type()
  let quiet = fn(words : String) {
    c.box(pt=2.0, fn() { c.text(words, size=quiet_size, color=k.subtle, line=quiet_line) |> ignore })
    |> ignore
  }
  match m.card {
    Some(card) if card.kind == "login" && card.login != "" => {
      let open = match m.decision {
        Some(d) => !d.resolved && !d.dismissed
        None => true
      }
      if open {
        match card.assignee_text {
          Some(a) => quiet(a)
          None => ()
        }
      }
      let station = if card.station == "" {
        here.station
      } else {
        match here.station.find("/") {
          Some(i) => here.station.view(end_offset=i).to_string() + "/" + card.station
          None => card.station
        }
      }
      match workspace_in_view(src).0 {
        Some(w) => @sfpages.login_card(c, settings_core(src, w), station, card.login)
        None => ()
      }
      return
    }
    _ => ()
  }
  let options = match m.card {
    Some(card) => if card.kind == "options" { card.options } else { None }
    None => m.options
  }
  if m.card is None && m.options is None {
    return
  }
  // a vault request that says what it is: answered on its own card, in place of the words (vault_approval.mbt)
  if m.card is Some({ ask: Some(_), .. }) || m.card is Some({ phone: Some(_), .. }) {
    return
  }
  let resolved = match m.decision {
    Some(d) => d.resolved || d.dismissed
    None => false
  }
  let options = match options {
    Some(o) if o.length() > 0 => o
    _ => {
      let label = if resolved {
        match m.decision {
          Some(d) => d.text
          None => None
        }
      } else {
        match m.card {
          Some(card) => card.assignee_text
          None => None
        }
      }
      match label {
        Some(l) => quiet(l)
        None => ()
      }
      return
    }
  }
  let key = here.station + "/" + m.ts
  let open = asking.unwrap_or(!resolved)
  let start_at = if asked_at >= 0.0 { Some(asked_at) } else { None }
  let busy = answering(here.station, m, options)
  let chosen = if resolved {
    match m.decision {
      Some(d) => d.chosen
      None => None
    }
  } else {
    None
  }
  under_post(
    c,
    "options/" + key,
    open,
    exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
    close=close_gap,
    start_at?,
    fn() {
      // (who decides right over the options, 6 over them as Decisions.kt pads them, and the vault's request)
      c.box(w=Fill(1.0), align=AStart, fn() {
        match m.card {
          Some({ assignee_text: Some(a), .. }) => quiet(a)
          _ => ()
        }
        c.box(style=options_room, fn() {
          match m.card {
            // an agent's request for a vault item: approved here (Vault.kt), not answered in the chat
            Some({ vault, assignee, .. }) if vault != "" => {
              let ws = match here.station.find("/") {
                Some(i) => here.station.view(end_offset=i).to_string()
                None => here.station
              }
              let me = here.view.me
              vault_approval(c, src, ws, vault, assignee == "" || me == "" || assignee.to_lower() == me.to_lower())
            }
            _ =>
              match
                decision_options(
                  c,
                  "options/" + m.ts,
                  options,
                  !resolved && !here.view.offline && !here.view.archived,
                  busy,
                  chosen~,
                ) {
                Some(o) if !resolved => answer_option(src, here.station, m.thread, m.seq, o.label)
                _ => ()
              }
          }
        })
        |> ignore
      })
      |> ignore
    },
  )
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
        Some(w) => quiet(w)
        None => ()
      }
    },
  )
}

///|
/// The room over a post's options in its chat (Decisions.kt DecisionUnder: padding(top = 6) on the options' card, or
/// on the vault's request in their place).
// kept across runs: a value (no field of it changes)
let options_room : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
/// The quiet line over or in place of a post's options (who decides, how it went): 13 on 19 (Decisions.kt); the wide
/// frame's 12 on 18 (Decisions.css.ts settledLine).
fn quiet_type() -> (Double, Double) {
  (13.0, 19.0)
}

///|
/// A card of options (SettingParts.kt DecisionOptions; the wide frame's Decisions.css.ts options): the library's
/// (@sf.options_card), each a Choice; the one tapped, on the frame after. In the wide frame as wide as what it says
/// within the message's column.
fn decision_options(
  c : @ui.Ctx,
  key : String,
  options : Array[Choice],
  enabled : Bool,
  busy : String?,
  chosen? : String? = None,
) -> Choice? {
  let at = fn(label : String?) {
    match label {
      Some(l) => options.search_by(fn(o) { o.label == l })
      None => None
    }
  }
  let picked = @sf.options_card(
    c,
    key,
    options.map(fn(o) { (o.label, o.detail, o.recommended) }),
    enabled,
    at(busy),
    chosen=at(chosen),
  )
  match picked {
    Some(i) => Some(options[i])
    None => None
  }
}

///|
/// What an activity shows, steadied (Chat.kt steady): another thing replaces the shown one once it has stayed 700 ms
/// (a passing 请求中 does not flicker by); the same thing's new words show at once. Per row: what shows (its key, its
/// words), what showed before it, and when it came (the frames' clock).
priv struct Steady {
  mut key : String
  mut words : String
  mut was : String
  mut at : Double
}

///|
let steadies : Map[String, Steady] = {}

///|
/// How far an activity's ring reaches round its avatar (Chat.kt: the messages' 18dp avatar, its ring 3dp round it).
let ring_room : Double = 3.0

///|
/// An agent's ring round its avatar (Chat.kt WorkRing): at work, eight arcs in the accent, the brightest a step further
/// round every 100 ms (Spokes.kt); waiting on work it started, a still, quiet whole ring.
fn work_ring(c : @ui.Ctx, waiting : Bool) -> Unit {
  let t = @sf.theme()
  if waiting {
    c.box(w=Px(24.0), h=Px(24.0), radius=12.0, border=1.5, border_color=t.p.line, fn() {  }) |> ignore
  } else {
    @sf.segments(c, 24.0, 1.5, ink().accent, t.p.bg) |> ignore
  }
}

///|
/// The chat a row is of.
fn ref_of(here : Here) -> ChatRef {
  { station: here.station, session: here.session, title: here.view.title, station_name: "" }
}
