// References to other chats in what is written, for each frame's composer (web Chat.tsx useComposerText's reference,
// its paste and its Backspace; ChatRef.tsx RefMirror): a mark, `@[its title]`, drawn in the accent with its brackets
// unseen; `@` and a few letters at the caret, what a menu of chats is opened by; a chat picked going in as its mark
// (the core's `chat.ref`); a Backspace just after a mark taking it whole; a chat's link pasted as it is copied going in
// as its mark; words pasted at once past the core's bound going as a file. What is written is read as the core reads
// it (`ref.at`, `ref.marks`, `ref.pasted`, `paste.info`: refLinks.ts, pasted.ts), never here; a page draws the menu.

///|
/// What a field of a draft was last seen as and what the core said of it: its words and selection (a change is told
/// apart by them); the `@words` at its caret (where the `@` is, what follows) for the words and caret they were asked
/// of; the `@` whose menu was closed (Escape, a pick; -1 none), not opened again until the `@words` are gone; the chat
/// chosen in the menu; the marks in the words (where each starts and ends past its `]`) and the words the core read
/// them in (others: moved along with an edit until it has read these); what the menu's words last found (refs_search).
priv struct RefField {
  mut text : String
  mut anchor : Int
  mut caret : Int
  at_of : @signals.Signal[String]
  at : @signals.Signal[(Int, String)?]
  closed : @signals.Signal[Int]
  active : @signals.Signal[Int]
  marks : @sf.LiveArray[(Int, Int)]
  marks_of : @signals.Signal[String]
  mut marks_asked : String
  mut found : Json?
}

///|
let ref_fields : Map[String, RefField] = {}

///|
/// From how many characters words pasted at once go as a file (the core's PASTE_THRESHOLD; 0 till it has said).
let paste_bound : Ref[Int] = Ref(0)

///|
let paste_bound_asked : Ref[Bool] = Ref(false)

///|
pub fn refs_reset() -> Unit {
  ref_fields.clear()
  paste_bound.val = 0
  paste_bound_asked.val = false
}

///|
fn ref_field(key : String) -> RefField {
  match ref_fields.get(key) {
    Some(f) => f
    None => {
      let f : RefField = {
        text: "",
        anchor: 0,
        caret: 0,
        at_of: @signals.signal("", same=fn(a, b) { a == b }),
        at: @signals.signal(None),
        closed: @signals.signal(-1),
        active: @signals.signal(0),
        marks: @sf.LiveArray::from([]),
        marks_of: @signals.signal("", same=fn(a, b) { a == b }),
        marks_asked: "",
        found: None,
      }
      ref_fields[key] = f
      f
    }
  }
}

///|
/// What an edit changed: the words before it the same up to `start`, the old words' end of what it took and the new
/// words' end of what it put in (each after them the same again).
fn edit_of(was : String, now : String) -> (Int, Int, Int) {
  let most = if was.length() < now.length() { was.length() } else { now.length() }
  let mut start = 0
  while start < most && was.at(start) == now.at(start) {
    start += 1
  }
  let mut end = 0
  while end < most - start && was.at(was.length() - 1 - end) == now.at(now.length() - 1 - end) {
    end += 1
  }
  (start, was.length() - end, now.length() - end)
}

///|
fn ref_key(text : String, caret : Int) -> String {
  text + "\u{1}" + caret.to_string()
}

///|
/// Draft `key`'s field (`input`) as the input left it since the last frame, read before it is built: a Backspace just
/// after a mark takes the mark whole (the caret where it began); the marks the words held moved along with what was
/// written, the core asked for the words' own; the `@words` at the caret asked of the core; a chat's link (of the
/// workspace of station `here`) in what was put in at once going in as its mark, once the core has made it (not while
/// `locked`).
pub fn refs_edits(c : @ui.Ctx, src : Source, key : String, input : @ui.Field, here : String, locked : Bool) -> Unit {
  let f = ref_field(key)
  let now = input.text()
  let (anchor, caret) = input.selection()
  if now == f.text && anchor == f.anchor && caret == f.caret {
    // (words the app put in itself: their marks)
    refs_ask_marks(c, src, key, now)
    return
  }
  let was = f.text
  let (wa, wc) = (f.anchor, f.caret)
  if now != was {
    let (start, took, put) = edit_of(was, now)
    // one character taken just before the caret: a mark ending there goes whole
    let one_back = wa == wc && anchor == caret && caret == wc - 1 && start == wc - 1 && took == wc && put == start
    let mark = if one_back { f.marks.search_by(fn(m) { m.1 == wc }) } else { None }
    match mark {
      Some(i) => {
        let a = f.marks[i].0
        refs_put(key, input, was.view(end_offset=a).to_string() + was.view(start_offset=wc).to_string(), caret=a)
        return
      }
      None => ()
    }
    // the marks the edit did not touch, where they are now
    let moved = put - took
    f.marks.replace(f.marks.filter_map(fn(m) {
      if m.1 <= start {
        Some(m)
      } else if m.0 >= took {
        Some((m.0 + moved, m.1 + moved))
      } else {
        None
      }
    }))
    // what was put in at once: the chats' links in it
    if put - start > 1 && !locked {
      let pasted = now.view(start_offset=start, end_offset=put).to_string()
      c.tell("refs/pasted/" + key, fn() { refs_pasted(src, key, input, here, now, start, pasted) })
    }
  }
  f.text = now
  f.anchor = anchor
  f.caret = caret
  refs_ask_marks(c, src, key, now)
  if anchor == caret {
    let asked = ref_key(now, caret)
    c.tell("refs/at/" + key, fn() {
      (src.call)("ref.at", { "text": Json::string(now), "caret": Json::number(caret.to_double()) }, fn(r) {
        match r {
          Ok(v) => {
            let at = match field(Some(v), "at") {
              Some(Object(_)) as o => Some((number(o, "start").to_int(), text(o, "query")))
              _ => None
            }
            match at {
              None => {
                f.closed.set(-1)
                f.found = None
              }
              Some((_, q)) =>
                match f.at.get() {
                  Some((_, was)) if was == q => ()
                  _ => f.active.set(0)
                }
            }
            f.at.set(at)
            f.at_of.set(asked)
          }
          Err(_) => ()
        }
      })
    })
  }
}

///|
/// The marks of words `now` asked of the core (once for them, holding a `@[`).
fn refs_ask_marks(c : @ui.Ctx, src : Source, key : String, now : String) -> Unit {
  let f = ref_field(key)
  if !now.contains("@[") {
    // (said only as it changes: said each build, what read it would be built again each frame)
    if !@signals.untracked(fn() { f.marks.is_empty() }) {
      f.marks.replace([])
    }
    f.marks_of.set(now)
    return
  }
  if f.marks_of.get() == now || f.marks_asked == now {
    return
  }
  f.marks_asked = now
  c.tell("refs/marks/" + key, fn() {
    (src.call)("ref.marks", { "text": Json::string(now) }, fn(r) {
      match r {
        Ok(v) if f.text == now => {
          f.marks.replace(items(Some(v), "marks").map(fn(m) {
            (number(Some(m), "start").to_int(), number(Some(m), "end").to_int())
          }))
          f.marks_of.set(now)
        }
        _ => ()
      }
    })
  })
}

///|
/// Words the app put in draft `key`'s field itself (a mark, the draft kept, put back): put there, seen as they are,
/// not as written (no paste in them, no Backspace).
pub fn refs_put(key : String, input : @ui.Field, words : String, caret? : Int) -> Unit {
  let f = ref_field(key)
  let was = f.text
  input.set(words, caret?)
  let (anchor, at) = input.selection()
  // its marks where they are now, those the change took gone
  if words != was {
    let (start, took, put) = edit_of(was, words)
    let moved = put - took
    f.marks.replace(f.marks.filter_map(fn(m) {
      if m.1 <= start {
        Some(m)
      } else if m.0 >= took {
        Some((m.0 + moved, m.1 + moved))
      } else {
        None
      }
    }))
  }
  f.text = words
  f.anchor = anchor
  f.caret = at
  f.at.set(None)
}

///|
/// How draft `key`'s field draws its words (RefMirror, refMark, refMarkHidden): each mark's `[` and `]` clear (the
/// `[` put before its `@`, the same width: what follows keeps its place), the rest in `accent`.
pub fn refs_look(key : String, accent : Int64) -> (String) -> (String, Array[(Int, Int, Int64)]) {
  fn(s) {
    let f = ref_field(key)
    if s != f.text || f.marks.is_empty() {
      return (s, [])
    }
    let sb = StringBuilder()
    let spans : Array[(Int, Int, Int64)] = []
    let mut at = 0
    for m in f.marks {
      let (a, b) = m
      if a < at || b > s.length() || b - a < 4 {
        continue
      }
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
/// The marks draft `key`'s field holds, where they are in `words` sent from it (its words trimmed, lines maybe put after
/// them): what was sent from here draws them as the field did until the core's row has them as links (sent_local,
/// flight_start). None where the field holds other words.
pub fn refs_sent_marks(key : String, words : String) -> Array[(Int, Int)] {
  let f = ref_field(key)
  let s = f.text
  let blank = fn(i : Int) {
    let u = s.unsafe_charcode_at(i)
    u == 32 || u == 10 || u == 9
  }
  let mut lead = 0
  while lead < s.length() && blank(lead) {
    lead += 1
  }
  let mut end = s.length()
  while end > lead && blank(end - 1) {
    end -= 1
  }
  guard words.has_prefix(s.view(start_offset=lead, end_offset=end).to_string()) else { return [] }
  f.marks.filter_map(fn(m) { if m.0 >= lead && m.1 <= end { Some((m.0 - lead, m.1 - lead)) } else { None } })
}

///|
/// Words `s` as a field draws its marks `marks` (refs_look): each one's `[` and `]` clear, the `[` before its `@`, the
/// rest in `accent`.
pub fn refs_runs(s : String, marks : Array[(Int, Int)], accent : Int64) -> Array[@ui.Run] {
  let out : Array[@ui.Run] = []
  let mut at = 0
  for m in marks {
    let (a, b) = m
    if a < at || b > s.length() || b - a < 4 {
      continue
    }
    if a > at {
      out.push(@ui.span(s.view(start_offset=at, end_offset=a).to_string()))
    }
    out.push(@ui.span("[", color=clear))
    out.push(@ui.span("@" + s.view(start_offset=a + 2, end_offset=b - 1).to_string(), color=accent))
    out.push(@ui.span("]", color=clear))
    at = b
  }
  if at < s.length() {
    out.push(@ui.span(s.view(start_offset=at).to_string()))
  }
  out
}

///|
/// (no ink: a rich run's 0 is the words' own)
let clear : Int64 = 0x00FFFFFFL

///|
/// Whether draft `key`'s field holds a mark, as the core read its words now; None while it has not read them (the words
/// changed since it was asked).
pub fn refs_marked(key : String) -> Bool? {
  let f = ref_field(key)
  if f.marks_of.get() == f.text {
    Some(!f.marks.is_empty())
  } else {
    None
  }
}

///|
/// The `@words` draft `key`'s field's caret is at the end of, as the core last read its words and caret (where the
/// `@` is, what follows it): while it reads them as they are now, as it read them before, if that `@` is still before
/// the caret (the menu stays as it was while the next letter is read, not closed for it and opened again); None in
/// none, in one whose menu was closed, or none read yet.
pub fn refs_at(key : String) -> (Int, String)? {
  let f = ref_field(key)
  if f.anchor != f.caret {
    return None
  }
  let read_now = f.at_of.get() == ref_key(f.text, f.caret)
  match f.at.get() {
    Some((start, _)) as at if start != f.closed.get() &&
      (read_now || (start < f.caret && f.caret <= f.text.length() && f.text.at(start).to_int() == 64)) => at
    _ => None
  }
}

///|
/// What the `@words` of draft `key` find (the core's `chatSearch` with `params`): while the core looks up the next
/// words, what the last ones found (the menu's chats stay till the next are there, not gone for a line saying it is
/// reading); what it says when it has none yet, or failed.
pub fn refs_search(src : Source, key : String, params : Map[String, Json]) -> Topic {
  let f = ref_field(key)
  let topic = (src.topic)("chatSearch", params)
  match (topic.value, f.found) {
    (Some(_), _) => {
      f.found = topic.value
      topic
    }
    (None, Some(_)) if topic.error is None => { value: f.found, error: None, version: topic.version }
    _ => topic
  }
}

///|
/// The menu of draft `key` closed for the `@` it is at (Escape), till its `@words` are gone.
pub fn refs_close(key : String) -> Unit {
  let f = ref_field(key)
  match f.at.get() {
    Some((start, _)) => f.closed.set(start)
    None => ()
  }
}

///|
/// The chat chosen in the menu of draft `key` among `n` (moved by `by`, round; -1 / 1: ↑ / ↓), and set (`to`).
pub fn refs_active(key : String, n : Int, by? : Int = 0, to? : Int) -> Int {
  let f = ref_field(key)
  match to {
    Some(i) => f.active.set(i)
    None => ()
  }
  if n <= 0 {
    return 0
  }
  f.active.set(((f.active.get() + by) % n + n) % n)
  f.active.get()
}

///|
/// A chat picked in the menu of draft `key` (its station, its id, its title) put in as the mark the core makes of it
/// (`chat.ref`, which keeps its link until it is sent; one of another workspace's keeps it for this one, `into`, too)
/// in the `@words`' place if they are still there, a space and the caret after it; the menu closed for this `@`.
/// Failing, `failed` is told why.
pub fn refs_pick(
  c : @ui.Ctx,
  src : Source,
  key : String,
  input : @ui.Field,
  into : String,
  station : String,
  id : String,
  title : String,
  failed : (String) -> Unit,
) -> Unit {
  let f = ref_field(key)
  guard f.at.get() is Some((start, _)) else { return }
  let caret = f.caret
  f.closed.set(start)
  c.tell("refs/pick/" + key, fn() {
    (src.call)(
      "chat.ref",
      {
        "station": Json::string(station),
        "id": Json::string(id),
        "title": Json::string(title),
        "base": Json::string(cloud_origin()),
        "into": Json::string(into),
      },
      fn(res) {
        match res {
          Ok(v) => {
            let mark = text(Some(v), "mark")
            let now = input.text()
            if mark == "" || start >= now.length() || now.at(start).to_int() != 64 || caret > now.length() {
              return
            }
            refs_put(
              key,
              input,
              now.view(end_offset=start).to_string() + mark + " " + now.view(start_offset=caret).to_string(),
              caret=start + mark.length() + 1,
            )
          }
          Err(e) => failed(text(Some(e), "message"))
        }
      },
    )
  })
}

///|
/// The chats' links in what was put in at once (`put`, at `at` of the words `pasted`) naming chats of the workspace of
/// station `here` (the core's `ref.pasted`), each made its mark by the core (`chat.ref`; one to its agent's execution
/// history keeping that link for it: `chat.refs`), put where its link is now: where it was put in while nothing was
/// written since, else where it still is. One the core cannot make a mark of stays as it is.
fn refs_pasted(src : Source, key : String, input : @ui.Field, here : String, pasted : String, at : Int, put : String) -> Unit {
  (src.call)("ref.pasted", { "text": Json::string(put), "here": Json::string(here) }, fn(r) {
    guard r is Ok(v) else { return }
    let base = cloud_origin()
    for x in items(Some(v), "refs") {
      let o = Some(x)
      let a = number(o, "start").to_int()
      let whole = put.view(start_offset=a, end_offset=number(o, "end").to_int()).to_string()
      let station = text(o, "station")
      let id = text(o, "id")
      let history = text(o, "history")
      let place = fn(mark : String) {
        let now = input.text()
        let (_, caret) = input.selection()
        let p = if now == pasted { Some(at + a) } else { now.find(whole) }
        match p {
          Some(p) => {
            let moved = if caret >= p + whole.length() { caret + mark.length() - whole.length() } else { caret }
            refs_put(
              key,
              input,
              now.view(end_offset=p).to_string() + mark + now.view(start_offset=p + whole.length()).to_string(),
              caret=moved,
            )
          }
          None => ()
        }
      }
      (src.call)(
        "chat.ref",
        {
          "station": Json::string(station),
          "id": Json::string(id),
          "title": Json::string(text(o, "title")),
          "base": Json::string(base),
        },
        fn(res) {
          let mark = match res {
            Ok(m) => text(Some(m), "mark")
            Err(_) => ""
          }
          if mark == "" || mark == whole {
            return
          }
          if history == "" {
            place(mark)
            return
          }
          let cut = station.find("/").unwrap_or(0)
          let page = trimmed(base) +
            "/w/" +
            station.view(end_offset=cut).to_string() +
            "/s/" +
            station.view(start_offset=cut + 1).to_string() +
            "/chats/" +
            @codec.encode_uri_component(id) +
            history
          // the mark only once the core keeps its link (failing, the link stays as it is)
          (src.call)(
            "chat.refs",
            { "links": [[Json::string(mark.view(start_offset=2, end_offset=mark.length() - 1).to_string()), Json::string(page)]] },
            fn(r) { if r is Ok(_) { place(mark) } },
          )
        },
      )
    }
  })
}

///|
fn trimmed(o : String) -> String {
  if o.has_suffix("/") {
    o.view(end_offset=o.length() - 1).to_string()
  } else {
    o
  }
}

///|
/// From how many characters words pasted at once go as a file (the core's: `paste.info`, asked once; 0 till it has
/// answered, none taken so).
pub fn paste_threshold(c : @ui.Ctx, src : Source) -> Int {
  if !paste_bound_asked.val {
    paste_bound_asked.val = true
    c.tell("refs/paste-bound", fn() {
      (src.call)("paste.info", { "text": Json::string("") }, fn(r) {
        match r {
          Ok(v) => paste_bound.val = number(Some(v), "threshold").to_int()
          Err(_) => paste_bound_asked.val = false
        }
      })
    })
  }
  paste_bound.val
}

///|
/// Words pasted at once past the bound (what the field gave up) going with draft `w` as a file of their own
/// (pastedText.ts makePastedFile: `pasted-text-<its id>.txt`), what the core says of them (`paste.info`) with it.
pub fn writing_paste(src : Source, w : Writing, station : String, words : String) -> Unit {
  (src.call)("paste.info", { "text": Json::string(words) }, fn(r) {
    guard r is Ok(v) else { return }
    let info = field(Some(v), "info")
    match info {
      Some(Object(_)) =>
        writing_add(src, w, station, "pasted-text-" + upload_id(w.key + "\u{2}" + words, w.files.length() + 1) + ".txt", @utf8.encode(words), pasted=info.unwrap())
      _ => ()
    }
  })
}

///|
/// Pasted words of draft `w` that failed going up (file `id`) made a file again from them (Chat.tsx: removed, and added
/// again with what the core said of them).
pub fn writing_paste_again(src : Source, w : Writing, id : String) -> Unit {
  guard writing_went.get(id) is Some((station, name, bytes)) else { return }
  let info = w.files.iter().find_first(fn(f) { text(Some(f), "id") == id }).map(fn(f) { field(Some(f), "pasted") })
  writing_remove(src, w, id)
  match info {
    Some(Some(p)) => writing_add(src, w, station, name, bytes, pasted=p)
    _ => ()
  }
}
