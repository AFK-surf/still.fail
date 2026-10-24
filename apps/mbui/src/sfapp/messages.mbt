// A chat's messages as its page draws them (ember apps/android chat/screens/Chat.kt SaidRow, Bubble, SystemNotice,
// QuoteCards, SentElsewhere, Activity, UnreadLine; Prose.kt AgentWords; ChatFiles.kt Files, FileCard, ChatImage;
// Decisions.kt DecisionUnder; SettingParts.kt DecisionOptions; LoginCards.kt LoginCard). The viewer's words sit right in
// a bubble; everyone else gets a picture, a name and the time over their words; what still.fail itself says is a pill
// across the chat. What a message asks to be done (its options, letting it go, keeping or archiving the chat) is done
// from here as decide.mbt has it.

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
/// When it was said, small (Chat.kt MessageTime): how long ago, or when, in every message, after a tap on one.
fn message_time(c : @ui.Ctx, key : String, time : Stamp?) -> Unit {
  match time {
    None => ()
    Some(s) => {
      let id = c.id("time/" + key)
      if c.clicked(id) {
        absolute_times.val = !absolute_times.val
      }
      // the other way of saying it, on hover (ui.tsx Time: its Tip)
      @sf.tip(c, "time/" + key, id, if absolute_times.val { s.ago } else { s.full })
      c.box(id~, fn() {
        c.text(
          if absolute_times.val { s.full } else { s.ago },
          size=10.0,
          color=ink().muted,
          wrap=false,
          line=16.0,
        )
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// A message's picture (Chat.kt MessageAvatar): an agent's maker on the round grey ground, still.fail's mark, or a
/// person's face.
fn message_avatar(c : @ui.Ctx, src : Source, m : Message) -> Unit {
  match m.author_kind {
    "agent" => agent_avatar(c, m.by.maker, m.by.runtime)
    "ember" | "stillfail" => agent_avatar(c, "", "")
    _ => avatar(c, src, m.author, m.by.name, m.by.picture, 18.0)
  }
}

///|
/// An agent's picture in a chat (Chat.kt AgentAvatar): its model's maker (still.fail's mark without one), small on a
/// round grey ground.
fn agent_avatar(c : @ui.Ctx, maker : String, runtime : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Px(18.0), h=Px(18.0), radius=9.0, bg=ink().neutral, align=ACenter, justify=JCenter, fn() {
    if runtime != "" || maker != "" {
      @sf.maker_mark(c, maker, runtime, 12.0) |> ignore
    } else {
      @sf.drawable(
        c,
        if t.dark {
          "stillfail_mark_dark"
        } else {
          "stillfail_mark"
        },
        12.0,
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// A message (Chat.kt SaidRow): still.fail's own a notice across the chat; the viewer's on the right in a bubble;
/// anyone else's under their picture, name and time, an agent's as Markdown with its files placed in it, its tables
/// scrolling out to `bleed` past it either side.
fn said(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  list : Array[Entry],
  decide? : Bool = true,
  quotes? : Bool = false,
  bleed? : Double = 0.0,
) -> Unit {
  ignore(list)
  let k = ink()
  if m.system {
    system_notice(c, src, here.station, m)
    return
  }
  // whose it is as a quote of it says (MessagePick.kt: the viewer's own is 你)
  let who = if m.mine { tr("android-chat.annotate.you") } else { m.by.name }
  let role = if !m.mine && m.author_kind == "agent" { "agent" } else { "person" }
  // in the chat's list, its images held are quoted (MessagePick.kt QuotesImages)
  let quote = if quotes { Some(fn(a : Attachment) { quote_image(c, src, here, m.ts, who, role, a) }) } else { None }
  if m.mine {
    c.box(w=Fill(1.0), gap=4.0, align=AEnd, fn() {
      quote_cards(c, src, here, m.quotes, m.attachments, true)
      if m.text != "" {
        pickable(c, m.ts, who, role, m.text, false, fn() { bubble(c, m.text, m.ts) })
      }
      files(c, src, here, beside_quotes(m.quotes, m.attachments), true, quote~)
      if m.followed {
        ()
      } else {
        match m.blocked {
          Some(b) if b.state != "installed" => blocked_line(c, src, here.station, b)
          _ =>
            if m.waiting {
              under_way(c, tr("android-chat.chat.waitingAgent"))
            } else {
              // coming in with the words, when they fly here from the composer
              match flying.val {
                // (files sent alone: the row comes in where it is, its time with it)
                Some(f) if f.text != "" => {
                  let at = c.box(fn() { message_time(c, m.ts, m.time) })
                  c.look(at, @ui.look(alpha=flight_settled_of(c, f)))
                }
                _ => message_time(c, m.ts, m.time)
              }
            }
        }
      }
    })
    |> ignore
    return
  }
  let ek = here.station + "\u{1}" + here.session
  let em = emits_of(ek)
  c.box(w=Fill(1.0), fn() {
    let col = c.box(w=Fill(1.0), gap=4.0, align=AStart, fn() {
      // an agent of the chat's name opens its card (AgentSheet.kt)
      let mine = m.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == m.by.agent })
      let name = c.id("name/" + m.ts)
      if mine && c.clicked(name) {
        open_sheet(c, AgentOf(ref_of(here), m.by.agent))
      }
      // another chat's agent (session_send): its name opens that chat, by its link (Chat.tsx MessageRow `by.from`)
      let elsewhere = !mine && m.by.from != ""
      if elsewhere {
        c.cursor(name, Hand)
        if c.clicked(name) {
          open_link(m.by.from)
        }
      }
      said_head(c, m.by.name, if mine || elsewhere { name } else { 0 }, m.ts, m.time)
      quote_cards(c, src, here, m.quotes, m.attachments, false)
      if m.author_kind == "person" {
        if m.text != "" {
          pickable(c, m.ts, who, role, m.text, true, fn() { person_words(c, m.text, m.ts) })
        }
        files(c, src, here, beside_quotes(m.quotes, m.attachments), false, quote~)
      } else {
        pickable(c, m.ts, who, role, m.text, true, fn() { agent_words(c, src, here, m, quote~, bleed~) })
      }
      // what it asks, under it: not on the 奏 page, which has its options at its foot (Chat.kt SaidAlone)
      if !decide {
        return
      }
      // answered (or let go), what is under it for that closes in one turn among what changes the list's height
      // (turns.mbt), its options and 忽略 together, after the answer has come in (Chat.kt SaidRow: CLOSE_TURN_MS)
      let turns = turns_of(here.station + "\u{1}" + here.session)
      let resolved = match m.decision {
        Some(d) => d.resolved || d.dismissed
        None => false
      }
      let asking = turns.in_turn(c, "ask/" + m.ts, !resolved, close_turn_ms)
      let asked_at = turns.started_at("ask/" + m.ts)
      decision_under(c, src, here, m, asking~, asked_at~)
      // letting go what it asks (Chat.kt AskDismiss)
      ask_dismiss(c, src, here, m, asking, asked_at, turns)
    })
    // coming out of its agent's avatar (emit.mbt): from 35% at its corner, unrolling from its top
    if emit_goes(em, m.seq) {
      @motion.measure(c, col, "emit-col/" + seq_s(m.seq))
      emit_out(c, col, em, m.seq, 12.0)
    }
    // the picture over the name's start (where a message out of an avatar lands: hidden while the flying one is over it)
    c.layer(fn() {
      let av = said_avatar(c, fn() { message_avatar(c, src, m) })
      if emit_goes(em, m.seq) {
        @motion.measure(c, av, "emit-landing/" + ek + "/" + seq_s(m.seq))
        if emit_emitting(em, m.seq) {
          c.look(av, @ui.look(alpha=0.0))
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A message's head (Chat.kt SaidRow): in from the picture over its start (said_avatar), its name (15, 650, in the
/// chat's name colour, one line up to 240; `id` taps it) and when it was said. In the wide frame as the web's
/// (Chat.css.ts msgHead msgName): the picture out in the margin, the name where the words start, 13 in 600.
fn said_head(c : @ui.Ctx, name : String, id : Int, key : String, time : Stamp?) -> Unit {
  let k = ink()
  c.box(dir=Row, w=Fill(1.0), pl=head_in, min_h=24.0, gap=6.0, align=ACenter, fn() {
    c.box(max_w=240.0, id~, fn() {
      // (a mouse's pointer on one that opens something: the hand, as in the wide frame)
      if id != 0 {
        c.cursor(id, Hand)
      }
      c.text(name, size=15.0, weight=650, color=k.name, wrap=false, line=21.0) |> ignore
    })
    |> ignore
    message_time(c, key, time)
  })
  |> ignore
}

///|
/// How far a message's head stands in from its start: past the picture over it.
let head_in : Double = 25.0

///|
/// Where a message's picture goes, over its head's start (Chat.kt SaidRow: 3 down, centred on the name's line).
fn said_avatar(c : @ui.Ctx, body : () -> Unit, id? : Int = 0) -> Int {
  c.box(pt=3.0, id~, body)
}

///|
/// A spinner and a word, small, under a message of the viewer's (Chat.kt UnderWay).
fn under_way(c : @ui.Ctx, words : String) -> Unit {
  c.box(dir=Row, gap=5.0, align=ACenter, fn() {
    @sf.spinner(c, size=12.0) |> ignore
    c.text(words, size=10.0, color=ink().muted, wrap=false, line=16.0) |> ignore
  })
  |> ignore
}

///|
/// Under the viewer's message that waits for a runtime the station does not have (Chat.kt BlockedLine): how that
/// stands, red with a "!" while nothing is under way.
fn blocked_line(c : @ui.Ctx, src : Source, station : String, b : Install) -> Unit {
  let t = @sf.theme()
  let stuck = b.state == "missing" || b.state == "failed"
  let color = if stuck { t.p.red } else { ink().muted }
  // the whole line installs it, while it may (as a message not delivered is sent again from its line)
  let busy = b.action != "" && doing(install_key(station, b))
  let id = if b.action != "" && !busy { c.id("blocked/" + b.runtime) } else { 0 }
  if id != 0 && c.clicked(id) {
    install_runtime(src, station, b)
  }
  c.box(style=blocked_row, id~, fn() {
    if b.state == "installing" {
      @sf.spinner(c, size=12.0) |> ignore
    } else if stuck {
      c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.red, align=ACenter, justify=JCenter, fn() {
        c.text("!", size=8.0, weight=700, color=t.p.bg, wrap=false, line=8.0) |> ignore
      })
      |> ignore
    }
    let pct = match b.percent {
      Some(p) if b.state == "installing" => " \{p.to_int()}%"
      _ => ""
    }
    let note = if b.note != "" && b.action == "" { " · " + b.note } else { "" }
    // (a time's size: 10)
    let size = 10.0
    c.text(b.title + pct + note, size~, color~, line=16.0) |> ignore
    if b.action != "" {
      c.text("·", size~, color=ink().muted, wrap=false, line=16.0) |> ignore
      c.text(b.action, size~, weight=600, color=if busy { ink().muted } else { ink().text }, wrap=false, line=16.0)
      |> ignore
    }
  })
  |> ignore
}

///|
/// The blocked line's mark and words, 4 apart.
// kept across runs: a value (no field of it changes)
let blocked_row : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// What still.fail itself says (Chat.kt SystemNotice): a pill across the chat, one line cut short, no time; tapped,
/// all its words and its time under them. A failure (⚠️ at its start) is the pill in red.
fn system_notice(c : @ui.Ctx, src : Source, station : String, m : Message) -> Unit {
  let t = @sf.theme()
  // as the core says it is shown (the chat view's `notice`): a failure (its ⚠️ taken for the red), its words as a line
  // of the UI, where a profile's link begins
  let failed = m.notice_failed
  let said = m.notice_words
  let ground = if failed {
    if t.dark {
      0x442322FFL
    } else {
      0xFFF0EFFFL
    }
  } else {
    notice_ground(t.dark)
  }
  let color = if failed {
    if t.dark {
      0xF68482FFL
    } else {
      0xA12F35FFL
    }
  } else {
    ink().text
  }
  let id = c.id("notice/" + m.ts)
  if c.clicked(id) {
    opened_notices[m.ts] = !opened_notices.get(m.ts).unwrap_or(false)
  }
  let open = opened_notices.get(m.ts).unwrap_or(false)
  let first = match said.split("\n").find_first(fn(l) { l.trim(chars=" ").to_string() != "" }) {
    Some(l) => l.to_string()
    None => said
  }
  // in one about a profile (its sign-in failed), what went wrong (after its ：) leads to that profile's page
  let colon = if m.profile != "" && m.notice_link >= 0 && m.notice_link <= said.length() {
    Some(m.notice_link)
  } else {
    None
  }
  let to_install = match m.install {
    Some(i) if i.action != "" => Some(i)
    _ => None
  }
  let report = m.reportable && to_install is None && colon is None
  c.box(style=notice_across, fn() {
    notice_pill(c, id, ground, open, fn() {
      match colon {
        Some(at) =>
          c.rich(
            [
              @ui.span(said.view(end_offset=at).to_owned()),
              @ui.span(said.view(start_offset=at).to_owned(), underline=true, link="profile"),
            ],
            key="notice-profile/" + m.ts,
            style=if open { system_words_open } else { system_words },
            size=notice_type().0,
            line=notice_type().1,
            color~,
            link_color=color,
            on_link=fn(_) { app.nav.push(Setting(@settings.Route::Profile(station, m.profile))) },
          )
          |> ignore
        None =>
          c.box(dir=Row, align=if report { AEnd } else { ACenter }, fn() {
            // cut short where it does not fit, the word that acts on it after
            c.box(fn() {
              if open {
                @sf.markdown(c, said, key="notice/" + m.ts, size=notice_type().0, ink=color) |> ignore
              } else {
                pill_words(c, plain_words(if to_install is Some(_) { said } else { first }), color)
              }
            })
            |> ignore
            match to_install {
              Some(i) => notice_action(c, "notice-install/" + m.ts, i.action, color, doing(install_key(station, i)), fn() {
                  install_runtime(src, station, i)
                })
              None =>
                if report {
                  let key = "chat.report/" + station + "/" + m.thread.to_string() + "/" + m.seq.to_string()
                  let action = tr("common.report.action")
                  notice_action(c, "notice-report/" + m.ts, action, color, doing(key), fn() {
                    @sf.confirm(tr("common.report.title"), tr("common.report.lead") + "\n\n" + tr("common.report.sends"), action, fn() {
                      act(
                        src,
                        action,
                        key,
                        "chat.report",
                        { "station": Json::string(station), "thread": Json::number(m.thread), "seq": Json::number(m.seq) },
                        ok=fn(v) {
                          let number = match field(Some(v), "number") {
                            Some(Number(n, ..)) => n.to_int().to_string()
                            _ => "?"
                          }
                          toast_later(fill(if flag(Some(v), "duplicate") { "common.report.again" } else { "common.report.done" }, [("number", number)]))
                        },
                      )
                    })
                  })
                }
            }
          })
          |> ignore
      }
    })
    if open {
      message_time(c, m.ts, m.time)
    }
  })
  |> ignore
}

///|
/// A notice's pill (Chat.kt SystemNotice): as wide as its words, 14 and 6 in, round at its ends.
fn notice_pill(c : @ui.Ctx, id : Int, ground : Int64, open : Bool, body : () -> Unit) -> Unit {
  c.box(max_w=c.width - 28.0, padx=14.0, pady=6.0, radius=if open { 16.0 } else { 18.0 }, bg=ground, id~, body)
  |> ignore
}

///|
/// A notice's line of words (15 on a message's line), cut short where it does not fit.
fn pill_words(c : @ui.Ctx, words : String, color : Int64) -> Unit {
  let (size, line) = notice_type()
  c.text(words, size~, color~, wrap=false, line~) |> ignore
}

///|
/// A notice's words: 15 on a message's line (Chat.kt SystemNotice); in the wide frame the web's Markdown, 14 on 1.65
/// (Chat.css.ts msgSystemBox's `.markdown`).
fn notice_type() -> (Double, Double) {
  (15.0, 24.75)
}

///|
/// A notice's ground, what it says not a failure: the words' colour faint (Chat.kt SystemNotice).
fn notice_ground(dark : Bool) -> Int64 {
  if dark {
    0xFFFFFF0DL
  } else {
    0x26211711L
  }
}

///|
/// A notice across the chat, in its middle, its time 4 under it once opened.
// kept across runs: a value (no field of it changes)
let notice_across : @ui.Style = @ui.css("w=Full gap=S1 align=ACenter")

///|
/// A word at a notice's end that acts on it (Chat.kt InstallAction, ReportAction): " · " fainter, then the word, semibold
/// and underlined; while it is under way not offered.
fn notice_action(c : @ui.Ctx, key : String, action : String, color : Int64, busy : Bool, run : () -> Unit) -> Unit {
  let id = if busy { 0 } else { c.id(key) }
  if id != 0 && c.clicked(id) {
    run()
  }
  let (size, line) = notice_type()
  c.rich([@ui.span(" · ", color=@sf.alpha(color, notice_dot_alpha))], style=system_words, size~, line~, color~) |> ignore
  c.box(id~, fn() { c.rich([@ui.span(action, weight=600, underline=true)], style=system_words, size~, line~, color~) |> ignore })
  |> ignore
}

///|
/// A notice's words (15 on a message's line), on one line; all of it once opened.
// kept across runs: a value (no field of it changes)
let system_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=@sf.message_line, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let system_words_open : @ui.TextStyle = @ui.text_style(size=Lg, leading=@sf.message_line)

///|
/// The dot before a notice's word, its ink at 60%.
let notice_dot_alpha : Double = 0.6

///|
/// What says a runtime is being installed on a station (`software.update` by its id).
fn install_key(station : String, i : Install) -> String {
  "software.update/" + station + "/" + i.runtime
}

///|
/// Installs on `station` the runtime a notice or a waiting message says it lacks (`software.update`).
fn install_runtime(src : Source, station : String, i : Install) -> Unit {
  act(src, i.action, install_key(station, i), "software.update", { "station": Json::string(station), "id": Json::string(i.runtime) })
}

///|
/// A message's words as read, without Markdown's marks (Chat.kt plain).
fn plain_words(s : String) -> String {
  let sb = StringBuilder()
  let mut space = false
  for ch in s {
    match ch {
      '`' | '*' | '#' | '>' => ()
      ' ' | '\n' | '\t' | '\r' => space = true
      _ => {
        if space && sb.to_string() != "" {
          sb.write_char(' ')
        }
        space = false
        sb.write_char(ch)
      }
    }
  }
  sb.to_string()
}

///|
/// Plain words as a message draws them (sfbase's message_runs), references to chats in the chat's accent.
fn ref_runs(s : String) -> Array[@ui.Run] {
  message_runs(s, ink().accent)
}

///|
/// Someone's words as they wrote them (Chat.kt PersonWords): 15 on 23 lines, a reference to another chat its chip.
fn person_words(c : @ui.Ctx, words : String, ts : String) -> Unit {
  let t = @sf.theme()
  c.rich(
    @sf.found_weight(ref_runs(words), found_words_of(ts)),
    key="words/" + ts,
    size=15.0,
    color=ink().text,
    line=23.0,
    link_color=t.p.blue,
    pressed_bg=@sf.alpha(t.p.blue, 0.14),
    on_link=fn(h) { open_link(h) },
    on_link_hold=Some(fn(href, line) { link_held(c, href, line) }),
  )
  |> ignore
}

///|
/// The viewer's words, in their bubble on the right (Chat.kt Bubble): 16 on 21 lines, the bubble as wide as the
/// composer's field and its padding at most.
fn bubble(c : @ui.Ctx, words : String, ts : String) -> Unit {
  let t = @sf.theme()
  let k = ink()
  // words sent flying here: the bubble's ground comes in round them on their way (flight.mbt)
  let ground = match flying.val {
    Some(f) if f.placed => flight_ground_of(c, f)
    _ => 1.0
  }
  // gone to (a notification's), the bubble takes the accent's ground as it flashes (Chat.kt Bubble: lit)
  let lit = if flashing.val.0 == ts { flashing.val.1 } else { 0.0 }
  let neutral = if lit > 0.0 { @sf.mix(flash_ground(), lit, k.neutral) } else { k.neutral }
  // (the web's on a desktop's width: chat.css.ts msgMine msgBubble, 78% of the column and 560 at most, 8 by 14 in, 18
  // round)
  let b = c.box(
    max_w=c.width - 36.0,
    padx=14.0,
    pady=8.0,
    radius=18.0,
    bg=@sf.alpha(neutral, ground),
    fn() {
    c.rich(
      @sf.found_weight(ref_runs(words), found_words_of(ts)),
      key="bubble/" + ts,
      size=16.0,
      color=k.text,
      line=21.0,
      // (SendTextStyle's lines: a TextStyle of its own, no LineHeightStyle)
      trim=true,
      link_color=t.p.blue,
      pressed_bg=@sf.alpha(t.p.blue, 0.14),
      on_link=fn(h) { open_link(h) },
      on_link_hold=Some(fn(href, line) { link_held(c, href, line) }),
      // what people wrote: in the face chosen for it (Chat.kt SendTextFaced)
      words=true,
    )
    |> ignore
  })
  match flying.val {
    Some(f) => flight_bubble(c, f, b)
    None => ()
  }
}

///|
/// An agent's Markdown with its files (Prose.kt AgentWords): those its text names (`placed`) drawn there, the rest
/// below it; its links to a station's screens as their cards (screen_links.mbt); its tables scrolling out to `bleed`
/// past it either side.
fn agent_words(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  quote? : ((Attachment) -> Unit)? = None,
  bleed? : Double = 0.0,
) -> Unit {
  // an agent's request about a vault item: its card in place of the words, answered on it (vault_approval.mbt)
  match m.card {
    Some({ ask: Some(ask), .. } as card) => {
      vault_ask_card(c, src, here, card, ask)
      return
    }
    _ => ()
  }
  let placed : Map[String, Attachment] = {}
  for n in m.placed {
    match m.attachments.iter().find_first(fn(a) { a.name == n }) {
      Some(a) => placed[n] = a
      None => ()
    }
  }
  let rest = m.attachments.filter(fn(a) { !placed.contains(a.name) })
  c.box(w=Fill(1.0), fn() {
    if m.text != "" {
      @sf.markdown(
        c,
        m.text,
        tree=m.md,
        key="md/" + m.ts,
        size=15.0,
        ink=ink().text,
        on_link=fn(h) {
          // a link within a sentence to a file it places, by the file's name as written or escaped (Markdown.kt
          // fileNameOf): a visualization opened over the whole screen, any other in the preview as a tap on it below
          // the text opens it (Prose.kt OpenedFile)
          match placed.get(@sf.file_name_of(h)) {
            Some(a) if is_viz(a.name) => viz_open_full(a.name, here.station, owner_of(here, a), a.path, here.session, linked=true)
            Some(a) => open_preview(here.station, owner_of(here, a), a, steps=InChat(here.view.thread, here.session))
            None => open_link(h)
          }
        },
        on_link_hold=Some(fn(href, line) { link_held(c, href, line) }),
        found=found_words_of(m.ts),
        files=fn(name) {
          match placed.get(name) {
            // an HTML one is a visualization, drawn there; failing, its card (Prose.kt PlacedFile)
            Some(a) if is_viz(a.name) =>
              Some(fn() { viz_file(c, src, here, m.ts, a, fn() { files(c, src, here, [a], false) }) })
            Some(a) => Some(fn() { files(c, src, here, [a], false, quote~) })
            None => None
          }
        },
        // an image of its own in a table's cell, by its proportion (Prose.kt Placing.row: StationImage at a size)
        cell_files=fn(name) {
          match placed.get(name) {
            Some(a) if kind_of(a.name) == "image" => {
              let r = if a.width > 0.0 && a.height > 0.0 { a.width / a.height } else { cell_image_ratio }
              Some((r, fn(w) { file_item(c, src, here, a, w, quote~) }))
            }
            _ => None
          }
        },
        code=fn(lang, code) {
          let first = match lang.find(" ") {
            Some(i) => lang.view(end_offset=i).to_owned()
            None => lang
          }
          if first.to_lower() == "mermaid" && code.trim() != "" {
            Some(fn() { viz_mermaid_block(c, "chat/" + here.station + ":" + here.session + "/" + m.ts, code, ink().subtle) })
          } else {
            None
          }
        },
        // its links to a station's screens and 共享调试 as their cards (screen_links.mbt)
        screens=Some(screen_links(c, src, here.station + "/" + here.session + "/" + m.ts)),
        bleed~,
      )
      |> ignore
    }
    viz_opening(c, src, here)
    if rest.length() > 0 {
      c.box(w=Fill(1.0), pt=4.0, fn() { files(c, src, here, rest, false, quote~) }) |> ignore
    }
  })
  |> ignore
}

///|
/// Quotes as sent, each a card of its own ahead of the message (Chat.kt QuoteCards): the passage small and grey,
/// whose it is; its own picture under it (an image of a message quoted, a mark's screenshot: the file of `files` it
/// names, at most 120 high, opening as the message's do); then what was said about it.
fn quote_cards(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  quotes : Array[Quote],
  files : Array[Attachment],
  mine : Bool,
) -> Unit {
  if quotes.length() == 0 {
    return
  }
  let k = ink()
  let most = dmin(380.0, (c.width - 28.0) * 0.88)
  let (size, line, said) = quote_type()
  c.box(style=if mine { quote_cards_end } else { quote_cards_start }, fn() {
    for q in quotes {
      let own = quote_file(q, files)
      // pressed, the chat goes to the message it quotes, flashing it (Chat.tsx Quotes jump), its words in the text's
      // colour under the pointer
      let seq = match here.view.messages.iter().find_first(fn(m) { q.ts != "" && m.ts == q.ts }) {
        Some(m) => m.seq
        None => -1.0
      }
      let jump = if seq >= 0.0 { c.id("quote-jump/" + q.ts + "/" + q.text) } else { 0 }
      if jump != 0 {
        c.cursor(jump, Hand)
        if c.clicked(jump) {
          go_to(ref_of(here), seq)
        }
      }
      c.box(max_w=most, radius=12.0, bg=k.card, fn() {
        c.box(
          dir=Row,
          pl=11.0,
          pr=11.0,
          pt=7.0,
          pb=if q.comment == "" && own is None { 7.0 } else { 0.0 },
          align=AStart,
          id=jump,
          fn() {
            c.box(w=Px(15.0), h=Px(line), justify=JCenter, fn() {
              @sf.icon(c, "quote", size=11.0, color=k.accent) |> ignore
            })
            |> ignore
            // two lines at most
            c.box(max_h=line * 2.0, clip=true, fn() {
              c.rich(
                [
                  @ui.span(fill("android-chat.quote.who", [("name", q.author)]), weight=500, color=k.text),
                  @ui.span(q.text),
                ],
                size~,
                color=if jump != 0 && c.lit(jump) { k.text } else { k.muted },
                line~,
              )
              |> ignore
            })
            |> ignore
          },
        )
        |> ignore
        // under the words: its own picture (6 under them), what was said about it (3 under)
        if own is Some(_) || q.comment != "" {
          c.box(pl=11.0, pr=11.0, pb=8.0, fn() {
            match own {
              Some(a) =>
                c.box(style=quote_picture_room, fn() {
                  let w = if kind_of(a.name) == "image" {
                    let (bw, bh, _) = image_box(a, 16.0)
                    bw * dmin(1.0, 120.0 / bh)
                  } else {
                    dmin(236.0, most - 22.0)
                  }
                  file_item(c, src, here, a, w)
                })
                |> ignore
              None => ()
            }
            if q.comment != "" {
              c.box(pt=3.0, fn() { c.text(q.comment, size=said, color=k.text, line=said * 1.5) |> ignore }) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A quote card's words: the passage's size and line (13 on 19.5; the wide screen's 12 on 18, Chat.css.ts
/// quoteCardText), and what was said about it, on lines 1.5 its size (15; the wide screen's 13: quoteCardComment).
fn quote_type() -> (Double, Double, Double) {
  (13.0, 19.5, 15.0)
}

///|
/// A message's quote cards, one under another 4 apart, at its end when it is the viewer's (Chat.kt QuoteCards).
// kept across runs: a value (no field of it changes)
let quote_cards_end : @ui.Style = @ui.css("w=Full gap=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let quote_cards_start : @ui.Style = @ui.css("w=Full gap=S1 align=AStart")

///|
/// A quote card's own picture, 6 under its words (Chat.kt QuoteCard).
// kept across runs: a value (no field of it changes)
let quote_picture_room : @ui.Style = @ui.css("pt=S1_5")

///|
/// The file of a message's `files` that is a quote's own (Chat.kt fileOf): the one it names.
fn quote_file(q : Quote, files : Array[Attachment]) -> Attachment? {
  if q.file == "" {
    return None
  }
  files.iter().find_first(fn(a) { a.name == q.file })
}

///|
/// A message's files but those shown in its quotes' cards (Chat.kt besideQuotes, web Chat.tsx).
fn beside_quotes(quotes : Array[Quote], files : Array[Attachment]) -> Array[Attachment] {
  let own = quotes.filter_map(fn(q) { if q.file == "" { None } else { Some(q.file) } })
  if own.length() == 0 {
    files
  } else {
    files.filter(fn(a) { !own.contains(a.name) })
  }
}

///|
/// An image of the message `ts` held (MessagePick.kt quoteFile): into the chat's draft as a quote, its file going again
/// with the message as the station has it (nothing goes up), named by the session that keeps it; what was picked of
/// the message let go.
fn quote_image(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  ts : String,
  author : String,
  role : String,
  a : Attachment,
) -> Unit {
  draft_quote_file(draft_of(c, src, ref_of(here)), author, ts, role, attachment_json(a, owner_of(here, a)))
  pick_clear()
}

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
/// The box an image takes in the chat, known before it loads (ChatFiles.kt imageBox, MediaSize.kt mediaSize): its own
/// proportions within 360×300, a tiny one drawn to 40 on its longer side; a strip thinner than `least` letterboxed in
/// a box that thick. (width, height, letterboxed)
fn image_box(a : Attachment, least : Double) -> (Double, Double, Bool) {
  let (w, h) = if a.width > 0.0 && a.height > 0.0 {
    (a.width, a.height)
  } else {
    match thumb_ratio(a.thumbhash) {
      Some(r) => ((160.0 * r).round(), 160.0)
      None => return (240.0, 160.0, false)
    }
  }
  let scale = dmin(dmin(dmax(1.0, 40.0 / dmax(w, h)), 360.0 / w), 300.0 / h)
  let width = w * scale
  let height = h * scale
  if width >= least && height >= least {
    return (width.round(), height.round(), false)
  }
  (dmax(least, width).round(), dmax(least, height).round(), true)
}

///|
/// A ThumbHash's width over its height, from its header (mbui's @pixels.thumbhash_ratio).
fn thumb_ratio(hash : String) -> Double? {
  if hash == "" {
    return None
  }
  @pixels.thumbhash_ratio(@codec.from_base64(hash))
}

///|
/// A message's files, side by side and wrapping 6 apart, from its end when it is the viewer's (ChatFiles.kt Files,
/// Wrap): images and videos in boxes of their own proportions, the rest as cards.
fn files(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  list : Array[Attachment],
  mine : Bool,
  quote? : ((Attachment) -> Unit)? = None,
) -> Unit {
  if list.length() == 0 {
    return
  }
  let room = c.width - 28.0
  // each one's width as the row lays it
  let widths = list.map(fn(a) {
    match kind_of(a.name) {
      "image" => dmin(image_box(a, 16.0).0, room)
      "video" => dmin(image_box(a, 96.0).0, room)
      _ => dmin(236.0, room)
    }
  })
  let rows : Array[Array[Int]] = []
  let mut used = 0.0
  for i, w in widths {
    if rows.length() == 0 || used + 6.0 + w > room {
      rows.push([i])
      used = w
    } else {
      rows[rows.length() - 1].push(i)
      used = used + 6.0 + w
    }
  }
  c.box(w=Fill(1.0), gap=6.0, align=if mine { AEnd } else { AStart }, fn() {
    for r in rows {
      c.box(dir=Row, gap=6.0, align=AStart, fn() {
        for i in r {
          // (each in a box of its own: where a file sent from the composer flies to, flight.mbt)
          let item = c.box(fn() { file_item(c, src, here, list[i], widths[i], quote~) })
          match flying.val {
            Some(f) => flight_landing(c, f, item, list[i].path)
            None => ()
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
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
/// A file of a message (ChatFiles.kt FileItem): an image in its box (its likeness until it is here), a video's box
/// on black with the play mark and its name, anything else a card. `quote`: where the list quotes, an image held long
/// is quoted (ChatFiles.kt ChatImage: felt as it is).
fn file_item(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  a : Attachment,
  w : Double,
  quote? : ((Attachment) -> Unit)? = None,
) -> Unit {
  let t = @sf.theme()
  // tapped, it opens in the preview (preview.mbt)
  let open = c.id("file-open/" + a.path)
  if c.clicked(open) {
    // an image steps through the chat's (the core tells those beside it: imageNear)
    open_preview(here.station, owner_of(here, a), a, steps=InChat(here.view.thread, here.session))
  }
  match kind_of(a.name) {
    "image" => {
      let (bw, bh, letterbox) = image_box(a, 16.0)
      let h = bh * w / bw
      // one sent from here: the picture it was picked as, which flew in to it (not its likeness, then the station's)
      let sent = sent_picture(here.station, a)
      let key = match sent {
        Some(k) => k
        None => (src.file)(here.station, owner_of(here, a), base_name(a.path))
      }
      // where it is, for the viewer to fly from and back into (preview.mbt); hidden while the viewer is its picture
      let thumb = here.station + "/" + owner_of(here, a) + "/" + a.path
      note_thumb(c, thumb, open, file_corner(), letterbox~)
      // held long where the list quotes: quoted, the press its (lifting it opens nothing), once a press
      match quote {
        Some(q) => {
          let press = c.press()
          let held = @kit.after(c, "quote-image/" + thumb, c.pressed(open) && !press.moved, @ui.long_press_ms)
          if held && image_quoted_at.val != press.frame {
            image_quoted_at.val = press.frame
            c.take_press()
            feel_hold(c, "quote-image")
            q(a)
          }
        }
        None => ()
      }
      c.box(w=Px(w), h=Px(h), radius=file_corner(), clip=true, bg=t.p.chip, id=open, opacity=thumb_shows(thumb), fn() {
        if key != "" && key != "!" {
          c.image(
            key,
            w=Px(w),
            h=Px(h),
            fit=if letterbox { FitContain } else { FitCover },
            radius=file_corner(),
            bg=0L,
            fade=sent is None,
          )
          |> ignore
        } else if key == "!" {
          c.box(style=no_preview_box, fn() {
            @sf.icon(c, "read", size=20.0, color=t.p.muted) |> ignore
            c.text(tr("android-chat.file.noPreview"), style=no_preview_words) |> ignore
          })
          |> ignore
        } else {
          match @gallery.thumbhash_image(a.thumbhash) {
            Some(likeness) =>
              c.image(likeness, w=Px(w), h=Px(h), fit=FitCover, bg=0L, fade=false)
              |> ignore
            None => ()
          }
        }
      })
      |> ignore
    }
    "video" => {
      let (bw, bh, letterbox) = image_box(a, 96.0)
      let h = bh * w / bw
      // where it is, for the viewer to fly from and back into (preview.mbt); hidden while the viewer is its picture
      let thumb = here.station + "/" + owner_of(here, a) + "/" + a.path
      note_thumb(c, thumb, open, file_corner(), letterbox~)
      // the frame the viewer was left at, once it has been closed back into here; else its first as the station makes
      // it (ChatFiles.kt ChatVideo: the station's poster), or as drawn here where the station made none and it is
      // small; else the black alone
      let still = match pv_frames.get(thumb) {
        Some((k, _)) => k
        None =>
          match (src.poster)(here.station, owner_of(here, a), base_name(a.path)) {
            "!" => first_frame(c, src, here.station, owner_of(here, a), a, thumb)
            k => k
          }
      }
      c.box(w=Px(w), h=Px(h), radius=file_corner(), clip=true, bg=0x000000FFL, id=open, opacity=thumb_shows(thumb), fn() {
        if still != "" && still != "!" {
          c.layer(fn() {
            c.image(
              still,
              w=Px(w),
              h=Px(h),
              fit=if letterbox { FitContain } else { FitCover },
              radius=file_corner(),
              bg=0L,
            )
            |> ignore
          })
          |> ignore
        }
        c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
          c.box(w=Px(40.0), h=Px(40.0), radius=20.0, bg=0x000000A6L, align=ACenter, justify=JCenter, fn() {
            @sf.icon(c, "play", size=16.0, color=0xFFFFFFFFL) |> ignore
          })
          |> ignore
        })
        |> ignore
        // while the core downloads it (downloads.mbt), how far in its name's place, over a bar
        let dl = download_of(src, here.station, owner_of(here, a), base_name(a.path))
        c.layer(fn() {
          c.spacer()
          c.box(w=Fill(1.0), padx=8.0, pady=6.0, bg=0x000000A6L, align=ACenter, fn() {
            c.text(if flag(dl, "active") { text(dl, "statusText") } else { a.name }, size=12.0, color=0xFFFFFFFFL, wrap=false)
            |> ignore
            if flag(dl, "active") {
              c.box(style=video_coming_bar, fn() { @sf.progress(c, Some(number(dl, "progress"))) }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // (downloaded by the core: how far it has come, here too; ✕ calls it off, ↻ asks it again: downloads.mbt)
    _ => {
      let (key, name) = (owner_of(here, a), base_name(a.path))
      let dl = download_of(src, here.station, key, name)
      let act = c.id("file-act/" + a.path)
      if c.clicked(act) {
        // (told once the frame's builds are over, as the tap is the build's that took it)
        let (id, active) = (text(dl, "id"), flag(dl, "active"))
        c.tell("file-act/" + a.path, fn() { if active { download_cancel(src, id) } else { download_retry(src, id) } })
      }
      file_card(c, a, w, id=open, dl~, act~)
    }
  }
}

///|
/// A file as a card (ChatFiles.kt FileCard): its kind's mark, its name, its size, on the neutral ground. While the core
/// downloads it (`dl`, downloads.mbt) how far it has come in its size's place and as a ring in its mark's, ✕ (`act`)
/// at its end to call it off; failed, why, in red, ↻ to ask it again.
fn file_card(c : @ui.Ctx, a : Attachment, w : Double, id? : Int = 0, dl? : Json? = None, act? : Int = 0) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    w=Px(w),
    radius=8.0,
    bg=ink().neutral,
    id~,
    padx=10.0,
    pady=8.0,
    gap=10.0,
    align=ACenter,
    fn() {
      match file_card_coming(dl) {
        Some(part) => @sf.progress_ring(c, 16.0, part, t.p.accent) |> ignore
        None => @sf.icon(c, "read", size=16.0, color=t.p.muted) |> ignore
      }
      let (meta, failed) = file_card_said(a, dl)
      c.box(w=Fill(1.0), fn() {
        c.text(a.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
        c.text(meta, size=11.0, color=if failed { t.p.red } else { t.p.muted }, wrap=false, line=16.0)
        |> ignore
      })
      |> ignore
      match file_card_act(dl) {
        Some((icon, label)) if act != 0 => card_close(c, act, icon~, label~)
        _ => ()
      }
    },
  )
  |> ignore
}

///|
/// A card's own button while the core downloads its file (✕: call it off) or once that failed (↻: ask it again), its
/// icon and its name; None otherwise.
fn file_card_act(dl : Json?) -> (String, String)? {
  if flag(dl, "active") {
    Some(("close", tr("web-main.file.cancelDownload")))
  } else if text(dl, "state") == "failed" {
    Some(("retry", tr("web-main.file.retryDownload")))
  } else {
    None
  }
}

///|
/// A video's bar while the core downloads it: under its words, 4 below them.
// kept across runs: a value (no field of it changes)
let video_coming_bar : @ui.Style = @ui.css("w=Full pt=S1")

///|
/// What a file's card says under its name: its size, or while the core downloads it how far it has come (正在下载 42% ·
/// 18.3 MB), failed why (the core's words); and whether that is a failure.
fn file_card_said(a : Attachment, dl : Json?) -> (String, Bool) {
  if flag(dl, "active") || text(dl, "state") == "failed" {
    (text(dl, "statusText"), !flag(dl, "active"))
  } else {
    (@sf.file_size(a.size), false)
  }
}

///|
/// How far the core has downloaded a file (0 to 1) while it does; None while it does not.
fn file_card_coming(dl : Json?) -> Double? {
  if flag(dl, "active") {
    Some(number(dl, "progress"))
  } else {
    None
  }
}

///|
/// An image with no preview: its mark over its words, in its middle.
// kept across runs: a value (no field of it changes)
let no_preview_box : @ui.Style = @ui.css("w=Full h=Full gap=S1_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let no_preview_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)


///|
/// A message's pictures' corner: 10 (ChatFiles.kt).
fn file_corner() -> Double {
  10.0
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
      login_card(c, src, station, card.login)
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
  if m.card is Some({ ask: Some(_), .. }) {
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
      fade_spec=@motion.tween(options_out_ms, ease=CssOut, delay=options_out_ms),
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
    room=c.width - 2.0 * row_side(c),
  )
  match picked {
    Some(i) => Some(options[i])
    None => None
  }
}

///|
/// An ended login's line (LoginCards.kt LoginCard, ended: 13 on 19), in the chat's subtle ink, failed in red.
fn login_ended_line(c : @ui.Ctx, words : String, failed : Bool) -> Unit {
  c.text(words, size=13.0, color=if failed { @sf.theme().p.red } else { ink().subtle }, line=19.0) |> ignore
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

///|
/// An image's proportion in a table's cell when its size is not known (Markdown.kt CellImageRow: 1.5).
let cell_image_ratio : Double = 1.5
