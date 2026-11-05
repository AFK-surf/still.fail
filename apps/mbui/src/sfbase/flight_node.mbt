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
/// An ordinary row can still be making way when the send hands its copy back: meet it where it is drawn. A first
/// send carries its list on this very flight's path, so its destination excludes that path's drawing displacement.
/// Read plainly as the tree is placed (Live's Placed), never followed: none before it is placed.
fn flight_target_window(f : SendFlight, v : @view.View) -> (Double, Double, Double, Double)? {
  if f.carried { v.placed_window_was() } else { v.drawn_window_now() }
}

///|
/// Where a send's landing `v` is laid out and how big, read at its cause (as it comes, laid out as of that moment:
/// View::laid_window_now): how far the send flies, how big what flies lands; none where it is as wide as nothing.
fn flight_landing_laid(v : @view.View) -> (Double, Double, Double, Double)? {
  guard v.alive() else { return None }
  let r = v.laid_window_now()
  if r.2 > 0.0 { Some(r) } else { None }
}

///|
/// Send `f` set on its way as its landing comes, at that cause's moment (`at`): from `from` to where the landing is laid
/// out then (`to`), as long as so far takes where it carries no list of its own (whose way is the list's); a landing
/// come again for it (another row for the same message) none of that again.
fn flight_landed_at(f : SendFlight, to : (Double, Double, Double, Double), from : (Double, Double), at : Double) -> Unit {
  if !f.placed {
    if !f.carried {
      f.ms = flight_way_ms(flies_desk(f), dmax((to.0 - from.0).abs(), (to.1 - from.1).abs()))
    }
    f.timed = true
    flight_placed_at(@ui.current(), f, at)
  }
}

///|
/// A new chat's list comes up with its first sent words on the send's own path. `landing` is the bubble (or the
/// first file for a send without words) as laid out, without this drawing offset. No layout target starts a motion.
/// Read as the tree is placed (a drawing offset's Live's Placed).
pub fn send_list_rise(node : @view.View, draft : String, landing : (SendFlight) -> @view.View?) -> Double {
  match flight_of(draft) {
    Some(f) if f.carried => {
      let up = flight_up(f.way.shown(node), flies_desk(f))
      if f.placed {
        landing(f).bind(fn(v) { v.placed_window_was() })
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
    // (where the layer is drawn: read as the tree is placed, what is placed by it Live's Placed)
    let origin = fn() { layer.drawn_window_now().unwrap_or((0.0, 0.0, 0.0, 0.0)) }
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
/// remains the message's actual card, and all of its width, position and colour changes use the send's path. How big
/// it lands and how far it goes, read where its card is laid out as it comes (its cause); where it goes, where that is
/// drawn as the tree is placed.
fn flight_quote_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : @sf.QuoteCardNode?,
  origin : () -> (Double, Double, Double, Double),
) -> Unit {
  // (its card where it is laid out, and its words how wide, as it comes)
  let laid = landing.bind(fn(q) {
    match (flight_landing_laid(q.card), flight_landing_laid(q.words)) {
      (Some(to), Some(w)) => Some((to, w.2))
      _ => None
    }
  })
  match laid {
    Some((to, _)) => flight_landed_at(f, to, (ff.from.0, ff.from.1), parent.cause_at())
    None => ()
  }
  match landing {
    Some(q) => {
      q.root.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { q.root.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  let size_to = laid.map(fn(l) { l.0 }).unwrap_or(ff.from)
  // (where its card is drawn now, as the tree is placed: where it goes)
  let target = fn() { landing.bind(fn(q) { flight_target_window(f, q.card) }).unwrap_or(size_to) }
  let across = fn() { if laid is Some(_) { flight_across(f.way.shown(parent), flies_desk(f)) } else { 0.0 } }
  let up = fn() { if laid is Some(_) { flight_up(f.way.shown(parent), flies_desk(f)) } else { 0.0 } }
  let scale = fn() { ff.source_scale + (1.0 - ff.source_scale) * up() }
  // (its ground on its way from where it was to `to`, by how far along it is)
  let ground_by = fn(to : (Double, Double, Double, Double)) {
    let a = across()
    let p = up()
    (ff.from.0 + (to.0 - ff.from.0) * a, ff.from.1 + (to.1 - ff.from.1) * p,
      ff.from.2 + (to.2 - ff.from.2) * a, ff.from.3 + (to.3 - ff.from.3) * p)
  }
  // (how big: to how big its card was laid out as it came; where: to where its card is drawn, as the tree is placed)
  let ground_size = fn() {
    let g = ground_by(size_to)
    (g.2, g.3)
  }
  let ground_at = fn() {
    let g = ground_by(target())
    (g.0, g.1)
  }
  let visible = flight_visible_node(parent, ff.shown, ff.from, ground_at, ground_size, up, origin)
  match (landing, laid) {
    (Some(q), Some((_, natural))) => visible.box(fn(part) {
      part.over(Is(true)) |> ignore
      let copy = (q.copy)(part, fn() {
        match ff.quote_words {
          Some((_, from)) => Some(from + (natural - from) * across())
          None => None
        }
      })
      copy.root.over(Is(true)).width(Is(Some(size_to.2)))
      .scale(By(scale), about=@view.At(0.0, 0.0))
      .offset(By(fn() {
        let shift = (q.sent_shift)()
        (shift.0 * (1.0 - across()) * scale(), shift.1 * (1.0 - up()) * scale())
      })) |> ignore
      copy.card.ground_drawn(Placed(fn() {
        let (gw, gh) = ground_size()
        let shift = (q.sent_shift)()
        let h = copy.card.laid_size().1
        let s = scale()
        let (w, h) = if s > 0.0 { (gw / s - size_to.2, gh / s - h) } else { (0.0, 0.0) }
        (-shift.0 * (1.0 - across()), -shift.1 * (1.0 - up()), w, h)
      }))
      .ground(By(fn() {
        let own = @sf.quote_ground()
        let from = if ff.ground != 0L { @sf.over(@sf.theme().p.bg, ff.ground) } else { own }
        @sf.mix_seen(from, 1.0 - up(), own)
      })) |> ignore
    }) |> ignore
    _ =>
      match ff.node {
        Some(make) => visible.box(fn(snapshot) {
          let wide = if ff.source_scale > 0.0 { ff.from.2 / ff.source_scale } else { ff.from.2 }
          snapshot.over(Is(true)).width(Is(Some(wide)))
          .scale(Is(ff.source_scale), about=@view.At(0.0, 0.0)) |> ignore
          make(snapshot)
        }) |> ignore
        None => ()
      }
  }
  // The composer's close control and empty comment hint leave with the card, on the original leave path.
  parent.show(fn() { f.gone.shown(parent) < 1.0 }, fn(leaving) {
    leaving.over(Is(true)).alpha(By(fn() { 1.0 - f.gone.shown(leaving) })) |> ignore
    let side = @sf.corner_remove_side
    let reach = @sf.corner_remove_reach(@sf.composer_inner())
    let close_from = (ff.from.0 + ff.from.2 + reach - side, ff.from.1 - reach, side, side)
    let close_room = flight_visible_node(leaving, ff.shown, close_from, fn() {
      let (gx, gy) = ground_at()
      (gx + ground_size().0 + reach - side, gy - reach)
    }, fn() { (side, side) }, up, origin)
    let close = @sf.corner_remove_face_node(close_room)
    close.scale(By(fn() { 1.0 - (1.0 - @sf.leave_scale) * f.gone.shown(close) })) |> ignore
    match (ff.leaving, ff.leaving_node) {
      (Some((r, _)), Some(make)) => {
        let hint = flight_visible_node(leaving, ff.shown, r, fn() {
          let (gx, gy) = ground_at()
          (gx + r.0 - ff.from.0, gy + r.1 - ff.from.1)
        }, fn() { (r.2, r.3) }, up, origin)
        make(hint)
      }
      _ => ()
    }
  })
}

///|
/// The portion of a source still visible as it leaves an opening container, translated to the flight's current
/// rectangle: where (`at`, read as the tree is placed: Live's Placed), how big (`size`, of the way's progress and what
/// was laid out as it came alone). Only an existing cut is carried: an unclipped source may draw beyond its own layout
/// while reshaping.
fn flight_visible_node(
  parent : @view.View,
  shown : @ui.DrawnState?,
  from : (Double, Double, Double, Double),
  at : () -> (Double, Double),
  size : () -> (Double, Double),
  up : () -> Double,
  origin : () -> (Double, Double, Double, Double),
) -> @view.View {
  let visible = fn() { flight_visible(shown, from, up()) }
  let crop = parent.box(fn(crop) {
    crop.over(Is(true))
    .width(By(fn() { let v = visible(); Some(size().0 * dmax(0.0, v.right - v.left)) }))
    .height(By(fn() { let v = visible(); Some(size().1 * dmax(0.0, v.bottom - v.top)) }))
    .offset(Placed(fn() {
      let v = visible()
      let (x, y) = at()
      let (w, h) = size()
      let o = origin()
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
    .offset(By(fn() { let v = visible(); let (w, h) = size(); (-w * v.left, -h * v.top) })) |> ignore
  })
}

///|
fn flight_waiting_node(parent : @view.View, f : SendFlight, origin : () -> (Double, Double, Double, Double)) -> Unit {
  if f.text == "" { return }
  parent.box(fn(room) {
    room.over(Is(true)).width(Is(Some(f.field_w))).height(Is(Some(f.field_h)))
    .offset(Placed(fn() { let o = origin(); (f.field_x - o.0, f.field_y - o.1) })).clips(Is(true)) |> ignore
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
/// The words sent flown to where their row lands them: how far, how big their bubble lands and what they are laid out
/// as there (in pieces where the field and the message wrap otherwise), read where the bubble and its words are laid
/// out as they come (its cause); where they go, where those are drawn as the tree is placed.
fn flight_landing_node(
  parent : @view.View,
  f : SendFlight,
  bubble : @view.View,
  words : @view.View,
  origin : () -> (Double, Double, Double, Double),
) -> Unit {
  let laid = match (flight_landing_laid(bubble), flight_landing_laid(words)) {
    (Some(b), Some(w)) => Some((b, w))
    _ => None
  }
  match laid {
    Some((_, w)) => flight_landed_at(f, w, (f.from_x, f.from_y), parent.cause_at())
    None => ()
  }
  bubble.alpha(Is(0.0)).hides(Is(true)) |> ignore
  parent.owns(fn() { bubble.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
  guard laid is Some((b_laid, w_laid)) else {
    flight_waiting_node(parent, f, origin)
    return
  }
  // (where they are drawn now, as the tree is placed: where it goes)
  let brect = fn() { flight_target_window(f, bubble).unwrap_or(b_laid) }
  let wrect = fn() { flight_target_window(f, words).unwrap_or(w_laid) }
  parent.box(fn(paint) {
    paint.over(Is(true)) |> ignore
    let across = fn() { flight_across(f.way.shown(paint), flies_desk(f)) }
    let up = fn() { flight_up(f.way.shown(paint), flies_desk(f)) }
    let bx = fn() { let b = brect(); f.from_x - bubble_in_x + (b.0 - f.from_x + bubble_in_x) * across() }
    let by = fn() { let b = brect(); f.from_y - bubble_in_y + (b.1 - f.from_y + bubble_in_y) * up() }
    paint.box(fn(ground) {
      ground.over(Is(true)).width(Is(Some(b_laid.2))).height(Is(Some(b_laid.3)))
      .offset(Placed(fn() { let o = origin(); (bx() - o.0, by() - o.1) }))
      // The flying copy carries the bubble's surface as seen on its page. Neutral alone is a translucent tint:
      // over another row it would tint that row's words instead of covering them as the bubble passes.
      .ground(By(fn() {
        @sf.over(@sf.theme().p.bg,
          @sf.alpha(@ui.tree_theme().color(Neutral), flight_ground(f.way.shown(paint), flies_desk(f))))
      }))
      .radius(By(fn() { @ui.tree_theme().corner(Xl2) })) |> ignore
    }) |> ignore
    // (its words as they are laid out where they land, read as they come: in pieces where the field wrapped them
    // otherwise, each on a path of its own)
    match @ui.runs_words_now(words).bind(fn(w) { flight_pieces_of(f, Some(w)).map(fn(p) { p.0 }) }) {
      Some(pieces) =>
        for i, piece in pieces {
          paint.box(fn(cell) {
            cell.over(Is(true)) |> ignore
            // (where the field and the message wrap at different places the pieces cross: each only the room the
            // larger pieces leave it, as the old frame's pieces have it, flight_pieces_drawn; its path its own; the
            // same wherever they land, all moved alike)
            let room = fn() { flight_piece_room(pieces, i, w_laid.0, w_laid.1, across(), up()) }
            cell.width(By(fn() { let (l, r) = room(); Some(dmax(0.0, r - l)) })).height(Is(Some(piece.at.3))).clips(Is(true))
            .offset(Placed(fn() {
              let w = wrect()
              let o = origin()
              (piece.from.0 + (w.0 + piece.at.0 - piece.from.0) * across() - o.0 + room().0,
                piece.from.1 + (w.1 + piece.at.1 - piece.from.1) * up() - o.1)
            })) |> ignore
            flight_words_node(cell, words, w_laid.2, By(fn() { (-piece.at.0 - room().0, -piece.at.1) }))
          }) |> ignore
        }
      None =>
        flight_words_node(paint, words, w_laid.2, Placed(fn() {
          let b = brect()
          let w = wrect()
          let o = origin()
          (bx() + w.0 - b.0 - o.0, by() + w.1 - b.1 - o.1)
        }))
    }
  }) |> ignore
}

///|
fn flight_words_node(parent : @view.View, words : @view.View, width : Double, offset : @view.Live[(Double, Double)]) -> Unit {
  let set = fn() { words.words_said() |> ignore; words.runs_set_now() }
  parent.box(fn(w) {
    w.over(Is(true)).width(Is(Some(width))).offset(offset)
    .words_runs(By(fn() { set().0 })).words_look(By(fn() { set().1 })).runs_look(By(fn() { set().2 }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) })) |> ignore
  }) |> ignore
}
