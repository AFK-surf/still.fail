// The send's one path, drawn in the page's flying layer by retained nodes. Its destination is a real message's
// bubble and rich words, outside the list's clipping, under the page's bar. Until that landing exists, its text
// stays where it was typed. A replacement landing (outbox to message, or a virtual row remade) does not restart it.

///|
priv struct NodeFlight {
  value : SendFlight
}

///|
impl Eq for NodeFlight with equal(self, other) {
  physical_equal(self.value, other.value)
}

///|
priv struct NodeLanding {
  bubble : @view.View
  words : @view.View
}

///|
impl Eq for NodeLanding with equal(self, other) {
  physical_equal(self.bubble.tree, other.bubble.tree) &&
    self.bubble.id() == other.bubble.id() && self.words.id() == other.words.id()
}

///|
priv struct QuoteLanding {
  value : @sf.QuoteCardNode
}

///|
impl Eq for QuoteLanding with equal(self, other) {
  physical_equal(self.value.card.tree, other.value.card.tree) && self.value.card.id() == other.value.card.id()
}

///|
/// Where a landing is in the window as this frame is painted (a Painted's: read there and nowhere else). An ordinary
/// row can still be making way when the send hands its copy back: meet it where it is drawn. A first send carries its
/// list on this very flight's path, so its destination excludes that path's drawing displacement.
fn flight_target_in(laid : @view.Laid, f : SendFlight, v : @view.View) -> (Double, Double)? {
  (if f.carried { laid.rect(v) } else { laid.drawn(v) }).map(fn(r) { (r.0, r.1) })
}

///|
/// Where a landing is laid out and how big as of the moment it is said (its row come, what it says changed), said then
/// and never followed (View::laid_window_now): how big what flies is laid out on its way there, and how long its way
/// takes. None while it is laid out to nothing.
fn flight_to_now(v : @view.View) -> (Double, Double, Double, Double)? {
  let r = @signals.untracked(fn() { v.laid_window_now() })
  if r.2 > 0.0 && r.3 > 0.0 { Some(r) } else { None }
}

///|
/// The send set out for its landing, at that landing's moment (once): how long its way takes by how far it is from
/// where it set off to where the landing is laid out then (a first send's, carried with its list, as it was declared).
fn flight_set_out_for(node : @view.View, f : SendFlight, from : (Double, Double), to : (Double, Double, Double, Double)) -> Unit {
  if !f.placed {
    if !f.carried { f.ms = flight_way_ms(flies_desk(f), dmax((to.0 - from.0).abs(), (to.1 - from.1).abs())) }
    f.timed = true
    flight_placed_at(@ui.current(), f, node.cause_at())
  }
}

///|
/// A new chat's list comes up with its first sent words on the send's own path. `landing` is the bubble (or the
/// first file for a send without words) as laid out, without this drawing offset, as `laid` has it in the frame being
/// painted (a Painted drawn_off's: read there and nowhere else). No layout target starts a motion.
pub fn send_list_rise(
  laid : @view.Laid,
  node : @view.View,
  draft : String,
  landing : (SendFlight) -> @view.View?,
) -> Double {
  match flight_of(draft) {
    Some(f) if f.carried => {
      let up = flight_up(f.way.shown(node), flies_desk(f))
      if f.placed {
        landing(f).bind(fn(v) { laid.rect(v) })
        .map(fn(r) { (f.from_top - r.1) * (1.0 - up) }).unwrap_or(0.0)
      } else { 0.0 }
    }
    _ => 0.0
  }
}

///|
/// The sent row's time and other parts come in on the same path as its bubble, after the words have set off.
pub fn send_row_arrived(node : @view.View, draft : String, key : String) -> Double {
  match flight_of(draft) {
    Some(f) if f.key == key => flight_settled(f.way.shown(node), flies_desk(f))
    _ => 1.0
  }
}

///|
/// A sent message's time appears from its words' declared landing, as mine_message's time-in does. It keeps that
/// fade after the flying copy is released; the time cannot appear under the words while they pass its place.
pub fn send_time_node(node : @view.View, draft : () -> String, key : () -> String) -> Unit {
  let arrived = FlightWay::new(value=1.0)
  node.reacts(fn() {
    match flight_of(draft()) {
      Some(f) if f.key == key() && f.text != "" => Some((f.placed, f.way.ends()))
      _ => None
    }
  }, fn(now) {
    match now {
      Some((placed, end)) => {
        arrived.way.put(0.0)
        if placed { arrived.animate(1.0, @motion.tween(@sf.enter_ms, ease=Out), start_at=end) }
      }
      None => ()
    }
  })
  node.alpha(By(fn() { arrived.shown(node) })) |> ignore
}

///|
pub fn send_flight_node(
  layer : @view.View,
  draft : String,
  landing : (SendFlight) -> (@view.View, @view.View)?,
  quotes? : (SendFlight, String) -> @sf.QuoteCardNode? = fn(_, _) { None },
  files? : (SendFlight, String) -> FileLandingNode? = fn(_, _) { None },
) -> Unit {
  layer.pick(fn() { flight_of(draft).map(fn(f) { NodeFlight::{ value: f } }) }, fn(slot, now) {
    guard now is Some(now) else { return }
    let f = now.value
    slot.over(Is(true)).hides(Is(true)) |> ignore
    let finish = fn(at) {
      if send_flight.get() is Some(current) && physical_equal(current, f) {
        send_flight.set(None)
        turns_of(f.turns).over(@ui.current(), Send, at)
      }
    }
    // (no row ever arrived: the same bounded source hold as flight_frame, owned by this page)
    let waited = slot.cause_at() + flight_wait_ms
    slot.owns(slot.at_moment(waited, fn() { if !f.placed { finish(waited) } })) |> ignore
    let ends : Ref[() -> Unit] = Ref(fn() {  })
    slot.reacts(fn() { f.way.ends() }, fn(end) {
      (ends.val)()
      if f.placed {
        ends.val = slot.at_moment(end, fn() { finish(end) })
      }
    })
    slot.owns(fn() { (ends.val)() }) |> ignore
    // (where the layer is drawn, as each frame is painted: what flies is placed in it)
    let origin = fn(laid : @view.Laid) { laid.drawn(layer).map(fn(r) { (r.0, r.1) }).unwrap_or((0.0, 0.0)) }
    slot.pick(fn() { landing(f).map(fn(pair) { NodeLanding::{ bubble: pair.0, words: pair.1 } }) }, fn(part, at) {
      part.over(Is(true)) |> ignore
      match at {
        Some(at) => flight_landing_node(part, f, at.bubble, at.words, origin)
        None => flight_waiting_node(part, f, origin)
      }
    })
    for ff in f.files {
      if ff.key.has_prefix(quote_prefix) {
        slot.pick(fn() { quotes(f, ff.key).map(fn(q) { QuoteLanding::{ value: q } }) }, fn(part, at) {
          part.over(Is(true)) |> ignore
          flight_quote_node(part, f, ff, at.map(fn(q) { q.value }), origin)
        })
      } else {
        slot.pick(fn() { files(f, ff.key) }, fn(part, at) {
          part.over(Is(true)) |> ignore
          flight_file_node(part, f, ff, at, origin)
        })
      }
    }
  })
}

///|
/// The quote's own card carried over the list. Its source is frozen before the draft is taken; its destination
/// remains the message's actual card: how big it is laid out said as it comes (flight_to_now), where it is read as each
/// frame is painted; all of its width, position and colour changes use the send's path.
fn flight_quote_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : @sf.QuoteCardNode?,
  origin : (@view.Laid) -> (Double, Double),
) -> Unit {
  // (the card's size and its words' width, as of the moment it comes)
  let sized : @signals.Signal[((Double, Double), Double)?] = @signals.signal(None)
  // (said again as its words change, and as the window's size does: what the message's column is laid out by)
  parent.reacts(fn() { (landing.map(fn(q) { q.words.words_said() }), parent.window()) }, fn(_) {
    guard landing is Some(q) else { return }
    match (flight_to_now(q.card), flight_to_now(q.words)) {
      (Some(to), Some(words)) => {
        flight_set_out_for(parent, f, (ff.from.0, ff.from.1), to)
        sized.set(Some(((to.2, to.3), words.2)))
      }
      _ => ()
    }
  })
  match landing {
    Some(q) => {
      q.root.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { q.root.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  let to_size = fn() { sized.get().map(fn(s) { s.0 }) }
  let natural = fn() { sized.get().map(fn(s) { s.1 }) }
  let across = fn() { if sized.get() is Some(_) { flight_across(f.way.shown(parent), flies_desk(f)) } else { 0.0 } }
  let up = fn() { if sized.get() is Some(_) { flight_up(f.way.shown(parent), flies_desk(f)) } else { 0.0 } }
  let scale = fn() { ff.source_scale + (1.0 - ff.source_scale) * up() }
  // (how big its ground is on the way: laid out by the time; where it is: as painted)
  let ground_size = fn() {
    let to = to_size().unwrap_or((ff.from.2, ff.from.3))
    (ff.from.2 + (to.0 - ff.from.2) * across(), ff.from.3 + (to.1 - ff.from.3) * up())
  }
  let ground_at = fn(laid : @view.Laid) {
    let to = landing.bind(fn(q) { flight_target_in(laid, f, q.card) }).unwrap_or((ff.from.0, ff.from.1))
    (ff.from.0 + (to.0 - ff.from.0) * across(), ff.from.1 + (to.1 - ff.from.1) * up())
  }
  let visible = flight_visible_node(parent, ff.shown, ff.from, ground_size, ground_at, up, origin)
  visible.pick(fn() { sized.get() is Some(_) }, fn(part, ready) {
    part.over(Is(true)) |> ignore
    if ready {
      let q = landing.unwrap()
      let copy = (q.copy)(part, fn() {
        match (ff.quote_words, natural()) {
          (Some((_, from)), Some(to)) => Some(from + (to - from) * across())
          _ => None
        }
      })
      copy.root.over(Is(true)).width(By(fn() { to_size().map(fn(r) { r.0 }) }))
      .scale(By(scale), about=@view.At(0.0, 0.0))
      .offset(By(fn() {
        let shift = (q.sent_shift)()
        (shift.0 * (1.0 - across()) * scale(), shift.1 * (1.0 - up()) * scale())
      })) |> ignore
      copy.card.ground_drawn(Painted(fn(laid) {
        let g = ground_size()
        let to = to_size().unwrap_or((ff.from.2, ff.from.3))
        let shift = (q.sent_shift)()
        let h = laid.size(copy.card).map(fn(size) { size.1 }).unwrap_or(to.1)
        let s = scale()
        let (w, h) = if s > 0.0 { (g.0 / s - to.0, g.1 / s - h) } else { (0.0, 0.0) }
        (-shift.0 * (1.0 - across()), -shift.1 * (1.0 - up()), w, h)
      }))
      .ground(By(fn() {
        let own = @sf.quote_ground()
        let from = if ff.ground != 0L { @sf.over(@sf.theme().p.bg, ff.ground) } else { own }
        @sf.mix_seen(from, 1.0 - up(), own)
      })) |> ignore
    } else {
      match ff.node {
        Some(make) => part.box(fn(snapshot) {
          let wide = if ff.source_scale > 0.0 { ff.from.2 / ff.source_scale } else { ff.from.2 }
          snapshot.over(Is(true)).width(Is(Some(wide)))
          .scale(Is(ff.source_scale), about=@view.At(0.0, 0.0)) |> ignore
          make(snapshot)
        }) |> ignore
        None => ()
      }
    }
  })
  // The composer's close control and empty comment hint leave with the card, on the original leave path.
  parent.show(fn() { f.gone.shown(parent) < 1.0 }, fn(leaving) {
    leaving.over(Is(true)).alpha(By(fn() { 1.0 - f.gone.shown(leaving) })) |> ignore
    let side = @sf.corner_remove_side
    let reach = @sf.corner_remove_reach(@sf.composer_inner())
    let close_from = (ff.from.0 + ff.from.2 + reach - side, ff.from.1 - reach, side, side)
    let close_room = flight_visible_node(leaving, ff.shown, close_from, fn() { (side, side) }, fn(laid) {
      let g = ground_at(laid)
      (g.0 + ground_size().0 + reach - side, g.1 - reach)
    }, up, origin)
    let close = @sf.corner_remove_face_node(close_room)
    close.scale(By(fn() { 1.0 - (1.0 - @sf.leave_scale) * f.gone.shown(close) })) |> ignore
    match (ff.leaving, ff.leaving_node) {
      (Some((r, _)), Some(make)) => {
        let hint = flight_visible_node(leaving, ff.shown, r, fn() { (r.2, r.3) }, fn(laid) {
          let g = ground_at(laid)
          (g.0 + r.0 - ff.from.0, g.1 + r.1 - ff.from.1)
        }, up, origin)
        make(hint)
      }
      _ => ()
    }
  })
}

///|
/// The portion of a source still visible as it leaves an opening container, translated to the flight's current
/// rectangle: how big that is laid out by the time (`size`), where it is read as each frame is painted (`at`, in the
/// window; `origin`, where what holds it is). Only an existing cut is carried: an unclipped source may draw beyond its
/// own layout while reshaping.
fn flight_visible_node(
  parent : @view.View,
  shown : @ui.DrawnState?,
  from : (Double, Double, Double, Double),
  size : () -> (Double, Double),
  at : (@view.Laid) -> (Double, Double),
  up : () -> Double,
  origin : (@view.Laid) -> (Double, Double),
) -> @view.View {
  let visible = fn() { flight_visible(shown, from, up()) }
  let crop = parent.box(fn(crop) {
    crop.over(Is(true))
    .width(By(fn() { let v = visible(); Some(size().0 * dmax(0.0, v.right - v.left)) }))
    .height(By(fn() { let v = visible(); Some(size().1 * dmax(0.0, v.bottom - v.top)) }))
    .offset(Painted(fn(laid) {
      let v = visible()
      let (w, h) = size()
      let (x, y) = at(laid)
      let o = origin(laid)
      (x + w * v.left - o.0, y + h * v.top - o.1)
    }))
    .clips(By(fn() { let v = visible(); v.left > 0.0 || v.top > 0.0 || v.right < 1.0 || v.bottom < 1.0 }))
    .alpha(By(fn() { visible().alpha }))
    .fades(By(fn() {
      let v = visible()
      (if v.left > 0.0 { v.soft } else { 0.0 }, if v.top > 0.0 { v.soft } else { 0.0 },
        if v.right < 1.0 { v.soft } else { 0.0 }, if v.bottom < 1.0 { v.soft } else { 0.0 })
    })) |> ignore
  })
  crop.box(fn(body) {
    body.over(Is(true)).width(By(fn() { Some(size().0) })).height(By(fn() { Some(size().1) }))
    .offset(By(fn() { let v = visible(); let r = size(); (-r.0 * v.left, -r.1 * v.top) })) |> ignore
  })
}

///|
fn flight_waiting_node(parent : @view.View, f : SendFlight, origin : (@view.Laid) -> (Double, Double)) -> Unit {
  if f.text == "" { return }
  parent.box(fn(room) {
    room.over(Is(true)).width(Is(Some(f.field_w))).height(Is(Some(f.field_h)))
    .offset(Painted(fn(laid) { let o = origin(laid); (f.field_x - o.0, f.field_y - o.1) })).clips(Is(true)) |> ignore
    room.box(fn(w) {
      w.width(Is(Some(f.field_w))).offset(Is((f.from_x - f.field_x, f.from_y - f.field_y)))
      .words_runs(By(fn() { person_runs(f.text, f.runs, @sf.theme().p.accent) }))
      .words_look(By(fn() { @ui.style_words(@sf.theme().t.words) }))
      .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) }))
      .runs_look(By(fn() { { ..@view.runs_plain, link: @sf.theme().p.blue, words: true } })) |> ignore
    }) |> ignore
  }) |> ignore
}

///|
/// The words sent flown to their bubble: how big it and its words are laid out said as they come and as what they say or
/// the window's size changes (flight_to_now), where they are read as each frame is painted.
fn flight_landing_node(
  parent : @view.View,
  f : SendFlight,
  bubble : @view.View,
  words : @view.View,
  origin : (@view.Laid) -> (Double, Double),
) -> Unit {
  let brect = fn(laid : @view.Laid) { flight_target_in(laid, f, bubble).unwrap_or((0.0, 0.0)) }
  let wrect = fn(laid : @view.Laid) { flight_target_in(laid, f, words).unwrap_or((0.0, 0.0)) }
  // (the bubble's size and its words' width, and the pieces they are cut in, as of the moment they are said)
  let sized : @signals.Signal[((Double, Double), Double)?] = @signals.signal(None)
  let pieces : @signals.Signal[Array[FlightPiece]?] = @signals.signal(None)
  // (said again as its words change, and as the window's size does: what the message's column is laid out by)
  parent.reacts(fn() { (words.words_said(), parent.window()) }, fn(_) {
    match (flight_to_now(bubble), flight_to_now(words)) {
      (Some(b), Some(w)) => {
        flight_set_out_for(parent, f, (f.from_x, f.from_y), w)
        sized.set(Some(((b.2, b.3), w.2)))
        pieces.set(@signals.untracked(fn() {
          @ui.runs_words_now(words).bind(fn(w) { flight_pieces_of(f, Some(w)).map(fn(p) { p.0 }) })
        }))
      }
      _ => ()
    }
  })
  bubble.alpha(Is(0.0)).hides(Is(true)) |> ignore
  parent.owns(fn() { bubble.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
  parent.pick(fn() { sized.get() is Some(_) }, fn(paint, placed) {
    paint.over(Is(true)) |> ignore
    if !placed {
      flight_waiting_node(paint, f, origin)
      return
    }
    let size = fn() { sized.get().unwrap().0 }
    let words_w = fn() { sized.get().unwrap().1 }
    let across = fn() { flight_across(f.way.shown(paint), flies_desk(f)) }
    let up = fn() { flight_up(f.way.shown(paint), flies_desk(f)) }
    let bx = fn(laid) { let b = brect(laid); f.from_x - bubble_in_x + (b.0 - f.from_x + bubble_in_x) * across() }
    let by = fn(laid) { let b = brect(laid); f.from_y - bubble_in_y + (b.1 - f.from_y + bubble_in_y) * up() }
    paint.box(fn(ground) {
      ground.over(Is(true)).width(By(fn() { Some(size().0) })).height(By(fn() { Some(size().1) }))
      .offset(Painted(fn(laid) { let o = origin(laid); (bx(laid) - o.0, by(laid) - o.1) }))
      // The flying copy carries the bubble's surface as seen on its page. Neutral alone is a translucent tint:
      // over another row it would tint that row's words instead of covering them as the bubble passes.
      .ground(By(fn() {
        @sf.over(@sf.theme().p.bg,
          @sf.alpha(@ui.tree_theme().color(Neutral), flight_ground(f.way.shown(paint), flies_desk(f))))
      }))
      .radius(By(fn() { @ui.tree_theme().corner(Xl2) })) |> ignore
    }) |> ignore
    paint.pick(fn() { pieces.get() is Some(_) }, fn(group, split) {
      group.over(Is(true)) |> ignore
      if split {
        group.each(fn() { pieces.get().unwrap_or([]).mapi(fn(i, _) { i }) }, fn(i) { i }, fn(cell, i) {
          cell.over(Is(true)) |> ignore
          let piece = fn() { pieces.get().unwrap()[i.get()] }
          // (where the field and the message wrap at different places the pieces cross: each only the room the larger
          // pieces leave it, as the old frame's pieces have it, flight_pieces_drawn; its path its own: cut so as it is
          // painted, where the pieces are then)
          let room = fn(laid) {
            let w = wrect(laid)
            flight_piece_room(pieces.get().unwrap(), i.get(), w.0, w.1, across(), up())
          }
          cell.width(By(fn() { Some(piece().at.2) })).height(By(fn() { Some(piece().at.3) })).clips(Is(true))
          .clip_drawn(Painted(fn(laid) { let (l, r) = room(laid); Some((l, 0.0, dmax(0.0, r - l), piece().at.3)) }))
          .offset(Painted(fn(laid) {
            let q = piece()
            let w = wrect(laid)
            let o = origin(laid)
            (q.from.0 + (w.0 + q.at.0 - q.from.0) * across() - o.0, q.from.1 + (w.1 + q.at.1 - q.from.1) * up() - o.1)
          })) |> ignore
          flight_words_node(cell, words, words_w, By(fn() { let q = piece(); (-q.at.0, -q.at.1) }))
        })
      } else {
        flight_words_node(group, words, words_w, Painted(fn(laid) {
          let b = brect(laid)
          let w = wrect(laid)
          let o = origin(laid)
          (bx(laid) + w.0 - b.0 - o.0, by(laid) + w.1 - b.1 - o.1)
        }))
      }
    })
  })
}

///|
fn flight_words_node(parent : @view.View, words : @view.View, width : () -> Double, offset : @view.Live[(Double, Double)]) -> Unit {
  let set = fn() { words.words_said() |> ignore; words.runs_set_now() }
  parent.box(fn(w) {
    w.over(Is(true)).width(By(fn() { Some(width()) })).offset(offset)
    .words_runs(By(fn() { set().0 })).words_look(By(fn() { set().1 })).runs_look(By(fn() { set().2 }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) })) |> ignore
  }) |> ignore
}
