// A message's video as nodes of the window's tree (message_files.mbt's video_item): its still on black, its capsule,
// its menu (加载 / 停止加载 with the rest), lifted while a finger's hold has it up.

///|
/// A message's video `a` in `parent` (video_item's), `w` by `h`: its still on black (the frame the preview was left at,
/// one sent from here the picture it was picked as, else its station's: @sfbase.video_still_node), contained where it
/// is letterboxed, its capsule in its foot's start corner (how long it is). Pressed, the preview (not while it goes
/// up); right clicked, its menu where; held by a finger, its menu, the video lifted while it is up: 引用, 在侧边打开,
/// 下载, and 加载 (brought onto this device before everything else) or 停止加载 while it is brought. Its name whole in a
/// tip in `tips` while what it shows shows cut short (video_item's, repeats). Made for one file (its still is read for
/// it): another in its place is made anew. While the core downloads it, or brings it after all else (加载, or opened
/// and let go: fill.ts), how far on its capsule (video_item's).
fn message_video_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  place : MessageFilesAt,
  a : () -> Attachment,
  by : () -> (String, String, String)?,
  at : String,
  w : Double,
  h : Double,
  corner? : Double = @sf.message_file_corner,
) -> Unit {
  let station = fn() { (place.station)() }
  let owner = fn() { owner_of(place.here(), a()) }
  let going_up = fn() { a().upload != "" && a().path == @sfbase.upload_path(a().upload) }
  let letterbox = fn() { image_box(a(), video_least).2 }
  let thumb = fn() {
    @sfbase.thumb_place(station() + "/" + owner() + "/" + a().path, station(), (place.session)(), at)
  }
  let held_menu : @signals.Signal[Int?] = @signals.signal(None)
  parent.box(fn(f) {
    @sf.style_node(f, fn() { video_frame.then(@ui.style(w=Fixed(w), h=Fixed(h))).then(frame_corner_node(corner)) })
    f.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.file.play", args=[("name", a().name)]))) })) |> ignore
    // (its name, which nothing over its picture says, whole by it while what it shows shows cut short: video_item's tip)
    @sf.tip_node(tips, f, fn() { a().name }, repeats=true) |> ignore
    // its still: what the viewer left, one sent from here, its station's (going up: the picture this device has)
    let station_still = @signals.untracked(fn() {
      @sfbase.video_still_node(f, src, station(), owner(), a(), station() + "/" + owner() + "/" + a().path)
    })
    let still = fn() {
      if going_up() {
        @sfbase.sent_picture_told(station(), a()).unwrap_or("")
      } else {
        station_still()
      }
    }
    let open_menu = fn(x : Double, y : Double, finger : Bool) {
      let here = place.here()
      let a = a()
      let owner = owner_of(here, a)
      let name = stored_name(a.path)
      let items : Array[@sf.MenuItem?] = []
      match quote_of(here, a, owner, by()) {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      items.push(beside_option(here, a, at))
      items.push(download_option(src, here, a, owner))
      // (being downloaded to be saved, or going up: nothing to load or stop here)
      if !going_up() && !flag(download_of(src, here.station, owner, name), "active") {
        match keeping_of(src, here.station, owner, name) {
          Some(_) as brought => {
            let id = text(brought, "id")
            items.push(Some(@sf.menu_item_of(@sf.t("web-main.file.stopLoading"), fn() { keeping_stop(src, id) }, icon="stop")))
          }
          None => {
            let (station, size) = (here.station, a.size)
            let from : Map[String, Json] = { "session": Json::string(here.session), "file": attachment_json(a, a.owner) }
            match here.view.thread {
              Some(n) => from["thread"] = Json::number(n)
              None => ()
            }
            items.push(
              Some(
                @sf.menu_item_of(@sf.t("web-main.file.load"), fn() { fill_want(src, station, owner, name, size, Json::object(from)) }, icon="download"),
              ),
            )
          }
        }
      }
      @sf.menu(items, from=@sf.at_point(x, y))
      held_menu.set(if finger { Some(@sf.last_presented()) } else { None })
    }
    @sf.menu_presses_node(f, fn() { if !going_up() { open_file(place.here(), a(), at~) } }, open_menu)
    @sf.lift_node(
      f,
      fn() { false },
      fn() {
        match held_menu.get() {
          Some(s) => @sf.presented_drawn_of(s)
          None => false
        }
      },
      file_lift_scale,
    )
    f.shared(By(thumb), @motion.flight_by(@motion.moved()), stays=true) |> ignore
    // the black and its still drawn as one, its edge cut once (the black under a picture cut apart from it left a rim
    // at their rounded edge): the black round a letterboxed one (contained in its own proportions, in the middle) and
    // all of it while it is decoded
    let (sw, sh) = @signals.untracked(fn() { picture_share(a(), video_least) })
    let (pw, ph) = (w * sw, h * sh)
    f.box(fn(s) {
      s
      .width(Is(Some(w)))
      .height(Is(Some(h)))
      .image(By(fn() {
        let k = still()
        if k == "" || k == "!" {
          None
        } else {
          // (decoded as large as it is drawn, reveal_px's: asked so by what draws it, as it comes to it)
          let px = dmin(dmax(w, h) * s.pixel_scale(), image_px_most)
          Some((k, "", px.to_int()))
        }
      }))
      // (no still to show: the black alone)
      .ground(By(fn() {
        let k = still()
        if k == "" || k == "!" {
          @ui.tree_theme().color(@sf.video_ground)
        } else {
          0L
        }
      }))
      .image_covers(By(fn() { !letterbox() }))
      .image_in(By(fn() { Some((((w - pw) / 2.0, (h - ph) / 2.0, pw, ph), @ui.tree_theme().color(@sf.video_ground))) }))
      .image_fades(Is(true))
      |> ignore
    })
    |> ignore
    f.box(fn(o) {
      o.over(Is(true)).width(Is(Some(w))).height(Is(Some(h))) |> ignore
      // (downloading, else brought after all else: how far)
      let coming = fn() -> Double? {
        let name = stored_name(a().path)
        let dl = download_of(src, station(), owner(), name)
        if flag(dl, "active") {
          Some(number(dl, "progress"))
        } else {
          match keeping_of(src, station(), owner(), name) {
            Some(_) as kept => Some(number(kept, "progress"))
            None => None
          }
        }
      }
      @sf.video_capsule_node(o, a().duration, corner~, coming~)
    })
    |> ignore
  })
  |> ignore
}
