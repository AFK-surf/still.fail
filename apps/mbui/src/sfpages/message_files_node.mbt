// A message's files (message_files.mbt's message_files) as nodes of the window's tree, made once: each by its key in
// rows that wrap as the column's width does, 6 apart (at the column's end, the viewer's own); an image in its box on
// the neutral ground till it shows, a video's still on black with its play mark and length, any other file as its
// card. Each said where what is sent to it lands (`landed`: @sfbase.FileLandingNode, what flies there drawn as it is).

///|
/// Files `list` (as they are now) of a message in `col`, as wide as the column at most; `mine` the viewer's own;
/// `by` whose and when (what quoting one says), `at` where in the chat it is (its preview's place); `landed` told each
/// one's landing by its key as it is made and let go; `corner` its pictures' (a quote's own: @sf.quote_picture_corner);
/// `by` whose message it is, their role and its ts (what quoting one of them says; none: not quoted from here); `most`
/// how wide they may be where what holds them is as wide as they are (a quote's card: none, the column's).
fn message_files_node(
  col : @view.View,
  src : Source,
  here : () -> MessageHere,
  list : () -> Array[Attachment],
  mine : Bool,
  at? : () -> String = fn() { "" },
  landed? : (String, @sfbase.FileLandingNode?) -> Unit = fn(_, _) {  },
  corner? : Double = @sf.message_file_corner,
  by? : () -> (String, String, String)? = fn() { None },
  most? : () -> Double? = fn() { None },
) -> Unit {
  col.box(fn(flow) {
    flow
    .row(Is(true))
    .gap(Is(files_gap))
    .wraps(Is(Some(files_gap)))
    .lies_along(Is(if mine { End } else { Start }))
    .lines_up(Is(Some(Start)))
    |> ignore
    // (the column's width as laid out, the pane's till it is)
    let room = fn() {
      match most() {
        Some(w) => w
        None =>
          match flow.laid_size_told() {
            Some((w, _)) if w > 0.0 => w
            _ => flow.window().0
          }
      }
    }
    flow.each(fn() { list().map(fn(a) { @sfbase.file_key(a) }) }, fn(k) { k }, fn(item, k) {
      let key = @signals.untracked(fn() { k.get() })
      // (as it is now; as it last was while it goes)
      let last : Ref[Attachment?] = Ref(None)
      let a = fn() {
        match list().iter().find_first(fn(x) { @sfbase.file_key(x) == key }) {
          Some(x) => {
            last.val = Some(x)
            x
          }
          None => last.val.unwrap()
        }
      }
      let kind = @signals.untracked(fn() { file_kind(a().name) })
      match kind {
        "image" | "video" => {
          let landing = media_file_node(item, src, here, a, kind, room, at, corner, by)
          landed(key, Some(landing))
        }
        _ => {
          let landing = card_file_node(item, src, here, a, room, at, by)
          landed(key, Some(landing))
        }
      }
      item.owns(fn() { landed(key, None) }) |> ignore
    })
  })
  |> ignore
}

///|
/// An image or a video of a message (image_item's, video_item's) in `item`: its box as wide as image_box says, the
/// column's at most; what it shows by message_media's picture of it; pressed, the preview (one that could not be had for
/// want of its station asked again); where the preview flies from and back into (note_thumb_node), hidden while the
/// preview is its picture. Its landing.
fn media_file_node(
  item : @view.View,
  src : Source,
  here : () -> MessageHere,
  a : () -> Attachment,
  kind : String,
  room : () -> Double,
  at : () -> String,
  corner : Double,
  by : () -> (String, String, String)?,
  fills? : Bool = false,
) -> @sfbase.FileLandingNode {
  let least = if kind == "image" { image_least } else { video_least }
  let side = if kind == "image" { image_min_side } else { 0.0 }
  let boxed = fn() { image_box(a(), least, min_side=side) }
  // (`fills`: as wide as its room, a row of the images its message places, each as high as the others)
  let w = fn() { if fills { room() } else { dmin(boxed().0, room()) } }
  let h = fn() {
    let (bw, bh, _) = boxed()
    bh * w() / bw
  }
  let letterbox = fn() { boxed().2 }
  let share = fn() { picture_share(a(), least, min_side=side) }
  let top_crop = fn() { kind == "image" && tall_image_cropped(a()) }
  let owner = fn() { owner_of(here(), a()) }
  let picture = fn() { message_media(@ui.current(), src, here().station, owner(), a()) }
  let fit = fn() -> @ui.Fit {
    if kind == "video" {
      if letterbox() { FitContain } else { FitCover }
    } else if top_crop() {
      FitCoverAt(0.0)
    } else {
      FitCover
    }
  }
  let thumb = fn() {
    let h = here()
    @sfbase.thumb_place(h.station + "/" + owner() + "/" + a().path, h.station, h.session, at())
  }
  let view = item.box(fn(b) {
    b
    .width(By(fn() { Some(w()) }))
    .height(By(fn() { Some(h()) }))
    .radius(Is(corner))
    .clips(Is(true))
    .ground(By(fn() {
      // Video content owns its black matte and waiting ground, under this one clip as in video_item.
      if kind == "image" && picture().key == "" && !letterbox() {
        @ui.tree_theme().color(Neutral)
      } else {
        0L
      }
    }))
    .alpha(By(fn() { @sfbase.thumb_shows(thumb()) }))
    .drawn_as(By(fn() { a().name }))
    .says(By(fn() {
      Some(
        @view.said(Button, label=@sf.t(if kind == "video" { "web-main.file.play" } else { "web-main.file.view" }, args=[("name", a().name)])),
      )
    }))
    |> ignore
    // (held or right clicked, its menu: 引用 where it is a message's, 下载, 复制图片 (file_menu's))
    @sf.presses_node(b, fn() {
      let p = @signals.untracked(picture)
      let now = here()
      if p.unreached {
        src.images.again(now.station)
      } else if !(kind == "video" && a().upload != "" && a().path == @sfbase.upload_path(a().upload)) {
        open_file(now, a(), at=at())
      }
    }, menu=fn(x, y) {
      let now = here()
      let key = if kind == "image" { @signals.untracked(picture).key } else { "" }
      menu_doing.offered = key
      let items : Array[@sf.MenuItem?] = []
      match quote_of(now, a(), owner(), by()) {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      items.push(download_option(src, now, a(), owner()))
      if kind == "video" { items.append(video_load_options(src, now, a(), owner())) }
      if key != "" && key != "!" {
        items.push(Some(@sf.menu_item_of(@sf.t("desktop.contextMenu.copyImage"), fn() { copy_menu_image(key) }, icon="copy")))
      }
      @sf.menu(items, from=@sf.at_point(x, y))
    })
    // (a letterboxed one's picture its own proportions in the box's middle, the box's ground round it)
    b.box(fn(room) {
      room
      .width(By(fn() { Some(w()) }))
      .height(By(fn() { Some(h()) }))
      .lies_along(Is(Middle))
      .lines_up(Is(Some(Middle)))
      |> ignore
      let (pw, ph) = if kind == "image" {
        (fn() { w() * share().0 }, fn() { h() * share().1 })
      } else {
        (w, h)
      }
      // (none of it drawn while the viewer has its picture, flying from it or back into it: note_thumb's hidden)
      room.show(fn() { @sfbase.thumb_shows(thumb()) > 0.0 }, fn(m) { media_fitted_node(m, picture, pw, ph, fit, fn() { 0.0 }) })
    })
    |> ignore
    if kind == "video" {
      @sf.video_capsule_node(b, fn() { a().duration }, corner~, coming=fn() {
        let (dl, kept) = card_coming(src, here(), a())
        if flag(dl, "active") || kept is Some(_) { Some(number(dl, "progress")) } else { None }
      })
    }
    // how far it has come, at its foot's end: downloaded by the viewer, or asked of its station and not here yet
    if kind == "image" {
      image_coming_node(b, fn() {
        let now = here()
        let dl = @sfbase.download_of(src, now.station, owner(), stored_name(a().path))
        if flag(dl, "active") {
          let total = number(dl, "size")
          Some((number(dl, "loaded"), if total > 0.0 { Some(total) } else { None }))
        } else {
          let p = picture()
          let going_up = !p.sent && a().upload != "" && a().path == @sfbase.upload_path(a().upload)
          if p.key == "" && !going_up {
            src.images.coming(@sfbase.file_image_id(now.station, owner(), stored_name(a().path)))
          } else {
            None
          }
        }
      }, corner)
    }
    @sfbase.note_thumb_node(
      b,
      @signals.untracked(thumb),
      fn() { corner },
      fn() {
        let p = picture()
        if p.key == "!" { "" } else { p.key }
      },
      letterbox~,
      top_crop~,
      list=@signals.untracked(fn() { list_of(here()) }),
    )
  })
  {
    view,
    share,
    top_crop,
    copy: fn(v, cw, ch, cfit, cradius) { media_fitted_node(v, picture, cw, ch, cfit, cradius) },
  }
}

///|
/// Any other file of a message as its card (card_item's, the library's file_card_node): pressed, the preview; while the
/// core downloads it, or brings it after everything else once opened and let go, how far in its size's place, ✕ to call
/// it off; failed, why, ↻ to ask it again. Its landing.
fn card_file_node(
  item : @view.View,
  src : Source,
  here : () -> MessageHere,
  a : () -> Attachment,
  room : () -> Double,
  at : () -> String,
  by : () -> (String, String, String)?,
) -> @sfbase.FileLandingNode {
  let coming = fn() { card_coming(src, here(), a()) }
  let active = fn() {
    let (dl, kept) = coming()
    flag(dl, "active") || kept is Some(_)
  }
  let failed = fn() { text(coming().0, "state") == "failed" }
  let info = fn() {
    let (dl, _) = coming()
    let f = a()
    @sf.file_card_info(
      f.name,
      f.size,
      path=f.path,
      error=if failed() && !active() { text(dl, "statusText") } else { "" },
      download=if active() { Some((number(dl, "progress"), text(dl, "statusText"))) } else { None },
    )
  }
  let id = fn() { text(coming().0, "id") }
  item.max_width(By(fn() { Some(room()) })) |> ignore
  let view = @sf.file_card_node(
    item,
    info,
    open=fn() { open_file(here(), a(), at=at()) },
    remove=fn() { if coming().1 is Some(_) { keeping_stop(src, id()) } else { download_cancel(src, id()) } },
    remove_shown=active,
    remove_label=fn() {
      if coming().1 is Some(_) { @sf.t("web-pages.files.stopKeeping") } else { @sf.t("web-main.file.cancelDownload") }
    },
    retry=fn() { download_retry(src, id()) },
    retry_shown=fn() { failed() && !active() },
    retry_label=fn() { @sf.t("web-main.file.retryDownload") },
  )
  @sf.presses_node(view, fn() { open_file(here(), a(), at=at()) }, menu=fn(x, y) {
    let now = here()
    let owner = owner_of(now, a())
    let items : Array[@sf.MenuItem?] = []
    match quote_of(now, a(), owner, by()) {
      Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
      None => ()
    }
    items.push(download_option(src, now, a(), owner))
    menu_doing.offered = ""
    @sf.menu(items, from=@sf.at_point(x, y))
  })
  {
    view,
    share: fn() { (1.0, 1.0) },
    top_crop: fn() { false },
    copy: fn(v, _, _, _, _) { @sf.file_card_node(v, info, floating=true) |> ignore },
  }
}

///|
/// How far a message's picture coming has come (image_coming's) over its box `b`, `coming` as it is now: in the box's
/// foot's end corner, concentric with it, a pill on the video's shade with a ring of how much of it is here and that
/// share in words; its size not known, the spinner and the bytes here so far; nothing heard yet, nothing. Shown only
/// once it has waited coming_after_ms, fading in over coming_in_ms, so one that comes at once never flashes it.
fn image_coming_node(b : @view.View, coming : () -> (Double, Double?)?, corner : Double) -> Unit {
  b.show(fn() { coming() is Some(_) }, fn(room) {
    let inset = if corner == @sf.message_file_corner {
      coming_in
    } else {
      @sf.capsule_fit(corner, coming_pill_h, coming_alone_in)
    }
    let shown = @motion.Way::new(0.0)
    room.reacts(fn() { () }, fn(_) {
      shown.go(1.0, @motion.tween(coming_in_ms, ease=Linear, delay=coming_after_ms), at=room.cause_at())
    })
    room
    .over(Is(true))
    .padding(Is((inset, inset, inset, inset)))
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .alpha(By(fn() { way_shown(shown, room) }))
    |> ignore
    room.box(fn(pill) {
      pill
      .row(Is(true))
      .height(Is(Some(coming_pill_h)))
      .gap(Is(@ui.Space::px(S1)))
      .padding(Is((coming_ring_in, 0.0, @ui.Space::px(S2), 0.0)))
      .radius(Is(coming_pill_h / 2.0))
      .ground(By(fn() { @ui.tree_theme().color(@sf.video_shade) }))
      .lines_up(Is(Some(Middle)))
      |> ignore
      let sized = fn() { coming().map(fn(c) { c.1 is Some(_) }).unwrap_or(false) }
      pill.pick(sized, fn(r, known) {
        if known {
          r.box(fn(ring) {
            ring
            .width(Is(Some(coming_ring)))
            .height(Is(Some(coming_ring)))
            .shapes(By(fn() {
              let part = match coming() {
                Some((n, Some(total))) => dmin(1.0, n / total)
                _ => 0.0
              }
              @sf.ring_shapes(coming_ring, part, @sf.white)
            }))
            |> ignore
          })
          |> ignore
        } else {
          @sf.spinner_node(r, size=coming_ring, ring=fn() { coming_track }, arc=fn() { @sf.white }) |> ignore
        }
      })
      @sf.words_node(pill, fn() {
        match coming() {
          Some((n, Some(total))) => "\{(dmin(1.0, n / total) * 100.0).floor().to_int()}%"
          Some((n, None)) => @sf.file_size(n)
          None => ""
        }
      }, fn() { coming_words })
      |> ignore
    })
    |> ignore
  })
}
