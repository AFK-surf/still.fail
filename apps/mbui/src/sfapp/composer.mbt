// A chat's composer (ember apps/android chat/screens/Composer.kt ComposerBar, DraftExtras, Drafts, upload; ChatHost.kt
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
/// The field's words: 16 on 21 lines, as the viewer's bubbles (SendText.kt); set as its SendTextStyle sets them,
/// a style of their own with no LineHeightStyle (`trim`).
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
/// What waits to go with the message, in the capsule's top left corner: a picture's tile (its remove button reaching
/// `picture_remove_out` beyond its top right corner), each file's card as tall and as round. The row stands as far
/// from the capsule's left edge as from its top (Glass.kt ComposerFilesIn, 10), its items' corner `Inner`: concentric
/// with the capsule's by how it is written (composer_files_row, files_card).
let picture_tile : Double = 56.0

///|
let picture_remove_out : Double = 5.0

///|
///|
/// A file's card and a pasted text's card in the files' row, how wide.
let file_card_w : Double = 236.0

///|
let pasted_card_w : Double = 260.0

///|
/// The files' row (the draft's files and its station files, in one): 2 in from the capsule's room at its sides and
/// top, 10 from its edges (Composer.kt `beyond`), the reach of the last picture's remove button kept at its end (`end =
/// beyond + PictureRemoveOut`), its items' tops in line; laid out as wide as it is, in a box that scrolls it sideways
/// (draft_files_row).
// kept across runs: a value (no field of it changes)
let composer_files_row : @ui.Style = @ui.style(
  row=true,
  pl=S0_5,
  pt=S0_5,
  pr=@sf.files_row_end,
  gap=@sf.files_gap,
  align=AStart,
)

///|
/// What waits in the files' row (a picture's tile, a file's card, a pasted text's): its corner concentric with the
/// capsule's (Glass.kt InComposerFiles) where the row is the capsule's first (in its corner: `Inner`); under a quote
/// or a notice, what Android gives Smooth there (Xl2 in @sf.radii), the row then in no corner.
fn files_card() -> @ui.Style {
  if files_cornered.val {
    files_card_inner
  } else {
    files_card_set
  }
}

///|
// kept across runs: a value (no field of it changes)
let files_card_inner : @ui.Style = @ui.css("radius=Inner")

///|
// kept across runs: a value (no field of it changes)
let files_card_set : @ui.Style = @ui.css("radius=Xl2")

///|
/// Whether the files' row (or the station files') is in the capsule's top left corner this frame (capsule_top).
let files_cornered : Ref[Bool] = Ref::new(false)

///|
/// How far down the capsule's room starts: its inset, less the reach of a remove button above a picture's tile when
/// the files' row (or the station files') is the first thing in it, so the tiles stand 10 from its top edge as from
/// its left (Composer.kt: the button reaches past the row there, Compose's horizontalScroll cutting only sideways;
/// here the row cuts all round, so its room for the button comes off the capsule's).
fn capsule_top(v : ChatView?, d : Draft) -> Double {
  files_cornered.val = files_in_corner(v, d)
  capsule_top_of(v, d)
}

///|
/// Whether the files go in the capsule's corner (no notice over them, no quote): its top as it has them.
fn files_in_corner(v : ChatView?, d : Draft) -> Bool {
  let notices = match v {
    Some(v) => v.archived || v.offline
    None => false
  }
  !notices && d.quotes.length() == 0 && (refs_of(d.key).length() > 0 || d.files.length() > 0)
}

///|
/// The capsule's top inset (capsule_top), nothing kept.
fn capsule_top_of(v : ChatView?, d : Draft) -> Double {
  let inset = ct().inset
  if files_in_corner(v, d) {
    dmax(0.0, inset - picture_remove_out)
  } else {
    inset
  }
}

///|
/// Where ＋'s ink starts in its 36 button (the 18 icon centred, its line from 4.5 of 24 less half its 1.75 stroke):
/// the opened field's words start there.
let plus_ink : Double = 9.0 + 18.0 * ((4.5 - 1.75 / 2.0) / 24.0)

///|
/// The composer's measures (Composer.kt, Glass.kt): its capsule's inset and, opened, its content's own padding more (the web's 6
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
fn ct() -> ComposerType {
  {
    inset: composer_inset,
    open_pad: 0.0,
    button: 36.0,
    plus_icon: 18.0,
    send_icon: 18.0,
    font: send_size,
    line: send_line,
    shut: (0.0, 14.0, 7.0, 7.0),
    opened: (plus_ink, 14.0, 7.0, 7.0),
    open_gap: 4.0,
    gap: 8.0,
    corner: composer_corner,
    over: 8.0,
    under: 10.0,
    least: composer_room,
  }
}

///|
/// How many lines the field grows to before it scrolls: six (Composer.kt).
let field_lines : Int = 6

///|
/// A file's part going up (web/src/api.ts UPLOAD_PART), the biggest file taken (1 GB).
let part_size : Int = 4 * 1024 * 1024

///|
let max_file : Int = 1024 * 1024 * 1024

///|
/// A file on its way to the station: going up, up (`done`, the station's Attachment), or failed. `image`: the picture
/// picked, shown from its bytes (an image's key, "" for any other file); `pasted`: the words it was made of and what
/// the core says of them (`paste.info`: their first line, how many characters, the words while they can be put back).
priv struct Pending {
  id : Int
  name : String
  size : Int
  image : String
  width : Int
  height : Int
  pasted : (String, Json)?
  /// a picture's bytes as picked (Composer.kt Pending.local): what the viewer shows it from before it is sent; None
  /// for any other file, and for one of a kept draft (only the file it went up as is kept)
  local : Bytes?
  mut done : Json?
  /// how much of it the station has
  mut sent : Int
  mut error : String?
  /// its id in the core, which sends it up (`composer.add`): a message sent before it is up names it (`uploads`); ""
  /// for one going up here (a station's file switched to one) and for any other
  mut core_id : String
  /// failed going up in the core: it can go again from what the core kept (`composer.retry`)
  mut retry : Bool
  /// asked to go again: the core's failure said before it is not taken again, until it says otherwise
  mut retrying : Bool
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
}

///|
/// Each chat's draft while the app runs (files still going up go on as its page goes).
let drafts : Map[String, Draft] = {}

///|
let next_pending : Ref[Int] = { val: 1 }

///|
/// Each quote's comment line's words, by quote (ids are never used again): given the comment it came with (a kept
/// draft's, a mark's note) as it is first shown.
let quote_fields : Map[Int, @ui.Field] = Map([])

///|
fn quote_field(d : Draft, id : Int) -> @ui.Field {
  match quote_fields.get(id) {
    Some(f) => f
    None => {
      let f = @ui.Field::new(text=d.comments.get(id).unwrap_or(""))
      quote_fields[id] = f
      f
    }
  }
}

///|
fn draft_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// The chat's draft, its kept words asked of the core the first time (`draft.get`).
fn draft_of(c : @ui.Ctx, src : Source, r : ChatRef) -> Draft {
  draft_by(c, src, draft_key(r))
}

///|
/// What a composer writes to that is not a chat yet (NewChat.kt NewChatOn): its draft's key (`new:<station>`, as a
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
/// The draft kept as `key`, its words asked of the core the first time (`draft.get`).
fn draft_by(c : @ui.Ctx, src : Source, key : String) -> Draft {
  match drafts.get(key) {
    Some(d) => d
    None => {
      let d : Draft = {
        key,
        text: "",
        put_text: None,
        field: @ui.Field::new(),
        quotes: [],
        comments: {},
        files: [],
        error: None,
        loaded: false,
        kept: "",
        changed_at: 0.0,
        warm_n: 0,
        focus: 0,
        id: "",
      }
      drafts[key] = d
      // (asked of the core once the frame's builds are over)
      c.tell("draft.get/" + key, fn() { (src.call)("draft.get", { "key": Json::string(key) }, fn(res) {
        match res {
          Ok(Object(_) as v) if draft_empty(d) => fill_draft(d, v)
          _ => ()
        }
        match res {
          Ok(v) => draft_named(d, v)
          _ => ()
        }
        d.loaded = true
        d.kept = draft_sig(d)
      }) })
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
      local: None,
      done: Some(a),
      sent: number(as_, "size").to_int(),
      error: None,
      core_id: "",
      retry: false,
      retrying: false,
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
      done: Some({ "link": l }),
      sent: 0,
      error: None,
      core_id: "",
      retry: false,
      retrying: false,
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
  (src.call)("draft.put", Json::object(params), fn(res) {
    match res {
      Ok(v) => draft_named(d, v)
      _ => ()
    }
  })
}

///|
/// A draft sent with `files` in it: kept again (empty) whatever was kept before, so the core names the next draft
/// (`draft.put`'s answer); until it has, what goes up is named by no draft of the core's.
fn sent_draft(d : Draft, files : Int) -> Unit {
  // (only one files went up from needs it: a draft with none named nothing)
  if files > 0 {
    d.kept = "\u{0}sent"
    d.id = ""
  }
}

///|
/// The draft's name as the core says it (`draft.get`'s value, `draft.put`'s answer), when it says one.
fn draft_named(d : Draft, v : Json) -> Unit {
  match text(Some(v), "id") {
    "" => ()
    id => d.id = id
  }
}

///|
/// The capsule changes shape over this long (Composer.kt Morph).
let composer_morph_ms : Double = 260.0

///|
/// Laid out for another page (a new chat become its chat, in the wide frame: dock.tsx), the composer goes from where
/// and how big it was to where and how big it is now, over this long (Ease.Out): one composer changing, its ground
/// from the shape it had to this one and what it holds from where it showed to its places (morph.ts morph).
let composer_page_ms : Double = 340.0

///|
/// The composer's move to another page: the draft whose composer goes (the chat's), from where (x, y, w, h).
let composer_page_from : Ref[(String, (Double, Double, Double, Double))?] = { val: None }

///|
/// The page under the composer changes from now (a new chat become chat `chat`'s, in the wide frame; "*": another
/// page, whose composer is the next drawn): from where its ground was as the frame before laid it out.
fn composer_page_starts(c : @ui.Ctx, chat : String) -> Unit {
  composer_page_from.val = None
  if @ui.reduced_motion() {
    return
  }
  match @motion.measured_rect(c, "composer/ground") {
    Some(rect) => {
      composer_page_from.val = Some((chat, rect))
      let a = @motion.anim(c, "composer/page", 1.0, global=true)
      a.snap(0.0)
      a.animate(1.0, @motion.tween(composer_page_ms, ease=Linear))
    }
    None => ()
  }
}

///|
/// The composer of chat `chat` on its way from another page's place: where it was, and how far it has come (0 … 1,
/// Ease.Out); None once there.
fn composer_page(c : @ui.Ctx, chat : String) -> ((Double, Double, Double, Double), Double)? {
  match composer_page_from.val {
    // (another page's, said before it was known whose: the first drawn there takes it)
    Some(("*", from)) => {
      composer_page_from.val = Some((chat, from))
      composer_page(c, chat)
    }
    Some((key, from)) if key == chat => {
      let a = @motion.anim(c, "composer/page", 1.0, global=true)
      if a.moving() {
        Some((from, @motion.Out.at(a.get())))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// The capsule (node `i`, box `cap`) on its way from another page's place (`from`: its ground there) to its own, `p` of
/// the way: drawn with its bottom left edge from where the other's ground's was to where it is laid out (what it holds stands on that edge,
/// each part going on from where it showed: their layout motion), its ground from that shape to its own (page_ground).
fn page_carry(c : @ui.Ctx, i : Int, cap : Int, from : (Double, Double, Double, Double), p : Double) -> Unit {
  let (fx, fy, _, fh) = from
  match c.laid_rect(cap) {
    Some((x, y, _, h)) => c.look(i, @ui.look(dx=(fx - x) * (1.0 - p), dy=(fy + fh - y - h) * (1.0 - p)))
    // (not laid out yet: built again once it is)
    None => ()
  }
}

///|
/// The capsule's ground on its way from another page's place (`from`) to its own (box `cap` as this frame lays it out,
/// `to_h` high when it is not all of it), `p` of the way, on the capsule's bottom left edge (page_carry): its size, and
/// its corner (a pill's while it is one line high, the box's past that, as in the wide frame).
fn page_ground(c : @ui.Ctx, cap : Int, from : (Double, Double, Double, Double), p : Double, to_h : Double?) -> Unit {
  let (_, _, fw, fh) = from
  match c.laid_rect(cap) {
    Some((_, _, w, laid_h)) => {
      let h = to_h.unwrap_or(laid_h)
      let corner = ct().corner
      let r0 = dmin(corner, fh / 2.0)
      let r1 = dmin(corner, h / 2.0)
      c.box(style=page_ground_room, fn() {
        c.box(style=@ui.style(w=Fixed(fw + (w - fw) * p), h=Fixed(fh + (h - fh) * p)), fn() {
          floating_ground(c, Fill(1.0), corner=r0 + (r1 - r0) * p) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // (not laid out yet: built again once it is)
    None => ()
  }
}

///|
/// What the ground stands in on its way: all of the capsule, from its bottom edge.
// kept across runs: a value (no field of it changes)
let page_ground_room : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
/// Words sent from chat `chat`'s composer hold its room as tall as when they went (`room`) for `ms` from the next frame,
/// then let it go to its own height over the morph's time: all of it said now, as they set off (flight_start), and
/// anew when they know their way (flight_placed).
fn composer_hold(chat : String, room : Double, ms : Double) -> Unit {
  let c = @ui.current()
  @motion.anim(c, "composer/held/" + chat, 0.0, global=true).snap(room)
  let a = @motion.anim(c, "composer/hold/" + chat, 0.0, global=true)
  a.snap(1.0)
  a.animate(0.0, @motion.tween(composer_morph_ms, ease=Out, delay=ms))
}

///|
/// The room held for words sent (composer_hold) and how much of it is still held (1 … 0).
fn composer_held(c : @ui.Ctx, chat : String) -> (Double, Double) {
  (
    @motion.anim(c, "composer/held/" + chat, 0.0, global=true).get(),
    @motion.anim(c, "composer/hold/" + chat, 0.0, global=true).get(),
  )
}

///|
/// Typing warms the agent's runtime at most this often.
let warm_every_ms : Double = 60000.0

///|
/// How long after a change to the draft it is kept.
pub let draft_keep_ms : Double = 400.0

///|
/// A change kept a moment after it is made (the core writes it down then too), and at once as the chat is left.
fn keep_draft_soon(c : @ui.Ctx, src : Source, d : Draft) -> Unit {
  let unsaved = d.loaded && !src.read_only && draft_sig(d) != d.kept
  // (asked each frame, unsaved or not: kept, its time starts again; nothing shown waits for it)
  if @kit.after(c, "draft/" + d.key, unsaved, draft_keep_ms, later=true) && unsaved {
    // (once the frame's builds are over: what the composer took in further on in this one kept with it)
    c.after_build("draft/" + d.key, fn() { save_draft(src, d) })
  }
}

///|
fn uploading(d : Draft) -> Bool {
  d.files.iter().any(fn(f) { f.done is None && f.error is None }) || refs_uploading(d.key)
}

///|
/// A file going up outside the core (a station's file switched to one, station_files.mbt): sending waits for it here
/// (Composer.kt goingHere).
fn going_here(d : Draft) -> Bool {
  d.files.iter().any(fn(f) { f.done is None && f.error is None && f.core_id == "" }) || refs_uploading(d.key)
}

///|
/// Something can be sent (Composer.kt ready): words, a file up or going up in the core, or a quote; nothing going up
/// here, no file that failed (sent again or taken out first, never left out unsaid), nothing locking it.
fn draft_ready(d : Draft, locked : Bool) -> Bool {
  (
    d.text.trim(chars=" \n\t") != "" ||
    d.files.iter().any(fn(f) { f.done is Some(_) || f.core_id != "" }) ||
    d.quotes.length() > 0 ||
    refs_of(d.key).length() > 0
  ) &&
  !going_here(d) &&
  !d.files.iter().any(fn(f) { f.error is Some(_) }) &&
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

///|
/// An image of a message quoted (Composer.kt Draft.quoteFile): a quote naming it, its comment line taking the focus;
/// the file (`a`, as the station has it) goes again with the message, nothing going up, once however often it is
/// quoted.
fn draft_quote_file(d : Draft, author : String, ts : String, role : String, a : Json) -> Unit {
  let s = Some(a)
  let name = text(s, "name")
  let path = text(s, "path")
  let id = next_pending.val
  next_pending.val += 1
  d.quotes.push({ id, author, text: name, ts, role, file: name })
  d.comments[id] = ""
  if !d.files.iter().any(fn(f) { f.done is Some(_) && text(f.done, "path") == path }) {
    let fid = next_pending.val
    next_pending.val += 1
    let size = number(s, "size").to_int()
    d.files.push({
      id: fid,
      name,
      size,
      image: "",
      width: number(s, "width").to_int(),
      height: number(s, "height").to_int(),
      pasted: None,
      local: None,
      done: Some(a),
      sent: size,
      error: None,
      core_id: "",
      retry: false,
      retrying: false,
    })
  }
  d.focus = id
}

///|
/// A quote's own picture in the composer's quote card: 16 in, 6 under its words (Composer.kt DraftExtras).
// kept across runs: a value (no field of it changes)
let quote_picture_in : @ui.Style = @ui.css("pl=S4 pt=S1_5")

///|
/// The file going with a quote (a mark's screenshot, an image of a message quoted), shown in its card rather than
/// with the files (Composer.kt Draft.fileOf): the one it names, by the name it went up as.
fn quote_file_of(d : Draft, q : DraftQuote) -> Pending? {
  if q.file == "" {
    return None
  }
  d.files
  .iter()
  .find_first(fn(f) {
    let up = text(f.done, "name")
    (if up != "" { up } else { f.name }) == q.file
  })
}

///|
/// A quote taken out (Composer.kt Draft.unquote), with the file that went with it unless another quote names it too.
fn draft_unquote(src : Source, d : Draft, q : DraftQuote) -> Unit {
  let own = quote_file_of(d, q)
  d.quotes.retain(fn(x) { x.id != q.id })
  d.comments.remove(q.id)
  match own {
    Some(f) if !d.quotes.iter().any(fn(x) { quote_file_of(d, x).map(fn(g) { g.id }) == Some(f.id) }) =>
      take_out(src, d, f)
    _ => ()
  }
}

// ── files ──────────────────────────────────────────────────────────────

///|
/// A file the host holds, too big to be read whole (a video: @hostapi.Picked.held), into the draft: the core sends it
/// up, reading it from the host a part at a time as it goes (`composer.add` with `blob: {hostFile, size, type}`:
/// still.fail's Android app's PickedFiles.kt), named by its content first where the host can say it; its tile the
/// host's picture of it (a video's still).
fn add_held_file(src : Source, d : Draft, station : String, f : @hostapi.Picked) -> Unit {
  let id = next_pending.val
  next_pending.val += 1
  let size = f.size.to_int64()
  let p : Pending = {
    id,
    name: f.name,
    size: f.size.to_int(),
    image: f.src,
    width: 0,
    height: 0,
    pasted: None,
    local: None,
    done: None,
    sent: 0,
    error: None,
    core_id: "",
    retry: false,
    retrying: false,
  }
  d.files.push(p)
  if size > max_file.to_int64() {
    p.error = Some(tr("android-chat.file.tooBig"))
    return
  }
  if src.read_only {
    p.error = Some(read_only_words)
    return
  }
  let cid = upload_id(d.key + "\u{1}" + d.id + "\u{1}held\u{1}" + station + "\u{1}" + f.name + "\u{1}\{size}", d.files.length() - 1)
  p.core_id = cid
  let one : Map[String, Json] = {
    "id": Json::string(cid),
    "name": Json::string(f.name),
    "size": Json::number(f.size),
    "blob": Json::object({
      "hostFile": Json::number(f.held.to_double()),
      "size": Json::number(f.size),
      "type": Json::string(file_type(f.name)),
    }),
  }
  (src.call)(
    "composer.add",
    Json::object({
      "key": Json::string(upload_key(d)),
      "station": Json::string(station),
      "files": Json::array([Json::object(one)]),
    }),
    fn(res) {
      match res {
        Err(e) if p.done is None =>
          p.error = Some(
            match text(Some(e), "message") {
              "" => tr("android-chat.file.uploadFailed")
              m => m
            },
          )
        _ => ()
      }
    },
  )
}

///|
/// A file picked or pasted, into the draft and up to the station at once (Composer.kt upload): over 1 GB it is
/// refused where it shows; on a read-only run it goes nowhere.
fn add_file(
  src : Source,
  d : Draft,
  station : String,
  name : String,
  bytes : Bytes,
  pasted : (String, Json)?,
) -> Unit {
  let id = next_pending.val
  next_pending.val += 1
  let (w, h) = match @pixels.image_size(bytes) {
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
    local: if w > 0 { Some(bytes) } else { None },
    done: None,
    sent: 0,
    error: None,
    core_id: "",
    retry: false,
    retrying: false,
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
  // the core sends it up, from its bytes handed over beside the call; a message sent before it is up waits for it
  let cid = upload_id(d.key + "\u{1}" + d.id + "\u{1}" + file_seed(station, name, bytes), d.files.length() - 1)
  p.core_id = cid
  if image != "" {
    sent_pictures["upload\u{1}" + cid] = image
  }
  let blob : Map[String, Json] = {
    "hostBytes": [0, Json::number(bytes.length().to_double())],
    "type": Json::string(file_type(name)),
  }
  // named by its content first, so a station that has it already copies its own (PickedFiles.kt picked.hash: worked
  // out here, on the frame's thread, only for what that is quick for)
  if bytes.length() <= hashed_max {
    blob["sha256"] = Json::string(@zip.sha256(bytes))
  }
  let one : Map[String, Json] = {
    "id": Json::string(cid),
    "name": Json::string(name),
    "size": Json::number(bytes.length().to_double()),
    "blob": Json::object(blob),
  }
  (src.call_bytes)(
    "composer.add",
    Json::object({
      "key": Json::string(upload_key(d)),
      "station": Json::string(station),
      "files": Json::array([Json::object(one)]),
    }),
    bytes,
    fn(res) {
      match res {
        Err(e) if p.done is None =>
          p.error = Some(
            match text(Some(e), "message") {
              "" => tr("android-chat.file.uploadFailed")
              m => m
            },
          )
        _ => ()
      }
    },
  )
}

///|
/// The most of a file named by its content before it goes up (its SHA-256, on the frame's thread).
let hashed_max : Int = 32 * 1024 * 1024

///|
/// Where a draft's files go up in the core: a composer of their own there (`composer.add`), by a key no chat has, so
/// nothing of it is kept there; the draft keeps what is written (Composer.kt uploadKey).
fn upload_key(d : Draft) -> String {
  "mbui:" + d.key
}

///|
/// What the core says of the draft's files as they go up (its composer's topic), each frame one is going: how far,
/// up (with a picture's size from here when the station gave none), or failed (to go again).
fn follow_uploads(src : Source, d : Draft, station : String) -> Unit {
  if !d.files.iter().any(fn(f) { f.core_id != "" && f.done is None && f.error is None }) {
    return
  }
  let v = (src.topic)("composer", { "key": Json::string(upload_key(d)) }).value
  for one in items(v, "files") {
    let id = text(Some(one), "id")
    for f in d.files {
      if f.core_id != id || f.done is Some(_) || f.error is Some(_) {
        continue
      }
      match field(Some(one), "sent") {
        Some(Number(n, ..)) => f.sent = n.to_int()
        _ => ()
      }
      match field(Some(one), "done") {
        Some(Object(a)) => {
          let file = a.copy()
          if f.width > 0 && f.height > 0 && !file.contains("width") {
            file["width"] = Json::number(f.width.to_double())
            file["height"] = Json::number(f.height.to_double())
          }
          f.sent = f.size
          f.done = Some(Json::object(file))
          if f.image != "" {
            sent_pictures[sent_key(station, text(f.done, "path"))] = f.image
          }
        }
        _ =>
          match text(Some(one), "error") {
            "" => f.retrying = false
            _ if f.retrying => ()
            e => {
              f.error = Some(e)
              f.retry = true
            }
          }
      }
    }
  }
}

///|
/// A file that failed going up in the core, sent again from what it kept (`composer.retry`).
fn retry_upload(src : Source, d : Draft, f : Pending) -> Unit {
  if !f.retry || f.core_id == "" {
    return
  }
  f.error = None
  f.sent = 0
  f.retry = false
  f.retrying = true
  (src.call)("composer.retry", Json::object({ "key": Json::string(upload_key(d)), "id": Json::string(f.core_id) }), fn(res) {
    match res {
      Err(e) if f.done is None => {
        f.retrying = false
        f.error = Some(text(Some(e), "message"))
      }
      // taken again: what it says from here on is of this try
      _ => f.retrying = false
    }
  })
}

///|
/// A file taken out of the draft: one going up in the core stops (it lets go of it: `composer.remove`).
fn take_out(src : Source, d : Draft, f : Pending) -> Unit {
  d.files.retain(fn(x) { x.id != f.id })
  if f.core_id != "" && f.done is None {
    (src.call)("composer.remove", Json::object({ "key": Json::string(upload_key(d)), "id": Json::string(f.core_id) }), fn(_) {  })
  }
}

///|
/// The files still going up in the core as a message takes them (Taken.uploads): it waits for them in the outbox.
fn up_uploads(d : Draft) -> Array[Json] {
  d.files.filter_map(fn(f) {
    if f.core_id == "" || f.done is Some(_) || f.error is Some(_) {
      return None
    }
    let u : Map[String, Json] = {
      "id": Json::string(f.core_id),
      "name": Json::string(f.name),
      "size": Json::number(f.size.to_double()),
    }
    if f.width > 0 && f.height > 0 {
      u["width"] = Json::number(f.width.to_double())
      u["height"] = Json::number(f.height.to_double())
    }
    Some(Json::object(u))
  })
}

///|
/// One part of a file up from `have` (Calls.kt upload): said as it goes (`progress`: how much of the part has gone,
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
  if !d.files.iter().any(fn(f) { f.id == p.id }) && !ref_upload(d.key, p.id) && p.done is None {
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
  // (how far it has gone, heard while the part goes: Calls.kt partSent)
  let heard = fn(v : Json, _b : Bytes?) {
    match field(Some(v), "sent") {
      Some(Number(n, ..)) if p.done is None && p.error is None => p.sent = have + n.to_int()
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
  |> ignore
}

///|
/// What a file going up says: how far it has gone, once that is known.
fn uploading_text(f : Pending) -> String {
  if f.sent <= 0 || f.size <= 0 {
    tr("common.uploading")
  } else {
    fill("android-chat.file.uploading.part", [
      ("percent", "\{(f.sent.to_double() * 100.0 / f.size.to_double()).to_int()}"),
      ("size", @sf.file_size(f.size.to_double())),
    ])
  }
}

///|
/// A long paste: the text file it goes as (`pasted-text-<id>.txt`, UTF-8, as the web names it; paste_name), with what
/// the core says of the words (`paste.info`).
fn paste_as_file(src : Source, d : Draft, station : String, words : String) -> Unit {
  let name = paste_name(d.key + "\u{1}" + d.id, words, d.files.length())
  (src.call)("paste.info", { "text": Json::string(words) }, fn(r) {
    match r {
      Ok(v) =>
        match field(Some(v), "info") {
          Some(Object(_) as info) => add_file(src, d, station, name, @utf8.encode(words), Some((words, info)))
          _ => ()
        }
      Err(_) => ()
    }
  })
}

///|
/// The name a long paste goes up as: from the draft it is in (`draft`: Draft::key and the core's name for it), its
/// words and its place among the draft's files (`n`), never a clock.
fn paste_name(draft : String, words : String, n : Int) -> String {
  "pasted-text-" + uuid(upload_id("paste\u{1}" + draft + "\u{1}" + words, n)) + ".txt"
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
/// outside the composer (it lets go of the keyboard once lifted or moved: ui/Keyboard.kt letsGoOfKeyboard).
priv struct ComposerUi {
  mut attach : Bool
  mut picking : @ui.Pick?
  mut picking_for : String
  /// a finger went down outside the composer (it lets go of the keyboard once lifted or moved: Ctx::press)
  mut outside : Bool
  /// why restoring the chat failed (Composer.kt ArchiveNotice: said under it until it is tried again), by its draft
  restore_error : Map[String, String]
  /// the draft the page's composer was last built for and the chat it was in (whose room the page's other parts ask:
  /// composer_room_of)
  mut room_for : (String, ChatView?)
  /// the ids of its capsule and the capsule's content where the composer is built (ids are by the scope they are
  /// asked in: the list's rows ask for the composer's room from scopes of their own)
  mut cap_id : Int
  mut content_id : Int
  /// the outbox's entries being sent again or dropped (their buttons spin meanwhile)
  doing : Map[String, Bool]
}

///|
let cui : ComposerUi = {
  attach: false,
  picking: None,
  picking_for: "",
  outside: false,
  restore_error: {},
  room_for: ("", None),
  cap_id: 0,
  content_id: 0,
  doing: {},
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
/// The id of the capsule's content (what it is as tall as, laid out at once: the morph draws from it).
fn composer_content_id(c : @ui.Ctx) -> Int {
  c.id("composer/content")
}

///|
/// How tall the capsule's content is as this frame lays it out (read back: grown this frame, built again from it).
fn composer_natural(c : @ui.Ctx) -> Double? {
  match c.laid_size(cui.content_id) {
    Some((_, h)) => Some(h)
    None => None
  }
}

///|
/// The capsule's height as drawn (Composer.kt Morph): from the height it was to the one its content now takes (260
/// ms, Ease.Out); words just sent held as tall as when they went until a quarter of the way (ChatHost.kt hold), then
/// down to its own on the morph's curve (composer_hold). None before its content is laid out.
fn composer_morph(c : @ui.Ctx, chat : String, natural : Double?) -> Double? {
  match natural {
    Some(h) => {
      // (one motion wherever it is asked from: the list's rows ask in scopes of their own)
      let a = @motion.anim(c, "composer/morph", h, global=true)
      // (laid out for another page, it goes there on the page's move, not this: composer_page)
      if composer_page(c, chat) is Some(_) {
        a.snap(h)
      }
      a.follow(h, @motion.tween(composer_morph_ms, ease=Out))
      let m = a.get()
      let (room, share) = composer_held(c, chat)
      Some(if room > m && share > 0.0 { m + (room - m) * share } else { m })
    }
    None => None
  }
}

///|
/// How much of the page's foot the composer of chat `r` takes, with its margins (the list keeps that clear; ChatHost.kt
/// roomForList: never less than an opened composer with one line): worked out from what this frame lays out and how
/// the capsule moves, by the list and the composer alike, as either is built (nothing kept between them, so neither is
/// a frame behind the other).
fn composer_room_for(c : @ui.Ctx, key : String, v : ChatView?) -> Double {
  let room = match drafts.get(key) {
    Some(d) => composer_room_with(c, d, v)
    // (no draft yet: the composer not built; the room it leaves at least)
    None => 0.0
  }
  dmax(ct().least, room)
}

///|
/// The room of the page's composer (composer_room_for the draft it was last built for).
fn composer_room_of(c : @ui.Ctx) -> Double {
  composer_room_for(c, cui.room_for.0, cui.room_for.1)
}

///|
/// The room the composer of chat `key` takes as it is drawn (composer_room_with), not the least a list keeps for it
/// (composer_room): how far it stays over the keyboard on a device half open (tabletop.mbt). The least until it is
/// laid out.
fn composer_own_room(c : @ui.Ctx, key : String, v : ChatView?) -> Double {
  let room = match drafts.get(key) {
    Some(d) => composer_room_with(c, d, v)
    None => 0.0
  }
  if room > 0.0 {
    room
  } else {
    composer_room
  }
}

///|
/// The composer's room for draft `d` (composer_room_for).
fn composer_room_with(c : @ui.Ctx, d : Draft, v : ChatView?) -> Double {
  let natural = composer_natural(c)
  let top = capsule_top_of(v, d)
  let k = ct()
  match (flight_of(d.key), natural, composer_morph(c, d.key, natural)) {
    // while words fly to their row, the list keeps the room the composer will have, so their place is where they
    // land (ChatHost.kt roomForList)
    (Some(_), Some(h), _) => h + top + k.inset + k.over + k.under
    // otherwise the room the capsule is drawn with (the list's rows going with it)
    (None, _, Some(h)) => h + top + k.inset + k.over + k.under
    _ =>
      match c.laid_size(cui.cap_id) {
        Some((_, h)) => h + k.over + k.under
        None => 0.0
      }
  }
}

// ── sending ─────────────────────────────────────────────────────────────

///|
/// The draft's files that are up, each from its tile in the composer (what flies to the message sent: flight.mbt;
/// ChatHost.kt sending: those up, each from where its tile is).
fn draft_flying(c : @ui.Ctx, src : Source, r : ChatRef, d : Draft) -> Array[FlyingFile] {
  let flying : Array[FlyingFile] = []
  for f in d.files {
    match (f.done, @motion.measured_rect(c, "composer/tile/\{f.id}")) {
      (Some(a), Some(from)) if text(Some(a), "path") != "" =>
        flying.push({
          path: text(Some(a), "path"),
          from,
          picture: if draft_is_picture(f, draft_picture_key(src, r, f)) { draft_picture_key(src, r, f) } else { "" },
          face: draft_face(c, src, r, d, f),
        })
      _ => ()
    }
  }
  flying
}

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
  // (the station files sent as files with them, taken before the draft lets go of its refs)
  let files = up_files(d)
  let uploads = up_uploads(d)
  for a in ref_attachments(d.key) {
    files.push(a)
  }
  let taken_refs = refs_of(d.key)
  draft_refs.remove(d.key)
  let quotes = d.quotes.map(fn(q) { quote_json(d, q, true) })
  // what was taken, to put back
  let taken_text = d.text
  let taken_files = d.files.copy()
  let taken_quotes = d.quotes.copy()
  let taken_comments = d.comments.copy()
  // the words take off from where they were typed, the files from their tiles (flight.mbt; ChatHost.kt sending: those
  // up, each from where its tile is)
  let flying = draft_flying(c, src, r, d)
  for x in taken_refs {
    match (x.up, @motion.measured_rect(c, "composer/tile/ref/\{x.order}")) {
      (Some({ done: Some(a), .. }), Some(from)) if x.mode == "file" && text(Some(a), "path") != "" =>
        flying.push({ path: text(Some(a), "path"), from, picture: "", face: fn() { ref_card(c, d.key, x) } })
      _ => ()
    }
  }
  // in the list from now, before the core has it (chat.mbt LocalSent): what is sent is on screen first
  let rk = r.station + "\u{1}" + r.session
  let row = sent_local(rk, Some(v), words, files)
  let room = @motion.measured(c, "composer/content").unwrap_or(0.0)
  let chat = d.key
  flight_start(
    c,
    chat,
    rk,
    row,
    words,
    room,
    flying,
    field=field_key,
    hold=fn(ms) { composer_hold(chat, room, ms) },
    font=ct().font,
    line=ct().line,
    desk=false,
  )
  ref_field_put(d, "")
  d.files.clear()
  d.quotes.clear()
  d.comments.clear()
  d.error = None
  // sent: what is written next is another draft, which the core names as this one is kept empty
  sent_draft(d, taken_files.length())
  save_draft(src, d)
  let params : Map[String, Json] = {
    "station": Json::string(r.station),
    "text": Json::string(words),
    "attachments": Json::array(files),
    "quotes": Json::array(quotes),
  }
  // the files still going up: it waits for them in the outbox (the core sends it once they are)
  if uploads.length() > 0 {
    params["uploads"] = Json::array(uploads)
  }
  match v.thread {
    Some(th) => params["thread"] = Json::number(th)
    None => params["session"] = Json::string(r.session)
  }
  (src.call)("chat.send", Json::object(params), fn(res) {
    // not gone: it leaves the list (the core's outbox has what failed on its way)
    match res {
      Err(_) => sent_local_gone(rk, row)
      _ => ()
    }
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
          app.toast_n += 1
        }
      _ => ()
    }
  })
  // the reader goes to the chat's end with what was sent (Chat.kt: by the composer as it sends); with words flying
  // there at once, the rows above going up with them (flight.mbt)
  c.list_to_end(list_key(r), glide=flight_of(d.key) is None)
}

// ── the composer ────────────────────────────────────────────────────────

///|
/// The composer at the chat page's foot (ChatHost.kt HostComposer): its notices, what waits to go, the bar, what went
/// wrong; ＋'s sheet over the page when open. `v` None while the chat is read the first time (it takes nothing yet).
fn composer(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView?, fresh? : Fresh? = None) -> Unit {
  let t = @sf.theme()
  let d = draft_by(c, src, match fresh {
    Some(f) => f.key
    None => draft_key(r)
  })
  // its files as they go up in the core
  follow_uploads(src, d, r.station)
  let offline = match v {
    Some(v) => v.offline
    None => false
  }
  let archived = match v {
    Some(v) => v.archived
    None => false
  }
  // while the chat is read the first time it takes words, but nothing goes (Chat.kt: its spec sends nothing yet); its
  // station down, what is sent waits in the outbox until it is reached, and no file is taken in (Composer.kt
  // draft.offline: files go up to the station first)
  let locked = archived
  let focused = c.editor_focused(field_key)
  // the words kept, or put back, into the field (put there, not written: no link in it taken as pasted, chat_refs.mbt)
  match d.put_text {
    Some(words) => {
      ref_field_put(d, words)
      d.put_text = None
    }
    None => ()
  }
  if d.focus == -1 {
    c.focus_editor(field_key)
    d.focus = 0
  }
  // marked images of this chat's pictures (preview_marks.mbt), up as ＋'s files go, each with a quote per mark: taken
  // in before the capsule is laid out, so this frame draws them (taken once from where they wait: the pictures as they
  // were marked, whichever build takes them)
  match marked_into.get(d.key) {
    Some(list) => {
      marked_into.remove(d.key)
      for x in list {
        add_file(src, d, r.station, x.0, x.1, None)
        for q in x.2 {
          let id = next_pending.val
          next_pending.val += 1
          d.quotes.push({ id, author: q.0, text: q.1, ts: "", role: x.3, file: if x.3 == "page" { x.0 } else { "" } })
          d.comments[id] = q.2
        }
      }
    }
    None => ()
  }
  // a message's files quoted from their menus (sfpages menus.mbt): each a quote with its file in its card
  match quoted_into.get(d.key) {
    Some(list) => {
      quoted_into.remove(d.key)
      for q in list {
        draft_quote_file(d, q.0, q.1, q.2, q.3)
      }
    }
    None => ()
  }
  // words a visualization of this chat asked to send (sfbase viz_page.mbt): after what is written, the field focused
  match followed_into.get(d.key) {
    Some(words) => {
      followed_into.remove(d.key)
      d.text = if d.text.trim() == "" { words } else { d.text.trim_end().to_owned() + "\n" + words }
      d.put_text = Some(d.text)
      d.focus = -1
    }
    None => ()
  }
  // what the system's picker answered, taken in before the capsule is laid out too (the host's word that it has
  // answered brings this frame)
  // (taken once from where it waits: what goes up is what was picked, whichever build takes it)
  match cui.picking {
    Some(p) =>
      match p.files() {
        Some(files) => {
          cui.picking = None
          if cui.picking_for == d.key {
            // (told once the frame's builds are over, as the host's answer is the build's that took it)
            let station = r.station
            c.tell("composer/picked", fn() {
              for f in files {
                if f.held != 0 {
                  add_held_file(src, d, station, f)
                } else {
                  add_file(src, d, station, f.name, f.bytes, None)
                }
              }
            })
          }
        }
        None => ()
      }
    None => ()
  }
  // a picture pasted into the field (⌘V with one on the clipboard), as a file, as the web's paste takes one
  match c.field_picture(field_key) {
    Some(png) => add_file(src, d, r.station, pasted_picture_name, png, None)
    None => ()
  }
  // what the 文件 tab's 添加到消息 put in for this chat (src/sfdesk/drive_tab.mbt), named by their paths or as files
  refs_put(src, d.key, @sfdesk.tab_take_sent(d.key))
  // files another app shared into this chat (share.mbt), up as ＋'s are
  // (taken once from where they wait: the files as they were shared, whichever build takes them)
  match shared_into.get(d.key) {
    Some(list) => {
      shared_into.remove(d.key)
      for f in list {
        add_file(src, d, r.station, f.name, f.bytes, None)
      }
    }
    None => ()
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
  // as tall as its content
  cui.room_for = (d.key, v)
  cui.cap_id = cap
  cui.content_id = composer_content_id(c)
  let morph = composer_morph(c, d.key, composer_natural(c))
  let mut content = -1
  let top = capsule_top(v, d)
  // `@` and a few letters: the chats they find, over the capsule (chat_refs.mbt)
  chat_ref_menu(c, src, d, r.station, if fresh is Some(_) { "" } else { r.session }, field_key, locked)
  let k = ct()
  let side = 10.0
  // laid out for another page (a new chat become its chat, in the wide frame), from where it was (composer_page)
  let page = composer_page(c, d.key)
  c.box(w=Fill(1.0), pl=side, pr=side, pt=k.over, pb=k.under, fn() {
    let capsule = c.box(w=Fill(1.0), pad=k.inset, pt=top, id=cap, fn() {
      // its ground, as tall as the morph has it, on the capsule's bottom edge (over it while it is taller); in the wide
      // frame its corner a pill's while it is one line high, the opened box's past that (the web's: its corners go from
      // capsule to box with its height)
      let ground_h = match morph {
        Some(h) => Some(h + top + k.inset)
        None => composer_natural(c).map(fn(h) { h + top + k.inset })
      }
      let corner = k.corner
      let ground = c.layer(fn() {
        match page {
          Some((from, p)) => page_ground(c, cap, from, p, ground_h)
          None =>
            c.box(w=Fill(1.0), h=Fill(1.0), justify=JEnd, fn() {
              let g = floating_ground(c, match morph {
                Some(h) => Px(h + top + k.inset)
                None => Fill(1.0)
              }, corner~)
              // (where it was as its page changes: composer_page_starts)
              @motion.measure(c, g, "composer/ground")
            })
            |> ignore
        }
      })
      c.draw_only(ground)
      // (named to be measured, not to be pressed: a tap anywhere in the capsule that nothing in it takes is the capsule's,
      // which puts the caret in the field, ChatHost.kt's clickable { draft.focus++ })
      content = c.box(w=Fill(1.0), gap=k.gap, pad=if expanded { k.open_pad } else { 0.0 }, id=composer_content_id(c), taps=false, fn() {
        match v {
          Some(v) => composer_notices(c, src, r, v, d.key)
          None => ()
        }
        draft_extras(c, src, r, d, locked)
        let held = match fresh {
          Some(f) => f.held
          None => false
        }
        composer_bar(c, src, r, v, d, expanded, locked || held, locked || offline || held, fresh)
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
    // on its way from another page's place, carried with what it holds
    match page {
      Some((from, p)) => page_carry(c, capsule, cap, from, p)
      None => ()
    }
  })
  |> ignore
  match morph {
    // growing: what is above the ground is not drawn yet
    Some(h) => c.cut_to_bottom(content, h + k.inset)
    None => ()
  }
  keep_draft_soon(c, src, d)
  // a finger down outside the composer (its capsule, the `@` menu over it) lets go of the keyboard once lifted or moved
  // on (reading on)
  let press = c.press()
  if press.fresh {
    let within = fn(id : Int) {
      match c.rect_of(id) {
        Some((x, y, w, h)) => press.x >= x && press.x < x + w && press.y >= y && press.y < y + h
        None => false
      }
    }
    let off_capsule = !within(cap) && !within(ref_menu_id(c, d.key))
    cui.outside = off_capsule && !cui.attach
  }
  // (lifted after a long press: not a tap, the keyboard stays: Keyboard.kt letsGoOfKeyboard)
  if cui.outside && c.editor_focused(field_key) && (press.moved || (press.lifted && !press.long)) {
    cui.outside = false
    c.blur()
  }
  if press.lifted {
    cui.outside = false
  }
  // its station files switched to go as files: up (station_files.mbt)
  for x in refs_of(d.key) {
    if x.mode == "file" && x.up is None {
      ref_send_up(c, src, d, r.station, x)
    }
  }
  // ＋'s sheet: up from below and back down on the sheet's spring, the scrim in and out (Sheet.kt SheetHost, mbui's
  // @kit.sheet); drawn until it has gone
  attach_sheet(c, src, r, d)
  // what the words refer to, shared before they go (outside.mbt)
  outside_sheet(c, src, d.key)
  // ＋'s Station 文件 (station_files.mbt)
  station_files_sheet(c, src, workspace_of(r.station), d.key)
  ref_sheet(c, src, d.key, r.station)
}

///|
/// What a picture pasted is called (a browser's paste names one so).
let pasted_picture_name : String = "image.png"

///|
/// The roomy composer's choices beside ＋ (the web's composer toolbar): 4 apart, on ＋'s line.
// kept across runs: a value (no field of it changes)
let composer_tools : @ui.Style = @ui.css("row h=S9 gap=S1 align=ACenter")

///|
/// What floats over the page in the composer's glass (Glass.kt floating, ComposerCorner): the capsule's ground, the
/// `@` menu's (chat_refs.mbt). `h` tall.
fn floating_ground(c : @ui.Ctx, h : @ui.Size, corner? : Double = composer_corner) -> Int {
  c.box(
    w=Fill(1.0),
    h~,
    radius=corner,
    glass=@sf.glass_floating(),
    shadow=@sf.floating.sigma,
    shadow_color=@sf.floating.color,
    shadow_y=@sf.floating.dy,
    fn() {  },
  )
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
/// A notice over the bar (Composer.kt: 8 in from the capsule's room at its sides, 2 above and under), its words in a
/// line (13, muted; the restore's in the ink, underlined, as a link), why the restore failed in red under them.
// kept across runs: a value (no field of it changes)
let notice_box : @ui.Style = @ui.css("px=S2 py=S0_5")

///|
// kept across runs: a value (no field of it changes)
let notice_line : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let notice_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let restore_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notice_failed : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger)

///|
/// What the composer says over its bar (Composer.kt ArchiveNotice, chatComposer's notices): an archived chat's, with its
/// restore (the words underlined; why it failed in red under it, tapped again to try again); an offline station's.
fn composer_notices(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, key : String) -> Unit {
  let t = @sf.theme()
  if v.archived {
    let restore = c.id("composer/restore")
    let busy = cui.doing.contains("restore")
    if c.clicked(restore) && !busy && !v.offline {
      if src.read_only {
        say(c, read_only_words)
      } else {
        cui.doing["restore"] = true
        cui.restore_error.remove(key)
        let p : Map[String, Json] = {
          "station": Json::string(r.station),
          "session": Json::string(r.session),
          "archived": Json::boolean(false),
        }
        match v.thread {
          Some(th) => p["thread"] = Json::number(th)
          None => ()
        }
        (src.call)("chat.archive", Json::object(p), fn(res) {
          cui.doing.remove("restore")
          match res {
            Err(e) => cui.restore_error[key] = text(Some(e), "message")
            Ok(_) => ()
          }
        })
      }
    }
    c.box(style=notice_box, fn() {
      c.box(style=notice_line, fn() {
        c.text(tr("android-chat.composer.archived"), style=notice_words)
        |> ignore
        c.box(id=restore, fn() {
          c.rich(
            [
              @ui.span(
                tr(if busy { "android-chat.composer.restoring" } else { "android-chat.composer.restore" }),
                underline=true,
              ),
            ],
            style=if v.offline { notice_words } else { restore_words },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
      match cui.restore_error.get(key) {
        Some(e) => c.text(e, style=notice_failed) |> ignore
        None => ()
      }
    })
    |> ignore
  }
  if v.offline {
    c.box(padx=8.0, pady=2.0, fn() {
      c.text(v.offline_note.unwrap_or(tr("android-chat.composer.offline")), size=13.0, color=t.p.muted, line=18.0) |> ignore
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
  no_files : Bool,
  fresh : Fresh?,
) -> Unit {
  let t = @sf.theme()
  // the roomy composer's choices (a new chat's in the wide frame): its words always over its row
  let tools = match fresh {
    Some(f) => f.tools
    None => None
  }
  let expanded = expanded || tools is Some(_)
  // typing may warm the agent's runtime: the first time, then a minute after the last (asked each frame, so it counts)
  let warm_due = d.warm_n == 0 ||
    @kit.after(c, "warm/" + d.key + "/\{d.warm_n}", true, warm_every_ms, later=true)
  let ready = draft_ready(d, locked)
  let plus = c.id("composer/plus")
  let send = c.id("composer/send")
  // ＋: its sheet (the camera, the photos, the files)
  if c.clicked(plus) && !no_files && (v is Some(_) || fresh is Some(_)) {
    cui.attach = true
    c.blur()
    attach_open(plus)
  }
  // sent once what it refers to can be read in this workspace (outside.mbt send_sharing): at once when it refers to
  // nothing outside, else after the core is asked (and the sheet answered)
  let go = fn() {
    match (fresh, v) {
      (Some(f), _) => (f.send)(d)
      (None, Some(view)) => send_draft(c, src, r, view, d)
      _ => ()
    }
  }
  sharing_go(d.key)
  let do_send = fn() {
    if ready && (fresh is Some(_) || v is Some(_)) {
      send_sharing(src, d, r.station, go)
      // (a core that answers at once has cleared it to go already)
      sharing_go(d.key)
    }
  }
  if c.clicked(send) {
    do_send()
  }
  // (laid out for another page, on its move: composer_page)
  let part_ms = if composer_page(c, d.key) is Some(_) { composer_page_ms } else { 260.0 }
  let part = fn(i : Int, name : String) {
    @motion.layout(c, i, "composer/part/" + name, spec=@motion.tween(part_ms, ease=Out), listed=false)
  }
  let k = ct()
  // pointed at with a mouse, its ground and the text's ink under the pointer,
  // its tip with its keys (Chat.tsx ComposerTools, Chat.css.ts attachBtn)
  let mouse = @ui.pointing() is Mouse
  if mouse && !no_files {
    c.cursor(plus, Hand)
    @sf.tip(c, "composer/plus", plus, tr("web-main.composer.attach"), shortcut="composer.file")
  }
  let plus_hot = mouse && !no_files && c.lit(plus)
  let plus_button = fn() {
    let b = c.box(
      w=Px(k.button),
      h=Px(k.button),
      radius=k.button / 2.0,
      align=ACenter,
      justify=JCenter,
      bg=if plus_hot { t.p.hover } else { 0L },
      id=plus,
      fn() {
        let ink = if no_files {
          @sf.alpha(t.p.text, 0.35)
        } else {
          t.p.text
        }
        @sf.icon(c, "plus", size=k.plus_icon, color=ink)
        |> ignore
        // Composer.kt: clip(CircleShape).clickable (not when locked)
        if !no_files {
          @motion.ripple(c, plus, 18.0)
        }
      },
    )
    c.semantics(b, Button, id=plus, label=tr("android-chat.attach.title"), disabled=no_files)
    part(b, "plus")
  }
  let send_button = fn() {
    // not ready: the ink faint over the capsule's own ground, its arrow that ground (Composer.kt: 18% ink over
    // C.surface, the phone's canvas; the web's over --raised on a desktop's width)
    let ground = if t.narrow { t.p.canvas } else { t.p.raised }
    // (its ink a step lighter under a mouse's pointer, in any layout: Chat.css.ts sendBtn, the text at 82%)
    let hot = mouse && ready && c.lit(send)
    if mouse && ready {
      c.cursor(send, Hand)
    }
    let b = c.box(
      w=Px(k.button),
      h=Px(k.button),
      radius=k.button / 2.0,
      align=ACenter,
      justify=JCenter,
      bg=if hot {
        @sf.mix(t.p.text, 0.82, t.p.canvas)
      } else if ready {
        t.p.text
      } else {
        @sf.over(ground, @sf.alpha(t.p.text, 0.18))
      },
      id=send,
      fn() {
        @sf.icon(c, "arrow-up", size=k.send_icon, color=if ready { t.p.bg } else { ground }) |> ignore
        // Composer.kt: clip(CircleShape).clickable(enabled = ready)
        if ready {
          @motion.ripple(c, send, 18.0)
        }
      },
    )
    c.semantics(b, Button, id=send, label=tr("android-chat.composer.send"), disabled=!ready)
    part(b, "send")
  }
  let placeholder = match (fresh, v) {
    (Some(f), _) => f.placeholder
    (_, Some(view)) if view.archived => tr("android-chat.composer.archived.placeholder")
    _ => tr("android-chat.chat.placeholder")
  }
  let (fl, fr, ft, fb) = if expanded { k.opened } else { k.shut }
  let field = fn() {
    let f = c.box(
      w=Fill(1.0),
      min_h=k.button,
      pl=fl,
      pr=fr,
      pt=ft,
      pb=fb,
      justify=JCenter,
      fn() {
        let hint = @motion.anim(c, "composer/hint", 1.0)
        if flight_hint_away(c, d.key) {
          hint.snap(0.0)
        } else {
          hint.follow(1.0, @motion.tween(200.0, ease=Arrive))
        }
        // what the input did since the last frame: a mark backspaced whole, a chat's link pasted (chat_refs.mbt)
        @sfbase.refs_edits(c, src, d.key, d.field, r.station, locked)
        let res = c.editor(
          field_key,
          placeholder~,
          // in the face chosen for what people write (Composer.kt SendTextFaced)
          words=true,
          font_size=k.font,
          line=k.line,
          // (SendTextStyle: a TextStyle of its own, no LineHeightStyle)
          trim=true,
          max_lines=field_lines,
          plain=true,
          color=t.p.text,
          placeholder_color=@sf.alpha(t.p.subtle, hint.get()),
          caret_color=t.p.accent,
          // pointed at with a mouse (a keyboard at hand) Enter sends and ⇧Enter is a new line; with a finger (the
          // screen's keyboard) Enter is a new line, whatever the layout (the web's `hover: hover`, mobile/Chat.tsx)
          enter_sends=@ui.pointing() is Mouse,
          paste_limit=if no_files { 0 } else { @sfbase.paste_threshold(c, src) },
          // ⌘V with a picture on the clipboard: it, as a file (Chat.tsx onPaste: the clipboard's files)
          pictures=!no_files,
          // references to other chats drawn as marks (chat_refs.mbt RefMarks)
          look=@sfbase.refs_look(d.key, t.p.accent),
          // the draft's words, its own (another chat's draft: another field)
          field=d.field,
        )
        match res.submitted {
          Some(words) => {
            // the field gave its words up as sent: the draft has them until they go
            d.text = words
            if draft_ready(d, locked) && (fresh is Some(_) || v is Some(_)) {
              // (the field gave its words up: they stay in it until they go)
              ref_field_put(d, words)
              send_sharing(src, d, r.station, go)
              sharing_go(d.key)
            } else {
              ref_field_put(d, words)
            }
          }
          None => ()
        }
        if res.text != d.text {
          // what shows (opened, send ready) follows the words: the typing's own frames draw it
          d.text = res.text
          // typing starts the agent's runtime, so a cold start overlaps the writing (once a minute)
          match v {
            Some(view) if !locked && !view.offline && !src.read_only && view.agents.length() > 0 &&
              warm_due => {
              d.warm_n += 1
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
          }
          None => ()
        }
      },
    )
    part(f, "field")
  }
  if expanded {
    c.box(w=Fill(1.0), gap=k.open_gap, fn() {
      field()
      c.box(dir=Row, w=Fill(1.0), align=AEnd, fn() {
        plus_button()
        match tools {
          Some(more) => c.box(style=composer_tools, more) |> ignore
          None => ()
        }
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
    // at most 176 tall, the rest scrolled to inside it (Composer.kt: heightIn(max = 176) over verticalScroll)
    c.capped("composer/quotes/" + d.key, 176.0, fn() {
    c.box(w=Fill(1.0), gap=6.0, fn() {
      for q in d.quotes {
        let close = c.id("composer/unquote/\{q.id}")
        if c.clicked(close) {
          draft_unquote(src, d, q)
        }
        let key = "composer/quote/\{q.id}"
        let field = quote_field(d, q.id)
        if d.focus == q.id {
          c.focus_editor(key)
          d.focus = 0
        }
        // (concentric with the capsule's, a smooth corner's: @sf.inner_corner, not the radius less the inset)
        c.box(w=Fill(1.0), radius=@sf.inner_corner(composer_corner, composer_inset), bg=k.card, fn() {
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
          // its own picture (an image of a message quoted, a mark's screenshot) under what it quotes (Composer.kt
          // DraftExtras: 56, the files' corner, 16 in and 6 under)
          match quote_file_of(d, q) {
            Some(f) => {
              let picture = draft_picture_key(src, r, f)
              if draft_is_picture(f, picture) {
                c.box(style=quote_picture_in, fn() { picture_face(c, f, picture, 0) |> ignore }) |> ignore
              }
            }
            None => ()
          }
          c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=3.0, pb=10.0, fn() {
            let res = c.editor(
              key,
              placeholder=tr("android-chat.quote.comment"),
              words=true,
              font_size=15.0,
              line=22.0,
              max_lines=1,
              plain=true,
              color=t.p.text,
              placeholder_color=k.subtle,
              caret_color=t.p.accent,
              field~,
            )
            d.comments[q.id] = res.text
            // its Enter goes on to the words
            if res.submitted is Some(_) {
              field.set(res.submitted.unwrap())
              d.comments[q.id] = res.submitted.unwrap()
              d.focus = -1
            }
          })
          |> ignore
          // in the quote's corner as far from both edges (Composer.kt: top 6, end 6)
          c.layer(align=AEnd, fn() {
            c.box(pt=6.0, pr=6.0, fn() {
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
    })
    |> ignore
  }
  draft_files_row(c, src, r, d, locked)
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
/// The draft's files and its station files, as they were put in; those going with a quote are in its card.
fn draft_items(d : Draft) -> Array[DraftItem] {
  let quoted = d.quotes.filter_map(fn(q) { quote_file_of(d, q).map(fn(f) { f.id }) })
  let all : Array[DraftItem] = d.files.filter(fn(f) { !quoted.contains(f.id) }).map(fn(f) { AFile(f) })
  for x in refs_of(d.key) {
    all.push(ARef(x))
  }
  all.sort_by(fn(a, b) { a.order().compare(b.order()) })
  all
}

///|
/// The files' row (Composer.kt DraftExtras): as far from the capsule's left edge as from its top, past its own room
/// (composer_files_row, capsule_top); its items' tops in line (Compose's Row: Alignment.Top); wider than the capsule,
/// it scrolls sideways (horizontalScroll).
fn draft_files_row(c : @ui.Ctx, src : Source, r : ChatRef, d : Draft, locked : Bool) -> Unit {
  let items = draft_items(d)
  if items.length() == 0 {
    return
  }
  c.sideways("composer/files/" + d.key, fn() {
    c.box(style=composer_files_row, fn() {
      for item in items {
        match item {
          ARef(x) => ref_card(c, d.key, x)
          AFile(f) => draft_file(c, src, r, d, f, locked)
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a draft's picture shows: the one picked, or (a draft kept, which keeps no picture, only the file it went up
/// as; an image of a message quoted) the station's, through the session keeping it (its `owner`, else the chat's)
/// ("" while it comes or when it cannot be had); "" for a file that is no picture.
fn draft_picture_key(src : Source, r : ChatRef, f : Pending) -> String {
  if f.image != "" {
    return f.image
  }
  match f.done {
    Some(a) if kind_of(f.name) == "image" && f.pasted is None => {
      let owner = text(Some(a), "owner")
      let k = (src.file)(r.station, if owner != "" { owner } else { r.session }, text(Some(a), "name"))
      if k == "!" {
        ""
      } else {
        k
      }
    }
    _ => ""
  }
}

///|
/// Whether a file of the draft shows as a picture's tile.
fn draft_is_picture(f : Pending, picture : String) -> Bool {
  picture != "" || (kind_of(f.name) == "image" && f.pasted is None && f.done is Some(_))
}

///|
/// A file of the draft in the files' row: a picture's tile, a long paste's card, a link's, any other file's. Where its
/// tile is, kept (`composer/tile/<id>`) for it to fly from when sent (flight.mbt).
fn draft_file(c : @ui.Ctx, src : Source, r : ChatRef, d : Draft, f : Pending, locked : Bool) -> Unit {
  let remove = c.id("composer/remove/\{f.id}")
  if c.clicked(remove) {
    take_out(src, d, f)
  }
  // failed going up in the core: tapped, it goes again (Composer.kt: the tile's 失败, a card's retry key)
  let again = c.id("composer/retry/\{f.id}")
  if c.clicked(again) {
    retry_upload(src, d, f)
  }
  let picture = draft_picture_key(src, r, f)
  if draft_is_picture(f, picture) {
    draft_picture(c, r.station, f, picture, remove, again)
  } else {
    // (as far down as a picture's tile, under its remove button's room: their tops in line; as wide as it is,
    // never squeezed by a row too narrow for all of them)
    c.box(w=Px(if f.pasted is Some(_) { pasted_card_w } else { file_card_w }), pt=picture_remove_out, fn() {
      let card = match f.pasted {
        Some((words, info)) => pasted_card(c, src, r, d, f, words, info, remove, locked)
        None => file_tile(c, f, remove, again~)
      }
      @motion.measure(c, card, "composer/tile/\{f.id}")
    })
    |> ignore
  }
}

///|
/// A file's tile as the composer draws it, nothing of it to be tapped (a file sent: drawn where it was until its
/// message is in the list, flight.mbt); a picture's without its remove button (Composer.kt sendTile: the picture's
/// box alone), a card's with its ×.
fn draft_face(c : @ui.Ctx, src : Source, r : ChatRef, d : Draft, f : Pending) -> () -> Unit {
  let picture = draft_picture_key(src, r, f)
  fn() {
    if draft_is_picture(f, picture) {
      picture_face(c, f, picture, 0) |> ignore
    } else {
      match f.pasted {
        Some((words, info)) => pasted_card(c, src, r, d, f, words, info, 0, false) |> ignore
        None => file_tile(c, f, 0) |> ignore
      }
    }
  }
}

///|
/// A picture waiting in the composer: a 56 tile, darkened with a spinner while it goes up (失败 when it failed), its
/// remove button over its corner. Tapped, it opens in the viewer, growing out of its tile, from the bytes picked
/// (Composer.kt draftPicture: `draft:<id>`, no session's; nothing to mark it into, it is in the draft already); one of
/// a draft kept, whose bytes are not, opens nothing.
fn draft_picture(c : @ui.Ctx, station : String, f : Pending, picture : String, remove : Int, again : Int) -> Unit {
  let open = c.id("composer/picture/\{f.id}")
  let a : Attachment = {
    name: f.name,
    path: "draft:\{f.id}",
    size: f.size.to_double(),
    width: f.width.to_double(),
    height: f.height.to_double(),
    thumbhash: "",
    owner: "",
    upload: "",
  }
  // the viewer's id of it (Viewer::id: its station, no session, its path), its tile kept for it to fly from
  let thumb = station + "//" + a.path
  match f.local {
    Some(bytes) if c.clicked(open) => {
      keep_read(thumb, bytes)
      open_preview(station, "", a)
    }
    _ => ()
  }
  with_remove(c, remove, picture_tile, fn() {
    let tile = picture_face(c, f, picture, if f.local is Some(_) { open } else { 0 }, again~)
    @motion.measure(c, tile, "composer/tile/\{f.id}")
    if f.local is Some(_) {
      note_thumb(c, thumb, open, files_corner())
    }
    // not drawn while the viewer is its picture (one picture on the screen, never two: preview.mbt)
    if pv_hidden.val == thumb {
      c.look(tile, @ui.look(alpha=0.0))
    }
  })
}

///|
/// A picture's tile (56, its corner the files' row's): darkened with a spinner while it goes up, 失败 when it failed
/// (with the retry mark over it when it can go again: tapped, `again`). Its node; `id` what a tap on it is (0 none).
fn picture_face(c : @ui.Ctx, f : Pending, picture : String, id : Int, again? : Int = 0) -> Int {
  let t = @sf.theme()
  c.box(
    w=Px(picture_tile),
    h=Px(picture_tile),
    style=files_card(),
    bg=t.p.chip,
    clip=true,
    id~,
    fn() {
      if picture != "" {
        c.image(picture, w=Px(picture_tile), h=Px(picture_tile), fit=FitCover, bg=0L) |> ignore
      }
      if f.done is None {
        c.layer(fn() {
          let can = f.error is Some(_) && f.retry && again != 0
          let shade = c.box(
            w=Fill(1.0),
            h=Fill(1.0),
            bg=@sf.alpha(0x000000FFL, if f.error is Some(_) { 0.5 } else { 0.25 }),
            align=ACenter,
            justify=JCenter,
            id=if can { again } else { 0 },
            fn() {
              if f.error is Some(_) {
                if can {
                  @sf.icon(c, "retry", size=16.0, color=0xFFFFFFFFL) |> ignore
                }
                c.text(tr("android-chat.file.failed"), size=11.0, color=0xFFFFFFFFL, wrap=false) |> ignore
              } else {
                @sf.spinner(c, ring=@sf.alpha(0xFFFFFFFFL, 0.3), arc=0xFFFFFFFFL) |> ignore
              }
            },
          )
          if can {
            c.semantics(shade, Button, id=again, label=tr("web-main.composer.retryUpload"))
          }
        })
        |> ignore
      }
    },
  )
}

///|
/// The corner of what waits in the files' row (files_card), as a number: what the viewer flies from and back into.
/// Inner in the capsule's corner, concentric with it, and Xl2 elsewhere come to the same (Glass.kt InComposerFiles:
/// concentric(ComposerCorner 26, ComposerFilesIn 10), 18).
fn files_corner() -> Double {
  @sf.radii.xl2
}

///|
/// The round × of a file's card in the composer, at its trailing end (ChatFiles.kt FileCard); `icon` another key's
/// mark of the same look (its retry).
/// `label`: what it says to a screen reader (a pasted text's: Composer.kt PastedCard's removePaste), none else.
fn card_close(c : @ui.Ctx, remove : Int, label? : String = "", icon? : String = "close") -> Unit {
  let t = @sf.theme()
  let b = c.box(w=Px(22.0), h=Px(22.0), radius=11.0, bg=@sf.alpha(t.p.text, 0.06), align=ACenter, justify=JCenter, id=remove, fn() {
    @sf.icon(c, icon, size=12.0, color=t.p.muted) |> ignore
  })
  if label != "" {
    c.semantics(b, Button, id=remove, label~)
  }
}

///|
/// A picture's tile waiting to go with the message, its remove button over its top right corner,
/// reaching `picture_remove_out` beyond it (Composer.kt: a picture's; a file's card the same here, so both read alike).
fn with_remove(c : @ui.Ctx, remove : Int, w : Double, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  // (as wide as what it holds and its button's reach: never squeezed by a row too narrow for all of them)
  // (the button reaches past its right edge over the gap after it, as Composer.kt's: it takes no room of its own there)
  c.box(w=Px(w), pt=picture_remove_out, fn() {
    body()
    c.layer(align=AEnd, fn() {
      c.box(w=Px(20.0), h=Px(20.0), radius=10.0, bg=t.p.text, align=ACenter, justify=JCenter, tx=picture_remove_out, id=remove, fn() {
        @sf.icon(c, "close", size=12.0, color=t.p.raised) |> ignore
      })
      |> ignore
    })
    |> ignore
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
  info : Json,
  remove : Int,
  locked : Bool,
) -> Int {
  let t = @sf.theme()
  let k = ink()
  let busy = f.done is None && f.error is None
  let action = c.id("composer/paste-action/\{f.id}")
  let can_retry = f.error is Some(_) && !src.read_only
  // (words not too long to put back: the core keeps them in what it says of them)
  let can_restore = field(Some(info), "text") is Some(String(_)) && !locked
  if c.clicked(action) {
    if can_retry {
      take_out(src, d, f)
      paste_as_file(src, d, r.station, words)
    } else if can_restore {
      take_out(src, d, f)
      let now = if d.text == "" { words } else { d.text + "\n" + words }
      d.text = now
      d.put_text = Some(now)
      d.focus = -1
    }
  }
  c.box(
    dir=Row,
    w=Px(pasted_card_w),
    pl=10.0,
    pr=8.0,
    pt=8.0,
    pb=8.0,
    gap=10.0,
    style=files_card(),
    bg=k.neutral,
    align=ACenter,
    fn() {
      if busy {
        @sf.spinner(c) |> ignore
      } else {
        @sf.icon(c, "read", size=16.0, color=t.p.muted) |> ignore
      }
      c.box(w=Fill(1.0), fn() {
        let first = text(Some(info), "preview")
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
                fill("web-main.composer.pasteAttachment", [("count", "\{number(Some(info), "characters").to_int()}")])
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
              // a link's ink (Composer.kt: C.link)
              style=@sf.link,
              size=13.0,
              wrap=false,
              line=18.0,
            )
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      card_close(c, remove, label=tr("web-main.composer.removePaste"))
    },
  )
}

///|
/// Any other file in the composer (ChatFiles.kt FileCard, in the composer's shape): its kind's mark, its name, its
/// size or how it goes.
fn file_tile(c : @ui.Ctx, f : Pending, remove : Int, again? : Int = 0, closable? : Bool = true) -> Int {
  let t = @sf.theme()
  let k = ink()
  let busy = f.done is None && f.error is None
  // a link shared in (share-in.ts): its title and its site, drawn as a file is; tapped, it opens (Composer.kt LinkCard)
  let link = field(f.done, "link")
  let open = c.id("composer/link/\{f.id}")
  match link {
    Some(l) if c.clicked(open) => open_link(text(Some(l), "url"))
    _ => ()
  }
  c.box(
    dir=Row,
    w=Px(file_card_w),
    padx=10.0,
    pady=8.0,
    gap=10.0,
    style=files_card(),
    bg=k.neutral,
    align=ACenter,
    id=if link is Some(_) { open } else { 0 },
    fn() {
    // a link's the web's mark; any other file's one mark whatever its kind (ChatFiles.kt FileCard: Icons.Read)
    if busy {
      @sf.spinner(c) |> ignore
    } else if link is Some(_) {
      @sf.icon(c, "web", size=16.0, color=t.p.muted) |> ignore
    } else {
      @sf.icon(c, "read", size=16.0, color=t.p.muted) |> ignore
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
          (None, None) => if busy { uploading_text(f) } else { @sf.file_size(f.size.to_double()) }
        },
        size=11.0,
        color=if f.error is Some(_) { t.p.red } else { t.p.muted },
        wrap=false,
        line=16.0,
      )
      |> ignore
    })
    |> ignore
    // failed going up in the core: its retry key before its × (ChatFiles.kt FileCard onRetry)
    if f.error is Some(_) && f.retry && again != 0 {
      card_close(c, again, icon="retry", label=tr("web-main.composer.retryUpload"))
    }
    if closable {
      card_close(c, remove)
    }
    },
  )
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

// ── ＋'s sheet (Attach.kt) ──────────────────────────────────────────────

///|
/// ＋'s sheet: the recent photos across the top (the camera first, recent.mbt), then 照片, 文件 and Station 文件
/// (station_files.mbt), as tall as those two rows: the library's panel (attach_open); this frame's part of it.
fn attach_sheet(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  d : Draft,
) -> Unit {
  let t = @sf.theme()
  let ask = fn(kind : @hostapi.PickKind) {
    cui.attach = false
    // (a big file, a video, held by the host and read a part at a time as it goes up: add_held_file)
    match @ui.pick(kind, hold=true) {
      Some(p) => {
        cui.picking = Some(p)
        cui.picking_for = d.key
      }
      None =>
        say(
          c,
          tr(if kind == Camera { "android-chat.composer.noCamera" } else { "android-chat.composer.noFiles" }),
        )
    }
  }
  ignore(r)
  // the gallery's recent photos (recent.mbt), read again as the sheet opens
  recent_frame(src, cui.attach)
  let tapped_tile = fn(i : Int) {
    if i == 0 {
      ask(Camera)
    } else if i > 0 {
      cui.attach = false
      let pick = match recent.photos.get(i - 1) {
        Some(photo) => @ui.pick_photo(photo.src)
        None => None
      }
      match pick {
        Some(p) => {
          cui.picking = Some(p)
          cui.picking_for = d.key
        }
        None => ()
      }
    } else {
      match recent.access {
        // no gallery on this host: said so
        NoGallery => {
          cui.attach = false
          say(c, tr("android-chat.composer.noRecent"))
        }
        _ => @hostapi.gallery_ask()
      }
    }
  }
  // what it shows, as this frame has it, drawn by the library's host (attach_open)
  attach_drawer.val = fn(c) {
    let photos = c.id("attach/photos")
    let files = c.id("attach/files")
    let station = c.id("attach/station")
    if c.clicked(photos) {
      ask(Photos)
    }
    if c.clicked(files) {
      ask(Files)
    }
    if c.clicked(station) {
      cui.attach = false
      station_files_open(c, d.key)
    }
    // the camera, the gallery's recent photos, the tile that asks for them (recent.mbt)
    recent_strip(c, tapped_tile)
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
          bg=t.p.chip,
          align=ACenter,
          justify=JCenter,
          id~,
          fn() {
            @sf.icon(c, icon, size=22.0, color=t.p.text) |> ignore
            c.text(label, size=13.0, color=t.p.text, wrap=false, line=18.0) |> ignore
            // Attach.kt: clip(Smooth(14)).clickable
            @motion.ripple(c, id, 14.0)
          },
        )
        |> ignore
      }
    })
    |> ignore
  }
  // let go of (a tile picked, the chat left): down
  if !cui.attach && attach_shown.val > 0 {
    if @sf.presented_drawn_of(attach_shown.val) {
      @sf.close_presented_of(attach_shown.val)
    } else {
      attach_shown.val = 0
    }
  }
}

///|
/// ＋'s sheet up (@sf.last_presented; 0 none), and what it shows as the composer's frame has it.
// kept across runs: put back by attach_reset
let attach_shown : Ref[Int] = Ref(0)

///|
// kept across runs: told anew by each frame of the composer before it is read
let attach_drawer : Ref[(@ui.Ctx) -> Unit] = Ref(fn(_) {  })

///|
/// No ＋ sheet (the app begun again).
fn attach_reset() -> Unit {
  attach_shown.val = 0
}

///|
/// ＋'s sheet put up by ＋ (`plus`): the library's panel, with a finger the phone's sheet from the foot (the grabber, the
/// recent photos, the three tiles), with a mouse beside ＋; closed by its scrim, back or a press outside.
fn attach_open(plus : Int) -> Unit {
  @sf.panel("", fn(c, _) { (attach_drawer.val)(c) }, from=Of(plus), gone=fn() { cui.attach = false })
  attach_shown.val = @sf.last_presented()
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
  pick_clear()
}

