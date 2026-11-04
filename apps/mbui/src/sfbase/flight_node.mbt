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
/// An ordinary row can still be making way when the send hands its copy back: meet it where it is drawn. A first
/// send carries its list on this very flight's path, so its destination excludes that path's drawing displacement.
fn flight_target_window(f : SendFlight, v : @view.View) -> (Double, Double, Double, Double)? {
  if f.carried { v.laid_window_told() } else { v.drawn_window_told() }
}

///|
/// A new chat's list comes up with its first sent words on the send's own path. `landing` is the bubble (or the
/// first file for a send without words) as laid out, without this drawing offset. No layout target starts a motion.
pub fn send_list_rise(node : @view.View, draft : String, landing : (SendFlight) -> @view.View?) -> Double {
  match flight_of(draft) {
    Some(f) if f.carried => {
      let up = flight_up(f.way.shown(node), flies_desk(f))
      if f.placed {
        landing(f).bind(fn(v) { v.laid_window_told() })
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
/// Where one of the flight's parts has it as it works it out: how far on its way the flight is (`p`), and whether where
/// its landing is comes from this very layout (`laid`: in the flight's own, after the rows of the same pass) or as told
/// for drawing it (flight_target_window).
priv struct FlightAt {
  p : Double
  laid : Bool
  // (what of its landing a part is sized by besides where it is: a picture's share of its file's box, read before layout)
  share : (Double, Double)
}

///|
/// The flight on `way` as node `v` is drawn.
fn flight_drawn(way : FlightWay, v : @view.View, share? : () -> (Double, Double) = flight_whole) -> FlightAt {
  { p: way.shown(v), laid: false, share: share() }
}

///|
/// All of its landing's box (FlightAt's share).
fn flight_whole() -> (Double, Double) {
  (1.0, 1.0)
}

///|
/// Where `v` is in the window as `at` has it: as this layout has laid it out, or as told for drawing.
fn flight_window_at(f : SendFlight, v : @view.View, at : FlightAt) -> (Double, Double, Double, Double)? {
  if at.laid {
    if v.alive() { Some(v.laid_window_now()) } else { None }
  } else {
    flight_target_window(f, v)
  }
}

///|
/// Whether `v` is laid out in this pass, with room (in a layout of the flight's).
fn flight_laid(v : @view.View) -> Bool {
  v.alive() && v.laid_window_now().2 > 0.0
}

///|
/// What of the flight `place` lays out in its own layout, by how far on its way the flight is as of it and where what it
/// goes to is laid out in that same pass: over its holder, taking no room of it, nothing it works out told back.
fn flight_layout(
  parent : @view.View,
  way : FlightWay,
  share? : () -> (Double, Double) = flight_whole,
  place : (@view.Layout, FlightAt) -> Unit,
) -> Unit {
  parent.box(fn(o) {
    o.over(Is(true)).width(Is(Some(0.0))).height(Is(Some(0.0)))
    .layout_box(By(fn() { (way.shown(o), share()) }), fn(l, said) { place(l, { p: said.0, laid: true, share: said.1 }) }) |> ignore
  }) |> ignore
}

///|
/// A part of the flight as wide and as tall (none: as it is) as `size` says in the flight's own layout.
fn flight_part(
  parent : @view.View,
  way : FlightWay,
  share? : () -> (Double, Double) = flight_whole,
  size : (FlightAt) -> (Double, Double?),
  make : (@view.View) -> Unit,
) -> Unit {
  flight_layout(parent, way, share~, fn(l, at) {
    let v = l.child("part", make)
    let (w, h) = size(at)
    l.measure(v, dmax(0.0, w), height?=h.map(fn(h) { dmax(0.0, h) })) |> ignore
    l.place(v, 0.0, 0.0)
  })
}

///|
/// What the flight holds, its own size none: each part over it, where its own offset puts it.
fn flight_holder(l : @view.Layout, key : String, make : (@view.View) -> Unit) -> Unit {
  let v = l.child(key, make)
  l.measure(v, 0.0, height=0.0) |> ignore
  l.place(v, 0.0, 0.0)
}

///|
/// The send's flight in `layer`: what flies of draft `draft`'s words, quotes and files, from where they were typed to
/// their row where the list has it. `place` says by what its row is found (followed: read before anything is laid out);
/// `landing` its bubble and words by that, `quotes` and `files` its quotes' cards and its files by that and their keys,
/// as the rows laid out in the same pass have them (read in the flight's own layout: no signal). Which of its parts
/// shows, waiting or flying, is said in that layout, after the list's: nothing the list's layout makes changes what
/// the flight is made of afterwards, and nothing the flight lays out is told back to it.
pub fn send_flight_node(
  layer : @view.View,
  draft : String,
  place : (SendFlight) -> String?,
  landing : (String) -> (@view.View, @view.View)?,
  quotes? : (String, String) -> @sf.QuoteCardNode? = fn(_, _) { None },
  files? : (String, String) -> FileLandingNode? = fn(_, _) { None },
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
    let origin = fn() { layer.drawn_window_told().unwrap_or((0.0, 0.0, 0.0, 0.0)) }
    // (on its way once what it goes to is told laid out, from `from`: timed as long as that is far, set out as the next
    // change at this one's moment, so that what setting out changes (the composer let go, the list's room) is laid out
    // with it in the next layout, never after this one)
    let asked = Ref(false)
    let set_out = fn(to : (Double, Double, Double, Double), from : (Double, Double)) {
      guard !f.placed && !asked.val else { return }
      asked.val = true
      if !f.carried { f.ms = flight_way_ms(flies_desk(f), dmax((to.0 - from.0).abs(), (to.1 - from.1).abs())) }
      f.timed = true
      let at = slot.cause_at()
      slot.owns(slot.at_moment(at, fn() { flight_placed_at(@ui.current(), f, at) })) |> ignore
    }
    slot.box(fn(fl) {
      fl.over(Is(true)).width(Is(Some(0.0))).height(Is(Some(0.0))) |> ignore
      // (found again each frame till it is placed: its row may be made in any pass, by the list, as it comes in sight)
      fl.layout_box(By(fn() { (place(f), if f.placed { 0.0 } else { fl.drawn_at() }) }), fn(l, said) {
        let at = said.0
        // (its words: their bubble and words in their row, once laid out in this pass; else where they were typed)
        match at.bind(landing) {
          Some((bubble, words)) if flight_laid(bubble) && flight_laid(words) =>
            flight_holder(l, "words/\{bubble.id().at}.\{bubble.id().gen}/\{words.id().at}.\{words.id().gen}", fn(v) {
              flight_landing_node(v, f, bubble, words, origin, set_out)
            })
          _ => if f.text != "" { flight_holder(l, "waiting", fn(v) { flight_waiting_node(v, f, origin) }) }
        }
        for ff in f.files {
          if ff.key.has_prefix(quote_prefix) {
            match at.bind(fn(at) { quotes(at, ff.key) }) {
              Some(q) if flight_laid(q.card) && flight_laid(q.words) =>
                flight_holder(l, "quote/\{ff.key}/\{q.card.id().at}.\{q.card.id().gen}", fn(v) {
                  flight_quote_node(v, f, ff, Some(q), origin, set_out)
                })
              _ => flight_holder(l, "quote/\{ff.key}", fn(v) { flight_quote_node(v, f, ff, None, origin, set_out) })
            }
          } else {
            match at.bind(fn(at) { files(at, ff.key) }) {
              Some(a) if flight_laid(a.view) && a.view.laid_window_now().3 > 0.0 =>
                flight_holder(l, "file/\{ff.key}/\{a.view.id().at}.\{a.view.id().gen}", fn(v) {
                  flight_file_node(v, f, ff, Some(a), origin, set_out)
                })
              _ => flight_holder(l, "file/\{ff.key}", fn(v) { flight_file_node(v, f, ff, None, origin, set_out) })
            }
          }
        }
      }) |> ignore
    }) |> ignore
  })
}

///|
/// The quote's own card carried over the list. Its source is frozen before the draft is taken; its destination
/// remains the message's actual card, and all of its width, position and colour changes use the send's path.
fn flight_quote_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : @sf.QuoteCardNode?,
  origin : () -> (Double, Double, Double, Double),
  set_out : ((Double, Double, Double, Double), (Double, Double)) -> Unit,
) -> Unit {
  let target = fn(at : FlightAt) { landing.bind(fn(q) { flight_window_at(f, q.card, at) }) }
  // (its card laid out in this pass when it is given: set out from there once that is told)
  parent.reacts(fn() { target(flight_drawn(f.way, parent)) }, fn(r) {
    guard r is Some(to) && to.2 > 0.0 else { return }
    set_out(to, (ff.from.0, ff.from.1))
  })
  match landing {
    Some(q) => {
      q.root.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { q.root.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  let going = landing is Some(_)
  let across = fn(at : FlightAt) { if going { flight_across(at.p, flies_desk(f)) } else { 0.0 } }
  let up = fn(at : FlightAt) { if going { flight_up(at.p, flies_desk(f)) } else { 0.0 } }
  let scale = fn(at) { ff.source_scale + (1.0 - ff.source_scale) * up(at) }
  let ground = fn(at) {
    let to = target(at).unwrap_or(ff.from)
    let a = across(at)
    let p = up(at)
    (ff.from.0 + (to.0 - ff.from.0) * a, ff.from.1 + (to.1 - ff.from.1) * p,
      ff.from.2 + (to.2 - ff.from.2) * a, ff.from.3 + (to.3 - ff.from.3) * p)
  }
  flight_visible_node(parent, f.way, ff.shown, ff.from, ground, up, origin, fn(part) {
    match landing {
      Some(q) =>
        // (as wide as its card where it lands; its words from the source's width to as wide as they are there, by the
        // share of the way across: what flexes them in the card's own layout)
        flight_part(part, f.way, fn(at) { (target(at).map(fn(r) { r.2 }).unwrap_or(0.0), None) }, fn(holder) {
          let copy = (q.copy)(holder, fn() {
            ff.quote_words.map(fn(w) { (w.1, across(flight_drawn(f.way, holder))) })
          })
          copy.root.scale(By(fn() { scale(flight_drawn(f.way, copy.root)) }), about=@view.At(0.0, 0.0))
          .offset(By(fn() {
            let at = flight_drawn(f.way, copy.root)
            let shift = (q.sent_shift)()
            (shift.0 * (1.0 - across(at)) * scale(at), shift.1 * (1.0 - up(at)) * scale(at))
          })) |> ignore
          copy.card.ground_drawn(By(fn() {
            let at = flight_drawn(f.way, copy.card)
            let g = ground(at)
            let to = target(at).unwrap_or(ff.from)
            let shift = (q.sent_shift)()
            let h = copy.card.laid_size_told().map(fn(size) { size.1 }).unwrap_or(to.3)
            let s = scale(at)
            let (w, h) = if s > 0.0 { (g.2 / s - to.2, g.3 / s - h) } else { (0.0, 0.0) }
            (-shift.0 * (1.0 - across(at)), -shift.1 * (1.0 - up(at)), w, h)
          }))
          .ground(By(fn() {
            let own = @sf.quote_ground()
            let from = if ff.ground != 0L { @sf.over(@sf.theme().p.bg, ff.ground) } else { own }
            @sf.mix_seen(from, 1.0 - up(flight_drawn(f.way, copy.card)), own)
          })) |> ignore
        })
      None =>
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
    flight_visible_node(leaving, f.way, ff.shown, close_from, fn(at) {
      let g = ground(at)
      (g.0 + g.2 + reach - side, g.1 - reach, side, side)
    }, up, origin, fn(close_room) {
      let close = @sf.corner_remove_face_node(close_room)
      close.scale(By(fn() { 1.0 - (1.0 - @sf.leave_scale) * f.gone.shown(close) })) |> ignore
    })
    match (ff.leaving, ff.leaving_node) {
      (Some((r, _)), Some(make)) =>
        flight_visible_node(leaving, f.way, ff.shown, r, fn(at) {
          let g = ground(at)
          (g.0 + r.0 - ff.from.0, g.1 + r.1 - ff.from.1, r.2, r.3)
        }, up, origin, make)
      _ => ()
    }
  })
}

///|
/// The portion of a source still visible as it leaves an opening container, translated to the flight's current
/// rectangle. Only an existing cut is carried: an unclipped source may draw beyond its own layout while reshaping.
/// What is in it (`body`) is as big as that rectangle, as the flight's layout has it.
fn flight_visible_node(
  parent : @view.View,
  way : FlightWay,
  shown : @ui.DrawnState?,
  from : (Double, Double, Double, Double),
  rect : (FlightAt) -> (Double, Double, Double, Double),
  up : (FlightAt) -> Double,
  origin : () -> (Double, Double, Double, Double),
  share? : () -> (Double, Double) = flight_whole,
  body : (@view.View) -> Unit,
) -> Unit {
  let visible = fn(at) { flight_visible(shown, from, up(at)) }
  flight_part(parent, way, share~, fn(at) {
    let v = visible(at)
    let r = rect(at)
    (r.2 * dmax(0.0, v.right - v.left), Some(r.3 * dmax(0.0, v.bottom - v.top)))
  }, fn(crop) {
    crop
    .offset(By(fn() {
      let at = flight_drawn(way, crop, share~)
      let v = visible(at)
      let (x, y, w, h) = rect(at)
      let o = origin()
      (x + w * v.left - o.0, y + h * v.top - o.1)
    }))
    .clips(By(fn() { let v = visible(flight_drawn(way, crop, share~)); v.left > 0.0 || v.top > 0.0 || v.right < 1.0 || v.bottom < 1.0 }))
    .alpha(By(fn() { visible(flight_drawn(way, crop, share~)).alpha }))
    .fades(By(fn() {
      let v = visible(flight_drawn(way, crop, share~))
      (if v.left > 0.0 { v.soft } else { 0.0 }, if v.top > 0.0 { v.soft } else { 0.0 },
        if v.right < 1.0 { v.soft } else { 0.0 }, if v.bottom < 1.0 { v.soft } else { 0.0 })
    })) |> ignore
    flight_part(crop, way, share~, fn(at) { let r = rect(at); (r.2, Some(r.3)) }, fn(b) {
      b.offset(By(fn() {
        let at = flight_drawn(way, b, share~)
        let v = visible(at)
        let r = rect(at)
        (-r.2 * v.left, -r.3 * v.top)
      })) |> ignore
      body(b)
    })
  })
}

///|
fn flight_waiting_node(parent : @view.View, f : SendFlight, origin : () -> (Double, Double, Double, Double)) -> Unit {
  if f.text == "" { return }
  parent.box(fn(room) {
    room.over(Is(true)).width(Is(Some(f.field_w))).height(Is(Some(f.field_h)))
    .offset(By(fn() { let o = origin(); (f.field_x - o.0, f.field_y - o.1) })).clips(Is(true)) |> ignore
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
/// The words sent on their way to `bubble` and `words` in their row, laid out in the pass this is made in: from where
/// they were typed, as one paragraph or piece by piece (flight_pieces_of: where the field and the message wrap
/// otherwise), each piece's room and shape as of the flight's own layout.
fn flight_landing_node(
  parent : @view.View,
  f : SendFlight,
  bubble : @view.View,
  words : @view.View,
  origin : () -> (Double, Double, Double, Double),
  set_out : ((Double, Double, Double, Double), (Double, Double)) -> Unit,
) -> Unit {
  let brect = fn(at) { flight_window_at(f, bubble, at).unwrap_or((0.0, 0.0, 0.0, 0.0)) }
  let wrect = fn(at) { flight_window_at(f, words, at).unwrap_or((0.0, 0.0, 0.0, 0.0)) }
  // (told from this pass on, the frame the flight sets out: where it is drawn going to them)
  parent.reacts(fn() { (flight_target_window(f, bubble), flight_target_window(f, words)) }, fn(rects) {
    guard rects is (Some(b), Some(w)) && b.2 > 0.0 && w.2 > 0.0 else { return }
    set_out(w, (f.from_x, f.from_y))
  })
  bubble.alpha(Is(0.0)).hides(Is(true)) |> ignore
  parent.owns(fn() { bubble.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
  let across = fn(at : FlightAt) { flight_across(at.p, flies_desk(f)) }
  let up = fn(at : FlightAt) { flight_up(at.p, flies_desk(f)) }
  let bx = fn(at) { let b = brect(at); f.from_x - bubble_in_x + (b.0 - f.from_x + bubble_in_x) * across(at) }
  let by = fn(at) { let b = brect(at); f.from_y - bubble_in_y + (b.1 - f.from_y + bubble_in_y) * up(at) }
  flight_part(parent, f.way, fn(at) { let b = brect(at); (b.2, Some(b.3)) }, fn(ground) {
    ground
    .offset(By(fn() { let at = flight_drawn(f.way, ground); let o = origin(); (bx(at) - o.0, by(at) - o.1) }))
    // The flying copy carries the bubble's surface as seen on its page. Neutral alone is a translucent tint:
    // over another row it would tint that row's words instead of covering them as the bubble passes.
    .ground(By(fn() {
      @sf.over(@sf.theme().p.bg,
        @sf.alpha(@ui.tree_theme().color(Neutral), flight_ground(f.way.shown(ground), flies_desk(f))))
    }))
    .radius(By(fn() { @ui.tree_theme().corner(Xl2) })) |> ignore
  })
  // (its pieces as its words are laid out in this pass, at the width they are laid out at)
  let pieces : Ref[Array[FlightPiece]?] = Ref(None)
  flight_layout(parent, f.way, fn(l, at) {
    let w = wrect(at)
    pieces.val = @ui.runs_words_now(words).bind(fn(w) { flight_pieces_of(f, Some(w)).map(fn(p) { p.0 }) })
    match pieces.val {
      Some(all) =>
        for i in 0..<all.length() {
          let cell = l.child("piece/\{i}", fn(cell) {
            let piece = fn() { pieces.val.unwrap()[i] }
            // (where the field and the message wrap at different places the pieces cross: each only the room the
            // larger pieces leave it, as the old frame's pieces have it, flight_pieces_drawn; its path its own)
            let room = fn(at) {
              let w = wrect(at)
              flight_piece_room(pieces.val.unwrap(), i, w.0, w.1, across(at), up(at))
            }
            cell.clips(Is(true))
            .offset(By(fn() {
              let at = flight_drawn(f.way, cell)
              let q = piece()
              let w = wrect(at)
              let o = origin()
              (q.from.0 + (w.0 + q.at.0 - q.from.0) * across(at) - o.0 + room(at).0,
                q.from.1 + (w.1 + q.at.1 - q.from.1) * up(at) - o.1)
            })) |> ignore
            flight_words_node(cell, f.way, words, wrect, fn() { let q = piece(); (-q.at.0 - room(flight_drawn(f.way, cell)).0, -q.at.1) })
          })
          let q = all[i]
          let (left, right) = flight_piece_room(all, i, w.0, w.1, across(at), up(at))
          l.measure(cell, dmax(0.0, right - left), height=q.at.3) |> ignore
          l.place(cell, 0.0, 0.0)
        }
      None =>
        flight_holder(l, "whole", fn(group) {
          flight_words_node(group, f.way, words, wrect, fn() {
            let at = flight_drawn(f.way, group)
            let b = brect(at)
            let w = wrect(at)
            let o = origin()
            (bx(at) + w.0 - b.0 - o.0, by(at) + w.1 - b.1 - o.1)
          })
        })
    }
  })
}

///|
/// The words of `words`, as wide as `rect` has them in the flight's layout, where `offset` puts them.
fn flight_words_node(
  parent : @view.View,
  way : FlightWay,
  words : @view.View,
  rect : (FlightAt) -> (Double, Double, Double, Double),
  offset : () -> (Double, Double),
) -> Unit {
  let set = fn() { words.words_said() |> ignore; words.runs_set_now() }
  flight_part(parent, way, fn(at) { (rect(at).2, None) }, fn(w) {
    w.offset(By(offset))
    .words_runs(By(fn() { set().0 })).words_look(By(fn() { set().1 })).runs_look(By(fn() { set().2 }))
    .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) })) |> ignore
  })
}
