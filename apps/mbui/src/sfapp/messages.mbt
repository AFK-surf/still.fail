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
    Said(m) => said(c, src, here, m, list)
    Sent(s) => sent_elsewhere(c, src, here, s)
    Out(o) => outgoing(c, src, here, o)
    Working(a) => activity(c, src, here, a)
    Top | Foot => ()
  }
}

///|
/// Over the first message that was unread when the chat opened: the accent, a rule each side.
fn unread_line(c : @ui.Ctx) -> Unit {
  let accent = ink().accent
  c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
    c.box(w=Fill(1.0), h=Px(1.0), bg=@sf.alpha(accent, 0.5), fn() {  }) |> ignore
    c.text(tr("android-chat.chat.newBelow"), size=13.0, weight=500, color=accent, wrap=false)
    |> ignore
    c.box(w=Fill(1.0), h=Px(1.0), bg=@sf.alpha(accent, 0.5), fn() {  }) |> ignore
  })
  |> ignore
}

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
/// anyone else's under their picture, name and time, an agent's as Markdown with its files placed in it.
fn said(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  list : Array[Entry],
  decide? : Bool = true,
) -> Unit {
  ignore(list)
  let k = ink()
  if m.system {
    system_notice(c, src, here.station, m)
    return
  }
  if m.mine {
    c.box(w=Fill(1.0), gap=4.0, align=AEnd, fn() {
      quote_cards(c, m.quotes, true)
      if m.text != "" {
        pickable(c, m.ts, m.by.name, "person", m.text, false, fn() { bubble(c, m.text, m.ts) })
      }
      files(c, src, here, m.attachments, true)
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
      said_head(c, m.by.name, if mine { name } else { 0 }, m.ts, m.time)
      quote_cards(c, m.quotes, false)
      if m.author_kind == "person" {
        if m.text != "" {
          pickable(c, m.ts, m.by.name, "person", m.text, true, fn() { person_words(c, m.text, m.ts) })
        }
        files(c, src, here, m.attachments, false)
      } else {
        pickable(c, m.ts, m.by.name, "agent", m.text, true, fn() { agent_words(c, src, here, m) })
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
    // the picture over the name's start (where a message out of an avatar lands: hidden while the flying one is
    // over it)
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
/// chat's name colour, one line up to 240; `id` taps it) and when it was said.
fn said_head(c : @ui.Ctx, name : String, id : Int, key : String, time : Stamp?) -> Unit {
  let k = ink()
  c.box(dir=Row, w=Fill(1.0), pl=25.0, min_h=24.0, gap=6.0, align=ACenter, fn() {
    c.box(max_w=240.0, id~, fn() {
      c.text(name, size=15.0, weight=650, color=k.name, wrap=false, line=21.0) |> ignore
    })
    |> ignore
    message_time(c, key, time)
  })
  |> ignore
}

///|
/// Where a message's picture goes, over its head's start (Chat.kt SaidRow: 3 down, centred on the name's line).
fn said_avatar(c : @ui.Ctx, body : () -> Unit) -> Int {
  c.box(pt=3.0, body)
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
    c.text(b.title + pct + note, size=10.0, color~, line=16.0) |> ignore
    if b.action != "" {
      c.text("·", size=10.0, color=ink().muted, wrap=false, line=16.0) |> ignore
      c.text(b.action, size=10.0, weight=600, color=if busy { ink().muted } else { ink().text }, wrap=false, line=16.0)
      |> ignore
    }
  })
  |> ignore
}

///|
/// The blocked line's mark and words, 4 apart.
// kept across runs: a value (no field of it changes)
let blocked_row : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

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
                @sf.markdown(c, said, key="notice/" + m.ts, size=15.0, ink=color) |> ignore
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
  c.text(words, size=15.0, color~, wrap=false, line=24.75) |> ignore
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
let notice_across : @ui.Style = @ui.style(w=Full, gap=S1, align=ACenter)

///|
/// A word at a notice's end that acts on it (Chat.kt InstallAction, ReportAction): " · " fainter, then the word, semibold
/// and underlined; while it is under way not offered.
fn notice_action(c : @ui.Ctx, key : String, action : String, color : Int64, busy : Bool, run : () -> Unit) -> Unit {
  let id = if busy { 0 } else { c.id(key) }
  if id != 0 && c.clicked(id) {
    run()
  }
  c.rich([@ui.span(" · ", color=@sf.alpha(color, notice_dot_alpha))], style=system_words, color~) |> ignore
  c.box(id~, fn() { c.rich([@ui.span(action, weight=600, underline=true)], style=system_words, color~) |> ignore })
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
  let b = c.box(max_w=c.width - 36.0, padx=14.0, pady=8.0, radius=18.0, bg=@sf.alpha(neutral, ground), fn() {
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
fn agent_words(c : @ui.Ctx, src : Source, here : Here, m : Message) -> Unit {
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
          // a link within a sentence to a visualization it places: opened over the whole screen (Prose.kt OpenedFile)
          match placed.get(base_name(h)) {
            Some(a) if is_viz(a.name) => viz_open_full(a.name, here.station, owner_of(here, a), a.path, here, linked=true)
            _ => open_link(h)
          }
        },
        on_link_hold=Some(fn(href, line) { link_held(c, href, line) }),
        found=found_words_of(m.ts),
        files=fn(name) {
          match placed.get(name) {
            // an HTML one is a visualization, drawn there; failing, its card (Prose.kt PlacedFile)
            Some(a) if is_viz(a.name) =>
              Some(fn() { viz_file(c, src, here, m.ts, a, fn() { files(c, src, here, [a], false) }) })
            Some(a) => Some(fn() { files(c, src, here, [a], false) })
            None => None
          }
        },
        // an image of its own in a table's cell, by its proportion (Prose.kt Placing.row: StationImage at a size)
        cell_files=fn(name) {
          match placed.get(name) {
            Some(a) if kind_of(a.name) == "image" => {
              let r = if a.width > 0.0 && a.height > 0.0 { a.width / a.height } else { cell_image_ratio }
              Some((r, fn(w) { file_item(c, src, here, a, w) }))
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
      c.box(w=Fill(1.0), pt=4.0, fn() { files(c, src, here, rest, false) }) |> ignore
    }
  })
  |> ignore
}

///|
/// Quotes as sent, each a card of its own ahead of the message (Chat.kt QuoteCards): the passage small and grey,
/// whose it is; then what was said about it.
fn quote_cards(c : @ui.Ctx, quotes : Array[Quote], mine : Bool) -> Unit {
  if quotes.length() == 0 {
    return
  }
  let k = ink()
  let most = dmin(380.0, (c.width - 28.0) * 0.88)
  c.box(w=Fill(1.0), gap=4.0, align=if mine { AEnd } else { AStart }, fn() {
    for q in quotes {
      c.box(max_w=most, radius=12.0, bg=k.card, fn() {
        c.box(
          dir=Row,
          pl=11.0,
          pr=11.0,
          pt=7.0,
          pb=if q.comment == "" { 7.0 } else { 0.0 },
          align=AStart,
          fn() {
            c.box(w=Px(15.0), h=Px(19.5), justify=JCenter, fn() {
              @sf.icon(c, "quote", size=11.0, color=k.accent) |> ignore
            })
            |> ignore
            // two lines at most
            c.box(max_h=39.0, clip=true, fn() {
              c.rich(
                [
                  @ui.span(fill("android-chat.quote.who", [("name", q.author)]), weight=500, color=k.text),
                  @ui.span(q.text),
                ],
                size=13.0,
                color=k.muted,
                line=19.5,
              )
              |> ignore
            })
            |> ignore
          },
        )
        |> ignore
        if q.comment != "" {
          c.box(pl=11.0, pr=11.0, pt=3.0, pb=8.0, fn() {
            c.text(q.comment, size=15.0, color=k.text, line=22.5) |> ignore
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
/// The kind of a file by its name (FileKinds.kt kindOf): image, video, or anything else.
fn kind_of(name : String) -> String {
  let lower = lower(name)
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
/// A file's size in words (Controls.kt fileSize).
fn file_size(bytes : Double) -> String {
  let kb = 1024.0
  if bytes < kb {
    "\{bytes.to_int()} B"
  } else if bytes < kb * kb {
    "\{(bytes / kb).round().to_int()} KB"
  } else if bytes < kb * kb * kb {
    one_decimal(bytes / kb / kb, 1) + " MB"
  } else {
    one_decimal(bytes / kb / kb / kb, 2) + " GB"
  }
}

///|
fn one_decimal(x : Double, places : Int) -> String {
  let scale = if places == 2 { 100.0 } else { 10.0 }
  let n = (x * scale).round().to_int()
  let whole = n / scale.to_int()
  let part = n % scale.to_int()
  let digits = if places == 2 && part < 10 { "0\{part}" } else { "\{part}" }
  "\{whole}.\{digits}"
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
          let item = c.box(fn() { file_item(c, src, here, list[i], widths[i]) })
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
/// on black with the play mark and its name, anything else a card.
fn file_item(c : @ui.Ctx, src : Source, here : Here, a : Attachment, w : Double) -> Unit {
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
      note_thumb(c, thumb, open, 10.0, letterbox~)
      c.box(w=Px(w), h=Px(h), radius=10.0, clip=true, bg=t.p.chip, id=open, opacity=thumb_shows(thumb), fn() {
        if key != "" && key != "!" {
          c.image(
            key,
            w=Px(w),
            h=Px(h),
            fit=if letterbox { FitContain } else { FitCover },
            radius=10.0,
            bg=0L,
            fade=sent is None,
          )
          |> ignore
        } else if key == "!" {
          c.box(w=Fill(1.0), h=Fill(1.0), gap=6.0, align=ACenter, justify=JCenter, fn() {
            @sf.icon(c, "read", size=20.0, color=t.p.muted) |> ignore
            c.text(tr("android-chat.file.noPreview"), size=12.0, color=t.p.muted, wrap=false)
            |> ignore
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
      note_thumb(c, thumb, open, 10.0, letterbox~)
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
      c.box(w=Px(w), h=Px(h), radius=10.0, clip=true, bg=0x000000FFL, id=open, opacity=thumb_shows(thumb), fn() {
        if still != "" && still != "!" {
          c.layer(fn() {
            c.image(
              still,
              w=Px(w),
              h=Px(h),
              fit=if letterbox { FitContain } else { FitCover },
              radius=10.0,
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
        c.layer(fn() {
          c.spacer()
          c.box(w=Fill(1.0), padx=8.0, pady=6.0, bg=0x000000A6L, align=ACenter, fn() {
            c.text(a.name, size=12.0, color=0xFFFFFFFFL, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    _ => file_card(c, a, w, id=open)
  }
}

///|
/// A file as a card (ChatFiles.kt FileCard): its kind's mark, its name, its size, on the neutral ground.
fn file_card(c : @ui.Ctx, a : Attachment, w : Double, id? : Int = 0) -> Unit {
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
      @sf.icon(c, "read", size=16.0, color=t.p.muted) |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(a.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
        c.text(file_size(a.size), size=11.0, color=t.p.muted, wrap=false, line=16.0)
        |> ignore
      })
      |> ignore
    },
  )
  |> ignore
}

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
  let quiet = fn(words : String) {
    c.box(pt=2.0, fn() { c.text(words, size=13.0, color=k.subtle, line=19.0) |> ignore })
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
      // (who decides over the options as the message's column has them: 4 apart)
      c.box(w=Fill(1.0), gap=4.0, align=AStart, fn() {
        match m.card {
          Some({ assignee_text: Some(a), .. }) => quiet(a)
          _ => ()
        }
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
/// How far in the card of options' rows stand, how far a row's number stands in it, its disc's size: the first disc is
/// in the card's corner, and the card's corner is drawn round it (docs/ui-panels.md: a whole circle stays round, the
/// container follows it).
let options_card_pad : Double = 8.0

///|
let options_row_pad : Double = 7.0

///|
let option_disc : Double = 22.0

///|
let options_card_radius : Double = @sf.around(options_card_pad + options_row_pad, option_disc / 2.0)

///|
/// A card of options (SettingParts.kt DecisionOptions): each a row to be pressed (its ground under the finger 8 in
/// from the card's edge, rounded 18), its number in a disc (the one recommended in the accent), its label and what it
/// leads to; hairlines between them; half there when not `enabled`, a spinner on the one being answered (`busy`, none
/// pressed meanwhile). The option tapped, on the frame after.
fn decision_options(
  c : @ui.Ctx,
  key : String,
  options : Array[Choice],
  enabled : Bool,
  busy : String?,
  chosen? : String? = None,
) -> Choice? {
  let t = @sf.theme()
  let free = enabled && busy is None
  let mut picked : Choice? = None
  c.box(w=Fill(1.0), pt=6.0, fn() {
    c.box(w=Fill(1.0), radius=options_card_radius, bg=t.p.chip, pad=options_card_pad, fn() {
      // (nothing drawn between two: SettingParts.kt DecisionOptions)
      for i, o in options {
        let id = c.id(key + "/" + i.to_string())
        if c.clicked(id) && free {
          picked = Some(o)
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          pl=options_row_pad,
          pr=12.0,
          pt=options_row_pad,
          pb=options_row_pad,
          gap=12.0,
          align=AStart,
          radius=18.0,
          opacity=if enabled || chosen == Some(o.label) { 1.0 } else { 0.5 },
          id~,
          fn() {
            c.box(
              w=Px(option_disc),
              h=Px(option_disc),
              radius=option_disc / 2.0,
              bg=if o.recommended { t.p.accent } else { @sf.alpha(t.p.text, 0.09) },
              align=ACenter,
              justify=JCenter,
              fn() {
                let color = if o.recommended { 0xFFFFFFFFL } else { t.p.muted }
                if i < 6 {
                  @sf.icon(c, "option-\{i + 1}", size=22.0, color~) |> ignore
                } else {
                  c.text("\{i + 1}", size=12.0, weight=600, color~, wrap=false) |> ignore
                }
              },
            )
            |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(o.label, size=15.0, weight=500, color=t.p.text, line=21.0) |> ignore
              if o.detail != "" {
                c.text(o.detail, size=13.0, color=t.p.muted, line=18.0) |> ignore
              }
            })
            |> ignore
            if busy == Some(o.label) {
              c.box(h=Px(21.0), justify=JCenter, fn() { @sf.spinner(c, size=12.0) |> ignore })
              |> ignore
            }
            // SettingParts.kt options: clickable while free, its ripple in the ink (ripple(color = C.ink))
            if free {
              @motion.ripple(c, id, 18.0, ink=@sf.alpha(t.p.text, 0.1))
            }
          },
        )
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  picked
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
  ignore(here)
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
/// A message sent from here that the chat does not show yet (Chat.kt Out): on its way, or failed (its words faded,
/// 未发送 in red).
fn outgoing(c : @ui.Ctx, src : Source, here : Here, o : Outgoing) -> Unit {
  let t = @sf.theme()
  let failed = o.state == "failed"
  c.box(w=Fill(1.0), gap=4.0, align=AEnd, fn() {
    c.box(w=Fill(1.0), gap=4.0, align=AEnd, opacity=if failed { 0.55 } else { 1.0 }, fn() {
      quote_cards(c, o.quotes, true)
      if o.text != "" {
        bubble(c, o.text, "o:" + o.id)
      }
      files(c, src, here, o.attachments, true)
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
          c.text(tr("android-chat.chat.unsent"), size=13.0, color=t.p.red, wrap=false) |> ignore
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
  c.box(
    dir=Row,
    padx=7.0,
    pady=3.0,
    gap=4.0,
    radius=7.0,
    align=ACenter,
    opacity=if enabled { 1.0 } else { 0.5 },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else {
        @sf.icon(c, icon, size=12.0, color=k.muted) |> ignore
      }
      c.text(label, size=13.0, color=k.muted, wrap=false) |> ignore
      // Chat.kt: clip(Smooth(7)).clickable (not while busy)
      if enabled && !busy {
        @motion.ripple(c, id, 7.0)
      }
    },
  )
  |> ignore
}

///|
/// A running clock's second.
let clock_tick_ms : Double = 1000.0


///|
/// A running clock's reading in short (Chat.kt elapsed): 45s, 3m 20s, 1h 5m.
fn elapsed(ms : Double) -> String {
  let s = dmax(ms / 1000.0, 0.0).to_int()
  if s < 60 {
    "\{s}s"
  } else if s < 3600 {
    if s % 60 != 0 {
      "\{s / 60}m \{s % 60}s"
    } else {
      "\{s / 60}m"
    }
  } else if s % 3600 / 60 != 0 {
    "\{s / 3600}h \{s % 3600 / 60}m"
  } else {
    "\{s / 3600}h"
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
    let said = fn(words : String) { c.text(words, style=now_said, color~) }
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
  // tapped, its execution history (History.kt), its press drawn round it
  let id = c.id("activity/" + a.key)
  if c.clicked(id) {
    app.nav.push(History(ref_of(here), a.key, None))
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    gap=5.0,
    align=ACenter,
    radius=6.0,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.1) } else { 0L },
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
        now_words(c, ek + "\u{1}" + a.key, said, k.muted)
        if clock != "" {
          c.box(pl=3.0, fn() { c.text(clock, size=15.0, color=k.subtle, wrap=false) |> ignore })
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
  ignore(first)
}

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
