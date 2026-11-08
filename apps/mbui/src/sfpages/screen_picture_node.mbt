// The screen's two decoded pictures: the whole frame and the sharper region
// requested while zoomed. The session owns the streams; the nodes own their display.

///|
priv struct ScreenPicture {
  whole : @ui.Stream?
  part : (@ui.Stream, Part)?
  rect : SRect
  faded : Bool
  layer : Bool
}

///|
fn screen_picture_node(parent : @view.View, read : () -> ScreenPicture) -> @view.View {
  parent.box(fn(v) {
    v.width(By(fn() { Some(read().rect.w) }))
    .height(By(fn() { Some(read().rect.h) }))
    .offset(By(fn() { let r = read().rect; (r.x, r.y) }))
    .alpha(By(fn() { if read().faded { 0.4 } else { 1.0 } })) |> ignore
    v.pick(fn() { read().whole.map(fn(s) { s.id() }) }, fn(p, id) {
      if id is Some(_) {
        match read().whole {
          Some(stream) =>
            @ui.stream_node(p, stream, layer=fn() { read().layer })
            .width(By(fn() { Some(read().rect.w) }))
            .height(By(fn() { Some(read().rect.h) })) |> ignore
          None => ()
        }
      }
    })
    v.pick(fn() { read().part.map(fn(p) { p.0.id() }) }, fn(p, id) {
      p.over(Is(true)) |> ignore
      if id is Some(_) {
        match read().part {
          Some((stream, _)) =>
            @ui.stream_node(p, stream, layer=fn() { read().layer }, content=fn() {
              let picture = read()
              picture.part.map(fn(part) {
                let crop = part.1
                (crop.x * picture.rect.w, crop.y * picture.rect.h,
                  crop.w * picture.rect.w, crop.h * picture.rect.h)
              })
            })
            .width(By(fn() { Some(read().rect.w) }))
            .height(By(fn() { Some(read().rect.h) })) |> ignore
          None => ()
        }
      }
    })
  })
}

///|
fn screen_stage_node(parent : @view.View, s : ScreenSess, u : ScreenUi, key : String) -> @view.View {
  let picture : @signals.Signal[ScreenPicture?] = @signals.signal(None, same=fn(a, b) {
    match (a, b) {
      (None, None) => true
      (Some(a), Some(b)) => a.rect == b.rect && a.faded == b.faded && a.layer == b.layer &&
        a.whole.map(fn(s) { s.id() }) == b.whole.map(fn(s) { s.id() }) &&
        a.part.map(fn(p) { (p.0.id(), p.1) }) == b.part.map(fn(p) { (p.0.id(), p.1) })
      _ => false
    }
  })
  parent.box(fn(v) {
    v.grow(Is(1.0)).basis(Is(Some(0.0))).clips(Is(true)) |> ignore
    v.pick(fn() { picture.get() is Some(_) }, fn(p, ready) {
      p.over(Is(true)) |> ignore
      if ready { screen_picture_node(p, fn() { picture.get().unwrap() }) |> ignore }
    })
    @ui.old(v, fn(c) {
      s.said.get() |> ignore
      screen_stage(c, s, u, key, picture=fn(value) { picture.set(value) })
    }).over(Is(true)) |> ignore
  })
}
