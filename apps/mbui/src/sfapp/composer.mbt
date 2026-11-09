// A chat's composer (still.fail apps/android chat/screens/Composer.kt ComposerBar, DraftExtras, Drafts, upload; ChatHost.kt
// HostComposer; Attach.kt; PastedText.kt; SendText.kt): a capsule floating over the list's foot. ＋, a field that grows
// with the words up to six lines, the round send button; focused or holding something, the field takes the whole
// width and the buttons go under it. What waits to go with the words sits over the field: the quotes (each with a
// line for a comment) and the files (pictures as tiles, a long paste as its card, any other file as a card), each
// handed to the core as soon as it is added, which sends it up to the station (`composer.add`, its bytes beside the
// call; a station that has it already copies its own), where it waits in no chat until a message takes it. A message
// sent while one is still going up names it (`uploads`) and waits in the outbox until it is up; one that failed goes
// again from what the core kept (`composer.retry`). Enter is a new line, as the Android app's field has it; send sends.
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
/// Whether the files' row (or the station files') is in the capsule's top left corner this frame (capsule_top).
let files_cornered : Ref[Bool] = Ref::new(false)

///|
/// The composer's measures: its capsule's inset and, opened, its content's own padding more (the web's 6
/// as a capsule, 12 as a box); ＋ and send across and their icons; the words' size and line, the field's padding shut
/// and opened; the gap between the field and the buttons under it, and between what waits over it; the opened box's
/// corner (shut, a pill); the field's most lines; the room over and under it on the page, and the least room the list
/// keeps for it (the web's one opened line: 14 × 1.5 + 102).
priv struct ComposerType {
  inset : Double
  open_pad : Double
  button : Double
  plus_icon : Double
  send_icon : Double
  font : Double
  line : Double
  shut : (Double, Double, Double, Double)
  opened : (Double, Double, Double, Double)
  open_gap : Double
  gap : Double
  corner : Double
  over : Double
  under : Double
  least : Double
}

///|
/// A file's part going up (web/src/api.ts UPLOAD_PART), the biggest file taken (1 GB).
let part_size : Int = 4 * 1024 * 1024

///|
/// A file on its way to the station: going up, up (`done`, the station's Attachment), or failed. `image`: its picture
/// here, its tile and its message drawn from it (an image's key from its bytes, or the host's picture of an image or a
/// video where it is: host_picture; "" for any other file); `pasted`: the words it was made of and what
/// the core says of them (`paste.info`: their first line, how many characters, the words while they can be put back).
priv struct Pending {
  id : Int
  name : String
  size : Int
  mut image : String
  width : Int
  height : Int
  pasted : (String, Json)?
  /// a picture's bytes as picked: what the viewer shows it from before it is sent; None
  /// for any other file, and for one of a kept draft (only the file it went up as is kept)
  local : Bytes?
  done : @signals.Signal[Json?]
  /// how much of it the station has
  sent : @signals.Signal[Int]
  error : @signals.Signal[String?]
  /// its id in the core, which sends it up (`composer.add`): a message sent before it is up names it (`uploads`); ""
  /// for one going up here (a station's file switched to one) and for any other
  mut core_id : String
  /// failed going up in the core: it can go again from what the core kept (`composer.retry`)
  mut retry : Bool
  /// a video's bytes, read whole, that the host has no picture of (no address for it: @hostapi.Picked.src): its
  /// `image` its first frame, made from them (draft_stills), None once it is
  mut unseen : Bytes?
  /// asked to go again: the core's failure said before it is not taken again, until it says otherwise
  retrying : @signals.Signal[Bool]
  /// what it is, picked or pasted as a file (file_seed, held_seed): the same added again while it is in the draft is
  /// not added twice; "" for any other
  seed : String
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
  text : @signals.Signal[String]
  /// words for the field to take the next time it is drawn (kept words read, words put back)
  put_text : @signals.Signal[String?]
  quotes : @sf.LiveArray[DraftQuote]
  /// the quotes' comments, by quote (their fields' words)
  comments : @sf.LiveMap[Int, String]
  files : @sf.LiveArray[Pending]
  error : @signals.Signal[String?]
  /// what the core kept has been read: only then is it written over
  loaded : @signals.Signal[Bool]
  /// what was last kept, and when it last changed
  kept : @signals.Signal[String]
  mut changed_at : Double
  /// how many times typing woke the agent's runtime (`session.warm`, once a minute: the next a minute of this
  /// composer shown after the last)
  mut warm_n : Int
  /// the quote whose comment line takes the focus next frame (0 none); -1: the words' field (ids count from 1)
  mut focus : Int
  /// its words and their selection, the field's (mbui's Field, Compose's TextFieldState): the composer's field shows
  /// them, typing writes them, the app (a core's answer included) writes them from anywhere
  field : @ui.Field
  /// the draft's own name, the core's (DraftView.id: `draft.get` gives it, `draft.put` answers it): another once it
  /// is sent or put back empty, so what goes up from it is another upload than the same in the message before, or in
  /// another new chat ("" until the core has said it)
  mut id : String
  /// what it is as kept (draft_sig), worked out again only as a part of it changes: asked each frame
  mut sig : @signals.Computed[String]?
}

///|
/// Each chat's draft while the app runs (files still going up go on as its page goes).
let drafts : @sf.LiveMap[String, Draft] = @sf.LiveMap::new()

///|
let next_pending : Ref[Int] = { val: 1 }

///|
/// Each quote's comment line's words, by quote (ids are never used again): given the comment it came with (a kept
/// draft's, a mark's note) as it is first shown.
let quote_fields : Map[Int, @ui.Field] = Map([])

///|
fn draft_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// What a composer writes to that is not a chat yet: its draft's key (`new:<station>`, as a
/// new chat's on the device) and what sending does.
priv struct Fresh {
  key : String
  /// what its field says while empty
  placeholder : String
  send : (Draft) -> Unit
  /// the wide frame's new chat (the web's roomy composer): its choices in the row under the words, beside ＋, the
  /// words always over them; None: the capsule as it is
  tools : (() -> Unit)?
  /// a new chat's while its stations are read: it takes words, but nothing goes and no file is taken in (NewChat.tsx:
  /// locked until there is a station to write to)
  held : Bool
}

///|
/// What the core kept (DraftView): its words, quotes and the files already up.
fn fill_draft(d : Draft, v : Json) -> Unit {
  let s = Some(v)
  let words = text(s, "text")
  d.text.set(words)
  d.put_text.set(Some(words))
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
      local: None,
      done: @signals.signal(Some(a)),
      sent: @signals.signal(number(as_, "size").to_int()),
      error: @signals.signal(None),
      core_id: "",
      retry: false,
      retrying: @signals.signal(false),
      unseen: None,
      seed: "",
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
      local: None,
      done: @signals.signal(Some({ "link": l })),
      sent: @signals.signal(0),
      error: @signals.signal(None),
      core_id: "",
      retry: false,
      retrying: @signals.signal(false),
      unseen: None,
      seed: "",
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
    "text": Json::string(d.text.get()),
    "quotes": Json::array(d.quotes.map(fn(q) { quote_json(d, q, false) })),
    "files": Json::array(up_files(d)),
  }
  // the links shared in, kept beside the files (the core's DraftView `links`)
  let links = d.files.filter_map(fn(f) { field(f.done.get(), "link") })
  if links.length() > 0 {
    v["links"] = Json::array(links)
  }
  v
}

///|
/// How long after a change to the draft it is kept.
pub let draft_keep_ms : Double = 400.0

///|
/// One part of a file up from `have`: said as it goes (`progress`: how much of the part has gone,
/// heard while it goes), the station answers with what it has so far, or, the last part in, the file as it keeps it
/// (an image's size put with it).
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
  if !d.files.iter().any(fn(f) { f.id == p.id }) && !ref_upload(d.key, p.id) && p.done.get() is None {
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
    "progress": Json::boolean(true),
  }
  // (how far it has gone)
  let heard = fn(v : Json, _b : Bytes?) {
    match field(Some(v), "sent") {
      Some(Number(n, ..)) if p.done.get() is None && p.error.get() is None => p.sent.set(have + n.to_int())
      _ => ()
    }
  }
  (src.stream)("station.upload.part", Json::object(params), Some(part), heard, fn(res) {
    match res {
      Ok(answer) =>
        match field(Some(answer), "file") {
          Some(Object(f)) => {
            let file = f.copy()
            if p.width > 0 && p.height > 0 {
              file["width"] = Json::number(p.width.to_double())
              file["height"] = Json::number(p.height.to_double())
            }
            p.sent.set(size)
            p.done.set(Some(Json::object(file)))
          }
          _ => {
            let next = match field(Some(answer), "have") {
              Some(Number(n, ..)) => n.to_int()
              _ => have + len
            }
            if next <= have {
              p.error.set(Some(tr("android-chat.file.uploadFailed")))
            } else {
              p.sent.set(next)
              upload_part(src, d, station, p, bytes, id, next)
            }
          }
        }
      Err(e) =>
        p.error.set(Some(
          match text(Some(e), "message") {
            "" => tr("android-chat.file.uploadFailed")
            m => m
          },
        ))
    }
  })
  |> ignore
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
/// What the page keeps of its composer: ＋'s sheet (open), the system's picker under way, a finger down
/// outside the composer.
priv struct ComposerUi {
  mut attach : Bool
  mut picking : @ui.Pick?
  mut picking_for : String
  /// a finger went down outside the composer (it lets go of the keyboard once lifted or moved: Ctx::press)
  mut outside : Bool
  /// why restoring the chat failed, by its draft
  restore_error : @sf.LiveMap[String, String]
  /// the draft the page's composer was last built for and the chat it was in (whose room the page's other parts ask:
  /// composer_room_of)
  mut room_for : (String, ChatView?)
  /// the ids of its capsule and the capsule's content where the composer is built (ids are by the scope they are
  /// asked in: the list's rows ask for the composer's room from scopes of their own)
  mut cap_id : Int
  mut content_id : Int
  /// the outbox's entries being sent again or dropped (their buttons spin meanwhile)
  doing : @sf.LiveMap[String, Bool]
  /// the draft and the shape its field's hint was last shown on (composer_bar): changed, the hint waits till it is there
  mut hint_shape : (String, String)
  /// the draft whose hint waits for its bar to be there (its parts' move, as long as it is far: composer_bar), "" none
  mut hint_after : String
}

///|
let cui : ComposerUi = {
  attach: false,
  picking: None,
  picking_for: "",
  outside: false,
  restore_error: @sf.LiveMap::new(),
  room_for: ("", None),
  cap_id: 0,
  content_id: 0,
  doing: @sf.LiveMap::new(),
  hint_shape: ("", ""),
  hint_after: "",
}

///|
/// What waits in the files' row, in the order it was put in the draft (Composer.kt: one row of the draft's files,
/// Station 文件's among them): each by its id (Pending's and DraftRef's come from one count, next_pending).
priv enum DraftItem {
  AFile(Pending)
  ARef(DraftRef)
}

///|
fn DraftItem::order(self : DraftItem) -> Int {
  match self {
    AFile(f) => f.id
    ARef(x) => x.order
  }
}

///|
/// The files that go up with the message: those up, a link shared in left out (it goes as words).
fn up_files(d : Draft) -> Array[Json] {
  d.files.filter_map(fn(f) { f.done.get() }).filter(fn(j) { field(Some(j), "link") is None })
}

///|
/// The words with each link shared into the draft after them (share-in.ts: its title on a line, then the link), as the
/// core's composer sends them (composer.ts linkWords).
fn with_link_words(words : String, d : Draft) -> String {
  let lines = if words == "" { [] } else { [words] }
  for f in d.files {
    match field(f.done.get(), "link") {
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

// ── ＋'s sheet ──────────────────────────────────────────────

///|
/// ＋'s sheet up (@sf.last_presented; 0 none), and what it shows as the composer's frame has it.
// kept across runs: put back by attach_reset
let attach_shown : Ref[Int] = Ref(0)

///|
/// No ＋ sheet (the app begun again).
fn attach_reset() -> Unit {
  attach_shown.val = 0
}
