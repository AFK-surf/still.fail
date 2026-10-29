// A message's files on the desktop (ember web/src/Chat.tsx Files, FileItem, MessageFileCard, imageBox.ts; Chat.css.ts
// msgFiles, msgImage, msgImageWait, msgVideo, fileCardOpen; styles/later.css.ts): side by side, wrapping 6 apart; an
// image in a box of its own proportions (known before it loads), brushed in from its top once decoded; a video's
// still on black with its play mark and its name; anything else a card. Pressed, each opens in the file viewer
// (viewer.mbt). While the core downloads one (downloads.mbt), how far on its card, ✕ to call it off, ↻ to ask it
// again.

///|
/// A message's files (Files), at the column's end when it is the viewer's (`mine`).
pub fn message_files(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  list : Array[Attachment],
  mine : Bool,
  by? : (String, String, String)? = None,
) -> Unit {
  if list.length() == 0 {
    return
  }
  // as wide as where it is at most (the column's, as laid out: c.width is the pane's), the pane's until it is laid out
  let at = c.id("msg-files/" + here.station + "/" + @sfbase.file_key(list[0]))
  let room = match c.laid_size(at) {
    Some((w, _)) if w > 0.0 => w
    _ => c.width
  }
  // each one's width as the row lays it (an image's and a video's box at most the column's)
  let widths = list.map(fn(a) {
    match file_kind(a.name) {
      "image" => dmin(image_box(a, image_least).0, room)
      "video" => dmin(image_box(a, video_least).0, room)
      _ => dmin(@sf.file_card_w, room)
    }
  })
  // (in a picture of the chat being shared, each with the room its ✕ hangs in past its top and right: publish.mbt)
  let hung = if picturing.val is Some(_) { publish_file_hung() } else { 0.0 }
  let rows : Array[Array[Int]] = []
  let mut used = 0.0
  for i, w in widths {
    if rows.length() == 0 || used + files_gap + w + hung > room {
      rows.push([i])
      used = w + hung
    } else {
      rows[rows.length() - 1].push(i)
      used = used + files_gap + w + hung
    }
  }
  let column = if mine { files_column_end } else { files_column }
  let column = if hung > 0.0 { column.then(@ui.style(pt=@sf.room_of(hung), gap=@sf.room_of(files_gap + hung))) } else { column }
  c.box(style=column, id=at, fn() {
    for r in rows {
      c.box(style=files_row, fn() {
        for i in r {
          // (each in a box of its own: where a file sent from the composer flies to, sfbase's flight.mbt)
          // (as wide as laid out for it: a card does not give way to the picture beside it)
          let item = c.box(style=@ui.style(w=Fixed(widths[i] + hung)), fn() { file_item(c, src, here, list[i], widths[i], by~) })
          match flight_here(here) {
            Some(f) => flight_landing(c, f, item, @sfbase.file_key(list[i]), share=landing_share(list[i]))
            None => ()
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The session whose workspace keeps a message's file: as the core says it, else the chat's first agent's (useKeeper).
fn owner_of(here : MessageHere, a : Attachment) -> String {
  if a.owner != "" {
    a.owner
  } else {
    match here.view.agents.get(0) {
      Some(ag) => ag.key
      None => here.session
    }
  }
}

///|
/// The last part of a path: the name the station keeps a file by (storedName).
fn stored_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_string()
    None => path
  }
}

///|
/// A message's file opened in the preview (FilePreview): an image steps through the chat's.
fn open_file(here : MessageHere, a : Attachment) -> Unit {
  open_preview(here.station, owner_of(here, a), a, steps=InChat(here.view.thread, here.session))
}

///|
/// A file a message of agent `agent` names by its path opened in the preview (Peeks.tsx FileRef open), read through
/// the agent's session as it is now; not a directory.
fn open_named(here : MessageHere, agent : String, path : String) -> Unit {
  guard agent != "" && !path.has_suffix("/") else { return }
  let a = attachment_of({ "name": Json::string(stored_name(path)), "path": Json::string(path) })
  open_preview(here.station, agent, a, named=true)
}

///|
/// What a file is by its name (FilePreview.tsx kindOf, as the chat tells them apart): image, video, or anything else.
pub fn file_kind(name : String) -> String {
  let lower = @sf.lower(name)
  let ext = match lower.rev_find(".") {
    Some(i) if i > 0 => lower.view(start_offset=i + 1).to_string()
    _ => ""
  }
  match ext {
    "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "avif" | "bmp" | "ico" => "image"
    "mp4" | "m4v" | "webm" | "mov" | "ogv" => "video"
    _ => ""
  }
}

///|
/// The box an image takes in the chat, known before it loads (imageBox.ts): its own proportions (sent with it, or its
/// ThumbHash's) within 360×300, a tiny one drawn to 40 on its longer side; a strip thinner than `least` letterboxed in
/// a box that thick; 240×160 for one sent before sizes were kept. (width, height, letterboxed)
pub fn image_box(a : Attachment, least : Double) -> (Double, Double, Bool) {
  let (w, h) = match own_size(a) {
    Some(s) => s
    None => return (box_unknown_w, box_unknown_h, false)
  }
  let scale = dmin(dmin(dmax(1.0, box_tiny / dmax(w, h)), box_most_w / w), box_most_h / h)
  let width = w * scale
  let height = h * scale
  if width >= least && height >= least {
    return (width.round(), height.round(), false)
  }
  (dmax(least, width).round(), dmax(least, height).round(), true)
}

///|
/// An image's width over its height in the chat (its image_box's), as a table's cell draws it that wide (@sf.Placed's
/// `image`); None for any other file.
fn image_ratio(a : Attachment) -> Double? {
  guard file_kind(a.name) == "image" else { return None }
  let (w, h, _) = image_box(a, image_least)
  Some(w / h)
}

///|
/// An image's own proportions, as known before it loads: its size sent with it, else its ThumbHash's at the unknown
/// box's height; None for one sent before sizes were kept.
fn own_size(a : Attachment) -> (Double, Double)? {
  if a.width > 0.0 && a.height > 0.0 {
    Some((a.width, a.height))
  } else {
    thumb_ratio(a.thumbhash).map(fn(r) { ((box_unknown_h * r).round(), box_unknown_h) })
  }
}

///|
/// The share of its box's width and height a picture takes in it (image_box's, `least` thick): all of it, or a
/// letterboxed one's, its own proportions fitted inside, centred (imageBox.ts letterbox).
pub fn picture_share(a : Attachment, least : Double) -> (Double, Double) {
  let (bw, bh, letterbox) = image_box(a, least)
  match own_size(a) {
    Some((w, h)) if letterbox => {
      let k = dmin(bw / w, bh / h)
      (w * k / bw, h * k / bh)
    }
    _ => (1.0, 1.0)
  }
}

///|
/// Where in its box a file sent from here lands (flight.mbt): an image's or a video's picture, its share of it.
fn landing_share(a : Attachment) -> (Double, Double) {
  match file_kind(a.name) {
    "image" => picture_share(a, image_least)
    "video" => picture_share(a, video_least)
    _ => (1.0, 1.0)
  }
}

///|
/// A ThumbHash's width over its height, from its header.
fn thumb_ratio(hash : String) -> Double? {
  if hash == "" {
    return None
  }
  @pixels.thumbhash_ratio(@codec.from_base64(hash))
}

///|
/// One of a message's files (FileItem), `w` wide.
fn file_item(c : @ui.Ctx, src : Source, here : MessageHere, a : Attachment, w : Double, by~ : (String, String, String)?) -> Unit {
  match picturing.val {
    // (in a picture of the chat being shared: to tick, publish.mbt)
    Some((seq, taking)) => publish_file(c, src, here, seq, taking, a, w, by~)
    None => file_drawn(c, src, here, a, w, by~)
  }
}

///|
/// Its message's file `a` quoted into the chat's draft, where it is a message's (`by`: whose, their role, its ts).
fn quote_of(here : MessageHere, a : Attachment, owner : String, by : (String, String, String)?) -> (() -> Unit)? {
  by.map(fn(b) {
    let (author, role, ts) = b
    let file = attachment_json(a, owner)
    let draft = here.station + ":" + here.session
    fn() { quote_file_into(draft, author, ts, role, file) }
  })
}

///|
/// A message's file as the chat draws it, by its kind.
fn file_drawn(c : @ui.Ctx, src : Source, here : MessageHere, a : Attachment, w : Double, by~ : (String, String, String)?) -> Unit {
  match file_kind(a.name) {
    "image" => image_item(c, src, here, a, w, by~)
    "video" => video_item(c, src, here, a, w, by~)
    _ => card_item(c, src, here, a, by~)
  }
}

///|
/// An image (FileItem's image): in its box on the neutral ground, what it waits on until it is decoded (its ThumbHash's
/// likeness), then brushed in from its top; one sent from here the picture it was picked as, there at once; one that
/// cannot be had says so. Pressed, the preview; right-clicked, 复制图片.
fn image_item(c : @ui.Ctx, src : Source, here : MessageHere, a : Attachment, w : Double, by~ : (String, String, String)?) -> Unit {

  let open = c.id("msg-file/" + @sfbase.file_key(a))
  let owner = owner_of(here, a)
  let (bw, bh, letterbox) = image_box(a, image_least)
  let h = bh * w / bw
  let sent = sent_picture(here.station, a)
  // (still going up, its picture not here: no station has it to ask yet)
  let going_up = sent is None && a.upload != "" && a.path == @sfbase.upload_path(a.upload)
  let key = match sent {
    Some(k) => k
    None if going_up => ""
    None => (src.file)(here.station, owner, stored_name(a.path))
  }
  // could not be had for want of its station (not its station having none): pressed, asked again
  let id = @sfbase.file_image_id(here.station, owner, stored_name(a.path))
  let unreached = key == "!" && sent is None && src.images.unreached(id)
  if c.clicked(open) {
    if unreached {
      src.images.again(here.station)
    } else {
      open_file(here, a)
    }
  }
  let thumb = here.station + "/" + owner + "/" + a.path
  file_menu(c, open, key, quote=quote_of(here, a, owner, by))
  // the picture covering the whole box; a letterboxed one's covering its own proportions centred in it, all it and
  // what it waits on take, the box's corners cutting it (imageBox.ts letterbox; any: its frame's, concentric with
  // what holds it where it is in a corner of that, a quote's card)
  let (sw, sh) = picture_share(a, image_least)
  let (pw, ph) = (w * sw, h * sh)
  let likeness = @gallery.thumbhash_image(a.thumbhash).unwrap_or("")
  let picture = fn() {
    if key != "" && sent is None {
      image_reveal(c, key, pw, ph, FitCover, a.thumbhash, radius=0.0, held=src.images.held(id))
    } else if key != "" {
      c.image(key, w=Px(pw), h=Px(ph), fit=FitCover, bg=0L, fade=false) |> ignore
    } else if likeness != "" {
      c.image(likeness, w=Px(pw), h=Px(ph), fit=FitCover, bg=0L, fade=false) |> ignore
    }
  }
  // one the device holds and not decoded yet: what the app's first page waits for
  if a.held && sent is None && (key == "" || (key != "!" && !c.image_ready(key, reveal_px(c, pw, ph)))) {
    @sfbase.held_pictures_waiting.val = true
  }
  // what it shows: its picture once decoded, until then its likeness (image_reveal's)
  let shows = if key == "" || key == "!" {
    likeness
  } else if sent is None && !c.image_ready(key, reveal_px(c, pw, ph)) {
    likeness
  } else {
    key
  }
  // asked of its station and not here yet: the whole of what stands in for it (the neutral ground, its likeness)
  // breathing gently, a page's bones' breath (the user, 2026-10-30: 整个 placeholder 的轻微加载动态), back to whole over
  // dur_ms once it is here
  let asked = key == "" && !going_up
  let breath = @motion.animate(c, "msg-breath/" + thumb, if asked { 1.0 } else { 0.0 }, spec=@motion.tween(@sf.dur_ms, ease=Out))
  let b = c.box(style=image_box_style(w, h, key != "!" || letterbox), id=open, fn() {
    if key == "!" {
      c.box(style=no_preview_box, fn() {
        @sf.icon(c, "read", size=no_preview_icon, color=@sf.theme().p.muted) |> ignore
        c.text(@sf.t(if unreached { "web-main.file.loadAgain" } else { "web-main.file.noPreview" }), style=no_preview_words)
        |> ignore
      })
      |> ignore
    } else {
      let stand_in = c.box(style=if key != "" || letterbox { image_fill } else { image_fill_waiting }, fn() {
        if letterbox {
          c.box(style=letterbox_room, fn() { c.box(style=@ui.style(w=Fixed(pw), h=Fixed(ph)), picture) |> ignore })
          |> ignore
        } else {
          picture()
        }
      })
      @sf.breathe(c, stand_in, share=breath)
    }
    // how far it has come, at its foot's end
    if asked {
      image_coming(c, "msg-coming/" + thumb, src.images.coming(id))
    }
  })
  // where it is and what it shows, for the preview to fly from and back into; hidden while the preview is its picture
  note_thumb(c, thumb, b, @sf.message_file_corner, picture=shows, letterbox~, list=list_of(here))
  c.look(b, @ui.look(alpha=thumb_shows(thumb)))
  // held by a finger for its menu: lifted over the menu's scrim (@sf.lift_over)
  @sf.lift_over(c, b, "file/" + thumb, @sf.lift_of(c, "file/" + thumb, false, file_held_open(open)), file_lift_scale)
  c.semantics(b, Button, id=open, label=@sf.t("web-main.file.view", args=[("name", a.name)]))
}

///|
/// How far a message's picture coming from its station has come (pengxiao, 2026-10-27: one that was slow showed only
/// its likeness, nothing telling it from one that was stuck): in its box's foot's end corner, concentric with it, a
/// pill on the video's shade with a ring of how much of it is here and that share in words (35%); its size not known, the spinner and the
/// bytes here so far; nothing heard yet, nothing (its stand-in breathing says it waits). Shown only once it has waited
/// 300 ms (fading in over 200), so one that comes at once never flashes it.
fn image_coming(c : @ui.Ctx, key : String, coming : (Double, Double?)?) -> Unit {
  let shown = @motion.animate(c, key, 1.0, spec=@motion.tween(coming_in_ms, ease=Linear, delay=coming_after_ms), from=0.0)
  if shown <= 0.0 || coming is None {
    return
  }
  c.layer(fn() {
    c.box(style=coming_room, fn() {
      let pill = c.box(style=coming_pill, fn() {
        match coming {
          Some((n, Some(total))) => {
            let part = dmin(1.0, n / total)
            @sf.progress_ring(c, coming_ring, part, @sf.white) |> ignore
            c.text("\{(part * 100.0).floor().to_int()}%", style=coming_words) |> ignore
          }
          Some((n, None)) => {
            @sf.spinner(c, size=coming_ring, ring=coming_track, arc=@sf.white) |> ignore
            c.text(@sf.file_size(n), style=coming_words) |> ignore
          }
          None => ()
        }
      })
      c.look(pill, @ui.look(alpha=shown))
    })
    |> ignore
  })
  |> ignore
}

///|
/// How long a picture waits before how far it has come shows, and how long that takes to fade in.
pub let coming_after_ms : Double = 300.0

///|
pub let coming_in_ms : Double = 200.0

///|
/// The pill's ring (14 across), or the spinner in its place on white at 25%.
let coming_ring : Double = 14.0

///|
/// The pill's height: its ring 1 from its top, foot and start, concentric with its end, and its words' line.
let coming_pill_h : Double = 16.0

///|
let coming_track : Int64 = 0xFFFFFF40L

///|
// kept across runs: a value (no field of it changes)
let coming_room : @ui.Style = @ui.style(
  w=Full,
  h=Full,
  // (concentric with the picture's corner, the ladder's: 8 in, the pill's ends were rounder than that corner left room
  // for, which the corners' check refused)
  p=@sf.capsule_fit_room(@sf.message_file_corner, coming_pill_h, 8.0),
  align=AEnd,
  justify=JEnd,
)

///|
// kept across runs: a value (no field of it changes)
let coming_pill : @ui.Style = @ui.style(
  row=true,
  h=Fixed(coming_pill_h),
  gap=S1,
  pl=@sf.room_of((coming_pill_h - coming_ring) / 2.0),
  pr=S2,
  radius=Full,
  bg=@sf.video_shade,
  align=ACenter,
)


///|
// kept across runs: a value (no field of it changes)
let coming_words : @ui.TextStyle = @ui.text_style(size=Caption, color=@sf.white_ink, wrap=false, tabular=true)

///|
/// How much larger a message's picture is lifted all the way, held for its menu.
let file_lift_scale : Double = 1.04

///|
/// An image's box (msgImage): `w` by `h`, rounded as a message's files are, the neutral ground while it waits (none
/// once it shows, nor round a letterboxed one: `shown`).
fn image_box_style(w : Double, h : Double, shown : Bool) -> @ui.Style {
  (if shown { image_frame } else { image_frame_waiting }).then(@ui.style(w=Fixed(w), h=Fixed(h)))
}

///|
/// A video (FileItem's video): its still on black (the frame the preview was left at, else the station's), its play
/// mark in its middle, its name at its foot over a dark band, how long it is at the band's end; while the core
/// downloads it, or brings it after everything else once opened and let go (fill.ts), how far there over a bar. Held or
/// right clicked, its menu: 引用; 加载 (brought onto this device by the core, whatever page shows, to play from here at
/// once), 停止加载 while it comes.
fn video_item(c : @ui.Ctx, src : Source, here : MessageHere, a : Attachment, w : Double, by~ : (String, String, String)?) -> Unit {

  let open = c.id("msg-file/" + @sfbase.file_key(a))
  let owner = owner_of(here, a)
  // (still going up: no station has it to play or ask its still of yet)
  let going_up = a.upload != "" && a.path == @sfbase.upload_path(a.upload)
  if c.clicked(open) && !going_up {
    open_file(here, a)
  }
  let name = stored_name(a.path)
  let coming = download_of(src, here.station, owner, name)
  // (being downloaded to be saved: it comes anyway, nothing to load or stop here)
  let load : Array[@sf.MenuItem?] = if going_up {
    []
  } else if flag(coming, "active") && flag(coming, "keep") {
    let id = text(coming, "id")
    [Some(@sf.menu_item_of(@sf.t("web-main.file.stopLoading"), fn() { download_cancel(src, id) }, icon="stop"))]
  } else if flag(coming, "active") {
    []
  } else {
    let (station, size) = (here.station, a.size)
    // (where it was asked: its chat and the file, as its viewer would say it, the list leading back here)
    let from : Map[String, Json] = { "session": Json::string(here.session), "file": attachment_json(a, a.owner) }
    match here.view.thread {
      Some(n) => from["thread"] = Json::number(n)
      None => ()
    }
    [
      Some(
        @sf.menu_item_of(@sf.t("web-main.file.load"), fn() { download_start(src, station, owner, name, size, keep=true, from=Json::object(from)) }, icon="download"),
      ),
    ]
  }
  file_menu(c, open, "", quote=quote_of(here, a, owner, by), more=load)
  @sf.tip(c, "msg-file/" + @sfbase.file_key(a), open, a.name)
  let (bw, bh, letterbox) = image_box(a, video_least)
  let h = bh * w / bw
  let thumb = here.station + "/" + owner + "/" + a.path
  // (going up: the picture this device has of it, else its play mark on black alone)
  let still = if going_up { sent_picture(here.station, a).unwrap_or("") } else { video_still(c, src, here.station, owner, a, thumb) }
  // its still kept on the device and not decoded yet: what the app's first page waits for
  if a.held && (still == "" || (still != "!" && !c.image_ready(still, reveal_px(c, w, h)))) {
    @sfbase.held_pictures_waiting.val = true
  }
  let dl = download_of(src, here.station, owner, stored_name(a.path))
  // (downloading, else opened and let go, being brought after everything else: fill.ts)
  let kept = if flag(dl, "active") { None } else { keeping_of(src, here.station, owner, stored_name(a.path)) }
  let dl = if kept is Some(_) { kept } else { dl }
  let b = c.box(style=video_frame.then(@ui.style(w=Fixed(w), h=Fixed(h))), id=open, fn() {
    if still != "" && still != "!" {
      c.layer(fn() {
        c.image(still, w=Px(w), h=Px(h), fit=if letterbox { FitContain } else { FitCover }, bg=0L)
        |> ignore
      })
      |> ignore
    }
    c.box(style=video_middle, fn() {
      @sf.play_mark(c, video_play_side, @sf.video_shade) |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.box(style=video_foot_room, fn() {
        c.box(style=video_name_band, fn() {
          let coming = flag(dl, "active") || kept is Some(_)
          if coming {
            c.text(text(dl, "statusText"), style=video_name) |> ignore
            c.box(style=video_bar, fn() { @sf.progress(c, "video/" + a.path, Some(number(dl, "progress"))) }) |> ignore
          } else {
            // its name, cut short before how long it is (as its message says: the station read it from its header)
            c.box(style=video_name_row, fn() {
              c.text(a.name, style=video_name.then(@ui.text_style(w=Cut))) |> ignore
              if a.duration > 0.0 {
                c.text(@sf.clock(a.duration), style=video_name) |> ignore
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // where it is and what it shows, for the preview to fly from and back into; hidden while the preview is its picture
  note_thumb(c, thumb, b, @sf.message_file_corner, picture=if still == "!" { "" } else { still }, letterbox~, list=list_of(here))
  c.look(b, @ui.look(alpha=thumb_shows(thumb)))
  // held by a finger for its menu: lifted over the menu's scrim (@sf.lift_over)
  @sf.lift_over(c, b, "file/" + thumb, @sf.lift_of(c, "file/" + thumb, false, file_held_open(open)), file_lift_scale)
  c.semantics(b, Button, id=open, label=@sf.t("web-main.file.play", args=[("name", a.name)]))
}

///|
/// Any other file as a card (MessageFileCard): pressed, the preview; while the core downloads it, or brings it after
/// everything else once opened and let go (fill.ts), how far in its size's place, ✕ at its end to call it off; failed, why, ↻ to ask it again. Held or right clicked, its menu (引用).
fn card_item(c : @ui.Ctx, src : Source, here : MessageHere, a : Attachment, by~ : (String, String, String)?) -> Unit {
  let owner = owner_of(here, a)
  let dl = download_of(src, here.station, owner, stored_name(a.path))
  // opened and let go, being brought after everything else (fill.ts): how far in its size's place, ✕ stops it
  let kept = if flag(dl, "active") { None } else { keeping_of(src, here.station, owner, stored_name(a.path)) }
  let dl = if kept is Some(_) { kept } else { dl }
  let active = flag(dl, "active") || kept is Some(_)
  let failed = text(dl, "state") == "failed"
  let key = "msg-card/" + @sfbase.file_key(a)
  file_menu(c, c.id(key), "", quote=quote_of(here, a, owner, by))
  let done = @sf.file_card(
    c,
    key,
    a.name,
    a.size,
    path=a.path,
    error=if failed && !active { text(dl, "statusText") } else { "" },
    download=if active { Some((number(dl, "progress"), text(dl, "statusText"))) } else { None },
    remove=active,
    retry=failed && !active,
    open=true,
    remove_label=if kept is Some(_) { @sf.t("web-pages.files.stopKeeping") } else { @sf.t("web-main.file.cancelDownload") },
    retry_label=@sf.t("web-main.file.retryDownload"),
  )
  let id = text(dl, "id")
  if done.removed {
    c.tell(key + "/cancel", fn() { if kept is Some(_) { keeping_stop(src, id) } else { download_cancel(src, id) } })
  } else if done.retried {
    c.tell(key + "/retry", fn() { download_retry(src, id) })
  } else if done.opened {
    open_file(here, a)
  }
}

///|
/// How many pixels a message's picture `w` by `h` is decoded to on its longer side: the size it is drawn at
/// (Ctx::image's).
fn reveal_px(c : @ui.Ctx, w : Double, h : Double) -> Double {
  dmin(dmax(w, h) * c.scale, image_px_most)
}

///|
/// A message's image coming in, as the web's (msgImageWait, msgImageReveal): until it is decoded what it waits on (its
/// likeness, the ThumbHash sent with it, else the neutral ground); once it is, brushed in from its top (an edge half its
/// height deep going down it), blurred to sharp and from 1.04 its size to its own (1100 ms, the ease out), what it
/// waited on fading out behind it (300 ms, from 800). One already decoded as it is first shown, or one the device had
/// (`held`: kept here, not brought from its station, a decode away), comes as it is.
pub fn image_reveal(
  c : @ui.Ctx,
  key : String,
  w : Double,
  h : Double,
  fit : @ui.Fit,
  hash : String,
  radius? : Double = @sf.message_file_corner,
  held? : Bool = false,
) -> Unit {
  let ready = c.image_ready(key, reveal_px(c, w, h))
  let way = match reveals.get(key) {
    Some(a) => a
    None => {
      let a = if ready || held { None } else { Some(@motion.Anim::new(0.0)) }
      reveals[key] = a
      a
    }
  }
  // its way in, said once as it is first seen decoded
  let p = match way {
    Some(a) if ready => {
      if a.target() == 0.0 {
        a.animate(1.0, @motion.tween(reveal_ms, ease=Linear))
      }
      a.get()
    }
    Some(_) => 0.0
    None => 1.0
  }
  let e = @ui.Out.at(p)
  let img = c.image(key, w=Px(w), h=Px(h), fit~, radius~, bg=0L, fade=false)
  if p >= 1.0 {
    return
  }
  c.look(img, @ui.look(alpha=if ready { 1.0 } else { 0.0 }, scale=1.0 + reveal_grow * (1.0 - e)))
  // blurred to sharp: a frost over it and what it waits on, its blur going
  let frost = fn() {
    let blur = reveal_blur * (1.0 - e)
    if ready && blur > reveal_blur_least {
      c.layer(fn() { c.box(style=reveal_frost, glass=@ui.Glass::frosted(blur~, tint=0L, solid=0L), fn() {  }) |> ignore })
      |> ignore
    }
  }
  // what it waits on, under the edge brushing down (its band in steps), fading out from 800 ms
  let waited = if ready {
    1.0 - dmin(1.0, dmax(0.0, (p * reveal_ms - reveal_wait_after_ms) / reveal_wait_out_ms))
  } else {
    1.0
  }
  if waited <= 0.0 {
    frost()
    return
  }
  let likeness = @gallery.thumbhash_image(hash)
  // (each step on the screen's pixels: one meets the next with no seam)
  let px_of = fn(y : Double) { (y * c.scale).round() / c.scale }
  let wait = fn(y0 : Double, y1 : Double, alpha : Double) {
    let y0 = px_of(dmax(0.0, y0))
    let y1 = px_of(dmin(h, y1))
    if y1 <= y0 || alpha <= 0.0 {
      return
    }
    // (each laid out from the picture's top, as a layer is: not under the one before)
    c.layer(fn() {
      if y0 > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(y0)), fn() {  }) |> ignore
      }
      let strip = c.box(style=@ui.style(w=Full, h=Fixed(y1 - y0), clip=true), fn() {
        let inner = match likeness {
          Some(l) => c.image(l, w=Px(w), h=Px(h), fit=FitCover, bg=0L, fade=false)
          None => c.box(style=reveal_ground.then(@ui.style(w=Fixed(w), h=Fixed(h))), fn() {  })
        }
        c.look(inner, @ui.look(dy=-y0))
      })
      c.look(strip, @ui.look(alpha=alpha * waited))
    })
    |> ignore
  }
  c.layer(fn() {
    if !ready {
      // (not decoded yet: all of it)
      wait(0.0, h, 1.0)
    } else {
      // the edge: half its height deep, from above it to past its foot
      let band = h * 0.5
      let top = -band + (h + band) * e
      let step = band / reveal_steps.to_double()
      for k in 0..<reveal_steps {
        let y = top + k.to_double() * step
        wait(y, y + step, (k.to_double() + 0.5) / reveal_steps.to_double())
      }
      wait(top + band, h, 1.0)
    }
  })
  |> ignore
  frost()
}

///|
/// Each image's way in, by its source, while the run lasts (None: first shown decoded, as it is).
let reveals : Map[String, @motion.Anim?] = {}

///|
/// What the messages keep of their own, let go (the package's reset).
fn message_reset() -> Unit {
  reveals.clear()
  notices_open.clear()
}

///|
/// How long an image comes in, how blurred and how much larger it starts (a blur under a quarter is none), and when
/// and how fast what it waited on goes; its edge's steps.
pub let reveal_ms : Double = 1100.0

///|
let reveal_blur : Double = 14.0

///|
let reveal_blur_least : Double = 0.25

///|
let reveal_grow : Double = 0.04

///|
let reveal_wait_after_ms : Double = 800.0

///|
let reveal_wait_out_ms : Double = 300.0

///|
let reveal_steps : Int = 16

///|
/// An image decoded at most this many pixels on its longer side.
let image_px_most : Double = 8192.0

///|
/// The least an image's box is across (16) and a video's (96: its play mark and its name); the box of one sent before
/// sizes were kept (240×160); the most (360×300); a tiny one drawn to 40 on its longer side (imageBox.ts).
pub let image_least : Double = 16.0

///|
pub let video_least : Double = 96.0

///|
let box_unknown_w : Double = 240.0

///|
let box_unknown_h : Double = 160.0

///|
let box_most_w : Double = 360.0

///|
let box_most_h : Double = 300.0

///|
let box_tiny : Double = 40.0

///|
/// Files 6 apart (msgFiles gap).
let files_gap : Double = 6.0

///|
/// An unavailable image's mark (20).
let no_preview_icon : Double = 20.0

///|
/// A video's play mark, 40 round.
let video_play_side : Double = 40.0

///|
// kept across runs: a value (no field of it changes)
let files_column : @ui.Style = @ui.css("w=Full gap=S1_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let files_column_end : @ui.Style = @ui.css("w=Full gap=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let files_row : @ui.Style = @ui.css("row gap=S1_5 align=AStart")

///|
/// An image's box (msgImage): clipped to its corners (in a corner of what holds it, a quote's card, concentric with
/// that one); the neutral ground while it waits.
// kept across runs: a value (no field of it changes)
let image_frame : @ui.Style = @ui.style(radius=InnerOr(@sf.message_file_radius), clip=true)

///|
// kept across runs: a value (no field of it changes)
let image_frame_waiting : @ui.Style = image_frame.then(@ui.css("bg=Neutral"))

///|
/// What stands in an image's box for it (image_item): the whole box, breathing while it is asked of its station; the
/// neutral ground under it while it waits (image_fill_waiting).
// kept across runs: a value (no field of it changes)
let image_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let image_fill_waiting : @ui.Style = image_fill.then(@ui.css("bg=Neutral"))

///|
/// Where a letterboxed picture is (msgImage[data-letterbox]): in its box's middle.
// kept across runs: a value (no field of it changes)
let letterbox_room : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// One that cannot be had (msgImageUnavailable): its mark over 无法预览, muted, in its middle.
// kept across runs: a value (no field of it changes)
let no_preview_box : @ui.Style = @ui.css("w=Full h=Full gap=S1_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let no_preview_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A video's box (msgVideo): black, clipped to its corners; its play mark 40 round in its middle on black at 65%
/// (msgVideoPlay); its name at its foot 6 by 8 in on the same (msgVideoName), 12, white, cut short; a bar 4 under it.
// kept across runs: a value (no field of it changes)
let video_frame : @ui.Style = @ui.style(radius=InnerOr(@sf.message_file_radius), clip=true, bg=@sf.video_ground)

///|
// kept across runs: a value (no field of it changes)
let video_middle : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let video_foot_room : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let video_name_band : @ui.Style = @ui.style(w=Full, px=S2, py=S1_5, bg=@sf.video_shade)

///|
// kept across runs: a value (no field of it changes)
let video_name : @ui.TextStyle = @ui.text_style(size=Caption, color=@sf.white_ink, wrap=false, max_lines=1)

///|
/// Its name and how long it is in one line, 8 apart, the length at its end.
// kept across runs: a value (no field of it changes)
let video_name_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let video_bar : @ui.Style = @ui.css("w=Full pt=S1")

///|
/// What an image waits on with no likeness (msgImageWait): the neutral ground; the frost over it on its way in.
// kept across runs: a value (no field of it changes)
let reveal_ground : @ui.Style = @ui.css("bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let reveal_frost : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The chat's list a message's file is in (its key: @sfbase.note_list), "" out of one.
fn list_of(here : MessageHere) -> String {
  match here.list {
    Some(l) => l.rk
    None => ""
  }
}
