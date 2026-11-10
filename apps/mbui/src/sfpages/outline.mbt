// A chat's outline (对话目录): what people said in it (the core's `chatOutline`: theirs and the viewer's, not agents'),
// oldest first under its days, each its first line and its time, a face before those of someone other than the viewer
// in a chat of more than one person; the one the reader is at (outline_current) in the accent. Pressed, the outline
// closes and the chat's list goes to that message, which flashes (@sfbase.go_to). A field over it looks in all of the
// chat (`chat.outline.find`, asked as the chat's find asks `chat.find`: ask_bringing), its rows then what has the words
// (people's and agents'), who and when over the line with them, the words marked as a found message's are (semibold:
// found_weight, what the window's tree marks a found message's words with). The library's panel shows it
// (@sf.panel_nodes): a sheet from the foot on Small, a small panel beside what opened it on Medium and Large; what it
// holds nodes, its rows a list made as they show (@sf.panel_list_node), standing at the reader's one as it opens. While
// not all of the chat is on the device, the rest is read (`chat.bring`) and said so over the rows.
//
// What opens it, on the chat's page (chat_list.mbt, the old view's, beside the way to the newest): on a page whose
// column leaves room at its right (rail_fits), a rail of ticks there, one for each person's message, the reader's
// longer and in the ink; on a narrower one a round button over the way to the newest, coming and going with it.
// ⌘G (chat.outline) opens it from either, its field taking the keys; ⌥⇧↑ and ⌥⇧↓ go to the message a person said
// before and after the reader's.

///|
/// What a chat's outline lists (the core's OutlineItem; a found row's too): the message, whether the viewer's, who said
/// it (their address, their name and picture; an agent's maker and runtime, whether it is one, still.fail's notice),
/// its first line (a found row's: the line with the words), and its time of day.
priv struct OutlineItem {
  seq : Double
  mine : Bool
  author : String
  name : String
  picture : String
  maker : String
  runtime : String
  agent : Bool
  system : Bool
  words : String
  clock : String
}

///|
fn outline_item(j : Json, found : Bool) -> OutlineItem {
  let v = Some(j)
  let by = field(v, "by")
  {
    seq: number(v, "seq"),
    mine: flag(v, "mine"),
    author: text(v, "author"),
    name: text(by, "name"),
    picture: text(by, "picture"),
    maker: text(field(by, "maker"), "id"),
    runtime: text(by, "runtime"),
    agent: flag(v, "agent"),
    system: flag(v, "system"),
    words: text(v, if found { "snippet" } else { "words" }),
    clock: text(v, "clock"),
  }
}

///|
/// The params of chat `r`'s outline (its thread `thread`).
pub fn outline_params(r : ChatRef, thread : Double) -> Map[String, Json] {
  { "station": Json::string(r.station), "thread": Json::number(thread) }
}

///|
/// The messages people said in an outline (`value`, the core's `chatOutline`), oldest first.
fn outline_seqs(value : Json?) -> Array[Double] {
  let out : Array[Double] = []
  for d in items(value, "days") {
    for it in items(Some(d), "items") {
      out.push(number(Some(it), "seq"))
    }
  }
  out
}

///|
/// The message of `said` (people's, oldest first) the reader is at: at the chat's end, the last; else the last at or
/// before `top` (the message at the top of what shows), the first where none is (-1: none at all).
pub fn outline_current(said : Array[Double], top : Double, at_end : Bool) -> Double {
  if said.is_empty() {
    return -1.0
  }
  if at_end || top < 0.0 {
    return said[said.length() - 1]
  }
  let mut at = said[0]
  for s in said {
    if s <= top {
      at = s
    }
  }
  at
}

///|
/// The message at the top of what shows of chat `r`'s list (its reading `rd`, its view `v`), where the reader is: the
/// one last gone to while it shows (put under the bar, what is over it under the bar too), else the first in view.
fn reader_top(rd : @sfbase.Reading, v : ChatView, top : Double) -> Double {
  if rd.flash != "" && top >= 0.0 {
    match v.messages.iter().find_first(fn(m) { m.ts == rd.flash }) {
      Some(m) if m.seq >= top && (rd.bottom_seq < 0.0 || m.seq <= rd.bottom_seq) => return m.seq
      _ => ()
    }
  }
  top
}

///|
/// The message a person said before (`by` -1) or after (1) the one the reader is at in chat `r` (its reading `rd`),
/// among `said` (people's, oldest first); None at either end.
pub fn said_step(said : Array[Double], top : Double, at_end : Bool, by : Int) -> Double? {
  let now = outline_current(said, top, at_end)
  match said.search(now) {
    Some(i) => said.get(i + by)
    None => None
  }
}

///|
/// What a person said in chat `r`'s view `v` as far as its window holds it, oldest first (where its outline is not
/// held: the steps' keys on a narrow page).
fn said_in_view(v : ChatView) -> Array[Double] {
  v.messages.filter(fn(m) { m.author_kind == "person" && !m.system }).map(fn(m) { m.seq })
}

///|
/// What a row of the outline's list is: a day's heading, a message said, one found.
priv enum OutlineRow {
  RowDay(String)
  RowSaid(OutlineItem)
  RowFound(OutlineItem)
}

///|
/// An outline open: its field, what is looked for (its words as last asked, "" nothing: the outline itself), what the
/// core found for them, whether it reads the rest of the chat for them, how many were asked (an answer to one asked
/// before let be), the row the keys are at (its key, "" none), the message the reader is at as it opened.
priv struct OutlineAt {
  field : @ui.Field
  query : @signals.Signal[String]
  found : @signals.Signal[Json?]
  bringing : @signals.Signal[Bool]
  mut asked : Int
  lit : @signals.Signal[String]
  current : Double
}

///|
/// Chat `r`'s outline (its thread `thread`), opened by `from` (on `side` of it, lined up `along` it, beside it: the round
/// button's at its left, their feet together, away from the window's corners; a sheet on Small, whatever opened it), at the message the reader is at (`current`); its field taking the keys as it opens
/// (`keys`: ⌘G, wherever it is shown; else beside what opened it, as the presenters give a panel's field the focus);
/// `typed` in it, looked for at once.
/// The rest of the chat read onto the device as it opens (`chat.bring`). `stint`: the page's time on top (faces asked
/// for on it).
pub fn open_outline(
  src : Source,
  r : ChatRef,
  thread : Double,
  current : Double,
  from~ : @sf.Anchor,
  side? : @ui.Side = Left,
  along? : @ui.Along = End,
  keys? : Bool = false,
  stint? : Int = 0,
  typed? : String = "",
) -> Unit {
  let at : OutlineAt = {
    field: @ui.Field::new(),
    query: @signals.signal("", same=fn(a, b) { a == b }),
    found: @signals.signal(None),
    bringing: @signals.signal(false, same=fn(a, b) { a == b }),
    asked: 0,
    lit: @signals.signal("", same=fn(a, b) { a == b }),
    current,
  }
  if keys {
    at.field.focus()
  }
  // (words in its field as it opens, looked for at once: a screen's fixture)
  at.field.set(typed)
  // (what is not on the device yet read onto it: the outline fills in as it comes)
  if !src.read_only {
    (src.call)("chat.bring", Json::object(outline_params(r, thread)), fn(_) {  })
  }
  @sf.panel_nodes(
    @sf.t("web-main.outline.title"),
    fn(v, close) { outline_body(v, src, r, thread, at, close, stint) },
    from~,
    side~,
    along~,
    // (the library's wider panel beside what opened it, as a model's choice has it: first lines read, not 12 letters)
    w=@sf.confirm_w,
    tall=outline_tall,
    hugs=true,
  )
}

///|
/// How much of the window the outline is at most (a long chat's: what it holds scrolls in that).
let outline_tall : Double = 0.7

///|
/// What the outline holds, in node `v` (the panel's body): its field, over its rows.
fn outline_body(
  v : @view.View,
  src : Source,
  r : ChatRef,
  thread : Double,
  at : OutlineAt,
  close : () -> Unit,
  stint : Int,
) -> Unit {
  let params = outline_params(r, thread)
  let value = fn() { src.topic("chatOutline", params).get().value }
  let searching = fn() { at.query.get() != "" }
  // (in a chat of more than one person: a face before the rows of those other than the viewer, a face's room before
  // the viewer's)
  let others = fn() {
    items(value(), "days").iter().any(fn(d) { items(Some(d), "items").iter().any(fn(i) { !flag(Some(i), "mine") }) })
  }
  // its rows by their keys, as the core has them now
  let table : @signals.Computed[(Array[String], Map[String, OutlineRow])] = @signals.computed(fn(_) {
    let keys : Array[String] = []
    let rows : Map[String, OutlineRow] = {}
    // (a key once: the list's keys are its rows', so a message the core said twice is one row)
    let put = fn(k : String, row : OutlineRow) {
      if !rows.contains(k) {
        keys.push(k)
        rows[k] = row
      }
    }
    let found = searching()
    let shown = if found { at.found.get() } else { value() }
    let whole = match shown {
      Some(_) => flag(shown, "whole")
      None => !found
    }
    for di, d in items(shown, "days") {
      let day = text(Some(d), "day")
      if day != "" {
        put("day/\{di}/" + day, RowDay(day))
      }
      for it in items(Some(d), "items") {
        let item = outline_item(it, found)
        let s = item.seq.to_int().to_string()
        put(if found { "found/" + s } else { "said/" + s }, if found { RowFound(item) } else { RowSaid(item) })
      }
    }
    (keys, rows)
  })
  // (the rows the keys go along: those of messages, in order)
  let goes = fn() { table.get().0.filter(fn(k) { k.has_prefix("said/") || k.has_prefix("found/") }) }
  let place : @view.ListPlace[String] = @view.ListPlace::new()
  let go = fn(item : OutlineItem) {
    let words = match at.found.get() {
      Some(f) if searching() => found_words(f)
      _ => []
    }
    close()
    @sfbase.go_to(r, item.seq)
    // (one found: the words marked in it, as a search's are, nothing flashing)
    if words.length() > 0 {
      @sfbase.go_to_words[r.station + "\u{1}" + r.session] = words
    }
  }
  let go_key = fn(k : String) {
    match @signals.untracked(fn() { table.get().1.get(k) }) {
      Some(RowSaid(item)) | Some(RowFound(item)) => go(item)
      _ => ()
    }
  }
  // what is typed looked for find_typing_ms after the last key, as the chat's find asks (ask_bringing); none, the outline
  let due : Ref[() -> Unit] = Ref(fn() {  })
  let ask = fn(words : String) {
    at.asked += 1
    let n = at.asked
    at.query.set(words)
    at.found.set(None)
    at.bringing.set(false)
    ask_bringing(
      src,
      "chat.outline.find",
      { "station": Json::string(r.station), "thread": Json::number(thread), "query": Json::string(words) },
      fn() { at.asked == n },
      fn(j, bring) {
        at.found.set(Some(j))
        if bring || flag(Some(j), "whole") {
          at.bringing.set(false)
        }
        // (the first found the one the keys are at)
        at.lit.set(goes().get(0).unwrap_or(""))
      },
      bringing=fn() { at.bringing.set(true) },
      failed=fn() { at.bringing.set(false) },
    )
  }
  let typed = fn(words : String) {
    (due.val)()
    let q = words.trim(chars=" ").to_string()
    if q == "" {
      at.asked += 1
      at.query.set("")
      at.found.set(None)
      at.bringing.set(false)
      at.lit.set(current_key(at))
      place.centre(current_key(at))
    } else {
      due.val = v.at_moment(v.cause_at() + find_typing_ms, fn() { ask(q) })
    }
  }
  // ↓ ↑ move the row the keys are at (the keymap's `Outline`'s, the field leaving them to it), the list keeping it in
  // sight; Enter in the field goes to it; Escape closes the panel (its own)
  let step = fn(by : Int) {
    let ks = goes()
    let now = ks.search(at.lit.get())
    let next = match now {
      Some(i) => i + by
      None => if by > 0 { 0 } else { ks.length() - 1 }
    }
    match ks.get(next) {
      Some(k) => {
        at.lit.set(k)
        place.bring(k, offset=-outline_keep)
      }
      None => ()
    }
  }
  v
  .key_context("Outline")
  .on_action("outline.down", fn(_) {
    step(1)
    true
  })
  .on_action("outline.up", fn(_) {
    step(-1)
    true
  })
  |> ignore
  // the field, its count at its end
  v.box(fn(fb) {
    // (where the library stands a field over a panel's rows: a pick's search's line in a small panel, a sheet's words')
    @sf.style_node(fb, fn() { outline_field_at.then(@sf.panel_field_in_node(fb)) })
    let f = @sf.input_node(
      fb,
      at.field,
      placeholder=@sf.t("web-main.outline.placeholder"),
      small=true,
      leaves=[@ui.key_code_down, @ui.key_code_up],
      submitted=fn(_) { go_key(at.lit.untracked()) },
      edited=typed,
      end=fn(e) {
        @sf.words_node(e, fn() { outline_count(at, searching()) }, fn() { outline_count_words }) |> ignore
      },
    )
    @sf.panel_opens_on_node(f)
  })
  |> ignore
  // while not all of the chat is on the device (the outline's, or what is found's), said so over the rows, as the
  // chat's find says it at its bar
  let bringing = fn() {
    if searching() {
      at.bringing.get() || (match at.found.get() {
        Some(f) => !flag(Some(f), "whole")
        None => false
      })
    } else {
      value() is Some(_) && !flag(value(), "whole")
    }
  }
  v.show(bringing, fn(n) { @sf.panel_note_node(n, fn() { @sf.t("web-main.outline.bringing") }) })
  // its rows, the reader's in the middle as it opens; what its field holds as it opens looked for at once
  at.lit.set(current_key(at))
  let first = @signals.untracked(fn() { at.field.text() }).trim(chars=" ").to_string()
  if first != "" {
    ask(first)
  }
  @sf.panel_list_node(
    v,
    fn() { table.get().0 },
    fn(row, k) {
      match @signals.untracked(fn() { table.get().1.get(k) }) {
        Some(RowDay(day)) => @sf.panel_heading_node(row, fn() { day })
        Some(RowSaid(item)) =>
          @sf.panel_said_row_node(
            row,
            fn() { [@ui.span(item.words)] },
            fn() { go(item) },
            fn() { item.words + " " + item.clock },
            lead?=if @signals.untracked(others) {
              Some(fn(col : @view.View, size : Double) { if !item.mine { outline_face(col, src, item, size, stint) } })
            } else {
              None
            },
            end=fn() { item.clock },
            chosen=fn() { item.seq == at.current },
            lit=fn() { at.lit.get() == k },
          )
        Some(RowFound(item)) => {
          let words = fn() {
            match at.found.get() {
              Some(f) => found_words(f)
              None => []
            }
          }
          let who = [item.name, item.clock].filter(fn(s) { s != "" }).join(" · ")
          @sf.panel_said_row_node(
            row,
            fn() { @sf.found_weight([@ui.span(item.words)], words()) },
            fn() { go(item) },
            fn() { who + " " + item.words },
            who=(fn() { who }, fn(f, size) { outline_face(f, src, item, size, stint) }),
            lit=fn() { at.lit.get() == k },
          )
        }
        None => ()
      }
    },
    est=outline_row_est,
    fills=true,
    place~,
  )
  |> ignore
  place.centre(current_key(at))
}

///|
/// The words the core looked for (`chat.outline.find`'s answer `f`).
fn found_words(f : Json) -> Array[String] {
  items(Some(f), "words").filter_map(fn(w) {
    match w {
      String(s) if s != "" => Some(s)
      _ => None
    }
  })
}

///|
/// The key of the row of the message the reader was at as the outline opened.
fn current_key(at : OutlineAt) -> String {
  if at.current < 0.0 {
    ""
  } else {
    "said/" + at.current.to_int().to_string()
  }
}

///|
/// What the field's end says: how many were found, or that none was (not before the core has answered, nor while it
/// still reads the rest of the chat for them having found none yet); nothing while nothing is looked for.
fn outline_count(at : OutlineAt, searching : Bool) -> String {
  guard searching else { return "" }
  match at.found.get() {
    Some(f) => {
      let n = number(Some(f), "total").to_int()
      if n > 0 {
        @sf.t("web-main.outline.count", args=[("n", n.to_string())])
      } else if at.bringing.get() {
        ""
      } else {
        @sf.t("web-main.outline.none")
      }
    }
    None => ""
  }
}

///|
/// Who said a row's message, `size` across, in `col`: a person's face, an agent's maker, still.fail's mark for its
/// notice.
fn outline_face(col : @view.View, src : Source, item : OutlineItem, size : Double, stint : Int) -> Unit {
  // (an agent's as its picture in the chat has it, agent_avatar's: its maker's mark, still.fail's where it says none)
  if item.system || (item.agent && item.maker == "" && item.runtime == "") {
    @sf.drawable_node(col, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, size) |> ignore
  } else if item.agent {
    @sf.maker_mark_node(col, item.maker, agent_runtime(item.runtime), size) |> ignore
  } else {
    @sf.avatar_node(col, fn() { item.author }, fn() { item.name }, fn() {
      if item.picture == "" {
        ""
      } else {
        (src.picture)(item.picture, stint)
      }
    }, size)
  }
}

///|
/// How tall a row of the outline is taken to be till it is laid out, and how far under the list's top one the keys come
/// to is kept (a row's room over it, so what is over it shows).
let outline_row_est : Double = 40.0

///|
let outline_keep : Double = outline_row_est

///|
/// The field over the rows: across the panel (where panel_field_in_node stands it), a row's room under it.
// kept across runs: a value (no field of it changes)
let outline_field_at : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
/// How many were found, at the field's end: 12, muted.
// kept across runs: a value (no field of it changes)
let outline_count_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

// ── What opens it on the chat's page (an old view's, as the way to the newest beside it) ──────────────────────────

///|
/// The chats whose page shows a way into the outline now, by the chat's key: what (its id, to stand beside) and whether
/// it is the rail (its outline held then: what the steps' keys go along). ⌘G opens it there.
// kept across runs: said as each page is built, let go of by the package's reset (pages.mbt)
let outline_entries : Map[String, (Int, Bool)] = {}

///|
/// What people said in chat `r` (its view `v`), oldest first, as a key's handler finds it: its outline where its rail
/// holds it, else what its window holds.
fn said_now(src : Source, r : ChatRef, v : ChatView) -> Array[Double] {
  match (outline_entries.get(chat_key(r)), v.thread) {
    (Some((_, true)), Some(th)) =>
      match src.topic("chatOutline", outline_params(r, th)).get().value {
        Some(_) as o => outline_seqs(o)
        None => said_in_view(v)
      }
    _ => said_in_view(v)
  }
}

///|
/// The outline of chat `r` (its view `v`) opened from the keys or ⌘K: beside its rail or its round button where one
/// shows, else as the presenters put what nothing opened (a dialog; a sheet on Small); its field taking the keys.
pub fn outline_open_keys(src : Source, r : ChatRef, v : ChatView, stint? : Int = 0, typed? : String = "") -> Bool {
  guard v.thread is Some(th) else { return false }
  let rd = reading_of(chat_key(r))
  let current = outline_current(said_now(src, r, v), reader_top(rd, v, rd.top_seq), rd.at_end)
  match outline_entries.get(chat_key(r)) {
    Some((id, true)) => open_outline(src, r, th, current, from=Of(id), side=Left, along=Middle, keys=true, stint~, typed~)
    Some((id, false)) => open_outline(src, r, th, current, from=Of(id), side=Left, keys=true, stint~, typed~)
    None => open_outline(src, r, th, current, from=Unanchored, keys=true, stint~, typed~)
  }
  true
}

///|
/// The outline to open in each chat as its page shows a way into it (a screen's fixture: outline_preset), with the
/// words to type in it, by the chat's key.
// kept across runs: let go of as it opens, and by the package's reset (pages.mbt)
let outline_presets : Map[String, String] = {}

///|
/// Chat `key`'s outline opened as its page next shows a way into it, `words` typed in its field (a screen's fixture).
pub fn outline_preset(key : String, words : String) -> Unit {
  outline_presets[key] = words
}

///|
/// ⌥⇧↑ (`by` -1) and ⌥⇧↓ (1): chat `r` (its view `v`) to the message a person said before or after the one the reader
/// is at, flashing (said_now's). Whether there was one.
pub fn said_go(src : Source, r : ChatRef, v : ChatView, by : Int) -> Bool {
  guard v.thread is Some(_) else { return false }
  let rd = reading_of(chat_key(r))
  match said_step(said_now(src, r, v), reader_top(rd, v, rd.top_seq), rd.at_end, by) {
    Some(seq) => {
      @sfbase.go_to(r, seq)
      true
    }
    None => false
  }
}

///|
/// Whether a page `w` wide leaves room at its column's right for the rail (rail_need): the column 760 at most in its
/// middle, the rows' words ending row_side in from its side (beside the system's bars, an iPhone Duo's, row_side's
/// dense_row_side, less than the rail needs: none there).
pub fn rail_fits(w : Double) -> Bool {
  w > chat_narrow_w && row_side(w) >= rail_need
}

///|
/// How wide the rail's press is (S11, 44: the six principles' room to press, on every input; as tall at least), how far
/// in from the pane's right it stands (clear of the list's scroll bar, @ui.scroll_bar_room), and how far clear of the
/// rows' words it is at least (S6, 24): the room the column must leave at its right for it to show.
let rail_press_w : Double = @ui.Space::px(S11)

///|
let rail_clear : Double = @ui.Space::px(S6)

///|
let rail_need : Double = rail_press_w + @ui.scroll_bar_room + rail_clear

///|
/// A tick of the rail, drawn as the library's rules are (a line of the line's colour, square): S0_5 (2) thick, S1 apart,
/// a day S3 from the one before; S2 long, the reader's S4 and in the ink; the press's room over and under them
/// (rail_pad). The rail at most half the list's height, the ticks about the reader's where there are more. The styles
/// and rail_window's sums are of these alone.
let tick_thick : Double = @ui.Space::px(S0_5)

///|
// kept across runs: a value (a token)
let tick_gap : @ui.Space = S1

///|
// kept across runs: a value (a token)
let tick_day_gap : @ui.Space = S3

///|
let tick_short : Double = @ui.Space::px(S2)

///|
let tick_long : Double = @ui.Space::px(S4)

///|
// kept across runs: a value (a token)
let rail_pad : @ui.Space = S2

///|
let rail_share : Double = 0.5

///|
/// The ticks shown of `days` (how many said on each, oldest first) about the `at`th of them all, as many as `most` tall
/// holds: each tick's index among all and whether a day begins at it (not the first shown).
fn rail_window(days : Array[Int], at : Int, most : Double) -> Array[(Int, Bool)] {
  let all : Array[(Int, Bool)] = []
  let mut n = 0
  for di, k in days {
    for j in 0..<k {
      all.push((n, di > 0 && j == 0))
      n += 1
    }
  }
  if all.is_empty() {
    return []
  }
  let height = fn(from : Int, to : Int) {
    let mut h = 0.0
    for i in from..<to {
      h += tick_thick + (if i > from { if all[i].1 { tick_day_gap.px() } else { tick_gap.px() } } else { 0.0 })
    }
    h
  }
  let at = if at < 0 || at >= all.length() { all.length() - 1 } else { at }
  let mut from = at
  let mut to = at + 1
  // (grown a tick at a time either way about the reader's, as far as it holds)
  let mut grew = true
  while grew {
    grew = false
    if to < all.length() && height(from, to + 1) <= most {
      to += 1
      grew = true
    }
    if from > 0 && height(from - 1, to) <= most {
      from -= 1
      grew = true
    }
  }
  all[from:to].to_array().mapi(fn(i, t) { (t.0, i > 0 && t.1) })
}

///|
/// The rail of chat `r`'s outline (its thread `thread`) at the list's right (an old view's, beside to_latest), the
/// list's visible room `top` under its top and `room` over its foot: shown while the outline has three said or more;
/// one tick for each, the one at `index` the reader's. Pressed, the outline beside it, at its left, its field taking
/// the keys. Whether it shows.
fn outline_rail(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  thread : Double,
  value : Json?,
  top_seq : Double,
  at_end : Bool,
  top : Double,
  room : Double,
) -> Bool {
  let days = items(value, "days").map(fn(d) { items(Some(d), "items").length() })
  let said = outline_seqs(value)
  guard said.length() >= rail_least else { return false }
  let current = outline_current(said, top_seq, at_end)
  let at = said.search(current).unwrap_or(said.length() - 1)
  // (its share of the list's height, less the press's own room over and under its ticks)
  let most = dmax(0.0, dmax(0.0, c.height - top - room) * rail_share - 2.0 * rail_pad.px())
  let shown = rail_window(days, at, most)
  let id = c.id("chat-outline-rail")
  let stint = c.page_stint()
  c.on_press(id, fn() { open_outline(src, r, thread, current, from=Of(id), side=Left, along=Middle, keys=true, stint~) })
  @sf.tip(c, "chat-outline-rail", id, @sf.t("web-main.keymap.chat.outline"), shortcut="chat.outline", side=Left)
  c.layer(fn() {
    c.box(style=rail_place.then(@ui.style(pt=@sf.room_of(top), pb=@sf.room_of(room))), fn() {
      // (a day's ticks together, the days further apart)
      let days : Array[Array[Int]] = []
      for t in shown {
        let (n, day) = t
        if day || days.is_empty() {
          days.push([])
        }
        days[days.length() - 1].push(n)
      }
      let b = c.box(style=rail_press, id~, fn() {
        for ticks in days {
          c.box(style=rail_day, fn() {
            for n in ticks {
              c.box(style=if n == at { tick_on } else { tick_off }, fn() {  }) |> ignore
            }
          })
          |> ignore
        }
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.outline.title"))
    })
    |> ignore
  })
  |> ignore
  true
}

///|
/// How many said the outline has at least for its rail to show.
let rail_least : Int = 3

///|
/// Where the rail stands: the list's right, in its middle between the bar and the composer's room, clear of its scroll
/// bar.
// kept across runs: a value (no field of it changes)
let rail_place : @ui.Style = @ui.style(w=Full, h=Full, align=AEnd, justify=JCenter, pr=@sf.room_of(@ui.scroll_bar_room))

///|
/// The rail's press: 44 wide and 44 tall at least (rail_press_w), its ticks in its middle at its right, rail_pad in.
// kept across runs: a value (no field of it changes)
let rail_press : @ui.Style = @ui.style(
  w=Fixed(rail_press_w),
  min_h=Fixed(rail_press_w),
  align=AEnd,
  justify=JCenter,
  py=rail_pad,
  pr=rail_pad,
  gap=tick_day_gap,
)

///|
/// A day's ticks: tick_gap apart, at the press's right.
// kept across runs: a value (no field of it changes)
let rail_day : @ui.Style = @ui.style(align=AEnd, gap=tick_gap)

///|
/// A tick: a rule, the reader's long in the ink, the rest short in the line's.
// kept across runs: a value (no field of it changes)
let tick_off : @ui.Style = @ui.style(w=Fixed(tick_short), h=Fixed(tick_thick), bg=Line)

///|
// kept across runs: a value (no field of it changes)
let tick_on : @ui.Style = @ui.style(w=Fixed(tick_long), h=Fixed(tick_thick), bg=Fg)

///|
/// The round button to chat `r`'s outline (its thread `thread`), over the way to the newest (`lift` over the foot,
/// `right` in from the pane's end), coming and going as that one does (`shown`, float_trans); pressed, the outline
/// beside it (a sheet on Small). `current`: the message the reader is at.
fn outline_float(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  thread : Double?,
  current : () -> Double,
  shown : Bool,
  right : Double,
  lift : Double,
) -> Unit {
  let p = @sf.theme().p
  let look = match @motion.presence(c, "chat-outline", shown, enter=float_trans(), exit=float_trans()) {
    Some(l) => l
    None => return
  }
  let id = c.id("chat-outline")
  let stint = c.page_stint()
  match thread {
    Some(th) if shown => c.on_press(id, fn() { open_outline(src, r, th, current(), from=Of(id), side=Left, stint~) })
    _ => ()
  }
  @sf.tip(c, "chat-outline", id, @sf.t("web-main.keymap.chat.outline"), shortcut="chat.outline")
  c.layer(fn() {
    float_box(c, right, lift, fn() {
      let b = c.box(style=if c.hovered(id) { float_button_hot } else { float_button }, id~, fn() {
        @sf.icon(c, "list", size=float_icon, color=p.text) |> ignore
      })
      c.semantics(b, Button, id~, label=@sf.t("web-main.outline.title"))
      c.look(b, look)
      @motion.leaving(c, b, shown)
      b
    })
  })
  |> ignore
}

///|
/// Chat `r`'s ways into its outline on its page (chat_list's, an old view's, `lay_w` wide as it is laid out, `list` its
/// rows): its rail where the page leaves it room (the outline asked for then), else its round button over the way to
/// the newest while that shows (`jump`); neither in a replay of a run from before (Source's `asks_outline`); its keys.
/// Whether the round button shows.
fn outline_entries_of(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  key : String,
  list : Array[Entry],
  lay_w : Double,
  jump : Bool,
  top : Double,
  room : Double,
) -> Bool {
  let k = chat_key(r)
  // (offered where the outline may be asked for: not in a replay of a run from before, whose app had none)
  let offered = (src.asks_outline)()
  let wide = rail_fits(lay_w)
  // where the reader is, as the list's first row in view and its end (built again only as those change)
  let (first, at_end) = outline_place(c.list_info_as(key, outline_place))
  let top_seq = {
    let mut s = -1.0
    if first >= 0 {
      let mut i = first
      while i < list.length() && s < 0.0 {
        match list[i] {
          Said(m) => s = m.seq
          _ => ()
        }
        i += 1
      }
    }
    reader_top(reading_of(k), v, s)
  }
  let railed = match v.thread {
    Some(th) if wide && offered => {
      let value = src.topic("chatOutline", outline_params(r, th)).get().value
      outline_rail(c, src, r, th, value, top_seq, at_end, top, room)
    }
    _ => false
  }
  let floated = offered && !wide && jump && v.thread is Some(_)
  outline_float(
    c,
    src,
    r,
    v.thread,
    fn() { outline_current(said_in_view(v), top_seq, at_end) },
    floated,
    float_right(c),
    room + float_lift + float_above,
  )
  if railed {
    outline_entries[k] = (c.id("chat-outline-rail"), true)
  } else if floated {
    outline_entries[k] = (c.id("chat-outline"), false)
  } else {
    outline_entries.remove(k) |> ignore
  }
  // (a screen's fixture: opened from what shows, once the frame's builds are over)
  match outline_presets.get(k) {
    Some(words) if railed || floated => {
      outline_presets.remove(k) |> ignore
      let stint = c.page_stint()
      c.tell("outline/preset/" + k, fn() { outline_open_keys(src, r, v, stint~, typed=words) |> ignore })
    }
    _ => ()
  }
  // its keys (keymap.ts's chat group): the outline, the message a person said before and after
  c.key_context("Chat")
  let stint = c.page_stint()
  c.on_action("chat.outline", fn() {
    guard v.thread is Some(_) else { return false }
    // (what asks the core told outside the build, at the key's moment: Ctx::tell)
    c.tell("chat.outline/" + k, fn() { outline_open_keys(src, r, v, stint~) |> ignore })
    true
  })
  c.on_action("chat.said.prev", fn() { said_go(src, r, v, -1) })
  c.on_action("chat.said.next", fn() { said_go(src, r, v, 1) })
  floated
}

///|
/// Where the reader is as a chat's list stands (Ctx::list_info_as's: built again only as this changes): its first row
/// in view (-1 none) and whether it is at its end.
fn outline_place(i : @ui.ListInfo?) -> (Int, Bool) {
  match i {
    Some(i) => (i.first, i.at_end)
    None => (-1, true)
  }
}
