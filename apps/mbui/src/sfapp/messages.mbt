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
    system_notice(c, m)
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
          Some(b) if b.state != "installed" => blocked_line(c, b)
          _ =>
            if m.waiting {
              under_way(c, tr("android-chat.chat.waitingAgent"))
            } else {
              // coming in with the words, when they fly here from the composer
              match flying.val {
                Some(f) => {
                  let at = c.box(fn() { message_time(c, m.ts, m.time) })
                  c.look(at, @ui.look(alpha=flight_settled(flight_p(c, f))))
                }
                None => message_time(c, m.ts, m.time)
              }
            }
        }
      }
    })
    |> ignore
    return
  }
  c.box(w=Fill(1.0), fn() {
    c.box(w=Fill(1.0), gap=4.0, align=AStart, fn() {
      c.box(dir=Row, w=Fill(1.0), pl=25.0, min_h=24.0, gap=6.0, align=ACenter, fn() {
        // an agent of the chat's name opens its card (AgentSheet.kt)
        let mine = m.by.agent != "" && here.view.agents.iter().any(fn(a) { a.key == m.by.agent })
        let name = c.id("name/" + m.ts)
        if mine && c.clicked(name) {
          open_sheet(c, AgentOf(ref_of(here), m.by.agent))
        }
        c.box(max_w=240.0, id=if mine { name } else { 0 }, fn() {
          c.text(m.by.name, size=15.0, weight=650, color=k.name, wrap=false, line=21.0)
          |> ignore
        })
        |> ignore
        message_time(c, m.ts, m.time)
      })
      |> ignore
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
      decision_under(c, src, here, m)
      // letting go what it asks (Chat.kt AskDismiss)
      ask_dismiss(c, src, here, m)
      match m.archive_check {
        Some((words, failed)) =>
          c.box(pt=6.0, fn() {
            c.text(
              words,
              size=12.0,
              color=if failed { @sf.theme().p.red } else { @sf.theme().p.muted },
              line=18.0,
            )
            |> ignore
          })
          |> ignore
        None => ()
      }
      if archive_under(here.view) == Some(m.seq) {
        archive_buttons(c, src, here)
      }
    })
    |> ignore
    // the picture over the name's start
    c.layer(fn() {
      c.box(pt=3.0, fn() { message_avatar(c, src, m) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The post 归档这个 chat goes under (Chat.kt Here.archiveUnder): the agents' latest that ended all done, while the
/// chat is offered to archive.
fn archive_under(v : ChatView) -> Double? {
  if !v.archive_offered || v.archived || v.pending {
    return None
  }
  let mut i = v.messages.length() - 1
  while i >= 0 {
    let m = v.messages[i]
    if m.author_kind == "agent" && m.ending == "all_done" {
      return Some(m.seq)
    }
    i = i - 1
  }
  None
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
fn blocked_line(c : @ui.Ctx, b : Install) -> Unit {
  let t = @sf.theme()
  let stuck = b.state == "missing" || b.state == "failed"
  let color = if stuck { t.p.red } else { ink().muted }
  c.box(dir=Row, gap=4.0, align=ACenter, fn() {
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
      c.text(b.action, size=10.0, weight=600, color=ink().text, wrap=false, line=16.0)
      |> ignore
    }
  })
  |> ignore
}

///|
/// What still.fail itself says (Chat.kt SystemNotice): a pill across the chat, one line cut short, no time; tapped,
/// all its words and its time under them. A failure (⚠️ at its start) is the pill in red.
fn system_notice(c : @ui.Ctx, m : Message) -> Unit {
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
  } else if t.dark {
    0xFFFFFF0DL
  } else {
    0x26211711L
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
  c.box(w=Fill(1.0), gap=4.0, align=ACenter, fn() {
    c.box(
      max_w=c.width - 28.0,
      padx=14.0,
      pady=6.0,
      radius=if open { 16.0 } else { 18.0 },
      bg=ground,
      id~,
      fn() {
        if open {
          @sf.markdown(c, said, key="notice/" + m.ts, size=15.0, ink=color) |> ignore
        } else {
          let first = match said.split("\n").find_first(fn(l) { l.trim(chars=" ").to_string() != "" }) {
            Some(l) => l.to_string()
            None => said
          }
          let row = c.box(dir=Row, align=ACenter, fn() {
            // cut short where it does not fit
            c.box(fn() {
              c.text(plain_words(first), size=15.0, color~, wrap=false, line=24.75) |> ignore
            })
            |> ignore
            match m.install {
              Some(i) if i.action != "" => {
                c.text(" · ", size=15.0, color=@sf.alpha(color, 0.6), wrap=false) |> ignore
                c.text(i.action, size=15.0, weight=600, color~, wrap=false, line=24.75)
                |> ignore
              }
              _ => ()
            }
          })
          ignore(row)
        }
      },
    )
    |> ignore
    if open {
      message_time(c, m.ts, m.time)
    }
  })
  |> ignore
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
    ref_runs(words),
    key="words/" + ts,
    size=15.0,
    color=ink().text,
    line=23.0,
    link_color=t.p.blue,
    pressed_bg=@sf.alpha(t.p.blue, 0.14),
    on_link=fn(h) { open_link(h) },
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
    Some(f) if f.placed_at >= 0.0 => flight_ground(flight_p(c, f))
    _ => 1.0
  }
  // gone to (a notification's), the bubble takes the accent's ground as it flashes (Chat.kt Bubble: lit)
  let lit = if flashing.val.0 == ts { flashing.val.1 } else { 0.0 }
  let neutral = if lit > 0.0 { @sf.mix(flash_ground(), lit, k.neutral) } else { k.neutral }
  let b = c.box(max_w=c.width - 36.0, padx=14.0, pady=8.0, radius=18.0, bg=@sf.alpha(neutral, ground), fn() {
    c.rich(
      ref_runs(words),
      key="bubble/" + ts,
      size=16.0,
      color=k.text,
      line=21.0,
      link_color=t.p.blue,
      pressed_bg=@sf.alpha(t.p.blue, 0.14),
      on_link=fn(h) { open_link(h) },
    )
    |> ignore
  })
  match flying.val {
    Some(f) => flight_bubble(c, f, b)
    None => ()
  }
}

///|
/// A link tapped in a message: one to another chat opens it here (AppState.openLink); the rest are not opened from
/// this slice.
fn open_link(href : String) -> Unit {
  match chat_of_link(href) {
    Some(r) => app.nav.push(Chat(r))
    None => ()
  }
}

///|
/// The chat a link names: …/w/<workspace>/s/<station>/chats/<key>.
fn chat_of_link(href : String) -> ChatRef? {
  guard href.find("/w/") is Some(i) else { return None }
  let parts = href.view(start_offset=i + 3).to_string().split("/").map(fn(v) { v.to_string() }).to_array()
  if parts.length() >= 5 && parts[1] == "s" && parts[3] == "chats" {
    let mut key = parts[4]
    for cut in ["?", "#"] {
      match key.find(cut) {
        Some(j) => key = key.view(end_offset=j).to_string()
        None => ()
      }
    }
    if key != "" {
      return Some({ station: parts[0] + "/" + parts[2], session: key, title: "", station_name: "" })
    }
  }
  None
}

///|
/// An agent's Markdown with its files (Prose.kt AgentWords): those its text names (`placed`) drawn there, the rest
/// below it.
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
        key="md/" + m.ts,
        size=15.0,
        ink=ink().text,
        on_link=fn(h) { open_link(h) },
        files=fn(name) {
          match placed.get(name) {
            Some(a) => Some(fn() { files(c, src, here, [a], false) })
            None => None
          }
        },
      )
      |> ignore
    }
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
/// A ThumbHash's width over its height, from its header (thumbhash.js thumbHashToApproximateAspectRatio).
fn thumb_ratio(hash : String) -> Double? {
  if hash == "" {
    return None
  }
  let bytes = @gallery.b64_decode(hash)
  if bytes.length() < 5 {
    return None
  }
  let header = bytes[3]
  let has_alpha = (bytes[2] & 0x80) != 0
  let is_landscape = (bytes[4] & 0x80) != 0
  let lx = if is_landscape { if has_alpha { 5 } else { 7 } } else { header & 7 }
  let ly = if is_landscape { header & 7 } else if has_alpha { 5 } else { 7 }
  if ly == 0 {
    None
  } else {
    Some(lx.to_double() / ly.to_double())
  }
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
          file_item(c, src, here, list[i], widths[i])
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
    open_preview(here.station, owner_of(here, a), a)
  }
  match kind_of(a.name) {
    "image" => {
      let (bw, bh, letterbox) = image_box(a, 16.0)
      let h = bh * w / bw
      let key = (src.file)(here.station, owner_of(here, a), base_name(a.path))
      c.box(w=Px(w), h=Px(h), radius=10.0, clip=true, bg=t.p.chip, id=open, fn() {
        if key != "" && key != "!" {
          c.image(
            key,
            w=Px(w),
            h=Px(h),
            fit=if letterbox { FitContain } else { FitCover },
            radius=10.0,
            bg=0L,
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
      let (bw, bh, _) = image_box(a, 96.0)
      let h = bh * w / bw
      c.box(w=Px(w), h=Px(h), radius=10.0, clip=true, bg=0x000000FFL, id=open, fn() {
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
/// Under a post (Decisions.kt DecisionUnder): a login card as its login stands; an options card's options while it
/// waits, who is to decide above them; once answered, how it went in a quiet line. (Answering is not done from here.)
fn decision_under(c : @ui.Ctx, src : Source, here : Here, m : Message) -> Unit {
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
  if resolved {
    match m.decision {
      Some({ text: Some(words), .. }) => quiet(words)
      _ => ()
    }
    return
  }
  match m.card {
    Some({ assignee_text: Some(a), .. }) => quiet(a)
    _ => ()
  }
  let busy = answering(here.station, m, options)
  match
    decision_options(
      c,
      "options/" + m.ts,
      options,
      !here.view.offline && !here.view.archived,
      busy,
    ) {
    Some(o) => answer_option(src, here.station, m.thread, m.seq, o.label)
    None => ()
  }
}

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
) -> Choice? {
  let t = @sf.theme()
  let free = enabled && busy is None
  let mut picked : Choice? = None
  c.box(w=Fill(1.0), pt=6.0, fn() {
    c.box(w=Fill(1.0), radius=24.4, bg=t.p.chip, pad=8.0, fn() {
      for i, o in options {
        if i > 0 {
          c.box(w=Fill(1.0), pl=41.0, pr=12.0, fn() {
            c.box(w=Fill(1.0), h=Px(1.0), bg=@sf.alpha(t.p.text, 0.07), fn() {  }) |> ignore
          })
          |> ignore
        }
        let id = c.id(key + "/" + i.to_string())
        if c.clicked(id) && free {
          picked = Some(o)
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          pl=7.0,
          pr=12.0,
          pt=7.0,
          pb=7.0,
          gap=12.0,
          align=AStart,
          radius=18.0,
          opacity=if enabled { 1.0 } else { 0.5 },
          bg=if free && c.pressed(id) { @sf.alpha(t.p.text, 0.08) } else { 0L },
          id~,
          fn() {
            c.box(
              w=Px(22.0),
              h=Px(22.0),
              radius=11.0,
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
/// A login as its card shows it (LoginCards.kt LoginCard): its title and how it stands while under way, with what the
/// person does now for one who may finish it (decide.mbt login_active); ended, a line saying how (failed in red). A
/// login the core does not know draws nothing.
fn login_card(c : @ui.Ctx, src : Source, station : String, id : String) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("machineLogin", { "station": Json::string(station), "id": Json::string(id) })
  let l = match topic.value {
    Some(Object(_)) as v => v
    _ => return
  }
  if !flag(l, "active") {
    let words = match text(l, "endedText") {
      "" => text(l, "title") + " · " + text(l, "statusText")
      s => s
    }
    c.box(pt=2.0, fn() {
      c.text(
        words,
        size=13.0,
        color=if text(l, "state") == "failed" { t.p.red } else { ink().subtle },
        line=19.0,
      )
      |> ignore
    })
    |> ignore
    return
  }
  let all = (src.topic)("machineLogins", { "station": Json::string(station) })
  c.box(pt=6.0, fn() {
    c.box(min_w=280.0, radius=17.6, bg=t.p.chip, pad=8.0, gap=2.0, fn() {
      c.box(pl=10.0, pr=10.0, pt=10.0, fn() {
        c.text(text(l, "title"), size=15.0, weight=500, color=t.p.text, line=21.0) |> ignore
      })
      |> ignore
      if flag(all.value, "canLogin") {
        login_active(c, src, station, l, flag(all.value, "canRelay"))
      } else {
        c.box(padx=10.0, pb=10.0, fn() {
          c.text(text(l, "statusText"), size=13.0, color=t.p.muted, line=19.0) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
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
      let sending = if o.waits != "" { o.waits } else { tr("android-chat.chat.sending") }
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
            app.toast_at = -1.0
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
    bg=if enabled { @sf.alpha(t.p.text, 0.08 * @motion.pressing(c, id)) } else { 0L },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      } else {
        @sf.icon(c, icon, size=12.0, color=k.muted) |> ignore
      }
      c.text(label, size=13.0, color=k.muted, wrap=false) |> ignore
    },
  )
  |> ignore
}

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
/// An agent at work, in one line (Chat.kt Activity): its picture ringed while it works (a still, quiet ring while it
/// waits on work it started), what it does now as the core says, and how long its turn has run.
fn activity(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  a : Agent,
  leaving? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let k = ink()
  let live = (src.topic)("live", { "station": Json::string(here.station), "key": Json::string(a.key) })
  let now_words = match a.wait {
    Some((_, _, w)) => if w != "" { w } else { tr("android-chat.chat.waiting") }
    None =>
      match text(field(field(live.value, "activity"), "now"), "text") {
        "" => tr("android-chat.chat.working")
        s => s
      }
  }
  let clock = if c.stable() {
    ""
  } else {
    let now = (src.now)()
    c.wake_in(1000.0, later=true)
    match a.wait {
      Some((since, most, _)) => {
        let waited = match most {
          Some(sec) => dmin(now, since + sec * 1000.0)
          None => now
        }
        elapsed(waited - since) +
        (match most {
          Some(sec) => " / " + elapsed(sec * 1000.0)
          None => ""
        })
      }
      None =>
        match a.since {
          Some(s) => elapsed(now - s)
          None => ""
        }
    }
  }
  // tapped, its execution history (History.kt), its press drawn round it
  let id = c.id("activity/" + a.key)
  if c.clicked(id) {
    app.nav.push(History(ref_of(here), a.key))
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
    c.box(w=Px(24.0), h=Px(24.0), tx=-3.0, align=ACenter, justify=JCenter, fn() {
      agent_avatar(c, a.maker, a.runtime)
      // its turn over, the ring goes first (Chat.kt WorkRing: 160 ms)
      let ring = @motion.animate(c, "ring/" + here.station + "/" + a.key, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(160.0))
      let rl = c.layer(fn() {
        if a.wait is Some(_) {
          c.box(w=Px(24.0), h=Px(24.0), radius=12.0, border=1.5, border_color=t.p.line, fn() {  })
          |> ignore
        } else {
          @sf.spinner(c, size=24.0, ring=0L, arc=k.accent, sweep=0.4, period=2000.0) |> ignore
        }
      })
      c.look(rl, @ui.look(alpha=ring))
    })
    |> ignore
    c.box(fn() { c.text(now_words, size=15.0, color=k.muted, wrap=false) |> ignore }) |> ignore
    if clock != "" {
      c.box(pl=3.0, fn() { c.text(clock, size=15.0, color=k.subtle, wrap=false) |> ignore })
      |> ignore
    }
    },
  )
  |> ignore
}

///|
/// The chat a row is of.
fn ref_of(here : Here) -> ChatRef {
  { station: here.station, session: here.session, title: here.view.title, station_name: "" }
}
