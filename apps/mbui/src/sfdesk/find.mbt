// A chat's own find on the desktop (ember web/src/ChatFind.tsx, ChatFind.css.ts): ⌘F opens its bar in the chat's
// bar, in place of its buttons, so it covers nothing of the chat. The core looks in all the chat's messages
// (`chat.find`: those not in the window shown too, and with `bring` those not on the device), 120 ms after the last
// key, answering which have the words and how many times; the list goes to the one the reader is at (the window moved
// about it first where it is outside: `chat.around`), the words bold and a stroke under each, the one gone to drawn
// in, the others' lighter. Enter the next, ⇧Enter the one before, Esc closes it; closed, what was looked for is
// forgotten. The list it goes along is the page's (FindList).

///|
/// What the core found (`chat.find`): the words looked for, the messages that have them (oldest first, each with how
/// many times), how many of the chat's entries were looked in of how many, and whether that was all of them.
priv struct Found {
  words : Array[String]
  hits : Array[(Double, Int)]
  held : Int
  of : Int
  whole : Bool
}

///|
/// What the find keeps of its own: the chat its bar is open in (its key, "" closed), its field, what is typed and what
/// was last asked of the core, what the core found (None nothing asked yet), the time the reader is at (which of its
/// messages, which time in it), whether what is not on the device is being read.
priv struct Finding {
  mut chat : String
  field : @ui.Field
  mut query : String
  mut asked : String
  mut found : Found?
  mut at : Int
  mut k : Int
  mut bringing : Bool
}

///|
let finding : Finding = {
  chat: "",
  field: @ui.Field::new(),
  query: "",
  asked: "",
  found: None,
  at: -1,
  k: 0,
  bringing: false,
}

///|
/// The list the find goes along (the page's message list, ChatFind.tsx `virtual`): the messages showing (the first's
/// and the last's seq; -1 none), the list to a message with the words marked in it, its marks let go.
pub(all) struct FindList {
  showing : () -> (Double, Double)
  go : (Double, Array[String]) -> Unit
  forget : () -> Unit
}

///|
/// A chat's key among the desktop's own: its station and session.
pub fn chat_key(r : ChatRef) -> String {
  r.station + "\u{1}" + r.session
}

///|
/// The chat ⌘F's bar is open in ("" none).
pub fn find_chat() -> String {
  finding.chat
}

///|
/// ⌘F's bar open in the chat `key` (opened again: its field takes the keyboard again).
pub fn find_open(c : @ui.Ctx, key : String) -> Unit {
  if finding.chat != key {
    find_close()
    finding.chat = key
  }
  c.focus_editor(find_key)
}

///|
/// ⌘F's bar closed: what it looked for forgotten (what the list marked for it is the page's to let go: FindList).
pub fn find_close() -> Unit {
  finding.chat = ""
  finding.field.set("")
  finding.query = ""
  finding.asked = ""
  finding.found = None
  finding.at = -1
  finding.k = 0
  finding.bringing = false
}

///|
/// ⌘F's bar open in chat `key` with `words` typed (a screen's fixture).
pub fn find_preset(key : String, words : String) -> Unit {
  finding.chat = key
  finding.field.set(words)
}

///|
/// The words to mark in every message of chat `key` drawn now: what ⌘F found while its bar is open in it.
pub fn find_words_in(key : String) -> Array[String] {
  match finding.found {
    Some(f) if finding.chat == key => f.words
    _ => []
  }
}

///|
/// Which time in the message gone to the reader is at (0 the first).
pub fn find_k() -> Int {
  finding.k
}

///|
/// Which of the messages found the reader is at (-1 none), and what is typed (a test's).
pub fn find_at() -> Int {
  finding.at
}

///|
pub fn find_query() -> String {
  finding.query
}

///|
/// What the core answered `chat.find` with.
fn found_of(v : Json) -> Found {
  let words : Array[String] = []
  for w in items(Some(v), "words") {
    if w is String(s) {
      words.push(s)
    }
  }
  let hits = items(Some(v), "hits").map(fn(h) { (number(Some(h), "seq"), number(Some(h), "count").to_int()) })
  {
    words,
    hits,
    held: number(Some(v), "held").to_int(),
    of: number(Some(v), "of").to_int(),
    whole: flag(Some(v), "whole"),
  }
}

///|
/// Where the reader starts among `hits`: one in the messages showing, else the nearest before them, else the first.
fn find_start(list : FindList, hits : Array[(Double, Int)]) -> Int {
  if hits.length() == 0 {
    return -1
  }
  let (from, to) = (list.showing)()
  for i, h in hits {
    if from >= 0.0 && h.0 >= from && (to < 0.0 || h.0 <= to) {
      return i
    }
  }
  let mut before = -1
  for i, h in hits {
    if from >= 0.0 && h.0 < from {
      before = i
    }
  }
  if before >= 0 {
    before
  } else {
    0
  }
}

///|
/// The list to the time the reader is at: its message gone to, the words marked there.
fn find_go(list : FindList) -> Unit {
  match finding.found {
    Some(f) if finding.at >= 0 && finding.at < f.hits.length() => (list.go)(f.hits[finding.at].0, f.words)
    _ => ()
  }
}

///|
/// How long after the last key the chat is looked in (ChatFind.tsx TYPING_MS).
pub let find_typing_ms : Double = 120.0

///|
/// The chat (station `station`, thread `thread`) looked in for `query`: at once in what the device holds, then with
/// what it does not.
fn find_ask(src : Source, station : String, thread : Double, key : String, list : FindList, query : String) -> Unit {
  finding.asked = query
  let q = query.trim(chars=" ").to_string()
  if q == "" {
    finding.found = None
    finding.at = -1
    finding.k = 0
    finding.bringing = false
    return
  }
  fn ask(bring : Bool) {
    (src.call)(
      "chat.find",
      {
        "station": Json::string(station),
        "thread": Json::number(thread),
        "query": Json::string(q),
        "bring": Json::boolean(bring),
      },
      fn(res) {
        // (typed on since, or closed: an answer to what is no longer asked)
        if finding.asked != query || finding.chat != key {
          return
        }
        match res {
          Ok(j) => {
            let f = found_of(j)
            let was = match finding.found {
              Some(o) if bring && finding.at >= 0 && finding.at < o.hits.length() => o.hits[finding.at].0
              _ => -1.0
            }
            finding.found = Some(f)
            finding.bringing = false
            // what the reader was at kept where it is still found
            match f.hits.search_by(fn(h) { h.0 == was }) {
              Some(i) => finding.at = i
              None => {
                finding.at = find_start(list, f.hits)
                finding.k = 0
                find_go(list)
              }
            }
            if !bring && !f.whole {
              finding.bringing = true
              ask(true)
            }
          }
          // its station away, or the core an older one: what was found stays as it is
          Err(_) => finding.bringing = false
        }
      },
    )
  }

  ask(false)
}

///|
/// The next time the words are in the chat (`by` 1) or the one before (-1), round from an end to the other.
fn find_step(list : FindList, by : Int) -> Unit {
  let hits = match finding.found {
    Some(f) if f.hits.length() > 0 => f.hits
    _ => return
  }
  let n = hits.length()
  if finding.at < 0 || finding.at >= n {
    finding.at = if by > 0 { 0 } else { n - 1 }
    finding.k = 0
  } else {
    let k = finding.k + by
    if k >= 0 && k < hits[finding.at].1 {
      finding.k = k
    } else {
      finding.at = (finding.at + by + n) % n
      finding.k = if by > 0 { 0 } else { dmax(0.0, (hits[finding.at].1 - 1).to_double()).to_int() }
    }
  }
  find_go(list)
}

///|
/// Which of how many times the words are in the chat the reader is at (1 the first; 0 none).
pub fn find_position() -> (Int, Int) {
  match finding.found {
    Some(f) => {
      let mut total = 0
      let mut at = 0
      for i, h in f.hits {
        if i < finding.at {
          at = at + h.1
        }
        total = total + h.1
      }
      if finding.at >= 0 && finding.at < f.hits.length() {
        let k = if finding.k < f.hits[finding.at].1 { finding.k } else { f.hits[finding.at].1 - 1 }
        (at + dmax(0.0, k.to_double()).to_int() + 1, total)
      } else {
        (0, total)
      }
    }
    None => (0, 0)
  }
}

///|
pub let find_key : String = "find/field"

///|
/// How wide its field is (ChatFind.css.ts field: 320), and each of its buttons (button: 26 square).
let find_field_w : Double = 320.0

///|
let find_button_w : Double = 26.0

///|
/// How light the strokes under the words in the messages other than the one the reader is at are (ChatFind.css.ts: .45).
pub let find_faint : Double = 0.45

///|
/// The bar (ChatFind.css.ts bar): before the field what it did not look in, said while it is so; the field 320 wide, 32
/// high, a line round it on the raised ground, the corner 10; the words typed in 14, which of how many in 12, the one
/// before, the next, close: 26 square, their corner 8 (concentric 2 in), the ground on hover.
pub fn find_bar(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, list : FindList) -> Unit {
  let t = @sf.theme()
  let key = chat_key(r)
  c.box(style=find_bar_style, fn() {
    match finding.found {
      Some(f) if !f.whole =>
        c.box(style=find_note_box, fn() {
          let note = if finding.bringing {
            @sf.t("web-main.find.bringing", args=[("held", f.held.to_string())])
          } else {
            @sf.t("web-main.find.partial", args=[("held", f.held.to_string()), ("of", f.of.to_string())])
          }
          c.text(note, style=find_meta) |> ignore
        })
        |> ignore
      _ => ()
    }
    c.box(style=find_field_style, fn() {
      // ⇧Enter: the one before (read before the field takes it as its Enter)
      let back = c.key_pressed(@ui.key_code_enter, mods=@ui.mod_shift_key, in_field=true)
      let res = c.editor(
        find_key,
        placeholder=@sf.t("web-main.find.placeholder"),
        font_size=14.0,
        line=20.0,
        max_lines=1,
        plain=true,
        color=t.p.text,
        placeholder_color=t.p.muted,
        caret_color=t.p.accent,
        enter_sends=true,
        field=finding.field,
      )
      // (Enter sent the words: they are what was typed, not what is left in the field)
      let sent = match res.submitted {
        Some(words) => words
        None => res.text
      }
      let typed = sent.replace_all(old="\n", new="")
      finding.query = typed
      // looked for 120 ms after the last key; none typed, nothing found at once
      if typed != finding.asked &&
        (typed.trim(chars=" ").is_empty() || @kit.after(c, "find/typing/" + typed, true, find_typing_ms)) {
        // (asked once the frame's builds are over)
        finding.asked = typed
        c.tell("find/ask/" + typed, fn() { find_ask(src, r.station, thread, key, list, typed) })
      }
      if back || res.submitted is Some(_) {
        finding.field.set(typed)
        find_step(list, if back { -1 } else { 1 })
      }
      let (at, total) = find_position()
      match finding.found {
        // (nothing found yet while the rest is read is not "nothing found")
        Some(_) if !(finding.bringing && total == 0) =>
          c.box(style=find_count_box, fn() {
            let words = if total > 0 { "\{at}/\{total}" } else { @sf.t("web-main.find.none") }
            c.text(words, style=find_meta) |> ignore
          })
          |> ignore
        _ => ()
      }
      if find_button(c, "find/prev", "chevron-up", @sf.t("web-main.find.prev"), total > 0) {
        find_step(list, -1)
      }
      if find_button(c, "find/next", "chevron-down", @sf.t("web-main.find.next"), total > 0) {
        find_step(list, 1)
      }
      if find_button(c, "find/close", "close", @sf.t("web-main.find.close"), true) {
        (list.forget)()
        find_close()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// One of the bar's buttons, named for a screen reader and in its tip under it; not pressed while `on` is false (drawn
/// fainter). True on the frame after a press.
fn find_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  if on {
    c.cursor(id, Hand)
  }
  let b = c.box(style=if on { find_button_style } else { find_button_off }, id~, fn() {
    @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key, id, label, side=Bottom)
  on && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let find_bar_style : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let find_note_box : @ui.Style = @ui.style(max_w=Fixed(find_field_w), clip=true)

///|
// kept across runs: a value (no field of it changes)
let find_field_style : @ui.Style = @ui.style(
  row=true,
  w=Fixed(find_field_w),
  h=S8,
  pl=S1_5,
  pr=S0_5,
  gap=S0_5,
  align=ACenter,
  radius=@sf.custom_field_r,
  border=B1,
  border_color=Line,
  bg=Raised,
)

///|
// kept across runs: a value (no field of it changes)
let find_count_box : @ui.Style = @ui.style(px=S1_5)

///|
// kept across runs: a value (no field of it changes)
let find_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let find_button_style : @ui.Style = @ui.style(
  w=Fixed(find_button_w),
  h=Fixed(find_button_w),
  radius=Lg,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let find_button_off : @ui.Style = @ui.style(
  w=Fixed(find_button_w),
  h=Fixed(find_button_w),
  radius=Lg,
  align=ACenter,
  justify=JCenter,
  opacity=O50,
)
