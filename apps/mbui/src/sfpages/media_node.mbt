// A file's picture (message_files.mbt's media_content, image_reveal) as nodes of the window's tree, made once: the
// same in a message, in a quote of it and in the composer's tiles, whatever holds it owning its controls and its cut.
// Which state it is in (a video's still or its ground, no preview, coming in, there, waited on) picks what it draws;
// its picture, its size and its corners followed as they change.

///|
/// What a picture shows (`p`), as media_content picks it: a video's still (1) or its black ground till it has one (2);
/// no preview (3); an image the core sends coming in (4); one sent from here, there at once (5); waited on in the
/// colours its ThumbHash makes (6) or on the neutral ground (7).
fn media_state(p : MediaPicture, w : Double, h : Double) -> Int {
  if p.kind == "video" {
    if p.key != "" && p.key != "!" { 1 } else { 2 }
  } else if p.key == "!" {
    3
  } else if p.key != "" && !p.sent {
    4
  } else if p.key != "" {
    5
  } else if image_wait_colours(p.hash, w, h) is Some(_) {
    6
  } else {
    7
  }
}

///|
/// A file's picture (media_content's, as nodes) in `parent`, `width` by `height` (each as it changes), fitted as `fit`
/// says, its corners `radius` round: a video's still on black, or black till it has one; no preview, said so (load it
/// again where its station could not be reached); an image coming in (image_reveal's); one sent from here at once; one
/// waited on, its likeness or the neutral ground. What it shows followed as `picture` changes.
fn media_content_node(
  parent : @view.View,
  picture : () -> MediaPicture,
  width : () -> Double,
  height : () -> Double,
  fit : @ui.Fit,
  radius : () -> Double,
) -> Unit {
  media_fitted_node(parent, picture, width, height, fn() { fit }, radius)
}

///|
/// A picture whose crop changes on a declared path: the same content, decode and reveal, with its current fit.
fn media_fitted_node(
  parent : @view.View,
  picture : () -> MediaPicture,
  width : () -> Double,
  height : () -> Double,
  fit : () -> @ui.Fit,
  radius : () -> Double,
) -> Unit {
  parent.box(fn(m) {
    m
    .width(By(fn() { Some(width()) }))
    .height(By(fn() { Some(height()) }))
    .radius(By(radius))
    |> ignore
    // (by its state, and one coming in by its picture too: another's way in its own, from its own decode)
    m.pick(fn() {
      let p = picture()
      let state = media_state(p, width(), height())
      (state, if state == 4 { p.key } else { "" })
    }, fn(s, which) {
      let state = which.0
      s.width(By(fn() { Some(width()) })).height(By(fn() { Some(height()) })).radius(By(radius)) |> ignore
      match state {
        1 => {
          s.ground(Is(0x000000FFL)) |> ignore
          media_image(s, fn() { picture().key }, width, height, fit, matte=Some(0x000000FFL))
        }
        2 => s.ground(Is(0x000000FFL)) |> ignore
        3 => {
          s.lies_along(Is(Middle)).lines_up(Is(Some(Middle))).gap(Is(6.0)) |> ignore
          @sf.icon_node(s, "read", no_preview_icon, By(fn() { @sf.theme().p.muted })) |> ignore
          @sf.words_node(
            s,
            fn() { @sf.t(if picture().unreached { "web-main.file.loadAgain" } else { "web-main.file.noPreview" }) },
            fn() { no_preview_words },
          )
          |> ignore
        }
        4 => media_reveal_node(s, picture, width, height, fit)
        5 => media_image(s, fn() { picture().key }, width, height, fit)
        6 =>
          s.image(By(fn() {
            image_wait_colours(picture().hash, width(), height()).map(fn(k) { (k, "", 64) })
          }))
          |> ignore
        _ => s.ground(By(fn() { @ui.tree_theme().color(Neutral) })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// Picture `key` filling `s` as `fit` says (FitCover: its middle, cut; FitContain: whole in its middle on `matte`;
/// else stretched to it), there at once as it is decoded, asked for at the pixels it is drawn at.
fn media_image(
  s : @view.View,
  key : () -> String,
  width : () -> Double,
  height : () -> Double,
  fit : () -> @ui.Fit,
  matte? : Int64? = None,
) -> Unit {
  s
  .image(By(fn() { Some((key(), "", image_px_most.to_int())) }))
  .image_fades(Is(false))
  |> ignore
  s.image_covers(By(fn() { fit() is FitCover })) |> ignore
  s.image_in(By(fn() {
    let mode = fit()
    match mode {
      FitContain | FitCoverAt(_) => {
        match @ui.image_natural(key()) {
          Some((iw, ih)) if iw > 0.0 && ih > 0.0 => {
            let (w, h) = (width(), height())
            let (k, at) = match mode {
              FitCoverAt(y) => (dmax(w / iw, h / ih), dclamp(y, 0.0, 1.0))
              _ => (dmin(w / iw, h / ih), 0.5)
            }
            let (dw, dh) = (iw * k, ih * k)
            Some((((w - dw) / 2.0, (h - dh) * at, dw, dh), matte.unwrap_or(0L)))
          }
          _ => None
        }
      }
      _ => None
    }
  })) |> ignore
}

///|
/// An image the core sends coming in (image_reveal's): till it is decoded, what it waits on (its ThumbHash's colours,
/// else the neutral ground); once it is (that moment its cause), it in, from 1.04 of itself and frosted 14 deep, as a
/// band of what it waited on brushes down off it in reveal_steps steps over reveal_ms, what is left of that fading out
/// from 800 ms on over 300. One decoded when first shown, or held while it waits (`held`: its station's own, as that
/// says now), there at once. Made for one picture (media_content_node makes another's afresh).
fn media_reveal_node(
  s : @view.View,
  picture : () -> MediaPicture,
  width : () -> Double,
  height : () -> Double,
  fit : () -> @ui.Fit,
) -> Unit {
  let px = fn() { dmin(dmax(width(), height()) * @ui.current().scale, image_px_most) }
  let ready = fn() { @ui.current().image_ready(picture().key, px()) }
  // (when it came in: none, there at once; its way in's end the moment it is all in)
  let first = @signals.untracked(fn() { ready() || picture().held })
  let came : @signals.Signal[Double?] = @signals.signal(if first { Some(-1.0e18) } else { None }, same=fn(a, b) { a == b })
  let moving = @signals.signal(false, same=fn(a, b) { a == b })
  s.reacts(fn() { (ready(), picture().held) }, fn(now) {
    let (decoded, held) = now
    if @signals.untracked(fn() { came.get() }) is None {
      // (held while it waits: there at once as it comes)
      if held {
        came.set(Some(-1.0e18))
      } else if decoded {
        let at = s.cause_at()
        came.set(Some(at))
        moving.set(true)
        s.at_moment(at + reveal_wait_after_ms + reveal_wait_out_ms, fn() { moving.set(false) }) |> ignore
      }
    }
  })
  // (how far in it is as drawn: by the clock while it comes, all of it once it has)
  let way = fn() {
    match came.get() {
      None => 0.0
      Some(t) =>
        if moving.get() {
          dmin(1.0, dmax(0.0, (s.drawn_at() - t) / reveal_ms))
        } else {
          1.0
        }
    }
  }
  let waited = fn() {
    match came.get() {
      None => 1.0
      Some(t) =>
        if moving.get() {
          1.0 - dmin(1.0, dmax(0.0, (s.drawn_at() - t - reveal_wait_after_ms) / reveal_wait_out_ms))
        } else {
          0.0
        }
    }
  }
  let e = fn() { @ui.Out.at(way()) }
  s.clips(Is(true)) |> ignore
  s.box(fn(i) {
    i
    .over(Is(true))
    .width(By(fn() { Some(width()) }))
    .height(By(fn() { Some(height()) }))
    .alpha(By(fn() { if ready() { 1.0 } else { 0.0 } }))
    .scale(By(fn() { 1.0 + reveal_grow * (1.0 - e()) }))
    |> ignore
    media_image(i, fn() { picture().key }, width, height, fit)
  })
  |> ignore
  // (the frost over it as it comes, none under a quarter deep)
  s.show(fn() { ready() && reveal_blur * (1.0 - e()) > reveal_blur_least }, fn(f) {
    f
    .over(Is(true))
    .width(By(fn() { Some(width()) }))
    .height(By(fn() { Some(height()) }))
    .glass(By(fn() { Some(@ui.Glass::frosted(blur=reveal_blur * (1.0 - e()), tint=0L, solid=0L, contained=true)) }))
    |> ignore
  })
  // (what it waits on: all of it till it is decoded; then the edge, half its height deep, from above it to past its
  // foot, in steps on the screen's pixels, and all under it)
  s.show(fn() { waited() > 0.0 }, fn(w) {
    w.over(Is(true)) |> ignore
    let likeness = fn() { image_wait_colours(picture().hash, width(), height()) }
    let px_of = fn(y : Double) { (y * @ui.current().scale).round() / @ui.current().scale }
    // (step k's top and foot and how much of it shows; k == reveal_steps: all under the band)
    let step = fn(k : Int) -> (Double, Double, Double) {
      let h = height()
      if !ready() {
        if k == reveal_steps { (0.0, h, 1.0) } else { (0.0, 0.0, 0.0) }
      } else {
        let band = h * 0.5
        let top = -band + (h + band) * e()
        let one = band / reveal_steps.to_double()
        let (y0, y1, a) = if k == reveal_steps {
          (top + band, h, 1.0)
        } else {
          (top + k.to_double() * one, top + (k + 1).to_double() * one, (k.to_double() + 0.5) / reveal_steps.to_double())
        }
        (px_of(dmax(0.0, y0)), px_of(dmin(h, y1)), a)
      }
    }
    for k in 0..=reveal_steps {
      w.box(fn(strip) {
        strip
        .over(Is(true))
        .clips(Is(true))
        .width(By(fn() { Some(width()) }))
        .offset(By(fn() { (0.0, step(k).0) }))
        .height(By(fn() {
          let (y0, y1, _) = step(k)
          Some(dmax(0.0, y1 - y0))
        }))
        .alpha(By(fn() { step(k).2 * waited() }))
        |> ignore
        strip.box(fn(inner) {
          inner
          .width(By(fn() { Some(width()) }))
          .height(By(fn() { Some(height()) }))
          .offset(By(fn() { (0.0, -step(k).0) }))
          .image(By(fn() { likeness().map(fn(l) { (l, "", 64) }) }))
          .ground(By(fn() { if likeness() is Some(_) { 0L } else { @ui.tree_theme().color(Neutral) } }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
}
