// A message's files as nodes of the window's tree (message_files.mbt's message_files and card_item): laid in rows by
// the width the message is given, a row going on in the next where it has not the room; each file its own, any other
// than a picture or a video as its card, its download's state as the core says it, its menu where it is held or right
// clicked; a picture or a video in the box its data says (message_media_node.mbt).

///|
/// Where a message's file is shown, as it is now: its chat's station and session, and its view (whose session keeps a
/// file the core names none for: its first agent's).
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-struct_never_constructed")
priv struct MessageFilesAt {
  station : () -> String
  session : () -> String
  view : () -> ChatView
  /// its message's `said` as it changes: said while the chat shows (its pictures brushed in only then)
  said : () -> Bool
}

///|
/// The same as a MessageHere out of a list (what the file's own actions take: opening it, quoting it, downloading it),
/// as it is when asked.
fn MessageFilesAt::here(self : MessageFilesAt) -> MessageHere {
  {
    station: (self.station)(),
    session: (self.session)(),
    view: (self.view)(),
    go: None,
    inline: false,
    gutter: 0.0,
    list: None,
    core: None,
  }
}

///|
/// A message's files in `parent` (message_files'), `list` as it is now, at the column's end where they are the viewer's
/// (`mine`): in rows by the width given, 6 apart along a row and between rows, a picture's and a video's box their data's
/// at most that width, a card as wide as what it says (236 at most, that width at most). `by`: whose message they are
/// (author, role, ts), for 引用 in their menus; `place` says where they are shown, `at` names where they are (thumb_occurrence's);
/// `over`: the room over them (message_files').
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn message_files_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  place : MessageFilesAt,
  list : () -> Array[Attachment],
  mine : () -> Bool,
  by : () -> (String, String, String)?,
  at : String,
  over? : () -> Double = fn() { 0.0 },
) -> Unit {
  parent.show(fn() { list().length() > 0 }, fn(s) {
    s.by_room(fn(r, room) {
      r.box(fn(files) {
        @sf.style_node(files, fn() {
          let wrap = if mine() { files_wrap_end } else { files_wrap }
          let o = over()
          if o > 0.0 { wrap.then(@ui.style(pt=@sf.room_of(o))) } else { wrap }
        })
        files.wraps(Is(Some(files_gap))) |> ignore
        let keys = fn() { list().map(fn(a) { @sfbase.file_key(a) }) }
        files.each(keys, fn(k) { k }, fn(slot, k) {
          // (its key read through what it is given, never kept: a block may be taken to show another key)
          let a = fn() {
            let key = k.get()
            match list().iter().find_first(fn(x) { @sfbase.file_key(x) == key }) {
              Some(x) => x
              None => attachment_of({ "name": Json::string(""), "path": Json::string(key) })
            }
          }
          slot.box(fn(item) {
            item.max_width(By(fn() { Some(room.width()) })).shrink(Is(0.0)) |> ignore
            item.pick(fn() { file_kind(a().name) }, fn(p, kind) {
              match kind {
                "image" =>
                  // (its box as its data says it, at most the width given; made again only for another size, as
                  // the width given or its data changes: a block given another picture of its size keeps its nodes)
                  p.pick(at_once=true, fn() { media_size(a(), image_least, image_min_side, room.width()) }, fn(q, size) {
                    message_image_node(q, src, place, a, by, at, size.0, size.1)
                  })
                  |> ignore
                "video" =>
                  // (made anew for another file, or another size: its still is read for the file it is made for)
                  p.pick(
                    at_once=true,
                    fn() { (@sfbase.file_key(a()), media_size(a(), video_least, 0.0, room.width())) },
                    fn(q, made) { message_video_node(q, src, tips, place, a, by, at, made.1.0, made.1.1) },
                  )
                  |> ignore
                _ => message_file_card_node(p, src, tips, place, a, by, at) |> ignore
              }
            })
          })
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A picture's or a video's box in a message (image_box's, `least` thick, `side` its least where it is cut), at most
/// `room` wide: (width, height).
fn media_size(a : Attachment, least : Double, side : Double, room : Double) -> (Double, Double) {
  let (bw, bh, _) = image_box(a, least, min_side=side)
  let w = dmin(bw, room)
  (w, bh * w / bw)
}

///|
/// Any other file of a message as its card (card_item's): pressed, the preview; while the core downloads it, or brings
/// it after everything else once opened and let go, how far in its size's place, ✕ to call it off; failed, why, ↻ to
/// ask it again. Held or right clicked, its menu (引用, 在侧边打开, 下载) where.
fn message_file_card_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  place : MessageFilesAt,
  a : () -> Attachment,
  by : () -> (String, String, String)?,
  at : String,
) -> @view.View {
  // (what the core says of its download, and of its being brought once opened and let go: kept)
  let coming = fn() { card_coming(src, place.here(), a()) }
  let active = fn() {
    let (dl, kept) = coming()
    flag(dl, "active") || kept is Some(_)
  }
  let failed = fn() { text(coming().0, "state") == "failed" && !active() }
  @sf.file_card_node(
    parent,
    tips,
    fn() { a().name },
    fn() {
      if failed() || active() {
        text(coming().0, "statusText")
      } else {
        @sf.file_size(a().size)
      }
    },
    failed,
    failed,
    active,
    fn() { @sf.t("web-main.file.retryDownload") },
    fn() {
      if coming().1 is Some(_) {
        @sf.t("web-pages.files.stopKeeping")
      } else {
        @sf.t("web-main.file.cancelDownload")
      }
    },
    fn(on) {
      let here = place.here()
      let a = a()
      let (dl, kept) = card_coming(src, here, a)
      let id = text(dl, "id")
      match on {
        Remove => if kept is Some(_) { keeping_stop(src, id) } else { download_cancel(src, id) }
        Retry => download_retry(src, id)
        Open => open_file(here, a, at~)
        Restore => ()
      }
    },
    menu=fn(x, y) {
      let here = place.here()
      let a = a()
      let owner = owner_of(here, a)
      let items : Array[@sf.MenuItem?] = []
      match quote_of(here, a, owner, by()) {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      items.push(beside_option(here, a, at))
      items.push(download_option(src, here, a, owner))
      @sf.menu(items, from=@sf.at_point(x, y))
    },
  )
}

///|
/// A message's files laid along rows (files_column and files_row as one): 6 apart along a row, the rows 6 apart; the
/// viewer's at the column's end.
// kept across runs: a value (no field of it changes)
let files_wrap : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let files_wrap_end : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart justify=JEnd")
