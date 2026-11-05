// A file's picture (message_files.mbt's media_content, image_reveal) as nodes of the window's tree, made once: the
// same in a message, in a quote of it and in the composer's tiles, whatever holds it owning its controls and its cut.
// Which state it is in (a video's still or its ground, no preview, coming in, there, waited on) picks what it draws;
// its picture, its size and its corners followed as they change.

///|
/// What a picture shows (`p`), as media_content picks it: a video's still (1) or its black ground till it has one (2);
/// no preview (3); an image the core sends coming in (4); one sent from here, there at once (5); waited on in the
/// colours its ThumbHash makes (6) or on the neutral ground (7).
fn media_state(p : MediaPicture) -> Int {
  if p.kind == "video" {
    if p.key != "" && p.key != "!" { 1 } else { 2 }
  } else if p.key == "!" {
    3
  } else if p.key != "" && !p.sent {
    4
  } else if p.key != "" {
    5
  } else if p.hash != "" {
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
    |> ignore
    media_box_node(m, picture, fit, radius)
  })
  |> ignore
}

///|
/// The same picture filling a box that layout sized, without feeding that size back into layout.
fn media_fitted_fill_node(
  box : @view.View,
  picture : () -> MediaPicture,
  fit : () -> @ui.Fit,
  radius : () -> Double,
) -> Unit {
  media_box_node(box, picture, fit, radius)
}

///|
fn media_box_node(
  m : @view.View,
  picture : () -> MediaPicture,
  fit : () -> @ui.Fit,
  radius : () -> Double,
) -> Unit {
  m.radius(By(radius)) |> ignore
  // A different picture has its own reveal. All its children fill the box as layout gave it.
  m.pick(fn() {
    let p = picture()
    let state = media_state(p)
    (state, if state == 4 { p.key } else { "" })
  }, fn(s, which) {
    let state = which.0
    s.over(Is(true)).radius(By(radius)) |> ignore
    match state {
      1 => {
        s.ground(Is(0x000000FFL)) |> ignore
        media_image(s, fn() { picture().key }, fit, matte=Some(0x000000FFL))
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
      4 => media_reveal_node(s, picture, fit)
      5 => media_image(s, fn() { picture().key }, fit)
      6 => {
        s.image(Painted(fn(laid) {
          let (w, h) = laid.size(s).unwrap_or((0.0, 0.0))
          image_wait_colours(picture().hash, w, h).map(fn(k) { (k, "", 64) })
        }))
        .ground(Painted(fn(laid) {
          let (w, h) = laid.size(s).unwrap_or((0.0, 0.0))
          if image_wait_colours(picture().hash, w, h) is Some(_) { 0L } else { @ui.tree_theme().color(Neutral) }
        })) |> ignore
      }
      _ => s.ground(By(fn() { @ui.tree_theme().color(Neutral) })) |> ignore
    }
  })
}

///|
/// Picture `key` filling `s` as `fit` says (FitCover: its middle, cut; FitContain: whole in its middle on `matte`;
/// else stretched to it), there at once as it is decoded, asked for at the pixels it is drawn at.
fn media_image(
  s : @view.View,
  key : () -> String,
  fit : () -> @ui.Fit,
  matte? : Int64? = None,
  visible? : Bool = false,
) -> Unit {
  s
  .image(Painted(fn(laid) {
    if visible {
      match laid.rect(s) {
        Some((_, y, _, h)) if y + h > 0.0 && y < s.window().1 => ()
        _ => return None
      }
    }
    Some((key(), "", image_px_most.to_int()))
  }))
  .image_fades(Is(false))
  |> ignore
  s.image_covers(By(fn() { fit() is FitCover })) |> ignore
  s.image_in(Painted(fn(laid) {
    let mode = fit()
    match mode {
      FitContain | FitCoverAt(_) => {
        match @ui.image_natural(key()) {
          Some((iw, ih)) if iw > 0.0 && ih > 0.0 => {
            let (w, h) = laid.size(s).unwrap_or((0.0, 0.0))
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
  fit : () -> @ui.Fit,
) -> Unit {
  // The image node asks for its actual painted size when it is in the window. Its decode's own notification starts
  // the reveal; no place or size is fed back into layout.
  let ready = fn() { @ui.image_state(picture().key) == 1 }
  // A chat's list tells what row is in sight. It is the owner of the picture, not a frame's drawing of the row,
  // that says whether a decode arrived while it could be seen.
  let in_sight = fn() { s.lent(chat_picture_in_sight).map(fn(sight) { sight() }).unwrap_or(true) }
  // (when it came in: none, there at once; its way in's end the moment it is all in)
  let initial = if @signals.untracked(fn() { ready() || picture().held }) { Some(-1.0e18) } else { None }
  let first_shown = s.cause_at()
  let came : @signals.Signal[Double?] = @signals.signal(initial, same=fn(a, b) { a == b })
  let moving = @signals.signal(false, same=fn(a, b) { a == b })
  s.reacts(fn() { (ready(), picture().held) }, fn(now) {
    let (decoded, held) = now
    if @signals.untracked(fn() { came.get() }) is None {
      // (held while it waits: there at once as it comes)
      if held {
        came.set(Some(-1.0e18))
      } else if decoded &&
        ((s.lent(chat_picture_in_sight) is Some(_) && s.cause_at() <= first_shown) || !@signals.untracked(in_sight)) {
        // A decode at the first sight is already there, as one decoded before the row entered is.
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
    .alpha(By(fn() { if ready() { 1.0 } else { 0.0 } }))
    .scale(By(fn() { 1.0 + reveal_grow * (1.0 - e()) }))
    |> ignore
    media_image(i, fn() { picture().key }, fit, visible=true)
  })
  |> ignore
  // (the frost over it as it comes, none under a quarter deep)
  s.show(fn() { ready() && reveal_blur * (1.0 - e()) > reveal_blur_least }, fn(f) {
    f
    .over(Is(true))
    .glass(By(fn() { Some(@ui.Glass::frosted(blur=reveal_blur * (1.0 - e()), tint=0L, solid=0L, contained=true)) }))
    |> ignore
  })
  // (what it waits on: all of it till it is decoded; then the edge, half its height deep, from above it to past its
  // foot, in steps on the screen's pixels, and all under it)
  s.show(fn() { waited() > 0.0 }, fn(w) {
    w.over(Is(true)) |> ignore
    w.layout_box(By(fn() { (ready(), e(), @ui.current().scale) }), fn(l, state) {
      let (decoded, progress, scale) = state
      for k in 0..=reveal_steps {
        let strip = l.child(k.to_string(), fn(strip) {
          let likeness = fn(laid : @view.Laid) {
            let (wide, high) = laid.size(w).unwrap_or((0.0, 0.0))
            image_wait_colours(picture().hash, wide, high)
          }
          strip.clips(Is(true))
          .alpha(By(fn() {
            let a = if k == reveal_steps { 1.0 } else { (k.to_double() + 0.5) / reveal_steps.to_double() }
            a * waited()
          }))
          .image(Painted(fn(laid) { likeness(laid).map(fn(key) { (key, "", 64) }) }))
          .ground(Painted(fn(laid) { if likeness(laid) is Some(_) { 0L } else { @ui.tree_theme().color(Neutral) } }))
          .image_in(Painted(fn(laid) {
            let (wide, high) = laid.size(w).unwrap_or((0.0, 0.0))
            let (y, _, _) = media_reveal_step(high, k, ready(), e(), @ui.current().scale)
            Some(((0.0, -y, wide, high), 0L))
          })) |> ignore
        })
        let (y0, y1, _) = media_reveal_step(l.height, k, decoded, progress, scale)
        l.measure(strip, l.width, height=dmax(0.0, y1 - y0)) |> ignore
        l.place(strip, 0.0, y0)
      }
    }) |> ignore
  })
}

///|
/// A strip's top, bottom and opacity in a waiting picture, rounded to the window's pixels.
fn media_reveal_step(h : Double, k : Int, decoded : Bool, progress : Double, scale : Double) -> (Double, Double, Double) {
  if !decoded {
    return if k == reveal_steps { (0.0, h, 1.0) } else { (0.0, 0.0, 0.0) }
  }
  let band = h * 0.5
  let top = -band + (h + band) * progress
  let one = band / reveal_steps.to_double()
  let (y0, y1, a) = if k == reveal_steps {
    (top + band, h, 1.0)
  } else {
    (top + k.to_double() * one, top + (k + 1).to_double() * one, (k.to_double() + 0.5) / reveal_steps.to_double())
  }
  let px_of = fn(y : Double) { (y * scale).round() / scale }
  (px_of(dmax(0.0, y0)), px_of(dmin(h, y1)), a)
}
