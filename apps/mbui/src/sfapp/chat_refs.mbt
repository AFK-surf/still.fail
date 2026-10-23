// References to other chats in what is written (ember apps/android chat/screens/Composer.kt ChatRefs, RefMarks, the
// field's InputTransformation, ChatRefMenu, markPasted; ChatLink.kt linkedRefs, insertedRange; web chatRefs.ts,
// ChatRef.tsx): in the composer a short mark, `@[its title]`, drawn in the accent, its brackets unseen (the same
// letters in the same places: `[@title]` with `[` and `]` clear); sent, a link the core keeps for it until then. `@`
// and a few letters at the caret open a menu over the composer of the chats it finds (the core's `chatSearch`: this
// station's, then the viewer's other workspaces', each saying whose); one picked goes in as the mark the core makes of
// it (`chat.ref`). A backspace just after a mark takes it whole. A chat's link pasted as it is copied
// (`[its title](its link)`, of this workspace) goes in as its mark (a link to its execution history kept with it:
// `chat.refs`).

///|
/// What the composer last saw of its field, by draft: its words and selection (what a change is told apart by), and
/// the `@` whose menu was closed by a pick (-1 none), not opened again until the `@words` are gone.
priv struct RefField {
  mut text : String
  mut anchor : Int
  mut caret : Int
  mut closed : Int
}

///|
let ref_fields : Map[String, RefField] = {}

///|
fn ref_field_of(key : String) -> RefField {
  match ref_fields.get(key) {
    Some(f) => f
    None => {
      let f = { text: "", anchor: 0, caret: 0, closed: -1 }
      ref_fields[key] = f
      f
    }
  }
}

///|
/// The marks in `text` (ChatRefs.MARK, `@\[([^\]\n]{1,120})\]`): each its start and its end (past the `]`).
fn ref_marks(text : String) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let n = text.length()
  let mut i = 0
  while i + 1 < n {
    if text.at(i).to_int() == 64 && text.at(i + 1).to_int() == 91 {
      // the title: 1 to 120 of anything but `]` and a new line, then `]`
      let mut j = i + 2
      while j < n && j - (i + 2) <= 120 && text.at(j).to_int() != 93 && text.at(j).to_int() != 10 {
        j = j + 1
      }
      let len = j - (i + 2)
      if j < n && text.at(j).to_int() == 93 && len >= 1 && len <= 120 {
        out.push((i, j + 1))
        i = j + 1
        continue
      }
    }
    i = i + 1
  }
  out
}

///|
/// How the field draws its words (RefMarks): each mark's `@[` as `[@`, the `[` and the `]` clear, the rest in the
/// accent.
fn ref_look(accent : Int64) -> (String) -> (String, Array[(Int, Int, Int64)]) {
  fn(s) {
    let marks = ref_marks(s)
    if marks.is_empty() {
      return (s, [])
    }
    let sb = StringBuilder()
    let spans : Array[(Int, Int, Int64)] = []
    let mut at = 0
    for m in marks {
      let (a, b) = m
      sb.write_string(s.view(start_offset=at, end_offset=a).to_string())
      sb.write_string("[@")
      sb.write_string(s.view(start_offset=a + 2, end_offset=b).to_string())
      at = b
      spans.push((a, a + 1, 0L))
      spans.push((a + 1, b - 1, accent))
      spans.push((b - 1, b, 0L))
    }
    sb.write_string(s.view(start_offset=at).to_string())
    (sb.to_string(), spans)
  }
}

///|
/// The `@words` the caret is at the end of (ChatRefs.at, `(?:^|\s)@([^\s@\[\]()]{0,40})$` before the caret): where the
/// `@` is and the words after it; None when it is not in one.
fn ref_at(text : String, caret : Int) -> (Int, String)? {
  let caret = if caret < 0 { 0 } else if caret > text.length() { text.length() } else { caret }
  let mut i = caret
  while i > 0 && caret - i <= 40 {
    let ch = text.at(i - 1).to_int()
    if ch == 64 {
      let before_ok = i - 1 == 0 || is_space_unit(text.at(i - 2).to_int())
      return if before_ok {
        Some((i - 1, text.view(start_offset=i, end_offset=caret).to_string()))
      } else {
        None
      }
    }
    if is_space_unit(ch) || ch == 91 || ch == 93 || ch == 40 || ch == 41 {
      return None
    }
    i = i - 1
  }
  None
}

///|
/// Whether a UTF-16 unit is whitespace as a regex's `\s` takes it on Android (java.util.regex, no
/// UNICODE_CHARACTER_CLASS: space, tab, the line breaks, \v and \f; not U+3000 nor the other Unicode spaces).
fn is_space_unit(ch : Int) -> Bool {
  ch == 32 || (ch >= 9 && ch <= 13)
}

///|
/// The mark just before `caret` (a backspace there takes it whole: ChatRefs.before), its start; None when there is none.
fn ref_before(text : String, caret : Int) -> Int? {
  for m in ref_marks(text.view(end_offset=caret).to_string()) {
    if m.1 == caret {
      return Some(m.0)
    }
  }
  None
}

///|
/// Where one change put words in (ChatLink.kt insertedRange): the range of `now` that is not in `was`; None when nothing
/// went in.
fn inserted_range(was : String, now : String) -> (Int, Int)? {
  let most = if was.length() < now.length() { was.length() } else { now.length() }
  let mut start = 0
  while start < most && was.at(start) == now.at(start) {
    start = start + 1
  }
  let mut end = 0
  while end < most - start && was.at(was.length() - 1 - end) == now.at(now.length() - 1 - end) {
    end = end + 1
  }
  if now.length() - end > start {
    Some((start, now.length() - end))
  } else {
    None
  }
}

///|
/// A chat a link names (ChatLink.kt chatOfLink): its station (`<workspace>/<station>`), its key, and `?history=…`
/// after it ("" none).
priv struct LinkedChat {
  station : String
  id : String
  history : String
}

///|
/// The chat a still.fail link names (`…/o/<workspace>/<station>/<session>`) or its page
/// (`…/w/<workspace>/s/<station>/chats/<id>`), with what follows it of an execution history; None otherwise.
fn linked_chat(href : String) -> LinkedChat? {
  // its history (`?history=…`, `&entry=n`), at its end
  let (path, history) = match href.find("?history=") {
    Some(k) => (href.view(end_offset=k).to_string(), href.view(start_offset=k).to_string())
    None => (href, "")
  }
  // as Android's SHARED and PAGE take it: `?history=` and some, `&entry=` and digits after it, then the end
  if history != "" && !history_ok(history) {
    return None
  }
  let path = if path.has_suffix("/") { path.view(end_offset=path.length() - 1).to_string() } else { path }
  let parts = path.split("/").map(fn(v) { v.to_string() }).to_array()
  let n = parts.length()
  let ok = fn(p : String) { p != "" && !p.contains("?") && !p.contains("#") && !p.contains(" ") }
  if n >= 4 && parts[n - 4] == "o" && ok(parts[n - 3]) && ok(parts[n - 2]) && ok(parts[n - 1]) {
    return Some({ station: parts[n - 3] + "/" + parts[n - 2], id: @codec.percent_decoded(parts[n - 1]), history })
  }
  if n >= 6 && parts[n - 6] == "w" && parts[n - 4] == "s" && parts[n - 2] == "chats" && ok(parts[n - 5]) &&
    ok(parts[n - 3]) &&
    ok(parts[n - 1]) {
    return Some({ station: parts[n - 5] + "/" + parts[n - 3], id: @codec.percent_decoded(parts[n - 1]), history })
  }
  None
}

///|
/// Whether `h` is `?history=…` as a link's end has it (`\?history=[^&#\s]+(?:&entry=\d+)?`).
fn history_ok(h : String) -> Bool {
  let rest = h.view(start_offset="?history=".length()).to_string()
  let (key, entry) = match rest.find("&") {
    Some(k) => (rest.view(end_offset=k).to_string(), Some(rest.view(start_offset=k).to_string()))
    None => (rest, None)
  }
  if key == "" || key.contains("#") || key.contains(" ") || key.contains("\n") || key.contains("\t") {
    return false
  }
  match entry {
    None => true
    Some(e) => {
      if !e.has_prefix("&entry=") || e.length() == "&entry=".length() {
        return false
      }
      for i in "&entry=".length()..<e.length() {
        let ch = e.at(i).to_int()
        if ch < 48 || ch > 57 {
          return false
        }
      }
      true
    }
  }
}

///|
/// The chats' links in `text`, `[its title](its link)` as one is copied, of the workspace of `here` (the station
/// written on), as the composer takes them when pasted (ChatLink.kt linkedRefs, PASTED_REF
/// `\[([^\]\n]{1,120})\]\((\S+?)\)`): each its range, its title and the chat.
fn linked_refs(text : String, here : String) -> Array[((Int, Int), String, LinkedChat)] {
  let out : Array[((Int, Int), String, LinkedChat)] = []
  let workspace = match here.find("/") {
    Some(k) => here.view(end_offset=k).to_string()
    None => return out
  }
  let n = text.length()
  let mut i = 0
  while i < n {
    if text.at(i).to_int() != 91 {
      i = i + 1
      continue
    }
    let mut j = i + 1
    while j < n && j - (i + 1) <= 120 && text.at(j).to_int() != 93 && text.at(j).to_int() != 10 {
      j = j + 1
    }
    let title_len = j - (i + 1)
    if j + 1 < n && text.at(j).to_int() == 93 && text.at(j + 1).to_int() == 40 && title_len >= 1 && title_len <= 120 {
      // the link (`\S+?`): one unit at least, none whitespace, up to the first `)` after it
      let mut k = j + 3
      if j + 2 < n && !is_space_unit(text.at(j + 2).to_int()) {
        while k < n && text.at(k).to_int() != 41 && !is_space_unit(text.at(k).to_int()) {
          k = k + 1
        }
      } else {
        k = n
      }
      if k < n && text.at(k).to_int() == 41 {
        let href = text.view(start_offset=j + 2, end_offset=k).to_string()
        match linked_chat(href) {
          Some(chat) if chat.station.has_prefix(workspace + "/") =>
            out.push(((i, k + 1), text.view(start_offset=i + 1, end_offset=j).to_string(), chat))
          _ => ()
        }
        // matched, a chat's or not: the next is looked for after it (findAll)
        i = k + 1
        continue
      }
    }
    i = i + 1
  }
  out
}

///|
/// Words the app put in draft `d`'s field itself (kept, put back, given up as sent, a mark): put there, taken as they
/// are, not as written (Android's InputTransformation sees the user's edits only; what the app puts in goes as it is).
fn ref_field_put(d : Draft, words : String, caret? : Int) -> Unit {
  d.field.set(words, caret?)
  d.text = words
  let f = ref_field_of(d.key)
  let (anchor, at) = d.field.selection()
  f.text = words
  f.anchor = anchor
  f.caret = at
}

///|
/// The composer's field before it is built (its words as the input left them since the last frame): a backspace just
/// after a mark takes the mark whole; a chat's link pasted becomes its mark. What it saw is kept for the next change.
fn ref_field_edits(src : Source, d : Draft, station : String, locked : Bool) -> Unit {
  let f = ref_field_of(d.key)
  let now = d.field.text()
  let (anchor, caret) = d.field.selection()
  let was = f.text
  if now != was {
    let wa = f.anchor
    let wc = f.caret
    // a backspace just after a mark: the mark goes whole, the caret where it began
    let one_back = wa == wc &&
      wc > 0 &&
      anchor == caret &&
      caret == wc - 1 &&
      now.length() == was.length() - 1 &&
      now ==
      was.view(end_offset=wc - 1).to_string() + was.view(start_offset=wc).to_string()
    match (if one_back { ref_before(was, wc) } else { None }) {
      Some(m) => {
        ref_field_put(d, was.view(end_offset=m).to_string() + was.view(start_offset=wc).to_string(), caret=m)
        return
      }
      None => ()
    }
    // a chat's link pasted: its mark in its place, once the core has made it
    match inserted_range(was, now) {
      Some((a, b)) if b - a > 1 && !locked =>
        for x in linked_refs(now, station) {
          let ((ra, rb), title, chat) = x
          if ra < b && rb > a {
            mark_pasted(src, d, now, ra, now.view(start_offset=ra, end_offset=rb).to_string(), title, chat)
          }
        }
      _ => ()
    }
  }
  f.text = now
  f.anchor = anchor
  f.caret = caret
}

///|
/// A chat's link pasted (`whole`: `[title](link)`, at `at` of the words as pasted, `pasted`) made its mark by the
/// core (`chat.ref`; one with a link to its execution history keeps that link for it: `chat.refs`), put where the link
/// is now: where it was pasted if nothing was written since, else where it is if it still is. One the core cannot
/// make a mark of stays as it is (Composer.kt markPasted).
fn mark_pasted(
  src : Source,
  d : Draft,
  pasted : String,
  at : Int,
  whole : String,
  title : String,
  chat : LinkedChat,
) -> Unit {
  let base = cloud_origin()
  // into the draft's field as it is now: where the link was pasted if nothing was written since, else where it is
  let put = fn(mark : String) {
    let now = d.field.text()
    let (_, caret) = d.field.selection()
    let place = if now == pasted { Some(at) } else { now.find(whole) }
    match place {
      Some(at) => {
        let moved = if caret >= at + whole.length() { caret + mark.length() - whole.length() } else { caret }
        ref_field_put(
          d,
          now.view(end_offset=at).to_string() + mark + now.view(start_offset=at + whole.length()).to_string(),
          caret=moved,
        )
      }
      None => ()
    }
  }
  (src.call)(
    "chat.ref",
    {
      "station": Json::string(chat.station),
      "id": Json::string(chat.id),
      "title": Json::string(title),
      "base": Json::string(base),
    },
    fn(res) {
      let mark = match res {
        Ok(v) => text(Some(v), "mark")
        Err(_) => ""
      }
      if mark == "" || mark == whole {
        return
      }
      if chat.history == "" {
        put(mark)
        return
      }
      let at = match chat.station.find("/") {
        Some(k) => k
        None => 0
      }
      let page = trim_slash(base) +
        "/w/" +
        chat.station.view(end_offset=at).to_string() +
        "/s/" +
        chat.station.view(start_offset=at + 1).to_string() +
        "/chats/" +
        @codec.encode_uri_component(chat.id) +
        chat.history
      // the mark only once the core keeps its link (failing, the link stays as it is)
      (src.call)(
        "chat.refs",
        { "links": [[Json::string(mark.view(start_offset=2, end_offset=mark.length() - 1).to_string()), Json::string(page)]] },
        fn(r) { if r is Ok(_) { put(mark) } },
      )
    },
  )
}

// ── the `@` menu ────────────────────────────────────────────────────────

///|
/// The menu over the composer (ChatRefMenu): 10 in from its sides, 8 over the capsule; its card 12 in, as round as the
/// capsule, at most 320 high.
// kept across runs: a value (no field of it changes)
let ref_menu_outer : @ui.Style = @ui.style(w=Full, px=S2_5, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_card : @ui.Style = @ui.style(w=Full, p=S3)

///|
/// Its heading: 引用对话 and the words typed, 13, 12 in, 6 under.
// kept across runs: a value (no field of it changes)
let ref_menu_head : @ui.Style = @ui.style(row=true, w=Full, pl=S3, pr=S3, pb=S1_5, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_head_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_head_query : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
/// What it says in place of chats: 15, muted, 12 in, 6 over, 4 under.
// kept across runs: a value (no field of it changes)
let ref_menu_note_box : @ui.Style = @ui.style(w=Full, pl=S3, pr=S3, pt=S1_5, pb=S1)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_note : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, w=Full)

///|
/// A chat: 44 high at least, 12 and 8 in, its maker's mark in 16, 10 apart; rounded concentric with the card (its
/// ground, laid under it as a layer: the capsule's corner, 12 in).
// kept across runs: a value (no field of it changes)
let ref_menu_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=@sf.ref_row_min_h,
  px=S3,
  py=S2,
  gap=S2_5,
  align=ACenter,
  radius=Inner,
)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_mark : @ui.Style = @ui.style(w=S4, align=ACenter)

///|
/// Its title and whose it is (another workspace's: its name right after the title, as a tag), 6 apart.
// kept across runs: a value (no field of it changes)
let ref_menu_title_line : @ui.Style = @ui.style(row=true, w=Full, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_title_box : @ui.Style = @ui.style()

///|
/// (weight(1f, fill = false): the title as wide as it is, cut short first, with an ellipsis)
// kept across runs: a value (no field of it changes)
let ref_menu_title : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_ago : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// The menu's most.
let ref_menu_max : Double = 320.0

///|
/// `@` and a few letters at the caret of the field (focused, nothing selected, words to send not locked): the chats
/// they find over the composer; one picked goes in as its mark, in the `@words`' place, a space after it.
fn chat_ref_menu(c : @ui.Ctx, src : Source, d : Draft, station : String, here : String, key : String, locked : Bool) -> Unit {
  let f = ref_field_of(d.key)
  let (anchor, caret) = d.field.selection()
  let words = d.field.text()
  let found = if anchor == caret && c.editor_focused(key) && !locked { ref_at(words, caret) } else { None }
  match found {
    None => {
      f.closed = -1
      return
    }
    Some((start, _)) if start == f.closed => return
    _ => ()
  }
  let (start, query) = found.unwrap()
  let params : Map[String, Json] = {
    "scope": Json::string(workspace_of(station)),
    "query": Json::string(query),
    "station": Json::string(station),
    "limit": Json::number(8.0),
    "elsewhere": Json::boolean(true),
  }
  if here != "" {
    params["exclude"] = Json::string(here)
  }
  let topic = (src.topic)("chatSearch", params)
  let chats = match topic.value {
    Some(v) => items(Some(v), "items")
    None => []
  }
  c.box(style=ref_menu_outer, fn() {
    c.box(style=ref_menu_card, fn() {
      let g = c.layer(fn() { floating_ground(c, Fill(1.0)) |> ignore })
      c.draw_only(g)
      c.capped("chat-ref/" + d.key, ref_menu_max - 24.0, fn() {
        c.box(style=@sf.full_width, fn() {
          c.box(style=ref_menu_head, fn() {
            c.text(tr("android-chat.ref.title"), style=ref_menu_head_words) |> ignore
            if query != "" {
              c.text(query, style=ref_menu_head_query) |> ignore
            }
          })
          |> ignore
          if topic.value is None && topic.error is Some(_) {
            c.box(style=ref_menu_note_box, fn() {
              c.text(fill("android-chat.ref.update", [("app", "still.fail")]), style=ref_menu_note) |> ignore
            })
            |> ignore
          } else if topic.value is None {
            c.box(style=ref_menu_note_box, fn() { @sf.wait_line(c, tr("common.reading"), key="chat-ref") })
            |> ignore
          } else if chats.is_empty() {
            c.box(style=ref_menu_note_box, fn() {
              c.text(
                tr(if query != "" { "android-chat.ref.none.match" } else { "android-chat.ref.none" }),
                style=ref_menu_note,
              )
              |> ignore
            })
            |> ignore
          } else {
            for x in chats {
              let item = chat_item(x)
              let outside = text(Some(x), "outside")
              let id = c.id("chat-ref/" + item.station + "/" + item.id)
              if c.clicked(id) {
                ref_pick(c, src, d, station, start, caret, item)
              }
              c.box(style=ref_menu_row, id~, fn() {
                c.box(style=ref_menu_mark, fn() {
                  match item.agents.get(0) {
                    Some(a) => @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
                    None => ()
                  }
                })
                |> ignore
                c.box(style=ref_menu_title_line, fn() {
                  c.box(style=ref_menu_title_box, fn() { c.text(item.title, style=ref_menu_title) |> ignore }) |> ignore
                  if outside != "" {
                    c.box(style=words_tag, fn() { c.text(outside, style=words_tag_words) |> ignore }) |> ignore
                  }
                })
                |> ignore
                if item.ago != "" {
                  c.text(item.ago, style=ref_menu_ago) |> ignore
                }
                // Composer.kt ChatRefMenu: clip(Smooth(concentric(ComposerCorner, 12))).clickable
                @motion.ripple(c, id, @sf.inner_corner(composer_corner, 12.0))
              })
              |> ignore
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A chat picked in the menu: its mark from the core (`chat.ref`, which keeps its link until it is sent), in the
/// `@words`' place if they are still there, a space after it, the caret after that; the menu closed for this `@`.
/// Failing, a toast says why.
fn ref_pick(
  c : @ui.Ctx,
  src : Source,
  d : Draft,
  station : String,
  start : Int,
  caret : Int,
  item : ChatItem,
) -> Unit {
  let f = ref_field_of(d.key)
  f.closed = start
  (src.call)(
    "chat.ref",
    {
      "station": Json::string(item.station),
      "id": Json::string(item.id),
      "title": Json::string(item.title),
      "base": Json::string(cloud_origin()),
      "into": Json::string(workspace_of(station)),
    },
    fn(res) {
      match res {
        Ok(v) => {
          let mark = text(Some(v), "mark")
          if mark == "" {
            return
          }
          // in the `@words`' place if they are still there
          let now = d.field.text()
          if start >= now.length() || now.at(start).to_int() != 64 || caret > now.length() {
            return
          }
          ref_field_put(
            d,
            now.view(end_offset=start).to_string() + mark + " " + now.view(start_offset=caret).to_string(),
            caret=start + mark.length() + 1,
          )
        }
        Err(e) => say(c, fill("android-chat.ref.failed", [("error", text(Some(e), "message"))]))
      }
    },
  )
}
