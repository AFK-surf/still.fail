// References to other chats in what is written, for each frame's composer (web Chat.tsx useComposerText's reference,
// its paste and its Backspace; ChatRef.tsx RefMirror): a mark, `@[its title]`, drawn in the accent with its brackets
// unseen; `@` and a few letters at the caret, what a menu of chats is opened by; a chat picked going in as its mark
// (the core's `chat.ref`); a Backspace just after a mark taking it whole; a chat's link pasted as it is copied going in
// as its mark; words pasted at once past the core's bound going as a file. What is written is read as the core reads
// it (`ref.at`, `ref.marks`, `ref.words`, `ref.pasted`, `paste.info`: refLinks.ts, pasted.ts), never here; a page
// draws the menu.

///|
/// What the core said of a draft's field (`input`, its words and caret as they are, followed: refs_follow; none till
/// its draft is made), and of the `@` at its caret: the `@words` at its caret (where the `@` is, what follows) for the
/// words and caret they were asked of; the `@` whose menu was closed (Escape, a pick; -1 none), not opened again until
/// the `@words` are gone; the chat chosen in the menu; the marks in its words (where each starts and ends past its `]`)
/// and the words they are placed in (moved along with each edit of them until the core has read the words: the words
/// it read them in, others); the runs its words will be drawn in once sent, for the words the core read them in; what
/// the menu's words last found (refs_search).
priv struct RefField {
  mut input : @ui.Field?
  at_of : @signals.Signal[String]
  at : @signals.Signal[(Int, String)?]
  closed : @signals.Signal[Int]
  active : @signals.Signal[Int]
  marks : @sf.LiveArray[(Int, Int)]
  mut marks_in : String
  marks_of : @signals.Signal[String]
  mut runs : Json
  mut runs_of : String
  mut found : Json?
}

///|
let ref_fields : Map[String, RefField] = Map([])

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
        input: None,
        at_of: @signals.signal("", same=fn(a, b) { a == b }),
        at: @signals.signal(None),
        closed: @signals.signal(-1),
        active: @signals.signal(0),
        marks: @sf.LiveArray::from([]),
        marks_in: "",
        marks_of: @signals.signal("", same=fn(a, b) { a == b }),
        runs: Json::null(),
        runs_of: "",
        found: None,
      }
      ref_fields[key] = f
      f
    }
  }
}

///|
/// The words of draft `key`'s field as they are now ("" before its draft is made).
fn ref_words(f : RefField) -> String {
  match f.input {
    Some(i) => i.text()
    None => ""
  }
}

///|
/// The marks of `f` placed in words `was`, where they are once an edit of them leaves them as `now` (@ui.words_changed):
/// those it did not touch, moved with it; those it touched gone. Placed in other words: as they are, the core to say
/// where they are in these.
fn refs_marks_moved(f : RefField, was : String, now : String) -> Unit {
  guard f.marks_in == was else { return }
  let (start, took, put) = @ui.words_changed(was, now)
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
  f.marks_in = now
}

///|
/// Draft `key`'s field (`input`) followed for what the core reads of its words, from as they are when its draft is
/// made (words kept, put back) and each time they change, whatever changes them: the marks in them and the runs they
/// will be drawn in once sent asked of the core. A reaction of the draft's own (compose.mbt's `following`), let go with
/// it. The `@words` at its caret are the person's edit's to ask (refs_edited): words the core or the app put in are
/// no one's typing, and ask nothing of it (a core write echoes nothing).
fn refs_follow(src : Source, key : String, input : @ui.Field) -> Unit {
  let f = ref_field(key)
  f.input = Some(input)
  @signals.effect(fn() {
    let now = input.text()
    @signals.untracked(fn() {
      refs_ask_marks(src, key, now)
      refs_ask_words(src, key, now)
    })
  })
  |> ignore
}

///|
fn ref_key(text : String, caret : Int) -> String {
  text + "\u{1}" + caret.to_string()
}

///|
/// The person's edit `e` of draft `key`'s field (`input`; Ctx::editor's `on_edit`), at its moment: a Backspace just
/// after a mark takes the mark whole (the caret where it began); the marks the words held moved along with what was
/// written; a chat's link (of the workspace of station `here`) in what was put in at once going in as its mark, once
/// the core has made it (not while `locked`); the `@words` at its caret asked of the core, its words changed or only
/// its caret moved (the marks and runs of its words: refs_follow asks, whatever changed them).
pub fn refs_edited(src : Source, key : String, input : @ui.Field, here : String, locked : Bool, e : @ui.FieldEdit) -> Unit {
  let f = ref_field(key)
  f.input = Some(input)
  let (was, now) = (e.was, e.now)
  let (wa, wc) = e.was_selection
  let (anchor, caret) = e.selection
  if now == was {
    if anchor == caret {
      refs_ask_at(src, key, now, caret)
    }
    return
  }
  let (start, took, put) = e.span()
  // one character taken just before the caret: a mark ending there goes whole
  let one_back = wa == wc && anchor == caret && caret == wc - 1 && start == wc - 1 && took == wc && put == start
  let mark = if one_back && f.marks_in == was { f.marks.search_by(fn(m) { m.1 == wc }) } else { None }
  match mark {
    Some(i) => {
      let a = f.marks[i].0
      refs_put(key, input, was.clamped_view(end=a).to_owned() + was.clamped_view(start=wc).to_owned(), caret=a)
      return
    }
    None => ()
  }
  // the marks the edit did not touch, where they are now
  refs_marks_moved(f, was, now)
  // what was put in at once: the chats' links in it
  if put - start > 1 && !locked {
    let pasted = now.clamped_view(start=start, end=put).to_owned()
    refs_pasted(src, key, input, here, now, start, pasted)
  }
  if anchor == caret {
    refs_ask_at(src, key, now, caret)
  }
}

///|
/// The `@words` at caret `caret` of words `now` of draft `key`'s field asked of the core (`ref.at`).
fn refs_ask_at(src : Source, key : String, now : String, caret : Int) -> Unit {
  let f = ref_field(key)
  let asked = ref_key(now, caret)
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
}

///|
/// The marks of words `now` of draft `key`'s field asked of the core (holding a `@[`, not read for them yet).
fn refs_ask_marks(src : Source, key : String, now : String) -> Unit {
  let f = ref_field(key)
  if !now.contains("@[") {
    if !f.marks.is_empty() {
      f.marks.replace([])
    }
    f.marks_in = now
    f.marks_of.set(now)
    return
  }
  if f.marks_of.get() == now {
    return
  }
  (src.call)("ref.marks", { "text": Json::string(now) }, fn(r) {
    match r {
      Ok(v) if ref_words(f) == now => {
        f.marks.replace(items(Some(v), "marks").map(fn(m) {
          (number(Some(m), "start").to_int(), number(Some(m), "end").to_int())
        }))
        f.marks_in = now
        f.marks_of.set(now)
      }
      _ => ()
    }
  })
}

///|
/// Words the app put in draft `key`'s field itself (a mark, the draft kept, put back): put there, seen as they are,
/// not as written (no paste in them, no Backspace); its marks where they are in them, the `@` it was at none.
pub fn refs_put(key : String, input : @ui.Field, words : String, caret? : Int) -> Unit {
  let f = ref_field(key)
  refs_marks_moved(f, input.text(), words)
  f.at.set(None)
  input.set(words, caret?)
}

///|
/// How draft `key`'s field draws its words (RefMirror, refMark, refMarkHidden): each mark as its message will draw it
/// (words_runs: `@` a little lighter, its title in `accent`), its `[` and `]` taking no room, so that what is sent goes
/// from the field with nothing of it moved or changed. As many code units as the words: the field's offsets hold.
pub fn refs_look(key : String, accent : Int64) -> (String) -> (String, Array[(Int, Int, Int64)]) {
  fn(s) {
    let f = ref_field(key)
    if s != f.marks_in || f.marks.is_empty() {
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
      sb.write_string(s.clamped_view(start=at, end=a).to_owned())
      sb.write_string("\u{200B}@")
      sb.write_string(s.clamped_view(start=a + 2, end=b - 1).to_owned())
      sb.write_string("\u{200B}")
      at = b
      spans.push((a + 1, a + 2, @sf.alpha(accent, ref_at_alpha)))
      spans.push((a + 2, b - 1, accent))
    }
    sb.write_string(s.clamped_view(start=at).to_owned())
    (sb.to_string(), spans)
  }
}

///|
/// Words `s` without the blanks at their ends, as they are sent.
fn sent_words_of(s : String) -> String {
  s.trim(chars=" \n\t").to_owned()
}

///|
/// The runs the words of draft `key`'s field `now` will be drawn in once sent (the core's `ref.words`: refLinks.ts
/// draftWords), asked for them (of words that may hold more than one: @sf.words_may_link; not read for them yet).
fn refs_ask_words(src : Source, key : String, now : String) -> Unit {
  let f = ref_field(key)
  let words = sent_words_of(now)
  if f.runs_of == words {
    return
  }
  if !@sf.words_may_link(words) {
    f.runs = Json::null()
    f.runs_of = words
    return
  }
  (src.call)("ref.words", { "text": Json::string(words) }, fn(r) {
    match r {
      Ok(v) if sent_words_of(ref_words(f)) == words => {
        f.runs = field(Some(v), "runs").unwrap_or(Json::null())
        f.runs_of = words
      }
      _ => ()
    }
  })
}

///|
/// The runs words sent from draft `key`'s field are drawn in (refs_ask_words; lines put after them, as they are) until
/// the core's row has them. Where the core has not read the words the field holds yet, its marks there as references
/// and the rest as it is (refs_marked_runs), never a mark's brackets on the way.
pub fn refs_sent_runs(key : String, words : String) -> Json? {
  let f = ref_field(key)
  let held = sent_words_of(ref_words(f))
  guard f.runs_of == held && words.has_prefix(held) else { return refs_marked_runs(key, words) }
  let runs : Array[Json] = match f.runs {
    Array(a) => a.copy()
    _ => if held != "" { [{ "text": Json::string(held) }] } else { [] }
  }
  let rest = words.exact_view(start=held.length()).to_owned()
  if rest != "" {
    runs.push({ "text": Json::string(rest) })
  }
  Some(Json::array(runs))
}

///|
/// Words sent from draft `key`'s field in runs by the marks it holds (draftWords' references, the rest as it is): None
/// where it holds none of them.
fn refs_marked_runs(key : String, words : String) -> Json? {
  let marks = refs_sent_marks(key, words)
  guard !marks.is_empty() else { return None }
  let runs : Array[Json] = []
  let plain = fn(a : Int, b : Int) {
    if b > a {
      runs.push({ "text": Json::string(words.clamped_view(start=a, end=b).to_owned()) })
    }
  }
  let mut at = 0
  for m in marks {
    let (a, b) = m
    plain(at, a)
    runs.push({ "text": Json::string(words.clamped_view(start=a + 2, end=b - 1).to_owned()), "ref": true })
    at = b
  }
  plain(at, words.length())
  Some(Json::array(runs))
}

///|
/// The marks draft `key`'s field holds, where they are in `words` sent from it (its words trimmed, lines maybe put after
/// them): their flight takes off with them as the field drew them (flight_start). None where the field holds other
/// words.
pub fn refs_sent_marks(key : String, words : String) -> Array[(Int, Int)] {
  let f = ref_field(key)
  let s = f.marks_in
  let blank = fn(i : Int) {
    let u = s.unsafe_get(i).to_int()
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
  guard words.has_prefix(s.exact_view(start=lead, end=end).to_owned()) else { return [] }
  f.marks.filter_map(fn(m) { if m.0 >= lead && m.1 <= end { Some((m.0 - lead, m.1 - lead)) } else { None } })
}

///|
/// Whether draft `key`'s field holds a mark, as the core read its words now; None while it has not read them (the words
/// changed since it was asked).
pub fn refs_marked(key : String) -> Bool? {
  let f = ref_field(key)
  let words = ref_words(f)
  if !words.contains("@[") {
    Some(false)
  } else if f.marks_of.get() == words {
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
  guard f.input is Some(input) else { return None }
  let (anchor, caret) = input.selection()
  if anchor != caret {
    return None
  }
  let words = input.text()
  let read_now = f.at_of.get() == ref_key(words, caret)
  match f.at.get() {
    Some((start, _)) as at if start != f.closed.get() &&
      (read_now || (start < caret && caret <= words.length() && words.at(start).to_int() == 64)) => at
    _ => None
  }
}

///|
/// What the `@words` of draft `key` find (the core's `chatSearch` with `params`): while the core looks up the next
/// words, what the last ones found (the menu's chats stay till the next are there, not gone for a line saying it is
/// reading); what it says when it has none yet, or failed.
pub fn refs_search(src : Source, key : String, params : Map[String, Json]) -> Topic {
  let f = ref_field(key)
  let topic = src.topic("chatSearch", params).get().snapshot()
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
/// Whether the menu of draft `key` was closed for the `@` at `start` (Escape, a pick), till its `@words` are gone.
pub fn refs_closed(key : String, start : Int) -> Bool {
  ref_field(key).closed.get() == start
}

///|
/// A chat picked in the menu of draft `key` for the `@` at `start` (as the menu showed it; its station, its id, its
/// title) put in as the mark the core makes of it (`chat.ref`, which keeps its link until it is sent; one of another
/// workspace's keeps it for this one, `into`, too) in the `@words`' place if they are still there, a space and the
/// caret after it; the menu closed for this `@`. Failing, `failed` is told why.
pub fn refs_pick(
  c : @ui.Ctx,
  src : Source,
  key : String,
  input : @ui.Field,
  start : Int,
  into : String,
  station : String,
  id : String,
  title : String,
  failed : (String) -> Unit,
) -> Unit {
  let f = ref_field(key)
  // (the caret as it is now: the words typed after the `@` since its menu was built are the `@`'s too)
  let caret = input.selection().1
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
              now.exact_view(end=start).to_owned() + mark + " " + now.clamped_view(start=caret).to_owned(),
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
/// Whether `input` still holds the `@` its menu was built for (`at`: where it starts; `before`: what was before it and
/// it then; `after`: what was after the caret then): those as they were, the caret where `after` begins, nothing
/// picked. The range the menu's choice is for, grown by what was typed in it since, not what the core makes of the
/// words in it.
pub fn refs_still_at(input : @ui.Field, at : (Int, String)?, before : String, after : String) -> Bool {
  guard at is Some((start, _)) else { return false }
  let now = input.text()
  let (a, caret) = input.selection()
  before != "" &&
  a == caret &&
  caret > start &&
  now.length() >= before.length() + after.length() &&
  caret == now.length() - after.length() &&
  now.has_prefix(before) &&
  now.has_suffix(after)
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
      let whole = put.clamped_view(start=a, end=number(o, "end").to_int()).to_owned()
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
              now.clamped_view(end=p).to_owned() + mark + now.clamped_view(start=p + whole.length()).to_owned(),
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
            station.exact_view(end=cut).to_owned() +
            "/s/" +
            station.clamped_view(start=cut + 1).to_owned() +
            "/chats/" +
            @codec.encode_uri_component(id) +
            history
          // the mark only once the core keeps its link (failing, the link stays as it is)
          (src.call)(
            "chat.refs",
            { "links": [[Json::string(mark.clamped_view(start=2, end=mark.length() - 1).to_owned()), Json::string(page)]] },
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
    o.exact_view(end=o.length() - 1).to_owned()
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
/// , what the core says of them (`paste.info`) with it.
pub fn writing_paste(src : Source, w : Writing, station : String, words : String) -> Unit {
  (src.call)("paste.info", { "text": Json::string(words) }, fn(r) {
    guard r is Ok(v) else { return }
    let info = field(Some(v), "info")
    match info {
      Some(Object(_)) =>
        writing_add(src, w, station, "pasted-text-" + upload_id(w.key + "\u{2}" + words, w.files.get().length() + 1) + ".txt", @utf8.encode(words), pasted=info.unwrap())
      _ => ()
    }
  })
}

///|
/// Pasted words of draft `w` that failed going up (file `id`) made a file again from them (Chat.tsx: removed, and added
/// again with what the core said of them).
pub fn writing_paste_again(src : Source, w : Writing, id : String) -> Unit {
  guard writing_went.get(id) is Some((station, name, bytes)) else { return }
  let info = w.files.get().iter().find_first(fn(f) { text(Some(f), "id") == id }).map(fn(f) { field(Some(f), "pasted") })
  writing_remove(src, w, id)
  match info {
    Some(Some(p)) => writing_add(src, w, station, name, bytes, pasted=p)
    _ => ()
  }
}
