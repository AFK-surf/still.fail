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
  // in the wide frame the web's own (styles/global.css.ts): its bubble the neutral ground, names in the accent's ink
  if wide_on.val {
    let p = @sf.theme().p
    return {
      text: p.text,
      muted: p.muted,
      subtle: p.subtle,
      neutral: p.neutral_bg,
      name: p.accent_text,
      card: p.card,
      accent: p.accent,
      canvas: p.canvas,
    }
  }
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
let absolute_times : Ref[Bool] = { val: false }

///|
/// The flight of words sent whose row is being built (flight.mbt), for its bubble and what is under it.
let flying : Ref[SendFlight?] = { val: None }

///|
/// System notices opened (all their words, and their time), by message.
let opened_notices : Map[String, Bool] = {}

///|
fn entry_view(c : @ui.Ctx, src : Source, here : Here, e : Entry, list : Array[Entry]) -> Unit {
  let k = ink()
  match e {
    Older =>
      c.box(w=Fill(1.0), pt=4.0, pb=8.0, align=ACenter, fn() { @sf.spinner(c) |> ignore })
      |> ignore
    Newer =>
      c.box(w=Fill(1.0), pt=8.0, pb=4.0, align=ACenter, fn() { @sf.spinner(c) |> ignore })
      |> ignore
    Empty =>
      c.box(w=Fill(1.0), padx=24.0, pady=30.0, fn() {
        c.text(
          tr("android-chat.chat.empty"),
          size=15.0,
          color=k.muted,
          line=24.0,
          center=true,
          w=Fill(1.0),
        )
        |> ignore
      })
      |> ignore
    Line => unread_line(c)
    Said(m) => said(c, src, here, m, list, quotes=true)
    Sent(s) => sent_elsewhere(c, src, here, s)
    Out(o) => outgoing(c, src, here, o)
    Working(a) => activity(c, src, here, a)
    Top | Foot => ()
  }
}

///|
/// Over the first message that was unread when the chat opened: the accent, a rule each side.
fn unread_line(c : @ui.Ctx) -> Unit {
  c.box(style=unread_row, fn() {
    c.box(style=unread_rule, fn() {  }) |> ignore
    c.text(tr("android-chat.chat.newBelow"), style=if wide_on.val { unread_words_wide } else { unread_words }) |> ignore
    c.box(style=unread_rule, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The unread line's row, its rules each side (1, the accent at 50%), its words 13 in 500 (the wide screen's 12:
/// Chat.css.ts chatUnreadLine) in the accent.
// kept across runs: a value (no field of it changes)
let unread_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unread_rule : @ui.Style = @ui.css("w=Grow(1.0) h=SPx bg=A(Accent,O50)")

///|
// kept across runs: a value (no field of it changes)
let unread_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Accent, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let unread_words_wide : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Accent, wrap=false)

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
      // in the wide frame the other way of saying it, on hover (ui.tsx Time: its Tip)
      @sf.tip(c, "time/" + key, id, if absolute_times.val { s.ago } else { s.full })
      c.box(id~, fn() {
        c.text(
          if absolute_times.val { s.full } else { s.ago },
          size=if wide_on.val { web_time } else { 10.0 },
          color=ink().muted,
          wrap=false,
          line=if wide_on.val { web_time_line } else { 16.0 },
        )
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// A chat's words on a desktop's width, as the web's (styles/global.css.ts, conversation.css.ts, chat.css.ts): a
/// message's 14 (a person's plain words on lines 1.55), its time 11; the viewer's bubble 14 on 1.55, 8 by 14 in, 18
/// round, 78% of the column and 560 wide at most (chat.css.ts msgMine msgBubble).
let web_body : Double = 14.0

///|
let web_time : Double = 11.0

///|
let web_plain_line : Double = web_body * 1.55

///|
/// (a time on a message's lines, 1.65)
let web_time_line : Double = web_time * 1.65

///|
let web_bubble_w : Double = 560.0

///|
let web_bubble_share : Double = 0.78

///|
let web_bubble_px : Double = 14.0

///|
let web_bubble_py : Double = 8.0

///|
let web_bubble_r : Double = 18.0

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
/// anyone else's under their picture, name and time, an agent's as Markdown with its files placed in it.
fn said(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  list : Array[Entry],
  decide? : Bool = true,
  quotes? : Bool = false,
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
      // an agent of the chat's name opens its card (AgentSheet.kt); in the wide frame its execution history beside the
      // chat, pressed again in front, closed (the web's chatPage.agent: its history where the page gives no card)
      let mine = m.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == m.by.agent })
      let name = c.id("name/" + m.ts)
      if mine && wide_on.val {
        c.cursor(name, Hand)
      }
      if mine && c.clicked(name) {
        if wide_on.val {
          side_toggle(ref_of(here), m.by.agent)
        } else {
          open_sheet(c, AgentOf(ref_of(here), m.by.agent))
        }
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
        pickable(c, m.ts, who, role, m.text, true, fn() { agent_words(c, src, here, m, quote~) })
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
      emit_out(c, col, em, m.seq)
    }
    // the picture over the name's start, or out in the margin before it in the wide frame, held at the list's top as a
    // long message scrolls past (where a message out of an avatar lands: hidden while the flying one is over it)
    c.layer(fn() {
      // one of the chat's agents': in the wide frame its card while the pointer rests on its picture (Chat.tsx
      // AgentAvatar, AgentHover)
      let carded_agent = if wide_on.val && m.author_kind == "agent" && m.by.agent != "" {
        here.view.agents.iter().find_first(fn(a) { a.key == m.by.agent })
      } else {
        None
      }
      let carded = carded_agent is Some(_)
      let hid = if carded { c.id("said-avatar/" + m.ts) } else { 0 }
      let av = said_avatar(c, id=hid, fn() { message_avatar(c, src, m) })
      if wide_on.val {
        c.stick(av, wide_avatar_held)
      }
      if carded_agent is Some(a) {
        let station = here.station
        @sfdesk.hover(c, "agent-hover/" + m.ts, hid, tile=true, fn() {
          match agent_json((src.topic)("chat", chat_params(ref_of(here))).value, a.key) {
            Some(j) => @sfdesk.agent_card(c, src, station, j)
            None => ()
          }
        })
        |> ignore
      }
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
  c.box(dir=Row, w=Fill(1.0), pl=head_in(), min_h=24.0, gap=6.0, align=ACenter, fn() {
    c.box(max_w=240.0, id~, fn() {
      if wide_on.val {
        // one that opens something takes the accent under the pointer (Chat.css.ts msgAgent:hover)
        c.text(name, style=if id != 0 && c.hovered(id) { wide_name_hot } else { wide_name }) |> ignore
      } else {
        c.text(name, size=15.0, weight=650, color=k.name, wrap=false, line=21.0) |> ignore
      }
    })
    |> ignore
    message_time(c, key, time)
  })
  |> ignore
}

///|
/// How far a message's head stands in from its start: past the picture over it, none in the wide frame (the picture
/// out in the margin).
fn head_in() -> Double {
  if wide_on.val {
    0.0
  } else {
    25.0
  }
}

///|
/// A name over its message in the wide frame (Chat.css.ts msgHead msgName): the UI's size in 600, the accent's ink, its
/// line inside the head's 24.
// kept across runs: a value (no field of it changes)
let wide_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, leading=L5, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wide_name_hot : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, leading=L5, color=Accent, wrap=false)

///|
/// Where a message's picture goes, over its head's start (Chat.kt SaidRow: 3 down, centred on the name's line); in the
/// wide frame out in the list's margin before the words, as far from the name as from the margin's edge (Chat.css.ts
/// msgRow > msgAvatar: 29 out).
fn said_avatar(c : @ui.Ctx, body : () -> Unit, id? : Int = 0) -> Int {
  if wide_on.val {
    c.box(tx=-wide_avatar_out, ty=3.0, id~, body)
  } else {
    c.box(pt=3.0, id~, body)
  }
}

///|
/// How far a message's picture stands out before its words in the wide frame (align.ts columns.avatar), and where it
/// is held as its message scrolls past: 8 under the chat's bar (Chat.css.ts: sticky, 8 under the pane's top).
let wide_avatar_out : Double = 29.0

///|
let wide_avatar_held : Double = wide_bar_h + 8.0

///|
/// A spinner and a word, small, under a message of the viewer's (Chat.kt UnderWay).
fn under_way(c : @ui.Ctx, words : String) -> Unit {
  c.box(dir=Row, gap=5.0, align=ACenter, fn() {
    @sf.spinner(c, size=12.0) |> ignore
    c.text(words, size=if wide_on.val { web_time } else { 10.0 }, color=ink().muted, wrap=false, line=16.0) |> ignore
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
    // (a time's size: 10, the wide screen's 11)
    let size = if wide_on.val { web_time } else { 10.0 }
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
  let failed = m.text.has_prefix("⚠️")
  let mut said = if failed {
    m.text.view(start_offset="⚠️".length()).to_string().trim_start(chars=" ").to_string()
  } else {
    m.text
  }
  // a line of the UI, not prose: no 。 at its end
  let trimmed = said.trim_end(chars=" \n").to_string()
  if trimmed.has_suffix("。") {
    said = trimmed.view(end_offset=trimmed.length() - 1).to_string()
  }
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
  let colon = if m.profile == "" {
    None
  } else {
    match said.find("：") {
      Some(i) => Some(i + "：".length())
      None => said.find(":").map(fn(i) { i + 1 })
    }
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
                    @settings.confirm(tr("common.report.title"), tr("common.report.lead") + "\n\n" + tr("common.report.sends"), action, fn() {
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
  if wide_on.val {
    (web_body, web_body * 1.65)
  } else {
    (15.0, 24.75)
  }
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
/// Plain words as a message draws them (Markdown.kt withRefs): `[title](…/chats/…)` a reference to that chat (`@`
/// a little lighter, its title, in the accent), a web address written bare a link.
fn ref_runs(s : String) -> Array[@ui.Run] {
  let accent = ink().accent
  let out : Array[@ui.Run] = []
  let words = StringBuilder()
  let flush = fn() {
    let w = words.to_string()
    if w != "" {
      bare_links(w, out)
    }
    words.reset()
  }
  let n = s.length()
  let mut i = 0
  while i < n {
    let ch = s.at(i).to_int()
    if ch == 91 {
      // [title](href) with /chats/ in it
      match s.view(start_offset=i + 1).find("](") {
        Some(close) if close >= 1 && close <= 120 => {
          let title = s.view(start_offset=i + 1, end_offset=i + 1 + close).to_string()
          let rest = s.view(start_offset=i + 1 + close + 2).to_string()
          match rest.find(")") {
            Some(end) if !title.contains("\n") => {
              let href = rest.view(end_offset=end).to_string()
              if href.contains("/chats/") && !href.contains(" ") {
                flush()
                out.push(@ui.span("@", link=href, color=@sf.alpha(accent, 0.7)))
                out.push(@ui.span(title, link=href, color=accent))
                i = i + 1 + close + 2 + end + 1
                continue
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
    }
    words.write_char(s.at(i).unsafe_to_char())
    i = i + 1
  }
  flush()
  out
}

///|
/// Words with the web addresses in them as links (bareLinks.ts: one ends at a space or at Chinese).
fn bare_links(s : String, out : Array[@ui.Run]) -> Unit {
  let mut from = 0
  let mut i = 0
  let n = s.length()
  while i < n {
    let at_link = s.view(start_offset=i).has_prefix("https://") ||
      s.view(start_offset=i).has_prefix("http://")
    if at_link {
      let mut j = i
      while j < n {
        let k = s.at(j).to_int()
        if k <= 32 || k >= 0x2E80 || k == 0xFF0C || k == 0x3002 {
          break
        }
        j = j + 1
      }
      // what ends a sentence is not the address's
      while j > i && ".,;:!?)'\"".contains(s.at(j - 1).unsafe_to_char().to_string()) {
        j = j - 1
      }
      if j - i > 8 {
        if i > from {
          out.push(@ui.plain(s.view(start_offset=from, end_offset=i).to_string()))
        }
        let href = s.view(start_offset=i, end_offset=j).to_string()
        out.push(@ui.link(href, href))
        from = j
        i = j
        continue
      }
    }
    i = i + 1
  }
  if from < n {
    out.push(@ui.plain(s.view(start_offset=from).to_string()))
  }
}

///|
/// Someone's words as they wrote them (Chat.kt PersonWords): 15 on 23 lines, a reference to another chat its chip.
fn person_words(c : @ui.Ctx, words : String, ts : String) -> Unit {
  let t = @sf.theme()
  c.rich(
    @sf.found_weight(ref_runs(words), found_words_of(ts)),
    key="words/" + ts,
    size=if wide_on.val { web_body } else { 15.0 },
    color=ink().text,
    line=if wide_on.val { web_plain_line } else { 23.0 },
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
    max_w=if wide_on.val { dmin(c.width * web_bubble_share, web_bubble_w) } else { c.width - 36.0 },
    padx=if wide_on.val { web_bubble_px } else { 14.0 },
    pady=if wide_on.val { web_bubble_py } else { 8.0 },
    radius=if wide_on.val { web_bubble_r } else { 18.0 },
    bg=@sf.alpha(neutral, ground),
    fn() {
    c.rich(
      @sf.found_weight(ref_runs(words), found_words_of(ts)),
      key="bubble/" + ts,
      size=if wide_on.val { web_body } else { 16.0 },
      color=k.text,
      line=if wide_on.val { web_plain_line } else { 21.0 },
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
/// A link tapped in a message (App.kt's UriHandler, AppState.openLink): one of still.fail's opens here as the core
/// says (links.mbt); any other is handed to the system (its browser, or the app that takes it: mbui's open_url), said
/// when nothing took it.
fn open_link(href : String) -> Unit {
  let elsewhere = fn() { if !@ui.open_url(href) { toast_later(tr("android-misc.link.cantOpen")) } }
  match link_src.val {
    Some(src) => open_link_in(src, href, or_else=elsewhere)
    None => elsewhere()
  }
}

///|
/// An agent's Markdown with its files (Prose.kt AgentWords): those its text names (`placed`) drawn there, the rest
/// below it; its links to a station's screens as their cards (screen_links.mbt).
fn agent_words(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  quote? : ((Attachment) -> Unit)? = None,
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
        size=if wide_on.val { web_body } else { 15.0 },
        ink=ink().text,
        on_link=fn(h) {
          // a link within a sentence to a file it places, by the file's name as written or escaped (Markdown.kt
          // fileNameOf): a visualization opened over the whole screen, any other in the preview as a tap on it below
          // the text opens it (Prose.kt OpenedFile)
          match placed.get(@sf.file_name_of(h)) {
            Some(a) if is_viz(a.name) => viz_open_full(a.name, here.station, owner_of(here, a), a.path, here, linked=true)
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
            Some(fn() { viz_mermaid_block(c, "chat/" + here.station + ":" + here.session + "/" + m.ts, code) })
          } else {
            None
          }
        },
        // its links to a station's screens and 共享调试 as their cards (screen_links.mbt)
        screens=Some(screen_links(c, src, here.station + "/" + here.session + "/" + m.ts)),
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
                color=if jump != 0 && c.hovered(jump) { k.text } else { k.muted },
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
  if wide_on.val {
    (12.0, 18.0, 13.0)
  } else {
    (13.0, 19.5, 15.0)
  }
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
/// A file as the core gives it (Attachment), kept by `owner`'s workspace.
fn attachment_json(a : Attachment, owner : String) -> Json {
  let o : Map[String, Json] = {
    "name": Json::string(a.name),
    "path": Json::string(a.path),
    "size": Json::number(a.size),
  }
  if a.width > 0.0 && a.height > 0.0 {
    o["width"] = Json::number(a.width)
    o["height"] = Json::number(a.height)
  }
  if a.thumbhash != "" {
    o["thumbhash"] = Json::string(a.thumbhash)
  }
  if owner != "" {
    o["owner"] = Json::string(owner)
  }
  Json::object(o)
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
/// The last part of a path.
fn base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_string()
    None => path
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
      // right clicked in the wide frame: 复制图片 (sfdesk/context_menu.mbt)
      if wide_on.val {
        @sfdesk.context_image(c, open, key)
      }
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
      if wide_on.val {
        c.cursor(open, Hand)
      }
      c.box(w=Px(w), h=Px(h), radius=file_corner(), clip=true, bg=if wide_on.val { t.p.neutral_bg } else { t.p.chip }, id=open, opacity=thumb_shows(thumb), fn() {
        if key != "" && key != "!" && wide_on.val && sent is None {
          // brought in as the web's: brushed in from its top, blurred to sharp (image_reveal)
          image_reveal(c, key, w, h, if letterbox { FitContain } else { FitCover }, a.thumbhash)
        } else if key != "" && key != "!" {
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
  if wide_on.val {
    file_card_wide(c, a, w, id, dl, act)
    return
  }
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
/// A file as a card in the wide frame (Chat.tsx FileCard, Chat.css.ts fileCard): its sheet (file_sheet), its name (13,
/// what is cut its middle, never its extension) over its size (11, grey), 236 wide at most, 8 by 10 in and 7 at the
/// sheet's side, rounded as the sheet stands in (13), on the neutral ground; under the pointer the pointer's, its path
/// said (the web's Tip).
fn file_card_wide(c : @ui.Ctx, a : Attachment, w : Double, id : Int, dl : Json?, act : Int) -> Unit {
  if id != 0 {
    c.cursor(id, Hand)
    @sf.tip(c, "file-card/" + a.path, id, if a.path != "" { a.path } else { a.name })
  }
  let hot = id != 0 && c.hovered(id)
  c.box(style=if hot { file_card_hot } else { file_card_box }, w=Px(w), radius=message_file_corner, id~, fn() {
    let (meta, failed) = file_card_said(a, dl)
    @sf.file_tile(c, a.name, progress=file_card_coming(dl), error=failed)
    c.box(style=file_card_words, fn() {
      @sf.file_name(c, a.name)
      c.text(meta, style=if failed { file_card_failed } else { file_card_meta }) |> ignore
    })
    |> ignore
    match file_card_act(dl) {
      Some((icon, label)) if act != 0 => file_card_button(c, act, icon, label)
      _ => ()
    }
  })
  |> ignore
}

///|
/// A wide card's own button at its end (Chat.tsx FileCard's remove and retry, Chat.css.ts fileCardRemove): 22 round,
/// nothing under it but under the pointer (the hover ground), its icon 13 in the muted ink (the text's under the
/// pointer); named.
fn file_card_button(c : @ui.Ctx, id : Int, icon : String, label : String) -> Unit {
  let p = @sf.theme().p
  c.cursor(id, Hand)
  let hot = c.hovered(id)
  let b = c.box(style=if hot { file_card_button_hot } else { file_card_button_box }, id~, fn() {
    @sf.icon(c, icon, size=file_card_button_icon, color=if hot { p.text } else { p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
}

///|
// kept across runs: a value (no field of it changes)
let file_card_button_box : @ui.Style = @ui.style(
  w=@sf.file_card_button,
  h=@sf.file_card_button,
  radius=Full,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let file_card_button_hot : @ui.Style = file_card_button_box.then(@ui.css("bg=Hover"))

///|
/// fileCardRemove's icons (Close 12, Retry 13: the larger of the two).
let file_card_button_icon : Double = 13.0

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
/// A message's image coming in at a desktop's width, as the web's (Chat.css.ts msgImageWait, msgImageReveal): until it
/// is decoded what it waits on (its likeness, the ThumbHash sent with it, else the ground); once it is, brushed in from
/// its top (an edge half its height deep going down it), blurred to sharp and from 1.04 its size to its own (1100 ms,
/// the ease out), what it waited on fading out behind it (300 ms, from 800). One already decoded as it is first shown
/// comes as it is.
fn image_reveal(c : @ui.Ctx, key : String, w : Double, h : Double, fit : @ui.Fit, hash : String) -> Unit {
  // (decoded at the size it is drawn at: Ctx::image's)
  let px = dmin(dmax(w, h) * c.scale, 8192.0)
  let ready = c.image_ready(key, px)
  let way = match reveals.get(key) {
    Some(a) => a
    None => {
      let a = if ready { None } else { Some(@motion.Anim::new(0.0)) }
      reveals[key] = a
      a
    }
  }
  // its way in, said once as it is first seen decoded
  let p = match way {
    Some(a) if ready => {
      if !a.moving() && a.get() == 0.0 {
        a.animate(1.0, @motion.tween(reveal_ms, ease=Linear))
      }
      a.get()
    }
    Some(_) => 0.0
    None => 1.0
  }
  let e = @motion.Out.at(p)
  let img = c.image(key, w=Px(w), h=Px(h), fit~, radius=file_corner(), bg=0L, fade=false)
  if p >= 1.0 {
    return
  }
  c.look(img, @ui.look(alpha=if ready { 1.0 } else { 0.0 }, scale=1.0 + reveal_grow * (1.0 - e)))
  // blurred to sharp: a frost over it and what it waits on (its edge's steps softened under it), its blur going
  let frost = fn() {
    let blur = reveal_blur * (1.0 - e)
    if ready && blur > 0.25 {
      c.layer(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), glass=@ui.Glass::frosted(blur~, tint=0L, solid=0L), fn() {  }) |> ignore
      })
      |> ignore
    }
  }
  // what it waits on, under the edge brushing down (its band in steps), fading out from 800 ms
  let waited = if ready {
    1.0 - dclamp((p * reveal_ms - reveal_wait_after_ms) / reveal_wait_out_ms, 0.0, 1.0)
  } else {
    1.0
  }
  if waited <= 0.0 {
    frost()
    return
  }
  let likeness = @gallery.thumbhash_image(hash)
  // (each step on the screen's pixels: one meets the next with no seam)
  let px_of = fn(y : Double) { (y * c.scale).round() / c.scale }
  let wait = fn(y0 : Double, y1 : Double, alpha : Double) {
    let y0 = px_of(dmax(0.0, y0))
    let y1 = px_of(dmin(h, y1))
    if y1 <= y0 || alpha <= 0.0 {
      return
    }
    // (each laid out from the picture's top, as a layer is: not under the one before)
    c.layer(fn() {
      bar_room_box(c, y0)
      let strip = c.box(style=@ui.style(w=Full, h=Fixed(y1 - y0), clip=true), fn() {
        let inner = match likeness {
          Some(l) => c.image(l, w=Px(w), h=Px(h), fit=FitCover, bg=0L, fade=false)
          None => c.box(style=@ui.style(w=Fixed(w), h=Fixed(h), bg=Neutral), fn() {  })
        }
        c.look(inner, @ui.look(dy=-y0))
      })
      c.look(strip, @ui.look(alpha=alpha * waited))
    })
    |> ignore
  }
  c.layer(fn() {
    if !ready {
      // (not decoded yet: all of it)
      wait(0.0, h, 1.0)
    } else {
      // the edge: half its height deep, from above it to past its foot
      let band = h * 0.5
      let top = -band + (h + band) * e
      let step = band / reveal_steps.to_double()
      for k in 0..<reveal_steps {
        let y = top + k.to_double() * step
        wait(y, y + step, (k.to_double() + 0.5) / reveal_steps.to_double())
      }
      wait(top + band, h, 1.0)
    }
  })
  |> ignore
  frost()
}

///|
/// Each image's way in, by its source, while the run lasts (None: first shown decoded, as it is).
let reveals : Map[String, @motion.Anim?] = {}

///|
/// How long it comes in, how blurred and how much larger it starts, and when and how fast what it waited on goes.
let reveal_ms : Double = 1100.0

///|
let reveal_blur : Double = 14.0

///|
let reveal_grow : Double = 0.04

///|
let reveal_wait_after_ms : Double = 800.0

///|
let reveal_wait_out_ms : Double = 300.0

///|
/// The steps its edge is drawn in.
let reveal_steps : Int = 16

///|
/// A message's pictures' corner: 10 (ChatFiles.kt), the wide screen's as its file cards' (message_file_corner).
fn file_corner() -> Double {
  if wide_on.val {
    message_file_corner
  } else {
    10.0
  }
}

///|
/// What a message's file card, its pictures and its pasted text are rounded (Chat.css.ts MESSAGE_FILE_CORNER: the
/// sheet's room 9.75 and its corner 3.25).
let message_file_corner : Double = 13.0

///|
// kept across runs: a value (no field of it changes)
let file_card_box : @ui.Style = @ui.style(
  row=true,
  pl=@sf.file_sheet_in,
  pr=S2_5,
  py=S2,
  gap=S2_5,
  bg=Neutral,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let file_card_hot : @ui.Style = file_card_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let file_card_words : @ui.Style = @ui.css("w=Grow(1.0)")

///|
// kept across runs: a value (no field of it changes)
let file_card_meta : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, leading=L4, wrap=false)

///|
/// Why the core's download of it failed, in its size's place.
// kept across runs: a value (no field of it changes)
let file_card_failed : @ui.TextStyle = @ui.text_style(size=Xs2, color=Danger, leading=L4, wrap=false)

///|
/// Options answered fade out in this long (Decisions.kt DecisionUnder); how it went fades in after them as long.
pub let options_out_ms : Double = 200.0

///|
/// The answered options' curve (CSS's ease-out) and how small they are as they have gone: 90%.
// kept across runs: a curve, never written
pub let options_ease : @motion.Ease = CssOut

///|
pub let options_scale : Double = 0.9

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
        c.box(style=if wide_on.val { options_room_wide } else { options_room }, fn() {
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
/// In the wide frame 8 over them (Decisions.css.ts options: margin-top 8).
// kept across runs: a value (no field of it changes)
let options_room_wide : @ui.Style = @ui.css("w=Full pt=S2 align=AStart")

///|
/// The quiet line over or in place of a post's options (who decides, how it went): 13 on 19 (Decisions.kt); the wide
/// frame's 12 on 18 (Decisions.css.ts settledLine).
fn quiet_type() -> (Double, Double) {
  if wide_on.val {
    (12.0, 18.0)
  } else {
    (13.0, 19.0)
  }
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
    wide=wide_on.val,
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
/// What an agent said in Slack, or a person's Slack message it was given (Chat.kt SentElsewhere): a picture with
/// Slack's mark on its corner and a name as messages have them, then where it went or came from over its words
/// beside a bar.
fn sent_elsewhere(c : @ui.Ctx, src : Source, here : Here, s : Elsewhere) -> Unit {
  if wide_on.val {
    sent_elsewhere_wide(c, src, here, s)
    return
  }
  let t = @sf.theme()
  let k = ink()
  c.box(w=Fill(1.0), fn() {
    c.box(w=Fill(1.0), gap=4.0, fn() {
      c.box(dir=Row, w=Fill(1.0), pl=25.0, min_h=24.0, gap=6.0, align=ACenter, fn() {
        c.box(max_w=240.0, fn() {
          c.text(s.by.name, size=15.0, weight=650, color=k.name, wrap=false, line=21.0)
          |> ignore
        })
        |> ignore
        message_time(c, "s:" + s.key, s.time)
      })
      |> ignore
      c.box(w=Fill(1.0), gap=5.0, fn() {
        c.box(dir=Row, align=ACenter, fn() {
          c.box(pr=5.0, fn() {
            @sf.icon(c, if s.received { "received" } else { "send" }, size=14.0, color=t.p.muted)
            |> ignore
          })
          |> ignore
          let words = tr(
            if s.received {
              "android-chat.chat.slack.from"
            } else {
              "android-chat.history.sent.to"
            },
          )
          let (before, after) = match words.find("{name}") {
            Some(i) =>
              (
                words.view(end_offset=i).to_string(),
                words.view(start_offset=i + 6).to_string(),
              )
            None => (words, "")
          }
          c.text(before, size=13.0, color=t.p.muted, wrap=false) |> ignore
          match s.place {
            Some(p) =>
              c.box(dir=Row, gap=3.0, align=ACenter, fn() {
                if p.surface == "ember" || p.surface == "stillfail" {
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
                } else {
                  @sf.slack_mark(c, 12.0) |> ignore
                }
                c.box(fn() {
                  c.text(
                    p.name,
                    size=13.0,
                    weight=600,
                    color=if p.session != "" || p.url != "" {
                      t.p.accent_text
                    } else {
                      t.p.text
                    },
                    wrap=false,
                  )
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            None =>
              c.box(dir=Row, gap=3.0, align=ACenter, fn() {
                @sf.slack_mark(c, 12.0) |> ignore
                c.text("Slack", size=13.0, weight=600, color=t.p.text, wrap=false) |> ignore
              })
              |> ignore
          }
          c.text(after, size=13.0, color=t.p.muted, wrap=false) |> ignore
          if s.failed {
            c.box(pl=6.0, fn() {
              c.box(padx=6.0, pady=1.0, radius=6.0, bg=@sf.alpha(t.p.red, 0.12), fn() {
                c.text(tr("android-chat.history.send.failed"), size=11.0, color=t.p.red, wrap=false)
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
        c.box(dir=Row, w=Fill(1.0), align=AStretch, fn() {
          c.box(w=Px(2.0), radius=1.0, bg=t.p.line, fn() {  }) |> ignore
          c.box(w=Fill(1.0), pl=10.0, max_h=42.0, clip=true, fn() {
            c.text(plain_words(s.text), size=14.0, color=t.p.text, line=21.0) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.box(pt=3.0, fn() {
        if s.received {
          avatar(c, src, s.by.name, s.by.name, "", 18.0)
        } else {
          agent_avatar(c, s.by.maker, s.by.runtime)
        }
        c.box(
          w=Px(14.0),
          h=Px(14.0),
          radius=7.0,
          bg=k.canvas,
          border=1.0,
          border_color=t.p.line,
          tx=10.0,
          ty=-8.0,
          align=ACenter,
          justify=JCenter,
          fn() { @sf.slack_mark(c, 9.0) |> ignore },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What was said elsewhere in the wide frame, as the web's (Chat.tsx SentElsewhere, an OthersMessage): its picture out
/// in the margin with Slack's (or Feishu's) mark on its corner, then its name, where it went or came from (an arrow in
/// the accent, 发送到 / 来自 in grey, the place on the neutral ground: a link when there is one) and its time over its
/// words, all of them, as Markdown.
fn sent_elsewhere_wide(c : @ui.Ctx, src : Source, here : Here, s : Elsewhere) -> Unit {
  let t = @sf.theme()
  // an agent of the chat's name opens its history beside the chat (the web's chatPage.agent)
  let mine = !s.received && s.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == s.by.agent })
  let name = c.id("elsewhere-name/" + s.key)
  if mine {
    c.cursor(name, Hand)
    if c.clicked(name) {
      side_toggle(ref_of(here), s.by.agent)
    }
  }
  let place_link = match s.place {
    Some(p) => p.url
    None => ""
  }
  let place = if place_link != "" { c.id("elsewhere-place/" + s.key) } else { 0 }
  if place != 0 {
    c.cursor(place, Hand)
    if c.clicked(place) {
      open_link(place_link)
    }
  }
  c.box(style=elsewhere_row, fn() {
    c.box(style=elsewhere_main, fn() {
      c.box(style=elsewhere_head, fn() {
        c.box(style=elsewhere_name, id=if mine { name } else { 0 }, fn() {
          c.text(s.by.name, style=if mine && c.hovered(name) { wide_name_hot } else { wide_name }) |> ignore
        })
        |> ignore
        c.box(style=elsewhere_route, fn() {
          @sf.icon(c, if s.received { "received" } else { "send" }, size=14.0, color=t.p.accent) |> ignore
          let words = tr(if s.received { "web-main.chat.fromSlack" } else { "web-main.history.sentTo" }).trim_end(chars=" ").to_string()
          c.text(words, style=elsewhere_words) |> ignore
          c.box(style=if place != 0 && c.hovered(place) { elsewhere_place_hot } else { elsewhere_place }, id=place, fn() {
            let (mark, said) = match s.place {
              Some(p) => (p.surface, p.name)
              None => ("slack", "Slack")
            }
            if mark == "ember" || mark == "stillfail" {
              @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 12.0) |> ignore
            } else {
              @sf.slack_mark(c, 12.0) |> ignore
            }
            c.text(said, style=elsewhere_place_words) |> ignore
          })
          |> ignore
          if s.failed {
            c.box(style=elsewhere_failed, fn() { c.text(tr("android-chat.history.send.failed"), style=elsewhere_failed_words) |> ignore }) |> ignore
          }
        })
        |> ignore
        message_time(c, "s:" + s.key, s.time)
      })
      |> ignore
      @sf.markdown(c, s.text, key="elsewhere/" + s.key, size=web_body, ink=t.p.text, on_link=fn(h) { open_link(h) }) |> ignore
    })
    |> ignore
    c.layer(fn() {
      let av = said_avatar(c, fn() {
        if s.received {
          avatar(c, src, s.by.name, s.by.name, "", 18.0)
        } else {
          agent_avatar(c, s.by.maker, s.by.runtime)
        }
        // the place's mark on its corner, 6 past it (Chat.css.ts msgAvatarSlack)
        c.layer(fn() {
          c.box(style=elsewhere_mark, tx=10.0, ty=10.0, fn() { @sf.slack_mark(c, 9.0) |> ignore }) |> ignore
        })
        |> ignore
      })
      c.stick(av, wide_avatar_held)
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let elsewhere_row : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let elsewhere_main : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// Its head (Chat.css.ts msgHead): 24 high at least, 6 apart; the route takes what room is left, its place cut short
/// first (msgRoute).
// kept across runs: a value (no field of it changes)
let elsewhere_head : @ui.Style = @ui.css("row w=Full min_h=S6 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let elsewhere_name : @ui.Style = @ui.style(max_w=@sf.name_max)

///|
// kept across runs: a value (no field of it changes)
let elsewhere_route : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let elsewhere_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The place (later.css.ts hPlace): its mark and its name, 12 in 500, 1 by 6 in, 6 round on the neutral ground; a
/// link's the pointer's ground under the pointer.
// kept across runs: a value (no field of it changes)
let elsewhere_place : @ui.Style = @ui.css("row px=S1_5 py=SPx gap=S1 radius=Md bg=Neutral align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let elsewhere_place_hot : @ui.Style = elsewhere_place.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let elsewhere_place_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Fg, leading=L5, wrap=false)

///|
/// Sending it failed: a red pill (the web's Pill tone red).
// kept across runs: a value (no field of it changes)
let elsewhere_failed : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Md bg=DangerBg")

///|
// kept across runs: a value (no field of it changes)
let elsewhere_failed_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Danger, wrap=false)

///|
/// The place's mark on the picture's corner: 14 round, 6 past its right and foot edges, on the list's ground, a line
/// round it (Chat.css.ts msgAvatarSlack).
// kept across runs: a value (no field of it changes)
let elsewhere_mark : @ui.Style = @ui.css(
  #|w=S3_5 h=S3_5 radius=Full bg=Bg border=B1 border_color=Line align=ACenter justify=JCenter
)

///|
/// A message sent from here that the chat does not show yet (Chat.kt Out): on its way, or failed (its words faded,
/// 未发送 in red).
fn outgoing(c : @ui.Ctx, src : Source, here : Here, o : Outgoing) -> Unit {
  let t = @sf.theme()
  let failed = o.state == "failed"
  c.box(w=Fill(1.0), gap=4.0, align=AEnd, fn() {
    c.box(w=Fill(1.0), gap=4.0, align=AEnd, opacity=if failed { 0.55 } else { 1.0 }, fn() {
      quote_cards(c, src, here, o.quotes, o.attachments, true)
      if o.text != "" {
        bubble(c, o.text, "o:" + o.id)
      }
      files(c, src, here, beside_quotes(o.quotes, o.attachments), true)
      // still going up: it is sent once they are (the core sends it), as the web's says (Chat.kt Out)
      for i, u in o.uploads {
        let (name, size, sent) = u
        let f : Pending = {
          id: i,
          name,
          size,
          image: "",
          width: 0,
          height: 0,
          pasted: None,
          local: None,
          done: None,
          sent,
          error: if failed { Some(if o.error != "" { o.error } else { tr("android-chat.file.failed") }) } else { None },
          core_id: "",
          retry: false,
          retrying: false,
        }
        file_tile(c, f, 0, closable=false) |> ignore
      }
    })
    |> ignore
    if failed {
      // said briefly (a tap says why); sending it again or dropping it right beside
      let why = c.id("unsent/" + o.id)
      if c.clicked(why) {
        say(
          c,
          if o.error != "" {
            fill("android-chat.chat.unsent.why", [("error", o.error)])
          } else {
            tr("android-chat.chat.unsent.toast")
          },
        )
      }
      let v = here.view
      let retrying = cui.doing.contains("retry/" + o.id)
      let discarding = cui.doing.contains("discard/" + o.id)
      c.box(dir=Row, pt=4.0, gap=2.0, align=ACenter, fn() {
        c.box(dir=Row, pr=6.0, gap=4.0, align=ACenter, id=why, fn() {
          @sf.icon(c, "info", size=12.0, color=t.p.red) |> ignore
          c.text(tr("android-chat.chat.unsent"), size=unsent_size(), color=t.p.red, wrap=false) |> ignore
        })
        |> ignore
        unsent_button(c, src, here, o, "chat.retry", "retry", tr("common.retry"), !v.offline && !v.archived && !discarding, retrying)
        unsent_button(c, src, here, o, "chat.discard", "trash", tr("common.delete"), !retrying, discarding)
      })
      |> ignore
    } else if !o.followed {
      let sending = if o.waits != "" {
        o.waits
      } else if o.uploads.length() > 0 {
        tr("common.uploading")
      } else {
        tr("android-chat.chat.sending")
      }
      // not seen while its words fly here, its room kept (Chat.kt Out: a layer at no opacity)
      match flying.val {
        Some(_) => {
          let w = c.box(fn() { under_way(c, sending) })
          c.look(w, @ui.look(alpha=0.0))
        }
        None => under_way(c, sending)
      }
    }
  })
  |> ignore
}

///|
/// 重试 or 删除 under a message that did not go (Chat.kt UnsentButton): a spinner on it while it is done, neither
/// pressed again meanwhile; what failed in it said in a toast.
fn unsent_button(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  o : Outgoing,
  call : String,
  icon : String,
  label : String,
  enabled : Bool,
  busy : Bool,
) -> Unit {
  let t = @sf.theme()
  let k = ink()
  let what = if call == "chat.retry" { "retry/" } else { "discard/" }
  let id = c.id("unsent/" + what + o.id)
  if c.clicked(id) && enabled && !busy {
    if src.read_only {
      say(c, read_only_words)
    } else {
      cui.doing[what + o.id] = true
      let p : Map[String, Json] = { "station": Json::string(here.station), "id": Json::string(o.id) }
      match here.view.thread {
        Some(th) => p["thread"] = Json::number(th)
        None => p["session"] = Json::string(here.session)
      }
      let verb = tr(if call == "chat.retry" { "android-chat.chat.retry.verb" } else { "android-chat.chat.delete.verb" })
      (src.call)(call, Json::object(p), fn(res) {
        cui.doing.remove(what + o.id)
        match res {
          Err(e) => {
            app.toast = verb + "：" + text(Some(e), "message")
            app.toast_n += 1
          }
          _ => ()
        }
      })
    }
  }
  // (in the wide frame the pointer's ground and the text's ink under it: Chat.css.ts msgUnsentBtn)
  let hot = wide_on.val && enabled && !busy && c.hovered(id)
  if wide_on.val && enabled && !busy {
    c.cursor(id, Hand)
  }
  let ink = if hot { k.text } else { k.muted }
  c.box(
    dir=Row,
    padx=7.0,
    pady=3.0,
    gap=4.0,
    radius=7.0,
    align=ACenter,
    bg=if hot { @sf.theme().p.hover } else { 0L },
    opacity=if enabled { 1.0 } else { 0.5 },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else {
        @sf.icon(c, icon, size=12.0, color=ink) |> ignore
      }
      c.text(label, size=unsent_size(), color=ink, wrap=false) |> ignore
      // Chat.kt: clip(Smooth(7)).clickable (not while busy)
      if enabled && !busy {
        @motion.ripple(c, id, 7.0)
      }
    },
  )
  |> ignore
}

///|
/// What is said under a message that did not go: 13 (Chat.kt); the web's 12 (Chat.css.ts msgUnsent).
fn unsent_size() -> Double {
  if wide_on.val {
    12.0
  } else {
    13.0
  }
}

///|
/// A running clock's second.
let clock_tick_ms : Double = 1000.0


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
/// How long a shown thing stays before another replaces it (Chat.kt steady).
let steady_ms : Double = 700.0

///|
/// How long the new words take to come in as the old go (Chat.kt Activity's AnimatedContent: 240 ms).
let now_swap_ms : Double = 240.0

///|
/// What the agent does now, steadied (`said`: its key and words), the new crossfading in from a quarter of its
/// height below as the old leaves a quarter above (Chat.kt Activity's AnimatedContent), on one line.
fn now_words(c : @ui.Ctx, row : String, said : (String, String), color : Int64) -> Unit {
  let (key, words) = said
  let st = match steadies.get(row) {
    Some(s) => s
    None => {
      let s = { key, words, was: "", at: -1.0e9 }
      steadies[row] = s
      s
    }
  }
  let swap = @motion.anim(c, "now-swap/" + row, 1.0, global=true)
  if key == st.key || words == st.words {
    st.key = key
    st.words = words
  } else if c.now >= st.at + steady_ms {
    st.was = st.words
    st.key = key
    st.words = words
    st.at = c.now
    swap.snap(0.0)
    swap.animate(1.0, @motion.tween(now_swap_ms))
  } else {
    c.wake_in(st.at + steady_ms - c.now)
  }
  let p = swap.get()
  // one line's room: the words going laid out under the new ones and drawn over them
  c.box(style=now_room, fn() {
    let said = fn(words : String) { c.text(words, style=if wide_on.val { now_said_wide } else { now_said }, color~) }
    let cur = said(st.words)
    if p < 1.0 {
      c.look(cur, @ui.look(alpha=p, dy=now_line / 4.0 * (1.0 - p)))
      c.look(said(st.was), @ui.look(alpha=1.0 - p, dy=-now_line - now_line / 4.0 * p))
    }
  })
  |> ignore
}

///|
/// The words' room, a line high: what goes and comes cut at its edges (AnimatedContent's SizeTransform clips).
// kept across runs: a value (no field of it changes)
let now_room : @ui.Style = @ui.style(h=Fixed(now_line), clip=true)

///|
/// What it does now: 15, on one line.
// kept across runs: a value (no field of it changes)
let now_said : @ui.TextStyle = @ui.text_style(size=Lg, wrap=false)

///|
/// The wide screen's: 13 (Chat.css.ts activityLine).
// kept across runs: a value (no field of it changes)
let now_said_wide : @ui.TextStyle = @ui.text_style(size=Sm, wrap=false)

///|
/// Its line's height (Lg's): the words come and go a quarter of it.
let now_line : Double = 21.0

///|
/// An agent at work, in one line (Chat.kt Activity): its picture ringed while it works (a still, quiet ring while it
/// waits on work it started), what it does now as the core says, and how long its turn has run.
fn activity(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  a : Agent,
  leaving? : Bool = false,
  first? : Bool = false,
) -> Unit {
  let ek = here.station + "\u{1}" + here.session
  let em = emits_of(ek)
  // a message coming out of its avatar: the line folds to its avatar (200 ms Ease.Out; faded by 160), and the avatar
  // is away while its copy flies (emit.mbt, ChatMotion.kt)
  let folded = emit_folded(em, a.key)
  let tail = @motion.animate(c, "tail/" + a.key, if folded { 0.0 } else { 1.0 }, spec=@motion.tween(200.0, ease=Out))
  let tail_fade = @motion.animate(c, "tail-fade/" + a.key, if folded { 0.0 } else { 1.0 }, spec=@motion.tween(160.0, ease=Out))
  let t = @sf.theme()
  let k = ink()
  let live = (src.topic)("live", { "station": Json::string(here.station), "key": Json::string(a.key) })
  let said = match a.wait {
    Some((_, _, w)) => ("wait", if w != "" { w } else { tr("android-chat.chat.waiting") })
    None => {
      let n = field(field(live.value, "activity"), "now")
      match text(n, "text") {
        "" => ("busy", tr("android-chat.chat.working"))
        s => (text(n, "key"), s)
      }
    }
  }
  let now = (src.now)()
  let clock = match a.wait {
    Some((since, most, _)) => {
      let waited = match most {
        Some(sec) => dmin(now, since + sec * 1000.0)
        None => now
      }
      // (stopped at the most it waits)
      if waited >= now {
        c.every(clock_tick_ms, elapsed=dmax(waited - since, 0.0)) |> ignore
      }
      elapsed(waited - since) +
      (match most {
        Some(sec) => " / " + elapsed(sec * 1000.0)
        None => ""
      })
    }
    None =>
      match a.since {
        Some(s) => {
          c.every(clock_tick_ms, elapsed=dmax(now - s, 0.0)) |> ignore
          elapsed(now - s)
        }
        None => ""
      }
  }
  // tapped, its execution history (History.kt), its press drawn round it; in the wide frame beside the chat, pressed
  // again in front closed (the web's chatPage.history), its words the text's under the pointer
  let id = c.id("activity/" + a.key)
  let wide = wide_on.val
  if c.clicked(id) {
    if wide {
      side_toggle(ref_of(here), a.key)
    } else {
      app.nav.push(History(ref_of(here), a.key, None))
    }
  }
  if wide {
    c.cursor(id, Hand)
  }
  let words_ink = if wide && c.hovered(id) { k.text } else { k.muted }
  // one of several agents: stopped alone from its row, under the pointer (Chat.tsx Activity `stoppable`)
  let row = c.id("activity-row/" + a.key)
  c.box(dir=Row, w=Fill(1.0), align=ACenter, id=row, fn() {
  c.box(
    dir=Row,
    gap=activity_gap(),
    align=ACenter,
    radius=6.0,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.1) } else { 0L },
    tx=activity_out(),
    id~,
    fn() {
    let face = c.box(w=Px(24.0), h=Px(24.0), tx=-ring_room, align=ACenter, justify=JCenter, fn() {
      let av = c.box(fn() { agent_avatar(c, a.maker, a.runtime) })
      @motion.measure(c, av, "emit-avatar/" + ek + "/" + a.key)
      // its turn over, the ring goes first (Chat.kt WorkRing: 160 ms)
      let ring = @motion.animate(c, "ring/" + here.station + "/" + a.key, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(160.0))
      let rl = c.layer(fn() { work_ring(c, a.wait is Some(_)) })
      c.look(rl, @ui.look(alpha=ring))
    })
    // away while its copy flies, the ring with it (Chat.kt: the face's alpha while motion.copied is this agent)
    if em.copied == a.key {
      c.look(face, @ui.look(alpha=0.0))
    }
    // what it does now and how long: folded away to its width's share, cut there, faded
    let natural = match @motion.measured_rect(c, "emit-tail/" + ek + "/" + a.key) {
      Some(r) => r.2
      None => 0.0
    }
    let cut = tail < 1.0 && natural > 0.0
    let tb = c.box(dir=Row, max_w=if cut { natural * tail } else { 1.0e9 }, clip=cut, fn() {
      let inner = c.box(dir=Row, fn() {
        now_words(c, ek + "\u{1}" + a.key, said, words_ink)
        if clock != "" {
          let (gap, size) = clock_type()
          c.box(pl=gap, fn() { c.text(clock, size~, color=k.subtle, wrap=false) |> ignore })
          |> ignore
        }
      })
      if !cut {
        @motion.measure(c, inner, "emit-tail/" + ek + "/" + a.key)
      }
    })
    if tail_fade < 1.0 {
      c.look(tb, @ui.look(alpha=tail_fade))
    }
    },
  )
  |> ignore
  // (always to a finger, which hovers over nothing: OpenJobs.css.ts openJobStop `hover: none`)
  if wide && here.view.agents.length() > 1 && (c.hovered(row) || c.hovered(id) || @ui.pointing() is Finger) {
    activity_stop(c, src, here, a)
  }
  })
  |> ignore
  ignore(first)
}

///|
/// Where an agent at work's line stands: its picture where a message's is, over the head's start; in the wide frame out
/// in the margin with them (Chat.css.ts activityLine: 35 out with its 6 of padding), the words 3 before the column's,
/// 8 after the picture (its 24 laid, drawn 3 before).
fn activity_out() -> Double {
  if wide_on.val {
    -wide_avatar_out
  } else {
    0.0
  }
}

///|
fn activity_gap() -> Double {
  if wide_on.val {
    2.0
  } else {
    5.0
  }
}

///|
/// How long its turn has run, after what it does: 3 after it in 15 (Chat.kt), the wide screen's 8 after in 13
/// (Chat.css.ts activityTail, activityElapsed).
fn clock_type() -> (Double, Double) {
  if wide_on.val {
    (8.0, 13.0)
  } else {
    (3.0, 15.0)
  }
}

///|
/// Stopping one agent of several from its line (Chat.tsx Activity's stop): a 22 square, 6 round, the stop's mark in
/// grey, the pointer's ground and the text's ink under the pointer; its tip says whose.
fn activity_stop(c : @ui.Ctx, src : Source, here : Here, a : Agent) -> Unit {
  let key = "stop/" + here.station + "/" + a.key
  let busy = doing(key)
  let id = if busy { 0 } else { c.id("activity-stop/" + a.key) }
  if id != 0 && c.clicked(id) {
    act(
      src,
      tr("android-chat.agent.stop"),
      key,
      "session.stop",
      { "station": Json::string(here.station), "key": Json::string(a.key) },
      done=tr("android-chat.history.stopped"),
    )
  }
  if id != 0 {
    c.cursor(id, Hand)
    @sf.tip(c, "activity-stop/" + a.key, id, fill("web-main.activity.stop", [("who", a.who)]))
  }
  let hot = id != 0 && c.hovered(id)
  c.box(style=if hot { activity_stop_hot } else { activity_stop_box }, id~, fn() {
    if busy {
      @sf.spinner(c, size=12.0) |> ignore
    } else {
      @sf.icon(c, "stop", size=12.0, color=if hot { @sf.theme().p.text } else { @sf.theme().p.muted }) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let activity_stop_box : @ui.Style = @ui.style(w=@sf.small_button, h=@sf.small_button, radius=Md, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let activity_stop_hot : @ui.Style = activity_stop_box.then(@ui.css("bg=Hover"))

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
