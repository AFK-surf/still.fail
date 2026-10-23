// A chat's own find in the wide frame (ember web/src/ChatFind.tsx, ChatFind.css.ts): ⌘F opens its bar in the chat's
// bar, in place of its buttons, so it covers nothing of the chat. The core looks in all the chat's messages
// (`chat.find`: those not in the window shown too, and with `bring` those not on the device), answering which have the
// words and how many times; the list goes to the one the reader is at (the window moved about it first where it is
// outside: `chat.around`, chat.mbt), as a search's message is gone to (search_marks.mbt): the words bold and a stroke
// under each, the one gone to drawn in, the others' lighter. Enter the next, ⇧Enter the one before, Esc closes it;
// closed, what was looked for is forgotten.

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
/// ⌘F's bar open in chat `r` (opened again: its field takes the keyboard again).
fn find_open(c : @ui.Ctx, r : ChatRef) -> Unit {
  let k = side_key(r)
  if wide.find_chat != k {
    find_forget()
    wide.find_chat = k
  }
  wide.info_open = false
  wide.jobs_open = false
  c.focus_editor(find_key)
}

///|
/// ⌘F's bar closed: what it looked for forgotten, its marks gone from the chat.
fn find_forget() -> Unit {
  match readings.get(wide.find_chat) {
    Some(rd) => {
      rd.found_at = ""
      rd.found_words = []
    }
    None => ()
  }
  go_tos.remove(wide.find_chat)
  go_to_words.remove(wide.find_chat)
  wide.find_chat = ""
  wide.find_field.set("")
  wide.find_query = ""
  wide.found = None
  wide.find_at = -1
  wide.find_k = 0
  wide.bringing = false
  wide.find_around = -1.0
}

///|
/// The words to mark in every message of chat `r` drawn now: what ⌘F found while its bar is open in it.
fn find_words_in(r : ChatRef) -> Array[String] {
  match wide.found {
    Some(f) if wide.find_chat == side_key(r) => f.words
    _ => []
  }
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
fn find_start(r : ChatRef, hits : Array[(Double, Int)]) -> Int {
  if hits.length() == 0 {
    return -1
  }
  let rd = reading_of(side_key(r))
  let (from, to) = (rd.top_seq, rd.bottom_seq)
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
/// The list to the time the reader is at: its message gone to (chat.mbt go_tos), the words marked there.
fn find_go(r : ChatRef) -> Unit {
  match wide.found {
    Some(f) if wide.find_at >= 0 && wide.find_at < f.hits.length() => {
      let k = side_key(r)
      go_tos[k] = f.hits[wide.find_at].0
      go_to_words[k] = f.words
    }
    _ => ()
  }
}

///|
/// The chat looked in for `query` as it is typed: at once in what the device holds, then with what it does not.
fn find_ask(src : Source, r : ChatRef, v : ChatView, query : String) -> Unit {
  wide.find_query = query
  let q = query.trim(chars=" ").to_string()
  let thread = match v.thread {
    Some(t) => t
    None => return
  }
  if q == "" {
    wide.found = None
    wide.find_at = -1
    wide.find_k = 0
    wide.bringing = false
    return
  }
  fn ask(bring : Bool) {
    (src.call)(
      "chat.find",
      {
        "station": Json::string(r.station),
        "thread": Json::number(thread),
        "query": Json::string(q),
        "bring": Json::boolean(bring),
      },
      fn(res) {
        // (typed on since, or closed: an answer to what is no longer asked)
        if wide.find_query != query || wide.find_chat != side_key(r) {
          return
        }
        match res {
          Ok(j) => {
            let f = found_of(j)
            let was = match wide.found {
              Some(o) if bring && wide.find_at >= 0 && wide.find_at < o.hits.length() => o.hits[wide.find_at].0
              _ => -1.0
            }
            wide.found = Some(f)
            wide.bringing = false
            // what the reader was at kept where it is still found
            match f.hits.search_by(fn(h) { h.0 == was }) {
              Some(i) => wide.find_at = i
              None => {
                wide.find_at = find_start(r, f.hits)
                wide.find_k = 0
                find_go(r)
              }
            }
            if !bring && !f.whole {
              wide.bringing = true
              ask(true)
            }
          }
          // its station away, or the core an older one: what was found stays as it is
          Err(_) => wide.bringing = false
        }
      },
    )
  }

  ask(false)
}

///|
/// The next time the words are in the chat (`by` 1) or the one before (-1), round from an end to the other.
fn find_step(r : ChatRef, by : Int) -> Unit {
  let hits = match wide.found {
    Some(f) if f.hits.length() > 0 => f.hits
    _ => return
  }
  let n = hits.length()
  if wide.find_at < 0 || wide.find_at >= n {
    wide.find_at = if by > 0 { 0 } else { n - 1 }
    wide.find_k = 0
  } else {
    let k = wide.find_k + by
    if k >= 0 && k < hits[wide.find_at].1 {
      wide.find_k = k
    } else {
      wide.find_at = (wide.find_at + by + n) % n
      wide.find_k = if by > 0 { 0 } else { dmax(0.0, (hits[wide.find_at].1 - 1).to_double()).to_int() }
    }
  }
  find_go(r)
}

///|
/// Which of how many times the words are in the chat the reader is at (1 the first; 0 none).
fn find_position() -> (Int, Int) {
  match wide.found {
    Some(f) => {
      let mut total = 0
      let mut at = 0
      for i, h in f.hits {
        if i < wide.find_at {
          at = at + h.1
        }
        total = total + h.1
      }
      if wide.find_at >= 0 && wide.find_at < f.hits.length() {
        let k = if wide.find_k < f.hits[wide.find_at].1 { wide.find_k } else { f.hits[wide.find_at].1 - 1 }
        (at + dmax(0.0, k.to_double()).to_int() + 1, total)
      } else {
        (0, total)
      }
    }
    None => (0, 0)
  }
}

///|
let find_key : String = "find/field"

///|
/// How wide its field is (ChatFind.css.ts field: 320), and each of its buttons (button: 26 square).
let find_field_w : Double = 320.0

///|
let find_button_w : Double = 26.0

///|
/// How light the strokes under the words in the messages other than the one the reader is at are (ChatFind.css.ts: .45).
let find_faint : Double = 0.45

///|
/// The bar (ChatFind.css.ts bar): before the field what it did not look in, said while it is so; the field 320 wide, 32
/// high, a line round it on the raised ground, the corner 10; the words typed in 14, which of how many in 12, the one
/// before, the next, close: 26 square, their corner 8 (concentric 2 in), the ground on hover.
fn find_bar(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let t = @sf.theme()
  c.box(style=find_bar_style, fn() {
    match wide.found {
      Some(f) if !f.whole =>
        c.box(style=find_note_box, fn() {
          let note = if wide.bringing {
            fill("web-main.find.bringing", [("held", f.held.to_string())])
          } else {
            fill("web-main.find.partial", [("held", f.held.to_string()), ("of", f.of.to_string())])
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
        placeholder=tr("web-main.find.placeholder"),
        font_size=14.0,
        line=20.0,
        max_lines=1,
        plain=true,
        color=t.p.text,
        placeholder_color=t.p.muted,
        caret_color=t.p.accent,
        enter_sends=true,
        field=wide.find_field,
      )
      // (Enter sent the words: they are what was typed, not what is left in the field)
      let sent = match res.submitted {
        Some(words) => words
        None => res.text
      }
      let typed = sent.replace_all(old="\n", new="")
      if typed != wide.find_query {
        find_ask(src, r, v, typed)
      }
      if back || res.submitted is Some(_) {
        wide.find_field.set(typed)
        find_step(r, if back { -1 } else { 1 })
      }
      let (at, total) = find_position()
      match wide.found {
        // (nothing found yet while the rest is read is not "nothing found")
        Some(_) if !(wide.bringing && total == 0) =>
          c.box(style=find_count_box, fn() {
            let words = if total > 0 { "\{at}/\{total}" } else { tr("web-main.find.none") }
            c.text(words, style=find_meta) |> ignore
          })
          |> ignore
        _ => ()
      }
      if find_button(c, "find/prev", "chevron-up", tr("web-main.find.prev"), total > 0) {
        find_step(r, -1)
      }
      if find_button(c, "find/next", "chevron-down", tr("web-main.find.next"), total > 0) {
        find_step(r, 1)
      }
      if find_button(c, "find/close", "close", tr("web-main.find.close"), true) {
        find_forget()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// One of the bar's buttons, named for a screen reader; not pressed while `on` is false (drawn fainter). True on the
/// frame after a press.
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
