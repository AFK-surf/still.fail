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
pub(all) struct Found {
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
pub(all) struct Finding {
  chat : @signals.Signal[String]
  field : @ui.Field
  query : @signals.Signal[String]
  asked : @signals.Signal[String]
  found : @signals.Signal[Found?]
  at : @signals.Signal[Int]
  k : @signals.Signal[Int]
  position : @signals.Signal[Int]
  total : @signals.Signal[Int]
  moves : @signals.Signal[Int]
  bringing : @signals.Signal[Bool]
}

///|
pub let finding : Finding = {
  chat: @signals.signal("", same=fn(a, b) { a == b }),
  field: @ui.Field::new(),
  query: @signals.signal("", same=fn(a, b) { a == b }),
  asked: @signals.signal("", same=fn(a, b) { a == b }),
  found: @signals.signal(None),
  at: @signals.signal(-1, same=fn(a, b) { a == b }),
  k: @signals.signal(0, same=fn(a, b) { a == b }),
  position: @signals.signal(0, same=fn(a, b) { a == b }),
  total: @signals.signal(0, same=fn(a, b) { a == b }),
  moves: @signals.signal(0, same=fn(a, b) { a == b }),
  bringing: @signals.signal(false, same=fn(a, b) { a == b }),
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
  finding.chat.get()
}

///|
/// ⌘F's bar open in the chat `key` (opened again: its field takes the keyboard again).
pub fn find_open(c : @ui.Ctx, key : String) -> Unit {
  if finding.chat.get() != key {
    find_close()
    finding.chat.set(key)
  }
  c.focus_editor(find_key)
}

///|
/// ⌘F's bar closed: what it looked for forgotten (what the list marked for it is the page's to let go: FindList).
pub fn find_close() -> Unit {
  finding.chat.set("")
  finding.field.set("")
  finding.query.set("")
  finding.asked.set("")
  finding.found.set(None)
  finding.at.set(-1)
  finding.k.set(0)
  finding.position.set(0)
  finding.total.set(0)
  finding.moves.set(0)
  finding.bringing.set(false)
}

///|
/// ⌘F's bar open in chat `key` with `words` typed (a screen's fixture).
pub fn find_preset(key : String, words : String) -> Unit {
  finding.chat.set(key)
  finding.field.set(words)
}

///|
/// The words to mark in every message of chat `key` drawn now: what ⌘F found while its bar is open in it.
pub fn find_words_in(key : String) -> Array[String] {
  match finding.found.get() {
    Some(f) if finding.chat.get() == key => f.words
    _ => []
  }
}

///|
/// Which time in the message gone to the reader is at (0 the first).
pub fn find_k() -> Int {
  finding.k.get()
}

///|
/// Which of the messages found the reader is at (-1 none), and what is typed (a test's).
pub fn find_at() -> Int {
  finding.at.get()
}

///|
pub fn find_query() -> String {
  finding.query.get()
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
/// The list to the time the reader is at: its message gone to, the words marked there.
fn find_go(list : FindList) -> Unit {
  match finding.found.get() {
    Some(f) if finding.at.get() >= 0 && finding.at.get() < f.hits.length() => (list.go)(f.hits[finding.at.get()].0, f.words)
    _ => ()
  }
}

///|
/// Where the reader goes among what was found, as the core says (`chat.find.go`, chat-find.ts): with `by` 0 where they
/// are while what was found still has it, else where they start (from the messages showing); else the next (1) or the
/// one before (-1). The list goes there as the reader moves to another message or another time in one.
fn find_move(src : Source, key : String, list : FindList, by : Int) -> Unit {
  let f = match finding.found.get() {
    Some(f) => f
    None => return
  }
  let at : Json = if finding.at.get() >= 0 && finding.at.get() < f.hits.length() {
    { "seq": Json::number(f.hits[finding.at.get()].0), "k": Json::number(finding.k.get().to_double()) }
  } else {
    Json::null()
  }
  let (from, to) = (list.showing)()
  let params : Map[String, Json] = {
    "hits": Json::array(
      f.hits.map(fn(h) { { "seq": Json::number(h.0), "count": Json::number(h.1.to_double()) } }),
    ),
    "at": at,
    "by": Json::number(by.to_double()),
  }
  if from >= 0.0 && to >= 0.0 {
    params["from"] = Json::number(from)
    params["to"] = Json::number(to)
  }
  finding.moves.set(finding.moves.get() + 1)
  let n = finding.moves.get()
  (src.call)("chat.find.go", Json::object(params), fn(res) {
    // (closed, typed on, or moved again since: an answer to what is no longer asked)
    if finding.chat.get() != key || finding.moves.get() != n {
      return
    }
    match (res, finding.found.get()) {
      (Ok(j), Some(now)) => {
        let was = (finding.at.get(), finding.k.get())
        let seq = match field(Some(j), "at") {
          Some(Object(_)) as a => Some((number(a, "seq"), number(a, "k").to_int()))
          _ => None
        }
        match seq {
          Some((s, k)) => {
            finding.at.set(now.hits.search_by(fn(h) { h.0 == s }).unwrap_or(-1))
            finding.k.set(k)
          }
          None => {
            finding.at.set(-1)
            finding.k.set(0)
          }
        }
        finding.position.set(number(Some(j), "position").to_int())
        finding.total.set(number(Some(j), "total").to_int())
        if (finding.at.get(), finding.k.get()) != was {
          find_go(list)
        }
      }
      // the core an older one: where the reader is stays as it is
      _ => ()
    }
  })
}

///|
/// How long after the last key the chat is looked in (ChatFind.tsx TYPING_MS).
pub let find_typing_ms : Double = 120.0

///|
/// The chat (station `station`, thread `thread`) looked in for `query`: at once in what the device holds, then with
/// what it does not.
fn find_ask(src : Source, station : String, thread : Double, key : String, list : FindList, query : String) -> Unit {
  finding.asked.set(query)
  let q = query.trim(chars=" ").to_string()
  if q == "" {
    finding.found.set(None)
    finding.at.set(-1)
    finding.k.set(0)
    finding.position.set(0)
    finding.total.set(0)
    finding.bringing.set(false)
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
        if finding.asked.get() != query || finding.chat.get() != key {
          return
        }
        match res {
          Ok(j) => {
            let f = found_of(j)
            // where the reader was, as a message of what is found now (gone: none)
            let was = match finding.found.get() {
              Some(o) if bring && finding.at.get() >= 0 && finding.at.get() < o.hits.length() => o.hits[finding.at.get()].0
              _ => -1.0
            }
            finding.found.set(Some(f))
            finding.bringing.set(false)
            finding.at.set(f.hits.search_by(fn(h) { h.0 == was }).unwrap_or(-1))
            if finding.at.get() < 0 {
              finding.k.set(0)
            }
            finding.position.set(0)
            finding.total.set(f.hits.fold(init=0, fn(n, h) { n + h.1 }))
            // kept where it is still found, else where the reader starts (the core's)
            find_move(src, key, list, 0)
            if !bring && !f.whole {
              finding.bringing.set(true)
              ask(true)
            }
          }
          // its station away, or the core an older one: what was found stays as it is
          Err(_) => finding.bringing.set(false)
        }
      },
    )
  }

  ask(false)
}

///|
/// Which of how many times the words are in the chat the reader is at (1 the first; 0 none), as the core said it.
pub fn find_position() -> (Int, Int) {
  (finding.position.get(), finding.total.get())
}

///|
pub let find_key : String = "find/field"

///|
/// How wide its field is (ChatFind.css.ts field: 320, less where the bar has less: 160 at least), and each of its
/// buttons (button: 26 square).
let find_field_w : Double = 320.0

///|
let find_field_least : Double = 160.0

///|
let find_button_w : Double = 26.0

///|
/// The field's height (32: S8): a capsule.
pub let find_field_h : Double = 32.0

///|
/// How light the strokes under the words in the messages other than the one the reader is at are (ChatFind.css.ts: .45).
pub let find_faint : Double = 0.45

///|
/// The bar (ChatFind.css.ts bar): before the field what it did not look in, said while it is so; the field 320 wide, 32
/// high, a line round it on the raised ground, a capsule (so in a panel's corner where its shape is concentric); the
/// words typed in 14, which of how many in 12, the one before, the next, close: 26 round, concentric in its end, the
/// ground on hover. Opened, it fades in (kit's tip_in, ChatFind.css.ts bar's 120 ms); closed, it goes at once.
pub fn find_bar(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, list : FindList) -> Unit {
  let t = @sf.theme()
  let key = chat_key(r)
  let bar = c.box(style=find_bar_style, fn() {
    match finding.found.get() {
      Some(f) if !f.whole =>
        c.box(style=find_note_box, fn() {
          let note = if finding.bringing.get() {
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
      // (⇧Enter put a new line in it: taken out)
      let typed = res.text.replace_all(old="\n", new="")
      finding.query.set(typed)
      // looked for 120 ms after the last key; none typed, nothing found at once
      if typed != finding.asked.get() &&
        (typed.trim(chars=" ").is_empty() || @kit.after(c, "find/typing/" + typed, true, find_typing_ms)) {
        // (asked once the frame's builds are over)
        finding.asked.set(typed)
        c.tell("find/ask/" + typed, fn() { find_ask(src, r.station, thread, key, list, typed) })
      }
      if back || res.submitted is Some(_) {
        if back {
          finding.field.set(typed)
        }
        let by = if back { -1 } else { 1 }
        c.tell("find/move", fn() { find_move(src, key, list, by) })
      }
      let (at, total) = find_position()
      match finding.found.get() {
        // (nothing found yet while the rest is read is not "nothing found")
        // (nor before the core has said where the reader is among them)
        Some(_) if !(finding.bringing.get() && total == 0) && !(total > 0 && at == 0) =>
          c.box(style=find_count_box, fn() {
            let words = if total > 0 { "\{at}/\{total}" } else { @sf.t("web-main.find.none") }
            c.text(words, style=find_meta) |> ignore
          })
          |> ignore
        _ => ()
      }
      // (as far apart as makes each a press's room across: @sf.keys_row)
      c.box(style=@sf.keys_row(size=find_button_w), fn() {
        if find_button(c, "find/prev", "chevron-up", @sf.t("web-main.find.prev"), total > 0) {
          c.tell("find/move", fn() { find_move(src, key, list, -1) })
        }
        if find_button(c, "find/next", "chevron-down", @sf.t("web-main.find.next"), total > 0) {
          c.tell("find/move", fn() { find_move(src, key, list, 1) })
        }
        if find_button(c, "find/close", "close", @sf.t("web-main.find.close"), true) {
          (list.forget)()
          find_close()
        }
      })
      |> ignore
    })
    |> ignore
  })
  @motion.entering(c, bar, "find-bar/" + key, @kit.tip_in)
}

///|
/// One of the bar's buttons, named for a screen reader and in its tip under it; not pressed while `on` is false (drawn
/// fainter). True on the frame after a press.
fn find_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(style=if on { find_button_style } else { find_button_off }, id~, fn() {
    @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key, id, label, side=Bottom)
  on && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let find_bar_style : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let find_note_box : @ui.Style = @ui.style(max_w=Fixed(find_field_w), clip=true)

///|
// kept across runs: a value (no field of it changes)
let find_field_style : @ui.Style = @ui.style(
  row=true,
  w=Fixed(find_field_w),
  min_w=Fixed(find_field_least),
  h=S8,
  pl=S3,
  pr=@sf.capsule_end_room(find_field_h, find_button_w),
  gap=S0_5,
  align=ACenter,
  radius=Full,
  border=B1,
  border_color=Line,
  bg=Raised,
)

///|
// kept across runs: a value (no field of it changes)
let find_count_box : @ui.Style = @ui.css("px=S1_5")

///|
// kept across runs: a value (no field of it changes)
let find_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let find_button_style : @ui.Style = @ui.style(
  w=Fixed(find_button_w),
  h=Fixed(find_button_w),
  radius=Full,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let find_button_off : @ui.Style = @ui.style(
  w=Fixed(find_button_w),
  h=Fixed(find_button_w),
  radius=Full,
  align=ACenter,
  justify=JCenter,
  opacity=O50,
)
