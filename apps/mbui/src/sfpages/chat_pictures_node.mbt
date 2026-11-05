// Pictures belong to the chat that asks for them, not to the list rows made to lay it out.

///|
struct ChatPicture {
  key : @signals.Signal[String]
  pixels : Array[Double]
  mut watching : Bool
}

///|
struct ChatPictures {
  owner : @view.View
  src : Source
  chat : ChatRef
  view : () -> ChatView?
  pictures : Map[String, ChatPicture]
}

///|
/// A sighted message's data and any Markdown answer still needed for the pictures it places.
struct ChatPictureRow {
  watch : @signals.Watch
  widths : Array[Double]
  mut width : Double
  mut inside : Bool
  mut waiting : Bool
  mut message : Message?
  mut reading_text : String
  mut reading : @sf.MdPictureReading?
}

///|
// kept across runs: each lender is removed when its chat node is let go
let chat_pictures_lent : @view.Lent[ChatPictures] = @view.Lent::new()

///|
/// Whether the list's current sighting includes this row. A picture uses it when its decode arrives.
// kept across runs: each lender is removed when its row node is let go
let chat_picture_in_sight : @view.Lent[() -> Bool] = @view.Lent::new()

///|
fn ChatPictures::new(owner : @view.View, src : Source, chat : ChatRef, view : () -> ChatView?) -> ChatPictures {
  { owner, src, chat, view, pictures: {} }
}

///|
fn chat_picture_id(station : String, owner : String, a : Attachment) -> String {
  let name = stored_name(a.path)
  if file_kind(a.name) == "video" {
    @sfbase.poster_image_id(station, owner, name)
  } else {
    @sfbase.file_image_id(station, owner, name)
  }
}

///|
fn ChatPictures::picture(self : ChatPictures, id : String) -> ChatPicture {
  match self.pictures.get(id) {
    Some(p) => p
    None => {
      let p = { key: @signals.signal("", same=fn(a, b) { a == b }), pixels: [], watching: false }
      self.pictures[id] = p
      p
    }
  }
}

///|
/// A row reads only the value the chat's picture owner has already obtained.
fn ChatPictures::read(self : ChatPictures, a : Attachment) -> MediaPicture {
  let station = self.chat.station
  let owner = file_owner(self.chat.session, (self.view)(), a)
  let kind = file_kind(a.name)
  let sent = sent_picture(station, a)
  let uploading = a.upload != "" && a.path == @sfbase.upload_path(a.upload)
  let id = chat_picture_id(station, owner, a)
  let key = match sent {
    Some(k) => k
    None if uploading => ""
    None if kind == "video" =>
      match @sfbase.pv_frames.get(station + "/" + owner + "/" + a.path) {
        Some((k, _)) => k
        None => self.picture(id).key.get()
      }
    None => self.picture(id).key.get()
  }
  {
    kind, key, hash: a.thumbhash, sent: sent is Some(_),
    held: kind == "image" && sent is None && self.src.images.held(id),
    unreached: kind == "image" && key == "!" && sent is None && self.src.images.unreached(id),
  }
}

///|
/// Want a picture for a sighted message. Following its answer and asking the host to decode it are owned by the chat,
/// so they continue when the temporary row that measured it has gone.
fn ChatPictures::want(self : ChatPictures, here : MessageHere, a : Attachment, room : Double, fills : Bool) -> Unit {
  let kind = file_kind(a.name)
  guard kind == "image" || kind == "video" else { return }
  let owner = owner_of(here, a)
  let held = self.picture(chat_picture_id(here.station, owner, a))
  let (w, h) = media_box_size(a, kind, room, fills)
  let (sx, sy) = if kind == "image" {
    picture_share(a, image_least, min_side=image_min_side)
  } else {
    (1.0, 1.0)
  }
  // The box may crop a tall image: its whole long side, not just the visible box, determines the decode size.
  let px = if kind == "image" {
    dmin(@ui.image_placed_px(w * sx, h * sy, FitCover, own_size(a), @ui.current().scale), image_px_most)
  } else {
    reveal_px(@ui.current(), w * sx, h * sy)
  }
  if !held.pixels.contains(px) { held.pixels.push(px) }
  if held.watching {
    let key = @signals.untracked(fn() { held.key.get() })
    if key != "" && key != "!" { @ui.current().image_want(key, px) }
    return
  }
  held.watching = true
  // The first call can complete synchronously; install the follower after it, so it sees that answer too.
  @signals.untracked(fn() { message_media(@ui.current(), self.src, here.station, owner, a) |> ignore })
  let stop = @signals.effect(fn() {
    let p = message_media(@ui.current(), self.src, here.station, owner, a)
    if p.key != "" && p.key != "!" {
      @signals.untracked(fn() {
        for size in held.pixels { @ui.current().image_want(p.key, size) }
      })
    }
    held.key.set(p.key)
  })
  self.owner.owns(stop) |> ignore
}

///|
/// Pictures of a message, including the ones it puts in quote cards.
fn ChatPictures::want_files(
  self : ChatPictures,
  here : MessageHere,
  files : Array[Attachment],
  quotes : Array[Quote],
  mine : Bool,
  width : Double,
) -> Unit {
  let room = dmax(0.0, width - 2.0 * row_side_in(width))
  let quote_room = if mine {
    @sf.quote_picture_room(composer_words_width(width) + 2.0 * bubble_side)
  } else {
    @sf.quote_picture_room(room)
  }
  for a in files {
    let quoted = quotes.any(fn(q) { q.file != "" && q.file == a.name })
    self.want(here, a, if quoted { quote_room } else { room }, false)
  }
}

///|
/// Whether another person's message draws its Markdown, as others_message_node does.
fn picture_markdown(m : Message) -> Bool {
  if m.system || m.mine || m.author_kind == "person" { return false }
  match m.card {
    Some({ ask: Some(_), .. }) | Some({ phone: Some(_), .. }) | Some({ signin: Some(_), .. }) => false
    _ => true
  }
}

///|
/// A message's quoted and unplaced pictures can be wanted immediately. Placed pictures use their Markdown's actual
/// picture rows and table cells once its reading has arrived.
fn ChatPictures::want_message(self : ChatPictures, here : MessageHere, m : Message, width : Double, placed : Bool) -> Unit {
  if m.system { return }
  let room = dmax(0.0, width - 2.0 * row_side_in(width))
  let quote_room = if m.mine {
    @sf.quote_picture_room(composer_words_width(width) + 2.0 * bubble_side)
  } else {
    @sf.quote_picture_room(room)
  }
  for q in m.quotes {
    match quote_file(q, m.attachments) {
      Some(a) => self.want(here, a, quote_room, false)
      None => ()
    }
  }
  let markdown = picture_markdown(m)
  if !m.mine && m.author_kind != "person" && !markdown { return }
  for a in beside_quotes(m.quotes, m.attachments) {
    if !markdown || !m.placed.contains(a.name) { self.want(here, a, room, false) }
  }
  if markdown && placed && !m.placed.is_empty() {
    let file = fn(name : String) { placed_of(m, name) }
    let ratio = fn(name : String) { file(name).bind(image_ratio) }
    for (name, w, fills) in @sf.md_picture_places(m.text, m.md, room, body_size, ratio, fn(name) { file(name) is Some(_) }) {
      match file(name) {
        Some(a) => self.want(here, a, w, fills)
        None => ()
      }
    }
  }
}
