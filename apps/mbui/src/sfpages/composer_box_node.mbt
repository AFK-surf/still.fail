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
) -> @view.View {
  parent.box(fn(cap) {
    let line = fn() {
      let look = @ui.style_words(@sf.theme().t.words)
      if look.line > 0.0 { look.line } else { look.size * @ui.tree_theme().text_line }
    }
    let extra = fn() { dmax(0.0, (line() - @sf.theme().round.side) / 2.0) }
    let tools_in = fn() { @sf.capsule_in(place().corner, @sf.theme().round.side) - @sf.composer_pad }
    cap.row(Is(true)).wraps(By(fn() { if opened() { Some(10.0) } else { None } }))
    .gap(By(fn() { if opened() { 4.0 } else { 2.0 } }))
    .lines_up(Is(Some(Middle)))
    .padding(By(fn() {
      let pad = if opened() { @sf.composer_pad } else { place().capsule_pad }
      let x = if opened() { pad } else { pad + extra() }
      (x, pad, x, pad)
    }))
    .margin(By(fn() {
      if opened() { (0.0, 0.0, 0.0, 0.0) } else {
        let (l, r, b) = place().capsule_in
        (l, 0.0, r, b)
      }
    }))
    .radius(By(fn() {
      if opened() { place().corner } else {
        (dmax(@sf.theme().round.side, line()) + 2.0 * place().capsule_pad) / 2.0
      }
    }))
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
              item.scale(By(fn() {
                match (part.laid_window_told(), item.laid_window_told()) {
                  (Some(p), Some(b)) if b.3 > 0.0 => {
                    let y = b.1 - p.1 + moving.box_change(item).1
                    let mut end = p.3 + moving.box_change(part).3
                    for next in held {
                      match next.laid_window_told() {
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
            part.margin(By(fn() { if opened() { (tools_in(), 0.0, 0.0, tools_in()) } else { (0.0, 0.0, 0.0, 0.0) } })) |> ignore
            plus(part)
            moving.add(part)
            named["plus"] = part
          }
          "choices" => {
            part.row(Is(true)).min_width(Is(Some(0.0)))
            .laid_nowhere(By(fn() { !opened() }))
            .margin(By(fn() { (0.0, 0.0, 0.0, tools_in()) })) |> ignore
            choices(part)
            moving.add(part)
            named["choices"] = part
          }
          "tail" => {
            // Opened, it takes what ＋ and the choices leave of their line, from nothing, its controls at its end: never
            // wider than that line, so it never goes on to a line of its own at the box's left (send there, past its
            // edge, the names it is copied to long). What it holds gives way there by leaving those names out.
            part.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))).lies_along(Is(End))
            .width(By(fn() { if opened() { Some(0.0) } else { None } })).grow(By(fn() { if opened() { 1.0 } else { 0.0 } }))
            .margin(By(fn() { if opened() { (0.0, 0.0, tools_in(), tools_in()) } else { (0.0, 0.0, 0.0, 0.0) } })) |> ignore
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
}
