// A chat's composer (ember apps/android chat/screens/Composer.kt ComposerBar, DraftExtras, Drafts, upload; ChatHost.kt
// HostComposer; Attach.kt; PastedText.kt; SendText.kt): a capsule floating over the list's foot. ＋, a field that grows
// with the words up to six lines, the round send button; focused or holding something, the field takes the whole
// width and the buttons go under it. What waits to go with the words sits over the field: the quotes (each with a
// line for a comment) and the files (pictures as tiles, a long paste as its card, any other file as a card), each
// going up to the station as soon as it is added (`station.upload.part`, 4 MB a part), waiting there in no chat until
// a message takes it. Enter is a new line, as the Android app's field has it; send sends.
//
// Each chat has its own draft (`<station>:<session>`, as the Android app keys it): the words, the quotes with what is
// said about them, the files already up, kept by the core on the device (`draft.get`, `draft.put` a moment after each
// change and as the chat is left) and put back when the chat is opened again. A long paste (5000 characters or more at
// once) goes as a text file, not into the field.
//
// Sending empties the composer at once: the message shows from the chat's outbox until the station has it (正在发送
// under it after a moment; 未发送 with 重试 and 删除 when it failed, messages.mbt), and the list goes to its end. A send
// the core refuses before the outbox (`invalid_params`) gives the words back and says why.
//
// With MBUI_READONLY=1 (Source.read_only) nothing leaves: no send, no draft kept, no file put up (said in a toast).

///|
/// The field's words: 16 on 21 lines, as the viewer's bubbles (SendText.kt).
let send_size : Double = 16.0

///|
let send_line : Double = 21.0

///|
/// The capsule's corner and its inset (ui/Glass.kt ComposerCorner, ComposerInset); what sits inside it is rounded
/// concentric with it.
let composer_corner : Double = 26.0

///|
let composer_inset : Double = 8.0

///|
/// Where ＋'s ink starts in its 36 button (the 18 icon centred, its line from 4.5 of 24 less half its 1.75 stroke):
/// the opened field's words start there.
let plus_ink : Double = 9.0 + 18.0 * ((4.5 - 1.75 / 2.0) / 24.0)

///|
/// Pasted at once, this many characters or more go as a file; a file of pasted words this long at most can be put
/// back (PastedText.kt).
let paste_threshold : Int = 5000

///|
let paste_restore_limit : Int = 25000

///|
/// A file's part going up (web/src/api.ts UPLOAD_PART), the biggest file taken (1 GB).
let part_size : Int = 4 * 1024 * 1024

///|
let max_file : Int = 1024 * 1024 * 1024

///|
/// A file on its way to the station: going up, up (`done`, the station's Attachment), or failed. `image`: the picture
/// picked, shown from its bytes (an image's key, "" for any other file); `pasted`: the words it was made of.
priv struct Pending {
  id : Int
  name : String
  size : Int
  image : String
  width : Int
  height : Int
  pasted : String?
  mut done : Json?
  /// how much of it the station has
  mut sent : Int
  mut error : String?
}

///|
/// A passage quoted in what is written, with what is said about it.
priv struct DraftQuote {
  id : Int
  author : String
  text : String
  ts : String
  role : String
  file : String
}

///|
/// A chat's draft: its words (the field's, kept here as they change), quotes and files.
priv struct Draft {
  key : String
  mut text : String
  /// words for the field to take the next time it is drawn (kept words read, words put back)
  mut put_text : String?
  quotes : Array[DraftQuote]
  /// the quotes' comments, by quote (their fields' words)
  comments : Map[Int, String]
  files : Array[Pending]
  mut error : String?
  /// what the core kept has been read: only then is it written over
  mut loaded : Bool
  /// what was last kept, and when it last changed
  mut kept : String
  mut changed_at : Double
  /// when typing last woke the agent's runtime (`session.warm`, once a minute)
  mut warmed : Double
  /// the quote whose comment line takes the focus next frame (0 none); 1: the words' field
  mut focus : Int
}

///|
/// Each chat's draft while the app runs (files still going up go on as its page goes).
let drafts : Map[String, Draft] = {}

///|
let next_pending : Ref[Int] = { val: 1 }

///|
fn draft_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// The chat's draft, its kept words asked of the core the first time (`draft.get`).
fn draft_of(src : Source, r : ChatRef) -> Draft {
  draft_by(src, draft_key(r))
}

///|
/// What a composer writes to that is not a chat yet (NewChat.kt NewChatOn): its draft's key (`new:<station>`, as a
/// new chat's on the device) and what sending does.
priv struct Fresh {
  key : String
  send : (Draft) -> Unit
}

///|
/// The draft kept as `key`, its words asked of the core the first time (`draft.get`).
fn draft_by(src : Source, key : String) -> Draft {
  match drafts.get(key) {
    Some(d) => d
    None => {
      let d : Draft = {
        key,
        text: "",
        put_text: None,
        quotes: [],
        comments: {},
        files: [],
        error: None,
        loaded: false,
        kept: "",
        changed_at: 0.0,
        warmed: -1.0e12,
        focus: 0,
      }
      drafts[key] = d
      (src.call)("draft.get", { "key": Json::string(key) }, fn(res) {
        match res {
          Ok(Object(_) as v) if draft_empty(d) => fill_draft(d, v)
          _ => ()
        }
        d.loaded = true
        d.kept = draft_sig(d)
      })
      d
    }
  }
}

///|
fn draft_empty(d : Draft) -> Bool {
  d.text == "" && d.quotes.length() == 0 && d.files.length() == 0 && refs_of(d.key).length() == 0
}

///|
/// What the core kept (DraftView): its words, quotes and the files already up.
fn fill_draft(d : Draft, v : Json) -> Unit {
  let s = Some(v)
  let words = text(s, "text")
  d.text = words
  d.put_text = Some(words)
  for q in items(s, "quotes") {
    let qs = Some(q)
    let id = next_pending.val
    next_pending.val += 1
    d.quotes.push({
      id,
      author: text(qs, "author"),
      text: text(qs, "text"),
      ts: text(qs, "ts"),
      role: if text(qs, "role") == "" { "person" } else { text(qs, "role") },
      file: text(qs, "file"),
    })
    d.comments[id] = text(qs, "comment")
  }
  for a in items(s, "files") {
    let as_ = Some(a)
    let id = next_pending.val
    next_pending.val += 1
    d.files.push({
      id,
      name: text(as_, "name"),
      size: number(as_, "size").to_int(),
      image: "",
      width: number(as_, "width").to_int(),
      height: number(as_, "height").to_int(),
      pasted: None,
      done: Some(a),
      sent: number(as_, "size").to_int(),
      error: None,
    })
  }
  // links shared in (share-in.ts): each a card among the files, kept and sent as words
  for l in items(s, "links") {
    let id = next_pending.val
    next_pending.val += 1
    let name = match text(Some(l), "title") {
      "" => text(Some(l), "url")
      t => t
    }
    d.files.push({
      id,
      name,
      size: 0,
      image: "",
      width: 0,
      height: 0,
      pasted: None,
      done: Some({ "link": l }),
      sent: 0,
      error: None,
    })
  }
}

///|
fn quote_json(d : Draft, q : DraftQuote, trim : Bool) -> Json {
  let comment = d.comments.get(q.id).unwrap_or("")
  let o : Map[String, Json] = {
    "author": Json::string(q.author),
    "text": Json::string(q.text),
    "comment": Json::string(if trim { comment.trim(chars=" \n\t").to_string() } else { comment }),
    "role": Json::string(q.role),
  }
  if q.ts != "" {
    o["ts"] = Json::string(q.ts)
  }
  if q.file != "" {
    o["file"] = Json::string(q.file)
  }
  Json::object(o)
}

///|
/// What is kept of it (DraftView): the words, the quotes with their comments, the files up.
fn draft_view(d : Draft) -> Map[String, Json] {
  let v : Map[String, Json] = {
    "text": Json::string(d.text),
    "quotes": Json::array(d.quotes.map(fn(q) { quote_json(d, q, false) })),
    "files": Json::array(up_files(d)),
  }
  // the links shared in, kept beside the files (the core's DraftView `links`)
  let links = d.files.filter_map(fn(f) { field(f.done, "link") })
  if links.length() > 0 {
    v["links"] = Json::array(links)
  }
  v
}

///|
fn draft_sig(d : Draft) -> String {
  Json::object(draft_view(d)).stringify()
}

///|
/// Kept on the device as it is now (`draft.put`), when it changed since it was last kept; never on a read-only run.
fn save_draft(src : Source, d : Draft) -> Unit {
  if !d.loaded || src.read_only {
    return
  }
  let sig = draft_sig(d)
  if sig == d.kept {
    return
  }
  d.kept = sig
  let params = draft_view(d)
  params["key"] = Json::string(d.key)
  (src.call)("draft.put", Json::object(params), fn(_) {  })
}

///|
/// A change kept a moment after it is made (the core writes it down then too), and at once as the chat is left.
fn keep_draft_soon(c : @ui.Ctx, src : Source, d : Draft) -> Unit {
  if !d.loaded || src.read_only {
    return
  }
  let sig = draft_sig(d)
  if sig == d.kept {
    return
  }
  if d.changed_at == 0.0 {
    d.changed_at = c.now()
  }
  let age = c.now() - d.changed_at
  if age >= 400.0 {
    d.changed_at = 0.0
    save_draft(src, d)
  } else {
    c.wake_in(400.0 - age)
  }
}

///|
fn uploading(d : Draft) -> Bool {
  d.files.iter().any(fn(f) { f.done is None && f.error is None })
}

///|
/// Something can be sent: words, a file up or a quote, nothing still going up, nothing locking it.
fn draft_ready(d : Draft, locked : Bool) -> Bool {
  (
    d.text.trim(chars=" \n\t") != "" ||
    d.files.iter().any(fn(f) { f.done is Some(_) }) ||
    d.quotes.length() > 0 ||
    refs_of(d.key).length() > 0
  ) &&
  !uploading(d) &&
  !locked
}

///|
/// A passage quoted into the draft (MessagePick.kt quote): its comment line takes the focus.
fn draft_quote(d : Draft, author : String, words : String, ts : String, role : String) -> Unit {
  let id = next_pending.val
  next_pending.val += 1
  d.quotes.push({ id, author, text: words, ts, role, file: "" })
  d.comments[id] = ""
  d.focus = id
}

// ── files ──────────────────────────────────────────────────────────────

///|
/// An upload's id: 32 hex digits, new each time (the Android app's UUID without its dashes).
let upload_serial : Ref[Int] = { val: 0 }

///|
fn upload_id(src : Source) -> String {
  upload_serial.val += 1
  let seed = "\{(src.now)()}/\{@host.now()}/\{upload_serial.val}"
  let hex = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = StringBuilder::new()
  let mut h = seed.hash()
  for i in 0..<32 {
    if i % 8 == 0 {
      h = (seed + "\{i}").hash()
    }
    out.write_char(hex[h & 15])
    h = h >> 4
  }
  out.to_string()
}

///|
/// The width and height a picture's bytes say (PNG, JPEG, GIF, WebP), or None.
fn image_size(b : Bytes) -> (Int, Int)? {
  let n = b.length()
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let le16 = fn(i : Int) -> Int { u8(i) | (u8(i + 1) << 8) }
  let be32 = fn(i : Int) -> Int { (be16(i) << 16) | be16(i + 2) }
  if n >= 24 && u8(0) == 0x89 && u8(1) == 0x50 && u8(2) == 0x4E && u8(3) == 0x47 {
    return Some((be32(16), be32(20)))
  }
  if n >= 10 && u8(0) == 0x47 && u8(1) == 0x49 && u8(2) == 0x46 {
    return Some((le16(6), le16(8)))
  }
  if n >= 30 && u8(0) == 0x52 && u8(1) == 0x49 && u8(8) == 0x57 && u8(9) == 0x45 {
    // RIFF….WEBP: VP8 , VP8L, VP8X
    let kind = u8(15)
    if kind == 0x20 {
      return Some((le16(26) & 0x3FFF, le16(28) & 0x3FFF))
    } else if kind == 0x4C {
      let bits = u8(21) | (u8(22) << 8) | (u8(23) << 16) | (u8(24) << 24)
      return Some(((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1))
    } else if kind == 0x58 {
      return Some(
        (
          (u8(24) | (u8(25) << 8) | (u8(26) << 16)) + 1,
          (u8(27) | (u8(28) << 8) | (u8(29) << 16)) + 1,
        ),
      )
    }
    return None
  }
  if n >= 4 && u8(0) == 0xFF && u8(1) == 0xD8 {
    let mut i = 2
    while i + 9 < n {
      if u8(i) != 0xFF {
        i += 1
        continue
      }
      let m = u8(i + 1)
      if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) || m == 0xFF {
        i += if m == 0xFF { 1 } else { 2 }
        continue
      }
      // a start of frame (not DHT C4, JPG C8, DAC CC)
      if m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC {
        return Some((be16(i + 7), be16(i + 5)))
      }
      i += 2 + be16(i + 2)
    }
  }
  None
}

///|
/// A file picked or pasted, into the draft and up to the station at once (Composer.kt upload): over 1 GB it is
/// refused where it shows; on a read-only run it goes nowhere.
fn add_file(src : Source, d : Draft, station : String, name : String, bytes : Bytes, pasted : String?) -> Unit {
  let id = next_pending.val
  next_pending.val += 1
  let (w, h) = match image_size(bytes) {
    Some(s) if pasted is None => s
    _ => (0, 0)
  }
  let image = if w > 0 {
    let key = "mem:draft/\{id}"
    @ui.add_image(key, bytes)
    key
  } else {
    ""
  }
  let p : Pending = {
    id,
    name,
    size: bytes.length(),
    image,
    width: w,
    height: h,
    pasted,
    done: None,
    sent: 0,
    error: None,
  }
  d.files.push(p)
  if bytes.length() > max_file {
    p.error = Some(tr("android-chat.file.tooBig"))
    return
  }
  if src.read_only {
    p.error = Some(read_only_words)
    return
  }
  upload_part(src, d, station, p, bytes, upload_id(src), 0)
}

///|
/// What a read-only run says it does not do.
let read_only_words : String = "只读运行：不发送，不上传，不保存草稿"

///|
/// One part of a file up from `have` (Calls.kt upload): the station answers with what it has so far, or, the last
/// part in, the file as it keeps it (an image's size put with it).
fn upload_part(
  src : Source,
  d : Draft,
  station : String,
  p : Pending,
  bytes : Bytes,
  id : String,
  have : Int,
) -> Unit {
  // taken out of the draft meanwhile: nothing more goes
  if !d.files.iter().any(fn(f) { f.id == p.id }) && p.done is None {
    return
  }
  let size = bytes.length()
  let len = if size - have < part_size { size - have } else { part_size }
  let part = Bytes::makei(len, fn(i) { bytes[have + i] })
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "id": Json::string(id),
    "name": Json::string(p.name),
    "size": Json::number(size.to_double()),
    "offset": Json::number(have.to_double()),
  }
  (src.call_bytes)("station.upload.part", Json::object(params), part, fn(res) {
    match res {
      Ok(answer) =>
        match field(Some(answer), "file") {
          Some(Object(f)) => {
            let file = f.copy()
            if p.width > 0 && p.height > 0 {
              file["width"] = Json::number(p.width.to_double())
              file["height"] = Json::number(p.height.to_double())
            }
            p.sent = size
            p.done = Some(Json::object(file))
          }
          _ => {
            let next = match field(Some(answer), "have") {
              Some(Number(n, ..)) => n.to_int()
              _ => have + len
            }
            if next <= have {
              p.error = Some(tr("android-chat.file.uploadFailed"))
            } else {
              p.sent = next
              upload_part(src, d, station, p, bytes, id, next)
            }
          }
        }
      Err(e) =>
        p.error = Some(
          match text(Some(e), "message") {
            "" => tr("android-chat.file.uploadFailed")
            m => m
          },
        )
    }
  })
}

///|
/// What a file going up says: how far it has gone, once that is known.
fn uploading_text(f : Pending) -> String {
  if f.sent <= 0 || f.size <= 0 {
    tr("common.uploading")
  } else {
    fill("android-chat.file.uploading.part", [
      ("percent", "\{(f.sent.to_double() * 100.0 / f.size.to_double()).to_int()}"),
      ("size", file_size(f.size.to_double())),
    ])
  }
}

///|
/// A long paste: the text file it goes as (`pasted-text-<id>.txt`, UTF-8, as the web names it).
fn paste_as_file(src : Source, d : Draft, station : String, words : String) -> Unit {
  let name = "pasted-text-" + uuid(upload_id(src)) + ".txt"
  add_file(src, d, station, name, utf8_bytes(words), Some(words))
}

///|
/// 32 hex digits as a UUID's 8-4-4-4-12.
fn uuid(h : String) -> String {
  h.view(end_offset=8).to_string() +
  "-" +
  h.view(start_offset=8, end_offset=12).to_string() +
  "-" +
  h.view(start_offset=12, end_offset=16).to_string() +
  "-" +
  h.view(start_offset=16, end_offset=20).to_string() +
  "-" +
  h.view(start_offset=20).to_string()
}

///|
/// A pasted file's first line (of its first 200 characters).
fn paste_preview(words : String) -> String {
  let head = if words.length() > 200 {
    words.view(end_offset=200).to_string()
  } else {
    words
  }
  let t = head.trim(chars=" \n\r\t").to_string()
  match t.find("\n") {
    Some(i) => t.view(end_offset=i).to_string().trim_end(chars="\r").to_string()
    None => t
  }
}

// ── the composer's state on the page ──────────────────────────────────────

///|
/// What the page keeps of its composer: ＋'s sheet (open, since when), the system's picker under way, a finger down
/// outside the composer (it lets go of the keyboard once lifted or moved: ui/Keyboard.kt letsGoOfKeyboard).
priv struct ComposerUi {
  mut attach : Bool
  mut attach_at : Double
  mut picking : @host.Pick?
  mut picking_for : String
  /// the finger: down last frame, down first this frame, lifted this frame, where and when it went down, moved past
  /// the slop since (track_press)
  mut was_down : Bool
  mut press_new : Bool
  mut released : Bool
  mut down_x : Double
  mut down_y : Double
  mut down_at : Double
  mut moved : Bool
  mut outside : Bool
  /// the composer's height with its margins, as last drawn (ids are the page's: the list's rows ask this)
  mut room : Double
  /// the outbox's entries being sent again or dropped (their buttons spin meanwhile)
  doing : Map[String, Bool]
  /// a message held: its words picked, the bar over them (MessagePick.kt)
  mut hold : Int
  mut hold_at : Double
  mut picked : String
  mut picked_id : Int
  mut picked_author : String
  mut picked_role : String
  mut picked_text : String
}

///|
let cui : ComposerUi = {
  attach: false,
  attach_at: 0.0,
  picking: None,
  picking_for: "",
  was_down: false,
  press_new: false,
  released: false,
  down_x: 0.0,
  down_y: 0.0,
  down_at: 0.0,
  moved: false,
  outside: false,
  room: 0.0,
  doing: {},
  hold: 0,
  hold_at: 0.0,
  picked: "",
  picked_id: 0,
  picked_author: "",
  picked_role: "",
  picked_text: "",
}

///|
/// The field's key: one per chat page.
let field_key : String = "composer/field"

///|
/// The capsule's id (its room is the list's foot; a tap on its own room puts the caret in the field).
fn capsule_id(c : @ui.Ctx) -> Int {
  c.id("composer/capsule")
}

///|
/// How much of the page's foot the composer takes, with its margins (the list keeps that clear; ChatHost.kt
/// roomForList: never less than an opened composer with one line).
fn composer_room_of(c : @ui.Ctx) -> Double {
  ignore(c)
  dmax(composer_room, cui.room)
}

// ── sending ─────────────────────────────────────────────────────────────

///|
/// Sends what the draft holds (Composer.kt chatSend): emptied at once, the message in the chat's outbox until the
/// station has it, the list taken to its end; refused before the outbox, the words come back and why is said.
fn send_draft(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, d : Draft) -> Unit {
  if src.read_only {
    say(c, read_only_words)
    return
  }
  // the station files named by their paths, a line each under the words
  let words = with_link_words(with_ref_words(d.text.trim(chars=" \n\t").to_string(), d.key), d)
  let taken_refs = refs_of(d.key)
  draft_refs.remove(d.key)
  let files = up_files(d)
  let quotes = d.quotes.map(fn(q) { quote_json(d, q, true) })
  // what was taken, to put back
  let taken_text = d.text
  let taken_files = d.files.copy()
  let taken_quotes = d.quotes.copy()
  let taken_comments = d.comments.copy()
  // the words take off from where they were typed (flight.mbt)
  flight_start(c, d.key, words, v, @motion.measured(c, "composer/content").unwrap_or(0.0))
  c.take_editor_text(field_key) |> ignore
  d.text = ""
  d.files.clear()
  d.quotes.clear()
  d.comments.clear()
  d.error = None
  save_draft(src, d)
  let params : Map[String, Json] = {
    "station": Json::string(r.station),
    "text": Json::string(words),
    "attachments": Json::array(files),
    "quotes": Json::array(quotes),
  }
  match v.thread {
    Some(th) => params["thread"] = Json::number(th)
    None => params["session"] = Json::string(r.session)
  }
  (src.call)("chat.send", Json::object(params), fn(res) {
    match res {
      Err(e) if text(Some(e), "code") == "invalid_params" =>
        if draft_empty(d) {
          d.text = taken_text
          d.put_text = Some(taken_text)
          for f in taken_files {
            d.files.push(f)
          }
          for q in taken_quotes {
            d.quotes.push(q)
          }
          draft_refs[d.key] = taken_refs
          for k, w in taken_comments {
            d.comments[k] = w
          }
          d.error = Some(text(Some(e), "message"))
          save_draft(src, d)
        } else {
          app.toast = fill("android-chat.composer.send.failed", [("error", text(Some(e), "message"))])
          app.toast_at = -1.0
        }
      _ => ()
    }
  })
  // the reader goes to the chat's end with what was sent (Chat.kt: by the composer as it sends); with words flying
  // there at once, the rows above going up with them (flight.mbt)
  c.list_to_end(list_key(r), glide=flight_of(d.key) is None)
  c.request_frame()
}

// ── the composer ────────────────────────────────────────────────────────

///|
/// The composer at the chat page's foot (ChatHost.kt HostComposer): its notices, what waits to go, the bar, what went
/// wrong; ＋'s sheet over the page when open. `v` None while the chat is read the first time (it takes nothing yet).
fn composer(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView?, fresh? : Fresh? = None) -> Unit {
  let t = @sf.theme()
  let d = match fresh {
    Some(f) => draft_by(src, f.key)
    None => draft_of(src, r)
  }
  let offline = match v {
    Some(v) => v.offline
    None => false
  }
  let archived = match v {
    Some(v) => v.archived
    None => false
  }
  // while the chat is read the first time it takes words, but nothing goes (Chat.kt: its spec sends nothing yet)
  let locked = offline || archived
  let focused = c.editor_focused(field_key)
  // the words kept, or put back, into the field
  if !c.has_editor(field_key) && d.text != "" && d.put_text is None {
    d.put_text = Some(d.text)
  }
  match d.put_text {
    Some(words) => {
      c.set_editor_text(field_key, words)
      d.put_text = None
    }
    None => ()
  }
  if d.focus == 1 {
    c.focus_editor(field_key)
    d.focus = 0
  }
  let expanded = focused ||
    d.text != "" ||
    d.files.length() > 0 ||
    d.quotes.length() > 0 ||
    refs_of(d.key).length() > 0
  let cap = capsule_id(c)
  if c.clicked(cap) && !locked {
    c.focus_editor(field_key)
  }
  // the capsule changes shape in one motion (Composer.kt Morph, web morph.ts): drawn from the height it was to the one
  // its content now takes (260 ms, Ease.Out), its ground standing on its bottom edge and its content cut to it, its
  // parts drawn carried from where they were to their places on the same timeline. Only drawn: laid out as tall as its
  // content at once, all of it (＋, the field, send, a quote's line) tapped where it is from the first frame. At rest
  // (and in screenshots) as tall as its content
  let natural = @motion.measured(c, "composer/content")
  // words just sent: as tall as when they went, until they are a quarter of the way (ChatHost.kt hold)
  let held = match flight_of(d.key) {
    Some(f) if flight_p(c, f) < flight_settle => f.room
    _ => 0.0
  }
  let morph = match natural {
    Some(h) if !c.stable() =>
      Some(@motion.animate(c, "composer/morph", dmax(h, held), spec=@motion.tween(260.0, ease=Out)))
    _ => None
  }
  let mut content = -1
  c.box(w=Fill(1.0), pl=10.0, pr=10.0, pt=8.0, pb=10.0, fn() {
    c.box(w=Fill(1.0), pad=composer_inset, id=cap, fn() {
      // its ground, as tall as the morph has it, on the capsule's bottom edge (over it while it is taller)
      let ground = c.layer(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), justify=JEnd, fn() {
          c.box(
            w=Fill(1.0),
            h=match morph {
              Some(h) => Px(h + 2.0 * composer_inset)
              None => Fill(1.0)
            },
            radius=composer_corner,
            glass=@sf.glass_floating(),
            shadow=2.0,
            shadow_color=0x0000004DL,
            shadow_y=0.5,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
      })
      c.draw_only(ground)
      content = c.box(w=Fill(1.0), gap=8.0, fn() {
        match v {
          Some(v) => composer_notices(c, src, r, v)
          None => ()
        }
        draft_extras(c, src, r, d, locked)
        composer_bar(c, src, r, v, d, expanded, locked, fresh)
        match d.error {
          Some(e) =>
            c.box(padx=6.0, fn() { c.text(e, size=12.0, color=t.p.red, line=16.0) |> ignore })
            |> ignore
          None => ()
        }
      })
      @motion.measure(c, content, "composer/content")
      @motion.scope(c, content, bottom=true)
    })
    |> ignore
  })
  |> ignore
  match morph {
    // growing: what is above the ground is not drawn yet
    Some(h) => c.cut_to_bottom(content, h + composer_inset)
    None => ()
  }
  let room = match (flight_of(d.key), natural, morph) {
    // while words fly to their row, the list keeps the room the composer will have, so their place is where they
    // land (ChatHost.kt roomForList)
    (Some(_), Some(h), _) => h + 2.0 * composer_inset + 8.0 + 10.0
    // otherwise the room the capsule is drawn with (the list's rows going with it)
    (None, _, Some(h)) => h + 2.0 * composer_inset + 8.0 + 10.0
    _ =>
      match c.rect_of(cap) {
        Some((_, _, _, h)) => h + 8.0 + 10.0
        None => 0.0
      }
  }
  if room != cui.room {
    cui.room = room
    c.request_frame()
  }
  keep_draft_soon(c, src, d)
  // a finger down outside the composer lets go of the keyboard once lifted or moved on (reading on)
  if cui.press_new {
    let off_capsule = match c.rect_of(cap) {
      Some((x, y, w, h)) =>
        !(cui.down_x >= x && cui.down_x < x + w && cui.down_y >= y && cui.down_y < y + h)
      None => true
    }
    cui.outside = off_capsule && !cui.attach
  }
  if cui.outside && c.editor_focused(field_key) && (cui.released || cui.moved) {
    cui.outside = false
    c.blur()
  }
  if cui.released {
    cui.outside = false
  }
  // what the system's picker answered
  match cui.picking {
    Some(p) =>
      match p.files() {
        Some(files) => {
          cui.picking = None
          if cui.picking_for == d.key {
            for f in files {
              add_file(src, d, r.station, f.name, f.bytes, None)
            }
          }
          c.request_frame()
        }
        None => ()
      }
    None => ()
  }
  // files another app shared into this chat (share.mbt), up as ＋'s are
  match shared_into.get(d.key) {
    Some(list) => {
      shared_into.remove(d.key)
      for f in list {
        add_file(src, d, r.station, f.name, f.bytes, None)
      }
      c.request_frame()
    }
    None => ()
  }
  // ＋'s sheet: up from below and back down on the sheet's spring, the scrim in and out (Sheet.kt SheetHost, mbui's
  // @kit.sheet); drawn until it has gone
  attach_sheet(c, src, r, d)
  // ＋'s Station 文件 (station_files.mbt)
  station_files_sheet(c, src, workspace_of(r.station), d.key)
}

///|
/// The workspace a station (`<workspace>/<station>`) is in.
fn workspace_of(station : String) -> String {
  match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
}

///|
/// What the composer says over its bar: an archived chat's (its restore), an offline station's.
fn composer_notices(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let t = @sf.theme()
  if v.archived {
    let restore = c.id("composer/restore")
    let busy = cui.doing.contains("restore")
    if c.clicked(restore) && !busy && !v.offline {
      if src.read_only {
        say(c, read_only_words)
      } else {
        cui.doing["restore"] = true
        let p : Map[String, Json] = {
          "station": Json::string(r.station),
          "session": Json::string(r.session),
          "archived": Json::boolean(false),
        }
        match v.thread {
          Some(th) => p["thread"] = Json::number(th)
          None => ()
        }
        (src.call)("chat.archive", Json::object(p), fn(_) { cui.doing.remove("restore") })
      }
    }
    c.box(dir=Row, padx=8.0, pady=2.0, align=ACenter, fn() {
      c.text(tr("android-chat.composer.archived"), size=13.0, color=t.p.muted, wrap=false) |> ignore
      c.box(id=restore, fn() {
        c.text(
          tr(if busy { "android-chat.composer.restoring" } else { "android-chat.composer.restore" }),
          size=13.0,
          color=if v.offline { t.p.muted } else { t.p.text },
          wrap=false,
        )
        |> ignore
        c.box(w=Fill(1.0), h=Px(1.0), bg=if v.offline { t.p.muted } else { t.p.text }, fn() {  })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  if v.offline {
    c.box(padx=8.0, pady=2.0, fn() {
      c.text(tr("android-chat.composer.offline"), size=13.0, color=t.p.muted, line=18.0) |> ignore
    })
    |> ignore
  }
}

///|
/// The bar (Composer.kt ComposerBar): ＋, the field, send. Folded: one row, the field between the buttons; opened
/// (focused, or holding something): the field the whole width, the buttons in a row under it.
fn composer_bar(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView?,
  d : Draft,
  expanded : Bool,
  locked : Bool,
  fresh : Fresh?,
) -> Unit {
  let t = @sf.theme()
  let ready = draft_ready(d, locked)
  let plus = c.id("composer/plus")
  let send = c.id("composer/send")
  if c.clicked(plus) && !locked && (v is Some(_) || fresh is Some(_)) {
    cui.attach = true
    cui.attach_at = c.now()
    c.blur()
  }
  let do_send = fn() {
    match (fresh, v) {
      (Some(f), _) if ready => (f.send)(d)
      (None, Some(view)) if ready => send_draft(c, src, r, view, d)
      _ => ()
    }
  }
  if c.clicked(send) {
    do_send()
  }
  let part = fn(i : Int, name : String) {
    @motion.layout(c, i, "composer/part/" + name, spec=@motion.tween(260.0, ease=Out), listed=false)
  }
  let plus_button = fn() {
    let b = c.box(
      w=Px(36.0),
      h=Px(36.0),
      radius=18.0,
      align=ACenter,
      justify=JCenter,
      bg=if locked { 0L } else { @sf.alpha(t.p.text, 0.08 * @motion.pressing(c, plus)) },
      id=plus,
      fn() {
        @sf.icon(c, "plus", size=18.0, color=if locked { @sf.alpha(t.p.text, 0.35) } else { t.p.text })
        |> ignore
      },
    )
    part(b, "plus")
  }
  let send_button = fn() {
    // not ready: the ink faint over the capsule's own ground (web: 18% text over --raised)
    let b = c.box(
      w=Px(36.0),
      h=Px(36.0),
      radius=18.0,
      align=ACenter,
      justify=JCenter,
      bg=if ready { t.p.text } else { @sf.over(t.p.raised, @sf.alpha(t.p.text, 0.18)) },
      id=send,
      fn() {
        @sf.icon(c, "arrow-up", size=18.0, color=if ready { t.p.bg } else { t.p.raised }) |> ignore
      },
    )
    part(b, "send")
  }
  let placeholder = match (fresh, v) {
    (Some(_), _) => tr("android-chat.new.placeholder")
    (_, Some(view)) if view.archived => tr("android-chat.composer.archived.placeholder")
    // with a mouse and nothing focused, the web's says Space takes the keyboard there (Chat.tsx)
    _ if wide_on.val && !c.field_focused() =>
      fill("web-main.composer.pressToTypeCjk", [("key", tr("web-main.keymap.space"))])
    _ => tr("android-chat.chat.placeholder")
  }
  let field = fn() {
    let f = c.box(
      w=Fill(1.0),
      min_h=36.0,
      pl=if expanded { plus_ink } else { 0.0 },
      pr=14.0,
      pt=7.0,
      pb=7.0,
      justify=JCenter,
      fn() {
        let hint = @motion.anim(c, "composer/hint", 1.0)
        if flight_hint_away(c, d.key) {
          hint.snap(0.0)
        } else {
          hint.follow(1.0, @motion.tween(200.0, ease=Arrive))
        }
        let res = c.editor(
          field_key,
          placeholder~,
          font_size=send_size,
          line=send_line,
          max_lines=6,
          plain=true,
          color=t.p.text,
          placeholder_color=@sf.alpha(t.p.subtle, hint.get()),
          caret_color=t.p.accent,
          // at a desktop's width Enter sends and ⇧Enter is a new line (the web's); on a phone Enter is a new line
          enter_sends=wide_on.val,
          paste_limit=if locked { 0 } else { paste_threshold },
        )
        match res.submitted {
          Some(words) => {
            // the field gave its words up as sent: the draft has them until they go
            d.text = words
            if draft_ready(d, locked) {
              match (fresh, v) {
                (Some(f), _) => (f.send)(d)
                (None, Some(view)) => send_draft(c, src, r, view, d)
                _ => c.set_editor_text(field_key, words)
              }
            } else {
              c.set_editor_text(field_key, words)
            }
          }
          None => ()
        }
        if res.text != d.text {
          // drawn again: what shows (opened, send ready) follows the words at once
          c.request_frame()
          d.text = res.text
          // typing starts the agent's runtime, so a cold start overlaps the writing (once a minute)
          match v {
            Some(view) if !locked && !src.read_only && view.agents.length() > 0 &&
              c.now() - d.warmed > 60000.0 => {
              d.warmed = c.now()
              (src.call)(
                "session.warm",
                {
                  "station": Json::string(r.station),
                  "key": Json::string(view.agents[0].key),
                },
                fn(_) {  },
              )
            }
            _ => ()
          }
        }
        match res.pasted {
          Some(words) => {
            paste_as_file(src, d, r.station, words)
            c.request_frame()
          }
          None => ()
        }
      },
    )
    part(f, "field")
  }
  if expanded {
    c.box(w=Fill(1.0), gap=4.0, fn() {
      field()
      c.box(dir=Row, w=Fill(1.0), align=AEnd, fn() {
        plus_button()
        c.spacer()
        send_button()
      })
      |> ignore
    })
    |> ignore
  } else {
    c.box(dir=Row, w=Fill(1.0), gap=2.0, align=ACenter, fn() {
      plus_button()
      field()
      send_button()
    })
    |> ignore
  }
}

///|
/// What waits to go with the words (Composer.kt DraftExtras): the quotes, each a card with a line for a comment (the
/// one just added takes the focus; its Enter goes back to the words), then the files.
fn draft_extras(c : @ui.Ctx, src : Source, r : ChatRef, d : Draft, locked : Bool) -> Unit {
  let t = @sf.theme()
  let k = ink()
  if d.quotes.length() > 0 {
    c.box(w=Fill(1.0), max_h=176.0, gap=6.0, clip=true, fn() {
      for q in d.quotes {
        let close = c.id("composer/unquote/\{q.id}")
        if c.clicked(close) {
          d.quotes.retain(fn(x) { x.id != q.id })
          d.comments.remove(q.id)
        }
        let key = "composer/quote/\{q.id}"
        if d.focus == q.id {
          c.focus_editor(key)
          d.focus = 0
        }
        c.box(w=Fill(1.0), radius=composer_corner - composer_inset, bg=k.card, fn() {
          c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=34.0, pt=9.0, align=AStart, fn() {
            // the quote's mark ahead of whose it is (Composer.kt quoteLine's quoteMark)
            c.box(w=Px(15.0), h=Px(19.5), justify=JCenter, fn() {
              @sf.icon(c, "quote", size=11.0, color=k.accent) |> ignore
            })
            |> ignore
            c.box(w=Fill(1.0), max_h=39.0, clip=true, fn() {
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
          })
          |> ignore
          c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=3.0, pb=10.0, fn() {
            let res = c.editor(
              key,
              placeholder=tr("android-chat.quote.comment"),
              font_size=15.0,
              line=22.0,
              max_lines=1,
              plain=true,
              color=t.p.text,
              placeholder_color=k.subtle,
              caret_color=t.p.accent,
            )
            d.comments[q.id] = res.text
            // its Enter goes on to the words
            if res.submitted is Some(_) {
              c.set_editor_text(key, res.submitted.unwrap())
              d.comments[q.id] = res.submitted.unwrap()
              d.focus = 1
            }
          })
          |> ignore
          c.layer(align=AEnd, fn() {
            c.box(pt=5.0, pr=7.0, fn() {
              c.box(w=Px(28.0), h=Px(28.0), radius=14.0, align=ACenter, justify=JCenter, id=close, fn() {
                @sf.icon(c, "close", size=12.0, color=k.subtle) |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  ref_cards(c, d.key)
  if d.files.length() > 0 {
    // as far from the capsule's edge as from its top (ComposerFilesIn 10), past its own room
    c.box(dir=Row, w=Fill(1.0), pl=2.0, pr=2.0, pt=2.0, gap=11.0, align=AEnd, clip=true, fn() {
      for f in d.files {
        let remove = c.id("composer/remove/\{f.id}")
        if c.clicked(remove) {
          d.files.retain(fn(x) { x.id != f.id })
        }
        let picture = if f.image != "" {
          f.image
        } else {
          match f.done {
            Some(a) if kind_of(f.name) == "image" && f.pasted is None => {
              let k = (src.file)(r.station, r.session, text(Some(a), "name"))
              if k == "!" {
                ""
              } else {
                k
              }
            }
            _ => ""
          }
        }
        if picture != "" || (kind_of(f.name) == "image" && f.pasted is None && f.done is Some(_)) {
          draft_picture(c, f, picture, remove)
        } else {
          match f.pasted {
            Some(words) => pasted_card(c, src, r, d, f, words, remove, locked)
            None => file_tile(c, f, remove)
          }
        }
      }
    })
    |> ignore
  }
}

///|
/// A picture waiting in the composer: a 56 tile, darkened with a spinner while it goes up (失败 when it failed), its
/// remove button over its corner.
fn draft_picture(c : @ui.Ctx, f : Pending, picture : String, remove : Int) -> Unit {
  let t = @sf.theme()
  c.box(w=Px(61.0), h=Px(61.0), pt=5.0, pr=5.0, fn() {
    c.box(w=Px(56.0), h=Px(56.0), radius=16.0, bg=t.p.chip, clip=true, fn() {
      if picture != "" {
        c.image(picture, w=Px(56.0), h=Px(56.0), radius=16.0, fit=FitCover, bg=0L) |> ignore
      }
      if f.done is None {
        c.layer(fn() {
          c.box(
            w=Fill(1.0),
            h=Fill(1.0),
            bg=@sf.alpha(0x000000FFL, if f.error is Some(_) { 0.5 } else { 0.25 }),
            align=ACenter,
            justify=JCenter,
            fn() {
              if f.error is Some(_) {
                c.text(tr("android-chat.file.failed"), size=11.0, color=0xFFFFFFFFL, wrap=false) |> ignore
              } else {
                @sf.spinner(c, ring=@sf.alpha(0xFFFFFFFFL, 0.3), arc=0xFFFFFFFFL) |> ignore
              }
            },
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    c.layer(align=AEnd, fn() {
      c.box(w=Px(20.0), h=Px(20.0), radius=10.0, bg=t.p.text, align=ACenter, justify=JCenter, id=remove, fn() {
        @sf.icon(c, "close", size=12.0, color=t.p.raised) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The round × of a card in the composer.
fn card_close(c : @ui.Ctx, remove : Int) -> Unit {
  let t = @sf.theme()
  c.box(w=Px(22.0), h=Px(22.0), radius=11.0, bg=@sf.alpha(t.p.text, 0.06), align=ACenter, justify=JCenter, id=remove, fn() {
    @sf.icon(c, "close", size=12.0, color=t.p.muted) |> ignore
  })
  |> ignore
}

///|
/// Words pasted as a file (Composer.kt PastedCard): their first line, then how it goes (going up, failed, or a text
/// file of so many characters); 展开到输入框 puts them back in the field (not too long for it), 重试上传 after it
/// failed.
fn pasted_card(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  d : Draft,
  f : Pending,
  words : String,
  remove : Int,
  locked : Bool,
) -> Unit {
  let t = @sf.theme()
  let k = ink()
  let busy = f.done is None && f.error is None
  let action = c.id("composer/paste-action/\{f.id}")
  let can_retry = f.error is Some(_) && !src.read_only
  let can_restore = words.length() <= paste_restore_limit && !locked
  if c.clicked(action) {
    if can_retry {
      d.files.retain(fn(x) { x.id != f.id })
      paste_as_file(src, d, r.station, words)
    } else if can_restore {
      d.files.retain(fn(x) { x.id != f.id })
      let now = if d.text == "" { words } else { d.text + "\n" + words }
      d.text = now
      d.put_text = Some(now)
      d.focus = 1
    }
  }
  c.box(
    dir=Row,
    w=Px(260.0),
    pl=10.0,
    pr=8.0,
    pt=8.0,
    pb=8.0,
    gap=10.0,
    radius=16.0,
    bg=k.neutral,
    align=ACenter,
    fn() {
      if busy {
        @sf.spinner(c) |> ignore
      } else {
        @sf.icon(c, "read", size=16.0, color=t.p.muted) |> ignore
      }
      c.box(w=Fill(1.0), fn() {
        let first = paste_preview(words)
        c.text(
          if first == "" { tr("web-main.composer.pastedText") } else { first },
          size=15.0,
          color=t.p.text,
          wrap=false,
          line=20.0,
        )
        |> ignore
        c.text(
          match f.error {
            Some(e) => e
            None =>
              if busy {
                tr("web-main.composer.pasteUploading")
              } else {
                fill("web-main.composer.pasteAttachment", [("count", "\{words.length()}")])
              }
          },
          size=11.0,
          color=if f.error is Some(_) { t.p.red } else { t.p.muted },
          wrap=false,
          line=16.0,
        )
        |> ignore
        if can_retry || can_restore {
          c.box(pt=2.0, id=action, fn() {
            c.text(
              tr(if can_retry { "web-main.composer.retryPaste" } else { "web-main.composer.expandPaste" }),
              size=13.0,
              color=t.p.accent,
              wrap=false,
              line=18.0,
            )
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      card_close(c, remove)
    },
  )
  |> ignore
}

///|
/// Any other file in the composer (ChatFiles.kt FileCard, in the composer's shape): its kind's mark, its name, its
/// size or how it goes.
fn file_tile(c : @ui.Ctx, f : Pending, remove : Int) -> Unit {
  let t = @sf.theme()
  let k = ink()
  let busy = f.done is None && f.error is None
  // a link shared in (share-in.ts): its title and its site, drawn as a file is
  let link = field(f.done, "link")
  c.box(dir=Row, w=Px(236.0), padx=10.0, pady=8.0, gap=10.0, radius=16.0, bg=k.neutral, align=ACenter, fn() {
    if busy {
      @sf.spinner(c) |> ignore
    } else if link is Some(_) {
      @sf.icon(c, "web", size=16.0, color=t.p.muted) |> ignore
    } else {
      @sf.icon(c, file_icon(f.name), size=16.0, color=t.p.muted) |> ignore
    }
    c.box(w=Fill(1.0), fn() {
      c.text(f.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
      c.text(
        match (f.error, link) {
          (Some(e), _) => e
          (None, Some(l)) =>
            match text(Some(l), "site") {
              "" => text(Some(l), "url")
              site => site
            }
          (None, None) => if busy { uploading_text(f) } else { file_size(f.size.to_double()) }
        },
        size=11.0,
        color=if f.error is Some(_) { t.p.red } else { t.p.muted },
        wrap=false,
        line=16.0,
      )
      |> ignore
    })
    |> ignore
    card_close(c, remove)
  })
  |> ignore
}

///|
/// The files that go up with the message: those up, a link shared in left out (it goes as words).
fn up_files(d : Draft) -> Array[Json] {
  d.files.filter_map(fn(f) { f.done }).filter(fn(j) { field(Some(j), "link") is None })
}

///|
/// The words with each link shared into the draft after them (share-in.ts: its title on a line, then the link), as the
/// core's composer sends them (composer.ts linkWords).
fn with_link_words(words : String, d : Draft) -> String {
  let lines = if words == "" { [] } else { [words] }
  for f in d.files {
    match field(f.done, "link") {
      Some(link) => {
        let title = text(Some(link), "title")
        let url = text(Some(link), "url")
        lines.push(if title != "" { title + "\n" + url } else { url })
      }
      None => ()
    }
  }
  lines.join("\n")
}

///|
/// A file's mark by its kind.
fn file_icon(name : String) -> String {
  match kind_of(name) {
    "image" => "photo"
    "video" => "file-video"
    _ => {
      let lower = name.to_lower()
      if lower.has_suffix(".pdf") {
        "file-pdf"
      } else if lower.has_suffix(".txt") || lower.has_suffix(".md") {
        "file-text"
      } else {
        "file"
      }
    }
  }
}

// ── ＋'s sheet (Attach.kt) ──────────────────────────────────────────────

///|
/// How tall ＋'s sheet is (over the foot's 26 it is drawn past): its grabber and head, the strip, the three tiles.
let attach_h : Double = 25.0 + 4.0 + 122.0 + 12.0 + 70.0 + 18.0

///|
/// ＋'s sheet: the recent photos across the top (the camera first; reading the gallery is not in this build, so its
/// tile only says so), then 照片, 文件 and Station 文件 (station_files.mbt). As tall as those two rows.
fn attach_sheet(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  d : Draft,
) -> Unit {
  let t = @sf.theme()
  let ask = fn(kind : @host.PickKind) {
    cui.attach = false
    match @host.pick(kind) {
      Some(p) => {
        cui.picking = Some(p)
        cui.picking_for = d.key
      }
      None =>
        say(
          c,
          if kind == Camera {
            "这台设备上还不能拍照"
          } else {
            "这个版本在这台设备上还不能选文件"
          },
        )
    }
  }
  ignore(src)
  ignore(r)
  let camera = c.id("attach/camera")
  let recent = c.id("attach/recent")
  let photos = c.id("attach/photos")
  let files = c.id("attach/files")
  let station = c.id("attach/station")
  if c.clicked(camera) {
    ask(Camera)
  }
  if c.clicked(photos) {
    ask(Photos)
  }
  if c.clicked(files) {
    ask(Files)
  }
  if c.clicked(recent) {
    cui.attach = false
    say(c, "这个版本还不能读相册的最近照片")
  }
  if c.clicked(station) {
    cui.attach = false
    station_files_open(c, d.key)
  }
  let sheet = @kit.sheet(
    c,
    "attach-sheet",
    cui.attach,
    h=attach_h,
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      c.box(
      fn() {
        // the grabber
        c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
          c.box(w=Px(38.0), h=Px(5.0), radius=3.0, bg=t.p.line, fn() {  }) |> ignore
        })
        |> ignore
        c.box(dir=Row, w=Fill(1.0), pl=12.0, pr=12.0, pt=4.0, pb=12.0, gap=6.0, fn() {
          attach_tile(c, camera, fn() { @sf.icon(c, "camera", size=24.0, color=t.p.text) |> ignore })
          attach_tile(c, recent, fn() {
            c.box(padx=8.0, gap=8.0, align=ACenter, fn() {
              @sf.icon(c, "photo", size=22.0, color=t.p.muted) |> ignore
              c.text(
                tr("android-chat.attach.recent.allow"),
                size=12.0,
                color=t.p.muted,
                line=16.0,
                center=true,
              )
              |> ignore
            })
            |> ignore
          })
        })
        |> ignore
        c.box(dir=Row, w=Fill(1.0), pl=12.0, pr=12.0, pb=18.0, gap=8.0, fn() {
          for item in [
            (photos, tr("android-chat.attach.photos"), "photo"),
            (files, tr("android-chat.attach.files"), "file"),
            (station, tr("web-pages.chat.files"), "server"),
          ] {
            let (id, label, icon) = item
            c.box(
              w=Fill(1.0),
              h=Px(70.0),
              padx=4.0,
              gap=6.0,
              radius=14.0,
              bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.1) } else { t.p.chip },
              align=ACenter,
              justify=JCenter,
              id~,
              fn() {
                @sf.icon(c, icon, size=22.0, color=t.p.text) |> ignore
                c.text(label, size=13.0, color=t.p.text, wrap=false, line=18.0) |> ignore
              },
            )
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
  )
  if cui.attach && !sheet.open {
    cui.attach = false
  }
}

///|
/// A tile of the recent photos' strip (92 × 122).
fn attach_tile(c : @ui.Ctx, id : Int, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(
    w=Px(92.0),
    h=Px(122.0),
    radius=14.0,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.1) } else { t.p.chip },
    align=ACenter,
    justify=JCenter,
    id~,
    body,
  )
  |> ignore
}

// ── picking a message's words (MessagePick.kt) ───────────────────────────

///|
/// A message's words that a finger held still on picks (all of them: MessagePick.kt picks a word and widens it by
/// words), to quote into the draft or copy; the bar over them (pick_bar) does that.
fn pickable(
  c : @ui.Ctx,
  ts : String,
  author : String,
  role : String,
  words : String,
  fill_w : Bool,
  body : () -> Unit,
) -> Unit {
  let id = c.id("pick/" + ts)
  // a tap on it: the keyboard goes, and what was picked is let go of
  if c.clicked(id) {
    c.blur()
    if cui.picked != "" && cui.picked != ts {
      cui.picked = ""
    }
  }
  // held still on it half a second: picked (by where the finger is, whatever in it took the press: a link, a code
  // block)
  let (px, py, down) = c.pointer()
  if down && !cui.moved && cui.picked != ts && words.trim(chars=" \n\t") != "" {
    match c.rect_of(id) {
      Some((x, y, w, h)) if px >= x && px < x + w && py >= y && py < y + h => {
        let held = c.now() - cui.down_at
        if held >= 500.0 {
          cui.picked = ts
          cui.picked_id = id
          cui.picked_author = author
          cui.picked_role = role
          cui.picked_text = words
          cui.hold = id
          c.request_frame()
        } else {
          c.wake_in(500.0 - held)
        }
      }
      _ => ()
    }
  }
  let lit = cui.picked == ts
  c.box(
    w=if fill_w { Fill(1.0) } else { Auto },
    radius=if lit { 6.0 } else { 0.0 },
    bg=if lit { @sf.alpha(ink().accent, 0.2) } else { 0L },
    id~,
    body,
  )
  |> ignore
}

///|
/// Over the list: what to do with the picked words (MessagePick.kt PickBar), over them (under them when the bar is
/// too near); a tap anywhere else lets go of them.
fn pick_bar(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  if cui.picked == "" {
    return
  }
  let t = @sf.theme()
  let quote = c.id("pick/quote")
  let copy = c.id("pick/copy")
  let bar = c.id("pick/bar")
  let (px, py, _) = c.pointer()
  if c.clicked(quote) {
    let d = draft_of(src, r)
    draft_quote(d, cui.picked_author, cui.picked_text.trim(chars=" \n\t").to_string(), cui.picked, cui.picked_role)
    cui.picked = ""
    c.request_frame()
    return
  }
  if c.clicked(copy) {
    c.copy_text(cui.picked_text)
    say(c, tr("android-chat.annotate.copied"))
    cui.picked = ""
    c.request_frame()
    return
  }
  // the press that picked it, lifted, is not a tap elsewhere
  if cui.released {
    cui.hold = 0
  }
  // a new press elsewhere than the bar lets go
  if cui.press_new {
    let on_bar = match c.rect_of(bar) {
      Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
      None => false
    }
    if !on_bar {
      cui.picked = ""
      return
    }
  }
  let (x, y, w, h) = match c.rect_of(cui.picked_id) {
    Some(rect) => rect
    None => return
  }
  let over = y - 52.0
  let top = chat_bar_h + 8.0
  let at_y = if over < top { y + h + 12.0 } else { over }
  let at_y = dmax(top, dmin(at_y, c.height - composer_room_of(c) - 48.0))
  let mid = dmax(130.0, dmin(x + w / 2.0, c.width - 130.0))
  let button = fn(id : Int, label : String, icon : String) {
    c.box(
      dir=Row,
      h=Px(32.0),
      padx=12.0,
      gap=5.0,
      radius=16.0,
      align=ACenter,
      bg=@sf.alpha(t.p.text, 0.08 * @motion.pressing(c, id)),
      id~,
      fn() {
        @sf.icon(c, icon, size=15.0, color=t.p.text) |> ignore
        c.text(label, size=14.0, color=t.p.text, wrap=false) |> ignore
      },
    )
    |> ignore
  }
  c.layer(fn() {
    c.box(dir=Row, w=Fill(1.0), pt=at_y, justify=JCenter, fn() {
      c.box(tx=mid - c.width / 2.0, fn() {
        c.box(
          dir=Row,
          h=Px(40.0),
          padx=4.0,
          radius=20.0,
          bg=t.p.raised,
          border=1.0,
          border_color=t.p.line,
          shadow=8.0,
          align=ACenter,
          id=bar,
          fn() {
            button(quote, tr("android-chat.pick.quote"), "quote")
            button(copy, tr("common.copy"), "copy")
          },
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
/// The chat left: its draft kept as it is now, ＋'s sheet and what was picked let go.
fn composer_left(src : Source, r : ChatRef) -> Unit {
  match drafts.get(draft_key(r)) {
    Some(d) => {
      d.changed_at = 0.0
      save_draft(src, d)
    }
    None => ()
  }
  cui.attach = false
  cui.picked = ""
  cui.hold = 0
}

///|
/// Words as UTF-8.
fn utf8_bytes(s : String) -> Bytes {
  let out = @buffer.new(size_hint=s.length() * 3)
  for ch in s {
    let u = ch.to_int()
    if u < 0x80 {
      out.write_byte(u.to_byte())
    } else if u < 0x800 {
      out.write_byte((0xC0 | (u >> 6)).to_byte())
      out.write_byte((0x80 | (u & 0x3F)).to_byte())
    } else if u < 0x10000 {
      out.write_byte((0xE0 | (u >> 12)).to_byte())
      out.write_byte((0x80 | ((u >> 6) & 0x3F)).to_byte())
      out.write_byte((0x80 | (u & 0x3F)).to_byte())
    } else {
      out.write_byte((0xF0 | (u >> 18)).to_byte())
      out.write_byte((0x80 | ((u >> 12) & 0x3F)).to_byte())
      out.write_byte((0x80 | ((u >> 6) & 0x3F)).to_byte())
      out.write_byte((0x80 | (u & 0x3F)).to_byte())
    }
  }
  out.to_bytes()
}

///|
/// The finger, once a frame before the chat's page is built: whether it went down or was lifted since the last frame,
/// where and when it went down, whether it has moved past the slop (8) since.
fn track_press(c : @ui.Ctx) -> Unit {
  let (px, py, down) = c.pointer()
  cui.press_new = down && !cui.was_down
  cui.released = !down && cui.was_down
  if cui.press_new {
    cui.down_x = px
    cui.down_y = py
    cui.down_at = c.now()
    cui.moved = false
  }
  if down && ((px - cui.down_x).abs() > 8.0 || (py - cui.down_y).abs() > 8.0) {
    cui.moved = true
  }
  cui.was_down = down
}
