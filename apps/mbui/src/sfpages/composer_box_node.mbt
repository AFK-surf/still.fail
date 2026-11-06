// The composer's parts keep their nodes while the capsule opens into a box. A wrapping row puts the words above
// the controls when opened; keyed order moves those same parts, so its field never loses focus or selection.

///|
fn composer_box_node(
  parent : @view.View,
  opened : () -> Bool,
  has_extras : () -> Bool,
  place : () -> ComposerPlace,
  by : () -> String,
  extras : (@view.View, (@view.View) -> Unit) -> Unit,
  words : (@view.View) -> @view.View,
  plus : (@view.View) -> Unit,
  choices : (@view.View) -> Unit,
  tail : (@view.View) -> Array[@view.View],
  ground? : (() -> (Double, Double, Double, Double)) -> Unit = fn(_) {  },
  from? : Map[String, (Double, Double, Double, Double)] = {},
  arrival? : @motion.Spec = @motion.move(),
  positions? : ((Double) -> Map[String, (Double, Double, Double, Double)]) -> Unit = fn(_) { },
  place_in? : (@view.View, (Double) -> ComposerPlace),
) -> @view.View {
  let cap_made : Ref[@view.View?] = Ref(None)
  // (the capsule in a box of its own, stood off what holds it as far as it stands in from its corners, which lays it
  // out at its width and reports how tall it is laid out ("cap"): what the page's layout reads of it, as it measures
  // the composer, for the room the list leaves it (the talk's: chat_node.mbt), nothing of its size read back)
  parent.box(fn(hold) {
    let line = fn() {
      let look = @ui.style_words(@sf.theme().t.words)
      if look.line > 0.0 { look.line } else { look.size * @ui.tree_theme().text_line }
    }
    let extra = fn() { dmax(0.0, (line() - @sf.theme().round.side) / 2.0) }
    // (its shape as the room it stands in is laid out (place_in: what holds it, the shape a width of it calls for),
    // in the same layout as a layout's property (Roomed), as it is painted as a look's (Painted); else `place`'s)
    let laid = fn(f : (ComposerPlace) -> (Double, Double, Double, Double)) -> @view.Live[(Double, Double, Double, Double)] {
      match place_in {
        Some((room, of)) => Roomed(room, fn(w, _) { f(of(w)) })
        None => By(fn() { f(place()) })
      }
    }
    let tools_in_of = fn(p : ComposerPlace) { @sf.capsule_in(p.corner, @sf.theme().round.side) - @sf.composer_pad }
    hold.margin(laid(fn(p) {
      if opened() { (0.0, 0.0, 0.0, 0.0) } else {
        let (l, r, b) = p.capsule_in
        (l, 0.0, r, b)
      }
    }))
    |> ignore
    let cap = hold.box(fn(cap) {
      cap.row(Is(true)).wraps(By(fn() { if opened() { Some(10.0) } else { None } }))
      .gap(By(fn() { if opened() { 4.0 } else { 1.0 } }))
      .lines_up(Is(Some(Middle)))
      .padding(laid(fn(p) {
        let pad = if opened() { @sf.composer_pad } else { p.capsule_pad }
        let x = if opened() { pad } else { pad + extra() }
        (x, pad, x, pad)
      }))
      .radius({
        let corner = fn(p : ComposerPlace) {
          if opened() { p.corner } else {
            (dmax(@sf.theme().round.side, line()) + 2.0 * p.capsule_pad) / 2.0
          }
        }
        match place_in {
          Some((room, of)) => Painted(fn(l) { corner(of(l.size(room).map(fn(z) { z.0 }).unwrap_or(0.0))) })
          None => By(fn() { corner(place()) })
        }
      })
      .glass(By(fn() { Some(@sf.glass_floating()) }))
      |> ignore
      let moving = @motion.moves_together(cap, by, spec=composer_open_spec())
      let named : Map[String, @view.View] = { "box": cap }
      moving.add(cap, reshapes=true)
      ground(fn() { moving.ground_of(cap) })
      cap.each(
        fn() {
          if opened() { ["extras", "words", "plus", "choices", "tail"] } else {
            ["extras", "plus", "words", "choices", "tail"]
          }
        },
        fn(k) { k },
        fn(part, key) {
          let key = @signals.untracked(fn() { key.get() })
          match key {
            "extras" => {
              // With no cards this part leaves no row or gap, and has no height to hand to a card arriving next.
              // An unconstrained overlay fills the capsule; using that as its old room made the first card
              // already full-sized while the capsule was still opening above the field.
              part.width_share(Is(1.0)).over(By(fn() { !has_extras() }))
              .height(By(fn() { if has_extras() { None } else { Some(0.0) } })) |> ignore
              moving.add(part)
              let held : Array[@view.View] = []
              extras(part, fn(item) {
                moving.add(item, within=part)
                held.push(item)
                item.owns(fn() {
                  match held.search_by(fn(v) { physical_equal(v, item) }) {
                    Some(i) => held.remove(i) |> ignore
                    None => ()
                  }
                }) |> ignore
                // Each card grows whole into the room made for it. A card inserted above an existing attachment
                // has only the space that attachment has opened so far; the existing attachment stays whole.
                // (from where this frame laid them out, read as it is painted)
                item.scale(Painted(fn(laid) {
                  match (laid.rect(part), laid.rect(item)) {
                    (Some(p), Some(b)) if b.3 > 0.0 => {
                      let y = b.1 - p.1 + moving.box_change(item).1
                      let mut end = p.3 + moving.box_change(part).3
                      for next in held {
                        match laid.rect(next) {
                          Some(n) if n.1 > b.1 + 0.5 && n.0 < b.0 + b.2 && n.0 + n.2 > b.0 => {
                            let gap = dmax(0.0, n.1 - b.1 - b.3)
                            end = dmin(end, n.1 - p.1 + moving.box_change(next).1 - gap)
                          }
                          _ => ()
                        }
                      }
                      dclamp((end - y) / b.3, 0.0, 1.0)
                    }
                    _ => 1.0
                  }
                }), about=At(0.5, 0.0)) |> ignore
              })
            }
            "words" => {
              part.width_share(By(fn() { if opened() { 1.0 } else { 0.0 } }))
              .grow(Is(1.0)).min_width(Is(Some(0.0)))
              .height(By(fn() { if opened() { None } else { Some(dmax(@sf.theme().round.side, line())) } }))
              .lies_along(Is(Middle))
              .padding(By(fn() { if opened() { (8.0, 8.0, 8.0, 0.0) } else { (0.0, 0.0, 8.0, 0.0) } }))
              |> ignore
              let field = words(part)
              moving.add(field)
              named["words"] = field
            }
            "plus" => {
              part.margin(laid(fn(p) { if opened() { (tools_in_of(p), 0.0, 0.0, tools_in_of(p)) } else { (0.0, 0.0, 0.0, 0.0) } })) |> ignore
              plus(part)
              moving.add(part)
              named["plus"] = part
            }
            "choices" => {
              part.row(Is(true)).min_width(Is(Some(0.0)))
              .laid_nowhere(By(fn() { !opened() }))
              .margin(laid(fn(p) { (0.0, 0.0, 0.0, tools_in_of(p)) })) |> ignore
              choices(part)
              moving.add(part)
              named["choices"] = part
            }
            "tail" => {
              // Opened, it takes what ＋ and the choices leave of their line, from nothing, its controls at its end: never
              // wider than that line, so it never goes on to a line of its own at the box's left (send there, past its
              // edge, the names it is copied to long). What it holds gives way there by leaving those names out.
              // Closed, where the capsule's line has not the room, it leaves out the names it is copied to (View::fits).
              part.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))).lies_along(Is(End)).fits(Is(true))
              .width(By(fn() { if opened() { Some(0.0) } else { None } })).grow(By(fn() { if opened() { 1.0 } else { 0.0 } }))
              .margin(laid(fn(p) { if opened() { (0.0, 0.0, tools_in_of(p), tools_in_of(p)) } else { (0.0, 0.0, 0.0, 0.0) } })) |> ignore
              // The chooser can come and go before the note and send button. Each keeps its own place through
              // that change; moving their shared row would carry them across by the chooser's changing width.
              for i, control in tail(part) {
                moving.add(control)
                named[if i == 0 { "note" } else { "send" }] = control
              }
            }
            _ => ()
          }
        },
      )
      let readers : Map[String, (Double) -> (Double, Double, Double, Double)?] = {}
      let handed : Array[(@view.View, (Double, Double, Double, Double))] = []
      for name, node in named {
        readers[name] = moving.position(node)
        match from.get(name) { Some(r) => handed.push((node, r)); None => () }
      }
      if !handed.is_empty() { moving.arrive_from(handed, spec=arrival) }
      positions(fn(at) {
        let out : Map[String, (Double, Double, Double, Double)] = {}
        for name, read in readers { match read(at) { Some(r) => out[name] = r; None => () } }
        out
      })
    })
    cap_made.val = Some(cap)
    hold.layout_box(Is(()), sized=true, fn(l, _) {
      let (_, h) = l.measure(cap, l.width)
      l.report("cap", h)
      l.size_to(h)
      l.place(cap, 0.0, 0.0)
    })
    |> ignore
  })
  |> ignore
  cap_made.val.unwrap()
}
