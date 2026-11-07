// Draft and file helpers retained for sharing, station files and their existing tests.
// Chat input is implemented by sfpages/composer.mbt and sfbase/compose.mbt.

///|
/// The capsule's corner and its inset (ui/Glass.kt ComposerCorner, ComposerInset); what sits inside it is rounded
/// concentric with it.
let composer_corner : Double = @sf.card_corner

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
  /// a picture's bytes as picked (Composer.kt Pending.local): what the viewer shows it from before it is sent; None
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
  retry : Bool
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
  id : String
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
/// The workspace a station (`<workspace>/<station>`) is in.
fn workspace_of(station : String) -> String {
  match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
}

///|
/// What waits in the files' row, in the order it was put in the draft (Composer.kt: one row of the draft's files,
/// Station 文件's among them): each by its id (Pending's and DraftRef's come from one count, next_pending).
priv enum DraftItem {
  AFile(Pending)
  ARef(DraftRef)
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
    duration: 0.0,
    frames: 0,
    held: false,
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
  with_remove(c, remove, picture_tile, tr("web-main.file.remove", args=[("name", f.name)]), fn() {
    let tile = picture_face(c, f, picture, if f.local is Some(_) { open } else { 0 }, again~)
    @motion.measure(c, tile, "composer/tile/\{f.id}")
    if f.local is Some(_) {
      note_thumb(c, thumb, tile, files_corner(), picture~)
    }
    // not drawn while the viewer is its picture (one picture on the screen, never two: preview.mbt)
    if pv_hidden.get() == thumb {
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
      @sfpages.local_picture(c, picture, f.name, picture_tile, picture_tile)
      if f.done.get() is None {
        c.layer(fn() {
          let can = f.error.get() is Some(_) && f.retry && again != 0
          let shade = c.box(
            w=Fill(1.0),
            h=Fill(1.0),
            bg=@sf.alpha(0x000000FFL, if f.error.get() is Some(_) { 0.5 } else { 0.25 }),
            align=ACenter,
            justify=JCenter,
            id=if can { again } else { 0 },
            fn() {
              if f.error.get() is Some(_) {
                if can {
                  @sf.icon(c, "retry", size=16.0, color=0xFFFFFFFFL) |> ignore
                }
                c.text(tr("android-chat.file.failed"), size=@sf.theme().t.caption, color=0xFFFFFFFFL, wrap=false) |> ignore
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
/// What waits to go with the message (a picture's tile, a file's card), its remove button over its top right corner,
/// reaching `picture_remove_out` beyond it, its centre on the corner's curve (Composer.kt: a picture's; a card's the
/// same, docs/ui-panels.md); `label` what a screen reader calls it.
fn with_remove(c : @ui.Ctx, remove : Int, w : Double, label : String, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  // (as wide as what it holds and its button's reach: never squeezed by a row too narrow for all of them)
  // (the button reaches past its right edge over the gap after it, as Composer.kt's: it takes no room of its own there)
  c.box(w=Px(w), pt=picture_remove_out, fn() {
    body()
    c.layer(align=AEnd, fn() {
      let b = c.box(w=Px(20.0), h=Px(20.0), radius=10.0, bg=t.p.text, align=ACenter, justify=JCenter, tx=picture_remove_out, id=remove, fn() {
        @sf.icon(c, "close", size=12.0, color=t.p.raised) |> ignore
      })
      c.semantics(b, Button, id=remove, label~)
    })
    |> ignore
  })
  |> ignore
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

// ── ＋'s sheet (Attach.kt) ──────────────────────────────────────────────

///|
/// ＋'s sheet up (@sf.last_presented; 0 none), and what it shows as the composer's frame has it.
// kept across runs: put back by attach_reset
let attach_shown : Ref[Int] = Ref(0)

///|
/// No ＋ sheet (the app begun again).
fn attach_reset() -> Unit {
  attach_shown.val = 0
}
