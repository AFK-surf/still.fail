// Layers in layers each drawn from a place of its own, moved by whole pixels and between them: each frame draws what
// the same tree with none of them a layer of its own draws, there and then (docs/retained.md rule 15: a layer's block
// in its own terms, put where it is; every glyph set on the pixels where the window has it).

///|
/// What a frame of a page holding `depth` boxes one in another, each `(3.0, 2.5)` in from the one holding it, cut to
/// its round corners, their words, draws: the outer moved down by `y` (each a layer of its own where `layers`, its
/// place bound; else none, its place as it is), after `frames` frames of moves before it (`step` each).
fn nested_drawn(layers : Bool, depth : Int, y : Double, step : Double, frames : Int) -> (Array[(Double, Double, Int64)], Array[(Double, Double, Double, Double, Int64)]) {
  let shift = @signals.signal(y - step * frames.to_double())
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(300.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.box(fn(mover) {
        mover.width(Is(Some(300.0))) |> ignore
        if layers {
          mover.offset(By(fn() { (10.0, shift.get()) })) |> ignore
        } else {
          mover.offset(Is((10.0, y))) |> ignore
        }
        fn nest(b : @view.View, d : Int) -> Unit {
          b.box(fn(w) { w.words(Is("deep \{d} ÿ")) |> ignore }) |> ignore
          if d < depth {
            b.box(fn(inner) {
              inner.clips(Is(true)).radius(Is(6.0)).ground(Is(0xEEF2FFFFL)) |> ignore
              if layers {
                inner.offset(By(fn() { (3.0, 2.5 + 0.0 * shift.get()) })) |> ignore
              } else {
                inner.offset(Is((3.0, 2.5))) |> ignore
              }
              nest(inner, d + 1)
            })
            |> ignore
          }
        }
        nest(mover, 0)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  for _ in 0..<frames {
    shift.set(shift.get() + step)
    t.draw()
  }
  (t.drawn_glyphs(), t.drawn_rects())
}

///|
test "layers in layers, each from a place of its own, moved: drawn where none of them a layer draws, glyphs and all" {
  for depth in [1, 3] {
    for step in [2.0, 0.75, 0.3333333333333333] {
      for frames in [0, 1, 5] {
        let y = 40.0 + step * 7.0
        let as_layers = nested_drawn(true, depth, y, step, frames)
        let alone = nested_drawn(false, depth, y, step, 0)
        assert_eq(as_layers, alone, msg="depth \{depth}, moved by \{step} \{frames} times")
      }
    }
  }
}
